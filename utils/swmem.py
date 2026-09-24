#!/usr/bin/env python3
"""swmem: StepWise Contextual Memory Sync, reference implementation (Python 3, standard library only).

A persistent, searchable, synchronizable store for the StepWise memory fields. The record format,
the merge rules and the safety gate are specified in v1/specs/memory-sync/ (schema, sync, safety).
The assistant never runs this. The operator does, and pastes the output.

    swmem init [--project SLUG]
    swmem recall [--context 'words'] [--kind K] [--limit N] [--verify] [--all-projects]
    swmem search 'words' [--kind K] [--tag T] [--path PREFIX] [--status S] [--limit N]
    swmem show ID
    swmem add KIND --trust observed|operator --subject '..' --text '..' [--risk LABEL] [--tag T]
              [--set K=V] [--fp KIND:REF] [--ttl 30d] [--dry-run]
    swmem retract ID [--reason '..']
    swmem verify [ID...]        swmem status        swmem export [--since MS]
    swmem import FILE           swmem rotate-replica

Exit status: 0 success, 1 refused or problem found, 2 usage error.
"""

import argparse
import base64
import datetime
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time

try:
    import fcntl
except ImportError:  # not available everywhere; the lock then degrades to a create-exclusive file
    fcntl = None

SCHEMA_V = 1
KINDS = ("fact", "constraint", "path", "failure", "correction", "warning", "task")
TRUSTS = ("observed", "operator")
TEXT_MAX, SUBJECT_MAX, RECORD_MAX, TAGS_MAX = 300, 120, 2048, 8
TAG_RE = re.compile(r"^[a-z0-9:_-]{1,32}$")
ID_RE = re.compile(r"^m_[a-z2-7]{20}$")
REPLICA_RE = re.compile(r"^[0-9a-f]{8}$")
FUTURE_SKEW_MS = 24 * 3600 * 1000
FACT_TTL_DAYS = 30
HASH_MAX_BYTES = 5 * 1024 * 1024
FP_KINDS = ("path-hash", "path-stat", "exists", "git-head")
KIND_WEIGHT = {"constraint": 1.0, "correction": 1.0, "failure": 0.9, "warning": 0.9, "fact": 0.8, "path": 0.7, "task": 0.6}
STANDING = ("constraint", "correction", "failure", "task", "warning")
BODY_KEYS = {"fact": (), "constraint": (), "path": ("path", "role"), "failure": ("symptom", "cause", "resolution"),
             "correction": ("was", "now"), "warning": ("status",),
             "task": ("objective", "status", "remaining", "criteria_met", "criteria_total")}
HOST_BOUND = ("fact", "path")


class Refused(Exception):
    """A write or request was refused. The message names a rule, never the offending text."""


# --------------------------------------------------------------------------- text helpers

_CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f]")


def clean(s):
    """Make text safe to print: no escape sequences or other control characters reach the terminal."""
    s = str(s).replace("\t", " ").replace("\n", " ").replace("\r", " ")
    return _CTRL.sub("?", s)


def has_control(s):
    return bool(_CTRL.search(s))


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def make_id(rec_without_id):
    digest = hashlib.sha256(canon(rec_without_id)).digest()
    return "m_" + base64.b32encode(digest).decode("ascii").lower()[:20]


def utc(ms):
    return datetime.datetime.fromtimestamp(ms / 1000.0, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_utc(s):
    try:
        return int(datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp() * 1000)
    except (ValueError, TypeError):
        return None


def slug(s, limit=40):
    s = re.sub(r"[^a-z0-9._-]+", "-", str(s).lower()).strip("-")
    return (s or "default")[:limit]


# --------------------------------------------------------------------------- risk gate (mirror of clipcopy.sh)

_ELIGIBLE = {"read-only", "creates", "creates-files", "modifies", "modifies-files", "changes-project-state",
             "privileged", "network", "destructive", "difficult-to-reverse", "irreversible", "eligible"}
_SENSITIVE = ("credential", "privileged-data", "secret", "sensitive")


def _norm_label(part):
    part = part.lower().replace(" ", "-").replace("_", "-")
    return re.sub(r"^-+|-+$", "", part)


def risk_class(raw):
    """eligible, sensitive or unrecognized. Must agree with _sw_risk_class in v1/utils/clipcopy.sh
    (a lint check compares them). Fail-closed: only known non-sensitive labels are eligible."""
    # The shell splits on commas through command substitution, which drops TRAILING empty parts.
    parts = raw.replace(",", "\n").rstrip("\n").split("\n")
    result = "eligible"
    for part in parts:
        norm = _norm_label(part)
        if any(s in norm for s in _SENSITIVE):
            return "sensitive"
        if norm not in _ELIGIBLE:
            result = "unrecognized"
    return result


# --------------------------------------------------------------------------- secret scanner and path denylist

_SECRET_RULES = [
    ("private-key", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")),
    ("aws-key", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("github-token", re.compile(r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
    ("api-key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}")),
    ("slack-token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("google-key", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}")),
    ("credential-assignment", re.compile(r"(?i)\b(pass(word|wd)?|secret|token|api[_-]?key)\b\s*[:=]\s*\S{4,}")),
    ("long-token", re.compile(r"[A-Za-z0-9+=_-]{40,}")),
]


def scan_secret(s):
    """Returns the NAME of the first rule that matches, or None. Never returns the matched text."""
    for name, rx in _SECRET_RULES:
        if rx.search(s):
            return name
    return None


_DENY_PATHS = [re.compile(p) for p in (
    r"(^|/)\.ssh(/|$)", r"(^|/)\.gnupg(/|$)", r"(^|/)\.aws(/|$)", r"(^|/)\.netrc$", r"(^|/)\.pgpass$",
    r"(^|/)\.docker/config\.json$", r"(^|/)\.kube/config$", r"(^|/)\.config/gcloud(/|$)",
    r"(^|/)\.env(\.[^/]*)?$", r"(^|/)id_(rsa|dsa|ecdsa|ed25519)$", r"\.(pem|key|p12|pfx|kdbx|jks|keystore)$",
    r"^/etc/(shadow|gshadow)$")]


def is_credential_path(path):
    p = os.path.abspath(os.path.expanduser(path)).lower()
    return any(rx.search(p) for rx in _DENY_PATHS)


def portable_path(path):
    """Store paths under the home directory as ~/..., so a store moves between users and machines."""
    home = os.path.expanduser("~")
    p = os.path.abspath(os.path.expanduser(path))
    if p == home:
        return "~"
    if p.startswith(home + os.sep):
        return "~" + p[len(home):]
    return p


def resolve_path(path):
    return os.path.expanduser(path)


# --------------------------------------------------------------------------- fingerprints (fixed kinds, nothing stored is ever run)

def fingerprint_value(kind, ref):
    """Current value of a fingerprint, or None if the target is missing or unavailable.
    Raises Refused for a credential-bearing path or a file too large to hash."""
    if kind not in FP_KINDS:
        raise Refused("fingerprint-kind")
    path = resolve_path(ref)
    if kind in ("path-hash", "path-stat") and is_credential_path(path):
        raise Refused("credential-path")
    if kind == "exists":
        return "1" if os.path.exists(path) else "0"
    if kind == "path-stat":
        try:
            st = os.stat(path)
        except OSError:
            return None
        return "%d:%d" % (st.st_size, st.st_mtime_ns)
    if kind == "path-hash":
        try:
            if not os.path.isfile(path):
                return None
            if os.path.getsize(path) > HASH_MAX_BYTES:
                raise Refused("file-too-large-to-hash")
            h = hashlib.sha256()
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
            return h.hexdigest()
        except OSError:
            return None
    if kind == "git-head":
        try:
            out = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10,
                                 env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
        except (OSError, subprocess.SubprocessError):
            return None
        return out.stdout.strip() if out.returncode == 0 and out.stdout.strip() else None
    return None


def check_fingerprint(fp):
    """Returns (status, detail): 'verified' or 'stale'. A record from a hostile store cannot make us read a credential file."""
    try:
        now = fingerprint_value(fp["kind"], fp["ref"])
    except Refused as e:
        return "stale", "refused (%s)" % e
    if now is None:
        return "stale", "target missing"
    return ("verified", "fingerprint matches") if now == fp["value"] else ("stale", "fingerprint changed")


# --------------------------------------------------------------------------- record validation

def _s(v, limit, required=True):
    if v is None and not required:
        return None
    if not isinstance(v, str) or (required and not v) or len(v) > limit or has_control(v):
        raise ValueError("bad string")
    return v


def validate_body(kind, body):
    if not isinstance(body, dict):
        raise ValueError("body")
    if kind == "path":
        _s(body.get("path"), 200)
        if body.get("role") not in ("created", "modified", "deleted", "read"):
            raise ValueError("role")
    elif kind == "failure":
        _s(body.get("symptom"), 160)
        _s(body.get("cause"), 160, required=False)
        _s(body.get("resolution"), 160, required=False)
    elif kind == "correction":
        _s(body.get("was"), 160)
        _s(body.get("now"), 160)
    elif kind == "warning":
        if body.get("status") not in ("open", "resolved"):
            raise ValueError("status")
    elif kind == "task":
        _s(body.get("objective"), 200)
        if body.get("status") not in ("open", "done", "abandoned"):
            raise ValueError("status")
        rem = body.get("remaining", [])
        if not isinstance(rem, list) or len(rem) > 8:
            raise ValueError("remaining")
        for r in rem:
            _s(r, 120)
        for k in ("criteria_met", "criteria_total"):
            if k in body and (not isinstance(body[k], int) or isinstance(body[k], bool) or body[k] < 0):
                raise ValueError(k)


def validate_record(rec):
    """Returns None if valid, else a short reason. Unknown envelope fields are ignored (forward compatibility)."""
    try:
        if not isinstance(rec, dict):
            return "not an object"
        if not isinstance(rec.get("id"), str) or not ID_RE.match(rec["id"]):
            return "id"
        if rec.get("prev") is not None and not (isinstance(rec["prev"], str) and ID_RE.match(rec["prev"])):
            return "prev"
        if rec.get("op") not in ("put", "retract") or rec.get("kind") not in KINDS or rec.get("trust") not in TRUSTS:
            return "op/kind/trust"
        sc = rec.get("scope")
        if not isinstance(sc, dict):
            return "scope"
        _s(sc.get("project"), 40)
        _s(sc.get("host"), 40)
        _s(rec.get("subject"), SUBJECT_MAX)
        _s(rec.get("text"), TEXT_MAX)
        tags = rec.get("tags")
        if not isinstance(tags, list) or len(tags) > TAGS_MAX or not all(isinstance(t, str) and TAG_RE.match(t) for t in tags):
            return "tags"
        validate_body(rec["kind"], rec.get("body"))
        h = rec.get("hlc")
        if not (isinstance(h, dict) and isinstance(h.get("t"), int) and isinstance(h.get("c"), int) and h["t"] >= 0 and h["c"] >= 0
                and isinstance(h.get("r"), str) and REPLICA_RE.match(h["r"])):
            return "hlc"
        src = rec.get("source")
        if not isinstance(src, dict):
            return "source"
        for k in ("session", "ledger"):
            _s(src.get(k), 80, required=False)
        val = rec.get("valid")
        if not isinstance(val, dict):
            return "valid"
        if val.get("until") is not None and parse_utc(val["until"]) is None:
            return "valid.until"
        fp = val.get("fp")
        if fp is not None:
            if not (isinstance(fp, dict) and fp.get("kind") in FP_KINDS):
                return "fp"
            _s(fp.get("ref"), 200)
            _s(fp.get("value"), 128)
        sup = rec.get("supersedes")
        if not isinstance(sup, list) or len(sup) > 64 or not all(isinstance(x, str) and ID_RE.match(x) for x in sup):
            return "supersedes"
        if rec["op"] == "retract" and not (isinstance(rec.get("retracts"), str) and ID_RE.match(rec["retracts"])):
            return "retracts"
        if len(canon(rec)) > RECORD_MAX:
            return "too large"
    except (ValueError, TypeError):
        return "field"
    return None


# --------------------------------------------------------------------------- the store

def default_store_path():
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.environ.get("SWMEM_STORE") or os.path.join(base, "stepwise", "memory", "default")


def default_project():
    env = os.environ.get("SWMEM_PROJECT")
    if env:
        return slug(env)
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=5)
        if out.returncode == 0 and out.stdout.strip():
            return slug(os.path.basename(out.stdout.strip()))
    except (OSError, subprocess.SubprocessError):
        pass
    return slug(os.path.basename(os.getcwd()))


class Loaded(object):
    def __init__(self):
        self.records = {}          # id -> record (valid, integrity-checked)
        self.files = {}            # path -> {count, head, torn, invalid, tampered, unsupported}
        self.chain_breaks = []     # ids whose prev does not follow their file's previous record
        self.forks = []            # (replica, prev) pairs claimed by more than one record
        self.order = {}            # id -> (file, index) for chain and own-file lookups
        self.file_ids = {}         # path -> [ids in order]


class Store(object):
    def __init__(self, path=None, state_dir=None, host=None, now_ms=None):
        self.root = os.path.abspath(path or default_store_path())
        self.replicas = os.path.join(self.root, "replicas")
        self.imports = os.path.join(self.root, "imports")
        self._state_override = state_dir or os.environ.get("SWMEM_STATE")
        self.host = slug(host or os.environ.get("SWMEM_HOST") or socket.gethostname())
        self._now = now_ms or (lambda: int(time.time() * 1000))
        self._info = None

    # ---- setup
    def now(self):
        return self._now()

    def info(self):
        if self._info is None:
            try:
                with open(os.path.join(self.root, "store.json"), encoding="utf-8") as f:
                    self._info = json.load(f)
            except (OSError, ValueError):
                raise Refused("store-not-initialised")
        return self._info

    def state_dir(self):
        sid = self.info()["store_id"]
        if self._state_override:
            return os.path.join(self._state_override, sid)
        base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
        return os.path.join(base, "stepwise", "memory", sid)

    def init(self):
        # makedirs applies the mode to the leaf only, so create the root explicitly and keep it private
        os.makedirs(self.root, mode=0o700, exist_ok=True)
        os.makedirs(self.replicas, mode=0o700, exist_ok=True)
        os.makedirs(self.imports, mode=0o700, exist_ok=True)
        p = os.path.join(self.root, "store.json")
        if os.path.exists(p):
            return False
        info = {"schema": SCHEMA_V, "store_id": os.urandom(8).hex(), "created": utc(self.now())}
        _write_atomic(p, json.dumps(info, sort_keys=True).encode("utf-8"))
        self._info = None
        return True

    # ---- replica state (local only)
    def _state_path(self):
        return os.path.join(self.state_dir(), "replica.json")

    def replica_state(self):
        try:
            with open(self._state_path(), encoding="utf-8") as f:
                st = json.load(f)
            if REPLICA_RE.match(st.get("replica", "")):
                return st
        except (OSError, ValueError):
            pass
        st = {"replica": os.urandom(4).hex(), "head": None, "count": 0}
        self._save_state(st)
        return st

    def _save_state(self, st):
        os.makedirs(self.state_dir(), mode=0o700, exist_ok=True)
        _write_atomic(self._state_path(), json.dumps(st, sort_keys=True).encode("utf-8"))

    def replica_file(self, rid=None):
        return os.path.join(self.replicas, (rid or self.replica_state()["replica"]) + ".jsonl")

    # ---- reading, with integrity checks
    def _source_files(self):
        out = []
        for d in (self.replicas, self.imports):
            if os.path.isdir(d):
                out += [os.path.join(d, n) for n in sorted(os.listdir(d)) if n.endswith(".jsonl")]
        return out

    def load(self):
        ld = Loaded()
        for path in self._source_files():
            meta = {"count": 0, "head": None, "torn": 0, "invalid": 0, "tampered": 0, "unsupported": 0}
            ld.files[path] = meta
            ld.file_ids[path] = []
            try:
                with open(path, "rb") as f:
                    data = f.read()
            except OSError:
                continue
            parts = data.split(b"\n")
            if parts and parts[-1] != b"":
                meta["torn"] += 1          # no trailing newline: a write in progress, or a copy made mid-append
            parts = parts[:-1]              # the last element is either empty or the torn fragment
            for raw in parts:
                if not raw.strip():
                    continue
                try:
                    rec = json.loads(raw.decode("utf-8"))
                except (ValueError, UnicodeDecodeError):
                    meta["invalid"] += 1
                    continue
                if isinstance(rec, dict) and isinstance(rec.get("v"), int) and rec["v"] > SCHEMA_V:
                    meta["unsupported"] += 1
                    continue
                if validate_record(rec) is not None:
                    meta["invalid"] += 1
                    continue
                body = dict(rec)
                rid = body.pop("id")
                if make_id(body) != rid:
                    meta["tampered"] += 1
                    continue
                meta["count"] += 1
                meta["head"] = rid
                ld.file_ids[path].append(rid)
                if rid not in ld.records:
                    ld.records[rid] = rec
        for path, ids in ld.file_ids.items():
            if os.path.dirname(path) != self.replicas:
                continue
            expected = None
            for rid in ids:
                if ld.records[rid]["prev"] != expected:
                    ld.chain_breaks.append(rid)
                expected = rid
        seen = {}
        for rid, rec in ld.records.items():
            seen.setdefault((rec["hlc"]["r"], rec["prev"]), []).append(rid)
        ld.forks = sorted(k for k, v in seen.items() if len(v) > 1)
        return ld

    def latest_hlc(self, ld, now):
        best = (0, -1)
        for rec in ld.records.values():
            t, c = rec["hlc"]["t"], rec["hlc"]["c"]
            if t <= now + FUTURE_SKEW_MS and (t, c) > best:
                best = (t, c)
        return best

    # ---- the view
    def view(self, ld=None, project=None, verify=False, all_projects=False):
        """Current memory as a list of entries {rec, status, detail, alternatives}. Deterministic for a given record set, clock, host."""
        ld = ld or self.load()
        now = self.now()
        project = project or default_project()
        suspect = {rid for rid, r in ld.records.items() if r["hlc"]["t"] > now + FUTURE_SKEW_MS}
        hidden = set()
        for rid, r in ld.records.items():
            if rid in suspect:
                continue          # a record from the far future cannot hide others until its time arrives
            hidden.update(r["supersedes"])
            if r["op"] == "retract":
                hidden.add(r["retracts"])
        groups, entries = {}, []
        for rid, r in ld.records.items():
            if r["op"] != "put" or rid in hidden:
                continue
            if not all_projects and r["scope"]["project"] != project:
                continue
            if rid in suspect:
                entries.append({"rec": r, "status": "suspect", "detail": "dated in the future", "alternatives": []})
                continue
            groups.setdefault((r["kind"], r["scope"]["project"], r["scope"]["host"], r["subject"]), []).append(r)
        for members in groups.values():
            members.sort(key=lambda r: (r["hlc"]["t"], r["hlc"]["c"], r["hlc"]["r"]), reverse=True)
            win, alts = members[0], [m["id"] for m in members[1:]]
            status, detail = self._status(win, verify)
            if alts:
                status, detail = "disputed", "%d concurrent records disagree" % (len(alts) + 1)
            entries.append({"rec": win, "status": status, "detail": detail, "alternatives": alts})
        return entries

    def _status(self, rec, verify):
        now = self.now()
        until = rec["valid"]["until"]
        if until is not None and parse_utc(until) is not None and parse_utc(until) < now:
            return "stale", "expired %s" % until
        foreign = rec["kind"] in HOST_BOUND and rec["scope"]["host"] not in ("*", self.host)
        fp = rec["valid"]["fp"]
        if verify and fp is not None:
            return check_fingerprint(fp)
        if foreign:
            return "other-host", "recorded on %s" % rec["scope"]["host"]
        return "unverified", "standing" if rec["kind"] in STANDING else "not checked"

    # ---- writing
    def add(self, kind, trust, subject, text, tags=(), body=None, risk=None, fp=None, ttl_ms=None,
            supersedes=(), auto_supersede=True, session=None, ledger=None, project=None, host=None,
            op="put", retracts=None, dry_run=False):
        if kind not in KINDS:
            raise Refused("kind")
        if trust not in TRUSTS:
            raise Refused("trust")
        if trust == "observed":
            if risk is None:
                raise Refused("risk-label-required")
            if risk_class(risk) != "eligible":
                raise Refused("risk-label-not-eligible")
        strings = [subject, text] + list(tags) + [str(v) for v in _flat(body or {})] + ([fp["ref"]] if fp else [])
        if any(has_control(x) for x in strings):
            raise Refused("control-characters")
        for x in strings:
            rule = scan_secret(x)
            if rule:
                raise Refused("secret-scan:" + rule)
        body = dict(body or {})
        if any(k not in BODY_KEYS[kind] for k in body):
            raise Refused("body-shape")
        try:
            validate_body(kind, body)
        except ValueError:
            raise Refused("body-shape")
        now = self.now()
        st = self.replica_state()
        rid = st["replica"]
        project = slug(project) if project else default_project()
        if host == "*":
            host = "*"
        else:
            host = slug(host) if host else (self.host if kind in HOST_BOUND else "*")
        src = {"replica": rid}
        if session:
            src["session"] = session
        if ledger:
            src["ledger"] = ledger
        fp_rec = None
        if fp:
            fp_rec = {"kind": fp["kind"], "ref": portable_path(fp["ref"]), "value": fp["value"]}
        until = utc(now + ttl_ms) if ttl_ms else None

        lock = _Lock(os.path.join(self.state_dir(), "write.lock"))
        with lock:
            ld = self.load()
            own = self.replica_file(rid)
            ids = ld.file_ids.get(own, [])
            if st["count"] > len(ids) or (st["head"] and st["head"] not in ids):
                raise Refused("replica-file-regressed")
            sup = set(supersedes)
            if op == "put" and auto_supersede:
                key = (kind, project, host, subject)
                for e in self.view(ld, project=project, all_projects=False):
                    r = e["rec"]
                    if (r["kind"], r["scope"]["project"], r["scope"]["host"], r["subject"]) == key:
                        sup.add(r["id"])
                        sup.update(e["alternatives"])
            lt, lc = self.latest_hlc(ld, now)
            t = max(now, lt)
            c = lc + 1 if t == lt else 0
            rec = {"v": SCHEMA_V, "prev": ids[-1] if ids else None, "op": op, "kind": kind,
                   "scope": {"project": project, "host": host}, "subject": subject, "text": text, "tags": sorted(set(tags)),
                   "body": body, "trust": trust, "source": src, "hlc": {"t": t, "c": c, "r": rid},
                   "valid": {"until": until, "fp": fp_rec}, "supersedes": sorted(sup)}
            if op == "retract":
                rec["retracts"] = retracts
            rec["id"] = make_id(rec)
            problem = validate_record(rec)
            if problem:
                raise Refused("record-invalid:" + problem)
            if dry_run:
                return rec
            line = canon(rec) + b"\n"
            os.makedirs(self.replicas, mode=0o700, exist_ok=True)
            heal = b""
            if os.path.exists(own) and os.path.getsize(own) > 0:
                with open(own, "rb") as f:
                    f.seek(-1, os.SEEK_END)
                    if f.read(1) != b"\n":
                        heal = b"\n"      # end an interrupted line so the new record starts cleanly
            fd = os.open(own, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
            try:
                os.write(fd, heal + line)
                os.fsync(fd)
            finally:
                os.close(fd)
            self._save_state({"replica": rid, "head": rec["id"], "count": len(ids) + 1})
        return rec

    def retract(self, target_id, reason=None):
        ld = self.load()
        rid = self.resolve_id(target_id, ld)
        t = ld.records[rid]
        return self.add(t["kind"], "operator", t["subject"], "retracted: " + (reason or "withdrawn"), body=t["body"],
                        op="retract", retracts=rid, project=t["scope"]["project"], host=t["scope"]["host"], auto_supersede=False)

    def resolve_id(self, prefix, ld=None):
        ld = ld or self.load()
        if prefix in ld.records:
            return prefix
        hits = [i for i in ld.records if i.startswith(prefix)] if len(prefix) >= 6 else []
        if len(hits) == 1:
            return hits[0]
        raise Refused("no-such-record" if not hits else "ambiguous-id")

    def rotate_replica(self):
        old = self.replica_state()["replica"]
        new = os.urandom(4).hex()
        self._save_state({"replica": new, "head": None, "count": 0})
        return old, new

    # ---- import / export
    def export_lines(self, since=0):
        ld = self.load()
        recs = sorted(ld.records.values(), key=lambda r: (r["hlc"]["t"], r["hlc"]["c"], r["hlc"]["r"], r["id"]))
        return [canon(r).decode("utf-8") for r in recs if r["hlc"]["t"] > since]

    def import_bundle(self, data):
        ld = self.load()
        good, dropped = {}, 0
        parts = data.split(b"\n")
        if parts and parts[-1] != b"":
            dropped += 1
        for raw in parts[:-1]:
            if not raw.strip():
                continue
            try:
                rec = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                dropped += 1
                continue
            if not isinstance(rec, dict) or (isinstance(rec.get("v"), int) and rec["v"] > SCHEMA_V) or validate_record(rec) is not None:
                dropped += 1
                continue
            body = dict(rec)
            rid = body.pop("id")
            if make_id(body) != rid:
                dropped += 1
                continue
            good[rid] = rec
        if not good:
            raise Refused("nothing-valid-to-import")
        lines = [canon(good[i]).decode("utf-8") for i in sorted(good)]
        payload = ("\n".join(lines) + "\n").encode("utf-8")
        name = hashlib.sha256(payload).hexdigest()[:16] + ".jsonl"
        os.makedirs(self.imports, mode=0o700, exist_ok=True)
        dest = os.path.join(self.imports, name)
        if not os.path.exists(dest):
            _write_atomic(dest, payload)
        new = sum(1 for i in good if i not in ld.records)
        return len(good), new, dropped


def _flat(body):
    for v in body.values():
        if isinstance(v, list):
            for x in v:
                yield x
        elif isinstance(v, dict):
            for x in _flat(v):
                yield x
        else:
            yield v


def _write_atomic(path, data):
    tmp = path + ".tmp%d" % os.getpid()
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, path)


class _Lock(object):
    def __init__(self, path):
        self.path, self.fd = path, None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path), mode=0o700, exist_ok=True)
        self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        deadline = time.time() + 10
        while True:
            try:
                if fcntl:
                    fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if time.time() > deadline:
                    os.close(self.fd)
                    raise Refused("store-busy")
                time.sleep(0.02)

    def __exit__(self, *exc):
        try:
            if fcntl:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
        finally:
            os.close(self.fd)


# --------------------------------------------------------------------------- search and ranking

def _terms(q):
    return [t for t in re.split(r"[^a-z0-9]+", (q or "").lower()) if t]


def _haystacks(rec):
    body = " ".join(str(v) for v in _flat(rec["body"]))
    return rec["subject"].lower(), rec["text"].lower(), " ".join(rec["tags"]).lower(), body.lower()


def score(entry, terms, now, cwd=None):
    rec = entry["rec"]
    subj, text, tags, body = _haystacks(rec)
    s = 0.0
    for t in terms:
        s += (3 if t in subj else 0) + (2 if t in text else 0) + (1 if t in tags else 0) + (1 if t in body else 0)
    age_days = max(0.0, (now - rec["hlc"]["t"]) / 86400000.0)
    s += KIND_WEIGHT.get(rec["kind"], 0.5) + 0.5 ** (age_days / 30.0)
    p = rec["body"].get("path") if rec["kind"] == "path" else None
    if cwd and p and resolve_path(p).startswith(cwd.rstrip("/") + "/"):
        s += 1.0
    return s


def matches(entry, terms, any_mode=False):
    if not terms:
        return True
    hay = " ".join(_haystacks(entry["rec"]))
    return any(t in hay for t in terms) if any_mode else all(t in hay for t in terms)


def is_standing_relevant(rec):
    """Recall always surfaces what applies to the whole project, whatever the task words are."""
    return (rec["kind"] in ("constraint", "correction")
            or (rec["kind"] == "warning" and rec["body"].get("status") == "open")
            or (rec["kind"] == "task" and rec["body"].get("status") == "open"))


def search(store, query="", kind=None, tag=None, path_prefix=None, status=None, limit=10, verify=False,
           project=None, all_projects=False, for_recall=False, cwd=None):
    ld = store.load()
    entries = store.view(ld, project=project, verify=verify, all_projects=all_projects)
    terms = _terms(query)
    out = []
    for e in entries:
        r = e["rec"]
        if kind and r["kind"] != kind:
            continue
        if tag and tag not in r["tags"]:
            continue
        if status and e["status"] != status:
            continue
        if path_prefix:
            p = portable_path(path_prefix)
            cand = r["body"].get("path") or r["subject"]
            if not str(cand).startswith(p):
                continue
        if for_recall and ((r["kind"] == "warning" and r["body"].get("status") == "resolved") or
                           (r["kind"] == "task" and r["body"].get("status") != "open")):
            continue
        if for_recall:
            if not (is_standing_relevant(r) or matches(e, terms, any_mode=True)):
                continue
        elif not matches(e, terms):
            continue
        e["score"] = score(e, terms, store.now(), cwd)
        out.append(e)
    out.sort(key=lambda e: (-e["score"], e["rec"]["id"]))
    return out[:limit], len(entries), ld


def age(ms, now):
    d = max(0, now - ms) // 1000
    for unit, secs in (("d", 86400), ("h", 3600), ("m", 60)):
        if d >= secs:
            return "%d%s" % (d // secs, unit)
    return "now"


def fmt_entry(e, now):
    r = e["rec"]
    extra = ""
    if r["scope"]["host"] != "*":
        extra += "; host=" + clean(r["scope"]["host"])
    line = "%s  %-10s %s: %s  [%s; %s%s]" % (r["id"][:10], r["kind"], clean(r["subject"]), clean(r["text"]), e["status"], age(r["hlc"]["t"], now), extra)
    if e["alternatives"]:
        line += "\n    alternatives: " + ", ".join(a[:10] for a in e["alternatives"])
    return line


def summary_line(entries, total, store):
    counts = {}
    for e in entries:
        counts[e["status"]] = counts.get(e["status"], 0) + 1
    parts = ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts)) or "none"
    return "swmem: %d shown (%s); %d visible in project; store %s" % (len(entries), parts, total, store.info()["store_id"])


# --------------------------------------------------------------------------- CLI

def _parse_ttl(s):
    m = re.match(r"^(\d+)([dhm])$", s or "")
    if not m:
        raise Refused("ttl-format")
    ms = int(m.group(1)) * {"d": 86400000, "h": 3600000, "m": 60000}[m.group(2)]
    if ms < 60000 or ms > 365 * 86400000:
        raise Refused("ttl-range")
    return ms


def _body_from_sets(kind, sets):
    body = {}
    for item in sets:
        if "=" not in item:
            raise Refused("set-format")
        k, v = item.split("=", 1)
        if k == "remaining":
            body.setdefault("remaining", []).append(v)
        elif k in ("criteria_met", "criteria_total"):
            if not v.isdigit():
                raise Refused("body-shape")
            body[k] = int(v)
        else:
            body[k] = v
    return body


def _fp_from_arg(arg):
    if not arg:
        return None
    if ":" not in arg:
        raise Refused("fingerprint-format")
    kind, ref = arg.split(":", 1)
    try:
        value = fingerprint_value(kind, ref)
    except Refused:
        raise
    if value is None:
        raise Refused("fingerprint-target-missing")
    return {"kind": kind, "ref": ref, "value": value}


def build_parser():
    p = argparse.ArgumentParser(prog="swmem", description="StepWise Contextual Memory Sync")
    p.add_argument("--store", default=None)
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("init")
    for name in ("recall", "search"):
        a = sub.add_parser(name)
        if name == "search":
            a.add_argument("query", nargs="?", default="")
        else:
            a.add_argument("--context", default="")
        a.add_argument("--kind", choices=KINDS); a.add_argument("--tag"); a.add_argument("--path")
        a.add_argument("--status"); a.add_argument("--limit", type=int, default=10)
        a.add_argument("--verify", action="store_true"); a.add_argument("--all-projects", action="store_true")
        a.add_argument("--project", default=None)
    a = sub.add_parser("show"); a.add_argument("id")
    a = sub.add_parser("add"); a.add_argument("kind", choices=KINDS)
    a.add_argument("--trust", required=True, choices=TRUSTS); a.add_argument("--subject"); a.add_argument("--text")
    a.add_argument("--risk"); a.add_argument("--tag", action="append", default=[]); a.add_argument("--set", action="append", default=[])
    a.add_argument("--fp"); a.add_argument("--ttl"); a.add_argument("--supersedes", action="append", default=[])
    a.add_argument("--no-supersede", action="store_true"); a.add_argument("--dry-run", action="store_true")
    a.add_argument("--session"); a.add_argument("--ledger"); a.add_argument("--project"); a.add_argument("--host")
    a = sub.add_parser("retract"); a.add_argument("id"); a.add_argument("--reason")
    a = sub.add_parser("verify"); a.add_argument("ids", nargs="*"); a.add_argument("--project"); a.add_argument("--all-projects", action="store_true")
    sub.add_parser("status")
    a = sub.add_parser("export"); a.add_argument("--since", type=int, default=0)
    a = sub.add_parser("import"); a.add_argument("file")
    sub.add_parser("rotate-replica")
    a = sub.add_parser("risk-class"); a.add_argument("label")
    sub.add_parser("risk-labels")
    return p


def main(argv=None, store=None, out=None, err=None):
    old = os.umask(0o077)
    try:
        return _main(argv, store, out, err)
    finally:
        os.umask(old)


def _main(argv, store, out, err):
    out, err = out or sys.stdout, err or sys.stderr
    args = build_parser().parse_args(argv)
    if not args.cmd:
        build_parser().print_usage(err)
        return 2
    if args.cmd == "risk-class":
        if args.label == "-":                       # one label per line on stdin, one class per line out
            for line in sys.stdin.read().split("\n")[:-1]:
                print(risk_class(line), file=out)
        else:
            print(risk_class(args.label), file=out)
        return 0
    if args.cmd == "risk-labels":
        for label in sorted(_ELIGIBLE):
            print("eligible " + label, file=out)
        for sub_str in _SENSITIVE:
            print("sensitive " + sub_str, file=out)
        return 0
    st = store or Store(args.store)
    try:
        return _run(args, st, out, err)
    except Refused as e:
        print("swmem: refused: %s" % e, file=err)
        if str(e) == "store-not-initialised":
            print("swmem: run 'swmem init' first", file=err)
        return 1


def _run(args, st, out, err):
    p = lambda *a: print(*a, file=out)
    if args.cmd == "init":
        created = st.init()
        st.replica_state()
        p("swmem: %s store %s (id %s), replica %s" % ("created" if created else "found", clean(st.root), st.info()["store_id"], st.replica_state()["replica"]))
        return 0
    st.info()
    if args.cmd in ("recall", "search"):
        query = args.context if args.cmd == "recall" else args.query
        entries, total, ld = search(st, query, args.kind, args.tag, args.path, args.status, max(1, min(args.limit, 50)),
                                    args.verify, args.project, args.all_projects, for_recall=(args.cmd == "recall"), cwd=os.getcwd())
        for e in entries:
            p(fmt_entry(e, st.now()))
        p(summary_line(entries, total, st))
        return 0
    if args.cmd == "show":
        ld = st.load()
        rid = st.resolve_id(args.id, ld)
        r = ld.records[rid]
        e = next((x for x in st.view(ld, all_projects=True, verify=True) if x["rec"]["id"] == rid), None)
        p("id:      " + rid)
        for k in ("op", "kind", "trust", "subject", "text"):
            p("%-8s %s" % (k + ":", clean(r[k])))
        p("scope:   project=%s host=%s" % (clean(r["scope"]["project"]), clean(r["scope"]["host"])))
        p("tags:    " + clean(", ".join(r["tags"])))
        p("body:    " + clean(json.dumps(r["body"], sort_keys=True)))
        p("written: %s (hlc %d.%d.%s)" % (utc(r["hlc"]["t"]), r["hlc"]["t"], r["hlc"]["c"], r["hlc"]["r"]))
        p("valid:   until=%s fp=%s" % (r["valid"]["until"], clean(json.dumps(r["valid"]["fp"], sort_keys=True))))
        p("status:  " + (("%s (%s)" % (e["status"], e["detail"])) if e else "superseded or retracted"))
        return 0
    if args.cmd == "add":
        kind = args.kind
        body = _body_from_sets(kind, args.set)
        subject, text = args.subject, args.text
        if kind == "path":
            if "path" not in body:
                raise Refused("body-shape")
            body["path"] = portable_path(body["path"])
            subject = subject or body["path"]
            text = text or "%s %s" % (body.get("role", "touched"), body["path"])
        if not subject or not text:
            raise Refused("subject-and-text-required")
        ttl = _parse_ttl(args.ttl) if args.ttl else (FACT_TTL_DAYS * 86400000 if kind == "fact" else None)
        rec = st.add(kind, args.trust, subject, text, args.tag, body, args.risk, _fp_from_arg(args.fp), ttl,
                     args.supersedes, not args.no_supersede, args.session, args.ledger, args.project, args.host, dry_run=args.dry_run)
        if args.dry_run:
            p(clean(json.dumps(rec, sort_keys=True)))
            p("swmem: dry run, nothing written")
        else:
            p("saved %s (%s %s)" % (rec["id"][:10], kind, clean(subject)))
        return 0
    if args.cmd == "retract":
        rec = st.retract(args.id, args.reason)
        p("retracted %s (record %s)" % (rec["retracts"][:10], rec["id"][:10]))
        return 0
    if args.cmd == "verify":
        ld = st.load()
        entries = st.view(ld, project=args.project, verify=True, all_projects=args.all_projects)
        if args.ids:
            want = {st.resolve_id(i, ld) for i in args.ids}
            entries = [e for e in entries if e["rec"]["id"] in want]
        entries.sort(key=lambda e: e["rec"]["id"])
        for e in entries:
            p("%s  %-10s %-10s %s" % (e["rec"]["id"][:10], e["rec"]["kind"], e["status"], clean(e["detail"])))
        p(summary_line(entries, len(entries), st))
        return 0
    if args.cmd == "status":
        return _status(st, out)
    if args.cmd == "export":
        for line in st.export_lines(args.since):
            p(line)
        return 0
    if args.cmd == "import":
        try:
            with open(args.file, "rb") as f:
                data = f.read()
        except OSError:
            raise Refused("cannot-read-file")
        total, new, dropped = st.import_bundle(data)
        p("swmem: imported %d record(s), %d new to this store, %d line(s) dropped as invalid" % (total, new, dropped))
        return 0
    if args.cmd == "rotate-replica":
        old, new = st.rotate_replica()
        p("swmem: replica %s -> %s (the old file stays and is still read)" % (old, new))
        return 0
    return 2


def _status(st, out):
    p = lambda *a: print(*a, file=out)
    ld = st.load()
    state = st.replica_state()
    mine = st.replica_file(state["replica"])
    ids = ld.file_ids.get(mine, [])
    now = st.now()
    problems = []
    p("store:    %s (id %s)" % (clean(st.root), st.info()["store_id"]))
    p("replica:  %s on host %s" % (state["replica"], st.host))
    p("records:  %d valid" % len(ld.records))
    for path, meta in sorted(ld.files.items()):
        rel = os.path.relpath(path, st.root)
        note = "".join(" %s=%d" % (k, meta[k]) for k in ("torn", "invalid", "tampered", "unsupported") if meta[k])
        p("  %-34s %5d records%s" % (rel, meta["count"], note))
        if meta["tampered"]:
            problems.append("%s has %d tampered record(s)" % (rel, meta["tampered"]))
    if state["count"] > len(ids) or (state["head"] and state["head"] not in ids):
        problems.append("REGRESSION: this machine wrote %d record(s) to its replica file but it now holds %d. A sync tool may have restored an older copy" % (state["count"], len(ids)))
    for rid in ld.chain_breaks:
        problems.append("chain break at %s (a record before it is missing or reordered)" % rid[:10])
    for r, prev in ld.forks:
        problems.append("FORK: replica %s has two records after %s (two machines share a replica id; run rotate-replica on one)" % (r, (prev or "start")[:10]))
    future = [r for r in ld.records.values() if r["hlc"]["t"] > now + FUTURE_SKEW_MS]
    if future:
        p("note: %d record(s) are dated more than a day in the future (suspect; they cannot win or hide others)" % len(future))
    if any(m["torn"] for m in ld.files.values()):
        p("note: a torn final line was ignored (a write in progress or a copy made mid-append); it completes on the next sync")
    for x in problems:
        p("problem: " + x)
    p("integrity: " + ("PROBLEMS FOUND" if problems else "ok"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
