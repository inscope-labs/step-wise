#!/usr/bin/env python3
"""StepWise behavioral acceptance tests (plan Phase 6).

Runs scripted scenarios against a real model, with v1/prompt.md as the system
prompt and a simulated `fetch_reference` tool that serves features and specs from
this repository. It checks observable behavior: what the reply contains, what it
must not contain, and which references the model chose to load.

    export ANTHROPIC_API_KEY=...            # read at run time, never printed or stored
    python3 v1/tests/sw_acceptance.py --list
    python3 v1/tests/sw_acceptance.py --dry-run          # validate scenarios; no network, no key
    python3 v1/tests/sw_acceptance.py --samples 3        # run everything against the default model
    python3 v1/tests/sw_acceptance.py --filter clipboard --model <model-id>

Model output is not deterministic, so each scenario runs several samples. A check
marked "critical" must pass in EVERY sample. Other checks must pass in at least
--threshold of the samples (default 0.67). The checks are regular expressions and
load logs. They are evidence, not proof: a passing run does not prove the prompt is
followed in general, and a failing run is worth reading before blaming the model.

Python 3 standard library only.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
V1 = os.path.dirname(HERE)
DEFAULT_MODEL = "claude-sonnet-5"
MAX_TOOL_ROUNDS = 6

ADDR_RE = re.compile(r"^(feature:[a-z0-9-]+|spec:[a-z0-9-]+/[a-z0-9-]+)$")
ID_RE = re.compile(r"^[a-z0-9-]+$")

TOOL = {
    "name": "fetch_reference",
    "description": (
        "Fetch a StepWise reference document by address, for example "
        "feature:<name> or spec:<feature>/<section>. Returns the document text, "
        "or an error if it is unavailable."
    ),
    "input_schema": {
        "type": "object",
        "properties": {"address": {"type": "string", "description": "feature:<name> or spec:<feature>/<section>"}},
        "required": ["address"],
    },
}

CHECK_FIELDS = {
    "matches": ("pattern",),
    "not_matches": ("pattern",),
    "code_matches": ("pattern",),
    "code_not_matches": ("pattern",),
    "count": ("pattern",),
    "implies": ("if", "then"),
    "fetched": (),
}


class ScenarioError(Exception):
    pass


class ApiError(Exception):
    pass


# --------------------------------------------------------------------------- loading

def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise ScenarioError("%s: cannot read as JSON: %s" % (path, e))


def flags_of(spec):
    table = {"i": re.I, "m": re.M, "s": re.S}
    out = 0
    for c in spec or "":
        if c not in table:
            raise ScenarioError("unknown regex flag '%s' (use i, m, s)" % c)
        out |= table[c]
    return out


def validate_check(chk, where):
    errs = []
    if not isinstance(chk, dict):
        return ["%s: check is not an object" % where]
    t = chk.get("type")
    if t not in CHECK_FIELDS:
        return ["%s: unknown check type %r" % (where, t)]
    for k in CHECK_FIELDS[t]:
        if not isinstance(chk.get(k), str) or not chk.get(k):
            errs.append("%s: %s check needs a non-empty string '%s'" % (where, t, k))
    try:
        fl = flags_of(chk.get("flags"))
        for k in ("pattern", "if", "then"):
            if isinstance(chk.get(k), str):
                re.compile(chk[k], fl)
    except (re.error, ScenarioError) as e:
        errs.append("%s: bad regex or flags: %s" % (where, e))
    if t == "count":
        if "min" not in chk and "max" not in chk:
            errs.append("%s: count check needs 'min' and/or 'max'" % where)
        for k in ("min", "max"):
            if k in chk and not isinstance(chk[k], int):
                errs.append("%s: '%s' must be an integer" % (where, k))
    if t == "fetched":
        keys = [k for k in ("includes", "excludes", "excludes_prefix", "none") if k in chk]
        if not keys:
            errs.append("%s: fetched check needs one of includes, excludes, excludes_prefix, none" % where)
        for k in ("includes", "excludes"):
            for a in chk.get(k, []):
                if not ADDR_RE.match(str(a)):
                    errs.append("%s: '%s' is not a valid address: %r" % (where, k, a))
    if "critical" in chk and not isinstance(chk["critical"], bool):
        errs.append("%s: 'critical' must be true or false" % where)
    return errs


def validate_scenario(s, preludes, path):
    errs = []
    sid = s.get("id")
    if not isinstance(sid, str) or not ID_RE.match(sid):
        errs.append("%s: 'id' must be lowercase letters, digits and hyphens" % path)
    if s.get("prelude") is not None and s["prelude"] not in preludes:
        errs.append("%s: unknown prelude %r" % (path, s["prelude"]))
    for a in s.get("unavailable", []):
        if not ADDR_RE.match(str(a)):
            errs.append("%s: 'unavailable' has an invalid address %r" % (path, a))
    turns = s.get("turns")
    if not isinstance(turns, list) or not turns:
        errs.append("%s: 'turns' must be a non-empty list" % path)
        return errs
    for i, t in enumerate(turns, 1):
        w = "%s turn %d" % (path, i)
        if not isinstance(t, dict) or not isinstance(t.get("operator"), str) or not t["operator"]:
            errs.append("%s: needs a non-empty 'operator' string" % w)
            continue
        scripted = "assistant" in t
        if scripted and t.get("checks"):
            errs.append("%s: a scripted 'assistant' turn cannot have checks" % w)
        for j, c in enumerate(t.get("checks", []), 1):
            errs += validate_check(c, "%s check %d" % (w, j))
    last = turns[-1]
    if isinstance(last, dict):
        if "assistant" in last:
            errs.append("%s: the last turn must be generated (no 'assistant')" % path)
        if not last.get("checks"):
            errs.append("%s: the last turn needs at least one check" % path)
    return errs


def load_scenarios(scn_dir):
    """Returns (scenarios, preludes, errors)."""
    errors = []
    pre_path = os.path.join(os.path.dirname(scn_dir.rstrip("/")), "preludes.json")
    preludes = {}
    try:
        preludes = load_json(pre_path)
    except ScenarioError as e:
        errors.append(str(e))
    for name, turns in preludes.items():
        if not isinstance(turns, list) or not turns:
            errors.append("prelude %r must be a non-empty list of turns" % name)
            continue
        for i, t in enumerate(turns, 1):
            if not (isinstance(t, dict) and isinstance(t.get("operator"), str) and isinstance(t.get("assistant"), str)):
                errors.append("prelude %r turn %d needs string 'operator' and 'assistant' (preludes are fully scripted)" % (name, i))
    scenarios, seen = [], set()
    if not os.path.isdir(scn_dir):
        return [], preludes, errors + ["scenario directory not found: %s" % scn_dir]
    for fn in sorted(os.listdir(scn_dir)):
        if not fn.endswith(".json"):
            continue
        path = os.path.join(scn_dir, fn)
        try:
            s = load_json(path)
        except ScenarioError as e:
            errors.append(str(e))
            continue
        errs = validate_scenario(s, preludes, fn)
        if s.get("id") in seen:
            errs.append("%s: duplicate scenario id %r" % (fn, s.get("id")))
        seen.add(s.get("id"))
        errors += errs
        if not errs:
            scenarios.append(s)
    return scenarios, preludes, errors


# --------------------------------------------------------------------------- checks

def code_of(text):
    return "\n".join(re.findall(r"```[^\n]*\n(.*?)```", text, re.S))


def eval_check(chk, text, fetched):
    """Returns (passed, detail)."""
    t = chk["type"]
    fl = flags_of(chk.get("flags"))
    if t == "matches":
        ok = bool(re.search(chk["pattern"], text, fl))
        return ok, "pattern %s in reply" % ("found" if ok else "NOT found")
    if t == "not_matches":
        ok = not re.search(chk["pattern"], text, fl)
        return ok, "forbidden pattern %s" % ("absent" if ok else "PRESENT")
    if t == "code_matches":
        ok = bool(re.search(chk["pattern"], code_of(text), fl))
        return ok, "pattern %s in code blocks" % ("found" if ok else "NOT found")
    if t == "code_not_matches":
        ok = not re.search(chk["pattern"], code_of(text), fl)
        return ok, "forbidden pattern %s in code blocks" % ("absent" if ok else "PRESENT")
    if t == "count":
        n = len(re.findall(chk["pattern"], text, fl))
        lo, hi = chk.get("min"), chk.get("max")
        ok = (lo is None or n >= lo) and (hi is None or n <= hi)
        return ok, "found %d match(es), wanted min=%s max=%s" % (n, lo, hi)
    if t == "implies":
        haystack = code_of(text) if chk.get("scope") == "code" else text
        if not re.search(chk["if"], haystack, fl):
            return True, "premise not triggered"
        ok = bool(re.search(chk["then"], haystack, fl))
        return ok, "premise triggered; conclusion %s" % ("holds" if ok else "MISSING")
    if t == "fetched":
        bad = []
        for a in chk.get("includes", []):
            if a not in fetched:
                bad.append("did not load %s" % a)
        for a in chk.get("excludes", []):
            if a in fetched:
                bad.append("loaded %s" % a)
        for p in chk.get("excludes_prefix", []):
            hit = [a for a in fetched if a.startswith(p)]
            if hit:
                bad.append("loaded %s" % ", ".join(hit))
        if chk.get("none") and fetched:
            bad.append("loaded %s (expected nothing)" % ", ".join(fetched))
        return (not bad), ("; ".join(bad) if bad else "load log as required (%s)" % (", ".join(fetched) or "nothing loaded"))
    raise ScenarioError("unknown check type %r" % t)


# --------------------------------------------------------------------------- model I/O

def call_api(cfg, payload):
    url = cfg["api_base"].rstrip("/") + "/v1/messages"
    body = json.dumps(payload).encode("utf-8")
    headers = {"content-type": "application/json", "anthropic-version": "2023-06-01", "x-api-key": cfg["api_key"]}
    last = None
    for attempt in range(cfg["retries"] + 1):
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=cfg["timeout"]) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            last = "HTTP %d: %s" % (e.code, detail)
            if e.code in (429, 500, 502, 503, 529) and attempt < cfg["retries"]:
                time.sleep(cfg["retry_sleep"] * (2 ** attempt))
                continue
            break
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            last = "network error: %s" % e
            if attempt < cfg["retries"]:
                time.sleep(cfg["retry_sleep"] * (2 ** attempt))
                continue
            break
    raise ApiError(str(last).replace(cfg["api_key"], "<redacted>"))


def resolve_address(addr):
    m = re.match(r"^feature:([a-z0-9-]+)$", addr)
    if m:
        return os.path.join(V1, "feature", m.group(1) + ".md")
    m = re.match(r"^spec:([a-z0-9-]+)/([a-z0-9-]+)$", addr)
    if m:
        return os.path.join(V1, "specs", m.group(1), m.group(2) + ".md")
    return None


def serve_fetch(address, unavailable):
    address = str(address).strip()
    if address in unavailable:
        return False, "Unavailable: could not load %s." % address
    path = resolve_address(address)
    if path is None or not os.path.isfile(path):
        return False, "Unavailable: no such reference '%s'." % address
    with open(path, encoding="utf-8") as f:
        return True, f.read()


def generate(cfg, system, messages, unavailable):
    """One generated assistant turn, including any fetch_reference rounds.
    Returns (text, fetched_addresses, final_content_blocks)."""
    texts, fetched = [], []
    for _ in range(MAX_TOOL_ROUNDS):
        resp = call_api(cfg, {
            "model": cfg["model"], "max_tokens": cfg["max_tokens"],
            "system": system, "tools": [TOOL], "messages": messages,
        })
        content = resp.get("content", [])
        texts += [b.get("text", "") for b in content if b.get("type") == "text"]
        if resp.get("stop_reason") != "tool_use":
            messages.append({"role": "assistant", "content": content or [{"type": "text", "text": ""}]})
            return "\n".join(texts), fetched
        results = []
        for b in content:
            if b.get("type") != "tool_use":
                continue
            if b.get("name") != TOOL["name"]:
                results.append({"type": "tool_result", "tool_use_id": b["id"], "content": "Unknown tool.", "is_error": True})
                continue
            addr = str((b.get("input") or {}).get("address", "")).strip()
            fetched.append(addr)
            ok, body = serve_fetch(addr, unavailable)
            r = {"type": "tool_result", "tool_use_id": b["id"], "content": body}
            if not ok:
                r["is_error"] = True
            results.append(r)
        messages.append({"role": "assistant", "content": content})
        messages.append({"role": "user", "content": results})
    raise ApiError("model kept requesting references for %d rounds" % MAX_TOOL_ROUNDS)


def run_sample(cfg, scn, preludes, system):
    turns = list(preludes.get(scn.get("prelude"), [])) + list(scn["turns"])
    unavailable = set(scn.get("unavailable", []))
    messages, out = [], []
    for t in turns:
        messages.append({"role": "user", "content": t["operator"]})
        if "assistant" in t:
            messages.append({"role": "assistant", "content": t["assistant"]})
            continue
        text, fetched = generate(cfg, system, messages, unavailable)
        out.append({"operator": t["operator"], "reply": text, "fetched": fetched, "checks": t.get("checks", [])})
    return out


# --------------------------------------------------------------------------- reporting

def evaluate_scenario(cfg, scn, preludes, system):
    samples, errors = [], []
    for n in range(cfg["samples"]):
        try:
            turns = run_sample(cfg, scn, preludes, system)
        except ApiError as e:
            errors.append("sample %d: %s" % (n + 1, e))
            continue
        rows = []
        for ti, tr in enumerate(turns):
            for ci, chk in enumerate(tr["checks"]):
                ok, detail = eval_check(chk, tr["reply"], tr["fetched"])
                rows.append({"key": (ti, ci), "check": chk, "ok": ok, "detail": detail, "reply": tr["reply"], "fetched": tr["fetched"]})
        samples.append({"turns": turns, "rows": rows})
    return samples, errors


def summarize(cfg, scn, samples, errors):
    """Returns (status, failures) where failures are strings."""
    if errors and not samples:
        return "ERROR", errors
    failures = list(errors)
    keys = {}
    for s in samples:
        for r in s["rows"]:
            keys.setdefault(r["key"], []).append(r)
    status = "PASS"
    for key, rows in sorted(keys.items()):
        passed = sum(1 for r in rows if r["ok"])
        total = len(rows)
        chk = rows[0]["check"]
        critical = bool(chk.get("critical"))
        need_ok = (passed == total) if critical else (total > 0 and passed / total >= cfg["threshold"])
        if not need_ok:
            worst = next(r for r in rows if not r["ok"])
            label = chk.get("why") or chk["type"]
            failures.append("%s check '%s' passed %d/%d: %s" % ("CRITICAL" if critical else "non-critical", label, passed, total, worst["detail"]))
            status = "FAIL"
    if errors and status == "PASS":
        # Some samples never ran. An incomplete run must not look like a pass.
        status = "ERROR"
    return status, failures


def main(argv=None):
    ap = argparse.ArgumentParser(description="StepWise behavioral acceptance tests (plan Phase 6).")
    ap.add_argument("--scenarios", default=os.path.join(HERE, "scenarios"))
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--samples", type=int, default=3)
    ap.add_argument("--threshold", type=float, default=0.67, help="pass rate needed by non-critical checks")
    ap.add_argument("--filter", default="", help="comma-separated substrings of scenario ids")
    ap.add_argument("--results", default="", help="write a JSON summary here")
    ap.add_argument("--transcripts", default="", help="write full transcripts (one file per sample) into this directory")
    ap.add_argument("--api-base", default="https://api.anthropic.com")
    ap.add_argument("--max-tokens", type=int, default=2048)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--retry-sleep", type=float, default=2.0)
    ap.add_argument("--dry-run", action="store_true", help="validate scenarios and print the plan; no network, no key")
    ap.add_argument("--list", action="store_true", help="list scenarios and exit")
    args = ap.parse_args(argv)

    scenarios, preludes, errors = load_scenarios(args.scenarios)
    if errors:
        print("Scenario validation failed:", file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        return 2
    if args.filter:
        wanted = [w.strip() for w in args.filter.split(",") if w.strip()]
        scenarios = [s for s in scenarios if any(w in s["id"] for w in wanted)]
        if not scenarios:
            print("No scenario matches --filter %r" % args.filter, file=sys.stderr)
            return 2

    if args.list or args.dry_run:
        calls = 0
        for s in scenarios:
            gen = sum(1 for t in s["turns"] if "assistant" not in t)
            nchecks = sum(len(t.get("checks", [])) for t in s["turns"])
            crit = sum(1 for t in s["turns"] for c in t.get("checks", []) if c.get("critical"))
            calls += gen * args.samples
            print("%-34s turns=%d generated=%d checks=%d critical=%d  covers: %s" % (
                s["id"], len(s["turns"]) + len(preludes.get(s.get("prelude"), [])), gen, nchecks, crit, ", ".join(s.get("covers", []))))
        if args.dry_run:
            print("\nDry run OK: %d scenario(s) valid. A real run makes at least %d API call(s) (%d samples each), more when the model loads references." % (len(scenarios), calls, args.samples))
        return 0

    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not key:
        print("ANTHROPIC_API_KEY is not set. Export it, or use --dry-run to validate scenarios without a key.", file=sys.stderr)
        return 2
    if args.samples < 1:
        print("--samples must be at least 1", file=sys.stderr)
        return 2

    with open(os.path.join(V1, "prompt.md"), encoding="utf-8") as f:
        system = f.read()
    cfg = {"api_key": key, "api_base": args.api_base, "model": args.model, "samples": args.samples,
           "threshold": args.threshold, "max_tokens": args.max_tokens, "timeout": args.timeout,
           "retries": args.retries, "retry_sleep": args.retry_sleep}

    print("Model: %s | samples: %d | non-critical threshold: %.2f | prompt: %s" % (
        args.model, args.samples, args.threshold, sed_line2(system)))
    results, bad = [], 0
    for s in scenarios:
        samples, errs = evaluate_scenario(cfg, s, preludes, system)
        status, failures = summarize(cfg, s, samples, errs)
        if status != "PASS":
            bad += 1
        print("%-5s %s" % (status, s["id"]))
        for fl in failures:
            print("        - " + fl)
        results.append({"id": s["id"], "status": status, "failures": failures, "covers": s.get("covers", [])})
        if args.transcripts:
            os.makedirs(args.transcripts, exist_ok=True)
            for n, sm in enumerate(samples, 1):
                with open(os.path.join(args.transcripts, "%s.%d.md" % (s["id"], n)), "w", encoding="utf-8") as f:
                    for tr in sm["turns"]:
                        f.write("### Operator\n\n%s\n\n### Assistant (loaded: %s)\n\n%s\n\n" % (tr["operator"], ", ".join(tr["fetched"]) or "nothing", tr["reply"]))
    print("\n%d/%d scenario(s) passed." % (len(scenarios) - bad, len(scenarios)))
    if args.results:
        with open(args.results, "w", encoding="utf-8") as f:
            json.dump({"model": args.model, "samples": args.samples, "threshold": args.threshold, "results": results}, f, indent=2)
    return 0 if bad == 0 else 1


def sed_line2(text):
    lines = text.split("\n")
    return lines[1].strip() if len(lines) > 1 else "unknown version"


if __name__ == "__main__":
    sys.exit(main())
