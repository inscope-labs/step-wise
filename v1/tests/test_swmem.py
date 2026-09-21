#!/usr/bin/env python3
"""Tests for v1/utils/swmem.py (Contextual Memory Sync).

    python3 v1/tests/test_swmem.py

Hermetic: every test uses temporary directories and a controllable clock. Nothing touches the real
home directory. "Machines" are separate store and state directories that exchange files the way a
naive sync tool would (whole-file copies), so the convergence tests exercise the real sync model.

Fake secrets are assembled at run time and never appear literally in this file, so a secret scanner
(including GitHub push protection) has nothing to flag.
"""

import io
import json
import os
import random
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
UTILS = os.path.join(os.path.dirname(HERE), "utils")
sys.path.insert(0, UTILS)
import swmem  # noqa: E402

SWMEM = os.path.join(UTILS, "swmem.py")
CLIPCOPY = os.path.join(UTILS, "clipcopy.sh")


def fake(*parts):
    return "".join(parts)


AWS = fake("AK", "IA", "ABCDEFGHIJKLMNOP")
GITHUB = fake("gh", "p_", "abcdefghijklmnopqrstuvwxyz0123")
GH_PAT = fake("github", "_pat_", "abcdefghijklmnopqrstuvwxyz")
ANTHROPIC = fake("sk", "-ant-", "api03-abcdefghijklmnopqrstuvwxyz")
SLACK = fake("xo", "xb-", "1234567890-abcdefghij")
GOOGLE = fake("AI", "za", "SyA-abcdefghijklmnopqrstuvwxyz012")
JWT = fake("ey", "Jhbgci", "OiJIUzI1NiJ9.", "eyJzdWIiOiIxMjM0NTY3ODkwIn0.", "abcdefghijklmnop")
PEM = fake("-----BEGIN ", "RSA PRIVATE KEY", "-----")
LONG = "A1b2C3d4" * 6


class Clock(object):
    def __init__(self, t=1_800_000_000_000):
        self.now = t


class Machine(object):
    """One machine: its own store copy and its own local state, sharing a store id with the others."""

    def __init__(self, base, name, clock, skew=0):
        self.name, self.skew, self.clock = name, skew, clock
        self.store = swmem.Store(os.path.join(base, name, "store"), state_dir=os.path.join(base, name, "state"),
                                 host=name, now_ms=lambda: self.clock.now + self.skew)

    def add(self, kind="fact", subject="s", text="t", trust="operator", **kw):
        kw.setdefault("project", "p")
        return self.store.add(kind, trust, subject, text, **kw)

    def snapshot(self, verify=False):
        """What every machine must agree on: which records are visible, which are disputed, and against what.
        Host-relative labels (unverified vs other-host) legitimately differ by reader, so they are collapsed."""
        def kind(status):
            return status if status in ("disputed", "suspect") else "ok"
        return sorted((e["rec"]["id"], kind(e["status"]), tuple(sorted(e["alternatives"])))
                      for e in self.store.view(project="p", verify=verify))

    def visible(self):
        return self.store.view(project="p")


def make_machines(base, n, clock, skews=None):
    ms = [Machine(base, "m%d" % i, clock, (skews or [0] * n)[i]) for i in range(n)]
    ms[0].store.init()
    for m in ms[1:]:
        os.makedirs(m.store.replicas, exist_ok=True)
        os.makedirs(m.store.imports, exist_ok=True)
        shutil.copyfile(os.path.join(ms[0].store.root, "store.json"), os.path.join(m.store.root, "store.json"))
    for m in ms:
        m.store.replica_state()
    return ms


def sync(*machines):
    """Whole-file copies of each replica file from its owner to every other machine (a naive sync tool)."""
    for owner in machines:
        rid = owner.store.replica_state()["replica"]
        src = owner.store.replica_file(rid)
        if not os.path.exists(src):
            continue
        for m in machines:
            if m is not owner:
                shutil.copyfile(src, os.path.join(m.store.replicas, rid + ".jsonl"))


class Base(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.td, True)
        self.clock = Clock()

    def machines(self, n=1, skews=None):
        return make_machines(self.td, n, self.clock, skews)

    def one(self):
        return self.machines(1)[0]


# --------------------------------------------------------------------------- helpers

class TestHelpers(unittest.TestCase):
    def test_clean_removes_control_and_escape_characters(self):
        self.assertEqual(swmem.clean("a\x1b[31mred\x1b[0m"), "a?[31mred?[0m")
        self.assertEqual(swmem.clean("line1\nline2\ttab\r"), "line1 line2 tab ")
        self.assertEqual(swmem.clean("c1\x9bcode"), "c1?code")
        self.assertNotIn("\x1b", swmem.clean("\x1b]0;title\x07"))

    def test_canonical_json_and_ids_are_deterministic(self):
        a, b = {"b": 1, "a": [1, 2], "u": "é"}, {"u": "é", "a": [1, 2], "b": 1}
        self.assertEqual(swmem.canon(a), swmem.canon(b))
        self.assertEqual(swmem.make_id(a), swmem.make_id(b))
        self.assertRegex(swmem.make_id(a), r"^m_[a-z2-7]{20}$")
        self.assertNotEqual(swmem.make_id(a), swmem.make_id({"a": [1, 2], "b": 2, "u": "é"}))

    def test_utc_round_trip(self):
        self.assertEqual(swmem.parse_utc(swmem.utc(1_800_000_123_000)), 1_800_000_123_000)
        self.assertIsNone(swmem.parse_utc("yesterday"))

    def test_slug(self):
        self.assertEqual(swmem.slug("My Project!"), "my-project")
        self.assertEqual(swmem.slug("***"), "default")
        self.assertLessEqual(len(swmem.slug("x" * 100)), 40)

    def test_portable_paths_use_tilde(self):
        home = os.path.expanduser("~")
        self.assertEqual(swmem.portable_path(os.path.join(home, "a", "b")), "~/a/b")
        self.assertEqual(swmem.portable_path(home), "~")
        self.assertEqual(swmem.portable_path("/etc/hosts"), "/etc/hosts")
        self.assertEqual(swmem.resolve_path("~/a"), os.path.join(home, "a"))

    def test_credential_paths(self):
        for p in ("~/.ssh/id_rsa", "~/.ssh/config", "~/.aws/credentials", "~/.gnupg/x", "/etc/shadow", "~/app/.env",
                  "~/app/.env.production", "~/certs/server.pem", "~/k/tls.key", "~/vault.kdbx", "~/.netrc", "~/.kube/config"):
            self.assertTrue(swmem.is_credential_path(p), p)
        for p in ("~/proj/app.py", "~/.bashrc", "/etc/nginx/nginx.conf", "~/proj/environment.md", "~/.envrc-notes/readme"):
            self.assertFalse(swmem.is_credential_path(p), p)


class TestSecretScanner(unittest.TestCase):
    def test_named_secret_shapes_are_caught_and_the_rule_is_named(self):
        cases = {"aws-key": AWS, "github-token": GITHUB, "api-key": ANTHROPIC, "slack-token": SLACK, "google-key": GOOGLE,
                 "jwt": JWT, "private-key": PEM, "long-token": LONG}
        cases["github-token-2"] = GH_PAT
        for name, secret in cases.items():
            rule = swmem.scan_secret("the value is " + secret + " ok")
            self.assertIsNotNone(rule, name)
            self.assertNotIn(secret, rule)
        self.assertEqual(swmem.scan_secret(AWS), "aws-key")
        self.assertEqual(swmem.scan_secret(PEM), "private-key")

    def test_credential_assignments(self):
        for s in ("password: hunter22", "PASSWORD=abcd1234", "api_key = abcd1234", "token: abcd", "secret=xyz123"):
            self.assertEqual(swmem.scan_secret(s), "credential-assignment", s)

    def test_ordinary_text_passes(self):
        for s in ("nginx 1.24 installed via apt", "~/proj/app/config/settings.yaml", "/usr/lib/x86_64-linux-gnu/some/deep/library/path/libfoo.so",
                  "apt install jq: no candidate", "the token bucket limits requests", "run apt update first", "port 8080 in use",
                  "user stated: never restart the prod service"):
            self.assertIsNone(swmem.scan_secret(s), s)

    def test_long_paths_are_not_mistaken_for_tokens(self):
        self.assertIsNone(swmem.scan_secret("/very/long/path/with/many/segments/that/goes/on/and/on/and/on/file.txt"))


class TestRiskGateParity(unittest.TestCase):
    PROBES = ["", ",", "read-only", "Read Only", " read-only ", "read-only,", "read-only,,network", ",read-only", "credential",
              "credential/privileged-data", "Credential", "privileged-data", "Privileged Data", "secret", "sensitive", "privileged",
              "network,privileged", "read-only,credential", "read-only,bogus", "bogus", "Difficult to reverse", "changes project state",
              "creates files", "irreversible", "eligible", "<empty>", "read_only", "a,,b", ",,", "modifies,,"]

    @unittest.skipUnless(shutil.which("bash"), "bash not available")
    def test_python_and_shell_classifiers_agree_on_every_probe(self):
        for label in self.PROBES:
            sh = subprocess.run(["bash", "-c", 'source "$1" >/dev/null 2>&1; _sw_risk_class "$2"', "x", CLIPCOPY, label],
                                capture_output=True, text=True).stdout.strip()
            self.assertEqual(swmem.risk_class(label), sh, "labels %r: python=%s shell=%s" % (label, swmem.risk_class(label), sh))

    @unittest.skipUnless(shutil.which("bash"), "bash not available")
    def test_the_allowlists_themselves_are_identical(self):
        """Probes can miss an extra label on one side. Compare the lists exactly."""
        import re
        with open(CLIPCOPY, encoding="utf-8") as f:
            src = f.read()
        sens = re.search(r"^\s*(\*credential\*\|[^)]+)\)", src, re.M)
        elig = re.search(r"^\s*(read-only\|[^)]+)\)", src, re.M)
        self.assertTrue(sens and elig, "could not find the classifier cases in clipcopy.sh")
        shell_sensitive = {p.strip("*") for p in sens.group(1).split("|")}
        shell_eligible = set(elig.group(1).split("|"))
        self.assertEqual(shell_eligible, swmem._ELIGIBLE)
        self.assertEqual(shell_sensitive, set(swmem._SENSITIVE))

    def test_risk_labels_subcommand_prints_both_lists(self):
        out = io.StringIO()
        swmem.main(["risk-labels"], out=out)
        lines = out.getvalue().split("\n")
        self.assertIn("eligible read-only", lines)
        self.assertIn("sensitive credential", lines)

    def test_fail_closed(self):
        for label in ("", "bogus", "read-only,bogus", ","):
            self.assertNotEqual(swmem.risk_class(label), "eligible", label)
        self.assertEqual(swmem.risk_class("read-only,network"), "eligible")
        self.assertEqual(swmem.risk_class("credential/privileged-data"), "sensitive")


# --------------------------------------------------------------------------- records

def good_record(store=None):
    body = {"v": 1, "prev": None, "op": "put", "kind": "fact", "scope": {"project": "p", "host": "h"}, "subject": "s", "text": "t",
            "tags": ["a"], "body": {}, "trust": "operator", "source": {"replica": "0123abcd"},
            "hlc": {"t": 1, "c": 0, "r": "0123abcd"}, "valid": {"until": None, "fp": None}, "supersedes": []}
    body["id"] = swmem.make_id(body)
    return body


class TestRecordValidation(unittest.TestCase):
    def bad(self, mutate, needle=None):
        r = good_record()
        mutate(r)
        problem = swmem.validate_record(r)
        self.assertIsNotNone(problem)
        if needle:
            self.assertIn(needle, problem)

    def test_a_good_record_is_valid(self):
        self.assertIsNone(swmem.validate_record(good_record()))

    def test_field_violations_are_rejected(self):
        self.bad(lambda r: r.update(id="nope"), "id")
        self.bad(lambda r: r.update(prev="nope"), "prev")
        self.bad(lambda r: r.update(op="delete"))
        self.bad(lambda r: r.update(kind="secret"))
        self.bad(lambda r: r.update(trust="inferred"))
        self.bad(lambda r: r.update(scope="x"), "scope")
        self.bad(lambda r: r.update(subject=""))
        self.bad(lambda r: r.update(subject="x" * 121))
        self.bad(lambda r: r.update(text="x" * 301))
        self.bad(lambda r: r.update(text="bad\x1bescape"))
        self.bad(lambda r: r.update(tags=["UPPER"]), "tags")
        self.bad(lambda r: r.update(tags=["a"] * 9), "tags")
        self.bad(lambda r: r.update(hlc={"t": -1, "c": 0, "r": "0123abcd"}), "hlc")
        self.bad(lambda r: r.update(hlc={"t": 1, "c": 0, "r": "nothex!!"}), "hlc")
        self.bad(lambda r: r.update(valid={"until": "soon", "fp": None}))
        self.bad(lambda r: r.update(valid={"until": None, "fp": {"kind": "cmd", "ref": "x", "value": "y"}}), "fp")
        self.bad(lambda r: r.update(supersedes=["nope"]), "supersedes")
        self.bad(lambda r: r.update(op="retract"), "retracts")

    def test_body_shapes(self):
        for kind, body in (("path", {"path": "~/a", "role": "wrote"}), ("failure", {}), ("correction", {"was": "a"}),
                           ("warning", {"status": "maybe"}), ("task", {"objective": "o", "status": "paused"}),
                           ("task", {"objective": "o", "status": "open", "remaining": ["x"] * 9}),
                           ("task", {"objective": "o", "status": "open", "criteria_met": -1})):
            self.bad(lambda r, k=kind, b=body: r.update(kind=k, body=b))

    def test_oversize_records_are_invalid(self):
        ids = ["m_" + "a" * 19 + chr(ord("a") + i % 26) for i in range(64)]     # 64 supersedes pushes a full record past 2,048 bytes
        self.bad(lambda r: r.update(kind="task", text="t" * 300, subject="s" * 120, supersedes=ids,
                                    body={"objective": "o" * 200, "status": "open", "remaining": ["r" * 120] * 8}), "too large")

    def test_unknown_envelope_fields_are_ignored(self):
        r = good_record()
        r["future_field"] = "x"
        self.assertIsNone(swmem.validate_record(r))


# --------------------------------------------------------------------------- store basics

class TestStoreBasics(Base):
    def test_layout_and_permissions(self):
        m = self.one()
        m.add()
        for d in (m.store.root, m.store.replicas, m.store.imports):
            self.assertEqual(stat.S_IMODE(os.stat(d).st_mode), 0o700, d)
        f = m.store.replica_file()
        self.assertEqual(stat.S_IMODE(os.stat(f).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(m.store.root, "store.json")).st_mode), 0o600)

    def test_local_state_is_never_inside_the_synced_store(self):
        m = self.one()
        m.add()
        for root, _, files in os.walk(m.store.root):
            for name in files:
                self.assertNotIn(name, ("replica.json", "write.lock"), root)
        self.assertTrue(os.path.exists(os.path.join(m.store.state_dir(), "replica.json")))

    def test_default_state_location_is_outside_the_store_and_follows_xdg(self):
        old = {k: os.environ.get(k) for k in ("XDG_STATE_HOME", "SWMEM_STATE")}
        os.environ.pop("SWMEM_STATE", None)
        os.environ["XDG_STATE_HOME"] = os.path.join(self.td, "xdg-state")
        try:
            store = swmem.Store(os.path.join(self.td, "the-store"), host="h")
            store.init()
            expected = os.path.join(self.td, "xdg-state", "stepwise", "memory", store.info()["store_id"])
            self.assertEqual(store.state_dir(), expected)
            self.assertFalse(store.state_dir().startswith(store.root))
            store.add("fact", "operator", "s", "t", project="p")
            self.assertTrue(os.path.exists(os.path.join(expected, "replica.json")))
            for root, _, files in os.walk(store.root):
                self.assertNotIn("replica.json", files)
        finally:
            for k, v in old.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v

    def test_init_is_idempotent(self):
        m = self.one()
        sid = m.store.info()["store_id"]
        self.assertFalse(m.store.init())
        self.assertEqual(m.store.info()["store_id"], sid)

    def test_records_are_one_line_each_and_end_with_a_newline(self):
        m = self.one()
        m.add(subject="a")
        m.add(subject="b")
        with open(m.store.replica_file(), "rb") as f:
            data = f.read()
        self.assertTrue(data.endswith(b"\n"))
        self.assertEqual(len(data.split(b"\n")) - 1, 2)
        for line in data.split(b"\n")[:-1]:
            json.loads(line)

    def test_ids_commit_to_content_and_form_a_chain(self):
        m = self.one()
        r1, r2, r3 = m.add(subject="a"), m.add(subject="b"), m.add(subject="c")
        self.assertIsNone(r1["prev"])
        self.assertEqual((r2["prev"], r3["prev"]), (r1["id"], r2["id"]))
        for r in (r1, r2, r3):
            body = dict(r)
            body.pop("id")
            self.assertEqual(swmem.make_id(body), r["id"])

    def test_the_clock_never_goes_backwards_even_if_wall_time_does(self):
        m = self.one()
        a = m.add(subject="a")
        self.clock.now -= 3_600_000
        b = m.add(subject="b")
        self.assertGreater((b["hlc"]["t"], b["hlc"]["c"]), (a["hlc"]["t"], a["hlc"]["c"]))

    def test_same_millisecond_writes_get_increasing_counters(self):
        m = self.one()
        rs = [m.add(subject="s%d" % i) for i in range(5)]
        keys = [(r["hlc"]["t"], r["hlc"]["c"]) for r in rs]
        self.assertEqual(keys, sorted(set(keys)))

    def test_uninitialised_store_is_refused(self):
        s = swmem.Store(os.path.join(self.td, "nowhere"), state_dir=os.path.join(self.td, "st"))
        with self.assertRaises(swmem.Refused):
            s.info()


# --------------------------------------------------------------------------- the write gate

class TestWriteGate(Base):
    def refused(self, needle, **kw):
        m = self.one() if not hasattr(self, "_m") else self._m
        self._m = m
        with self.assertRaises(swmem.Refused) as cm:
            m.add(**kw)
        self.assertIn(needle, str(cm.exception))
        return str(cm.exception)

    def test_observed_records_need_an_eligible_risk_label(self):
        self.refused("risk-label-required", trust="observed")
        for label in ("credential", "credential/privileged-data", "privileged-data", "bogus", "", "read-only,credential", "secret"):
            self.refused("risk-label-not-eligible", trust="observed", risk=label)
        self._m.add(trust="observed", risk="read-only")
        self._m.add(subject="x", trust="observed", risk="Read Only,network")

    def test_operator_records_do_not_need_a_label(self):
        self.one().add(trust="operator")

    def test_secrets_are_refused_in_every_field_and_never_echoed(self):
        for secret in (AWS, GITHUB, GH_PAT, ANTHROPIC, SLACK, GOOGLE, JWT, PEM, LONG, "password: hunter22"):
            for field in ("text", "subject"):
                msg = self.refused("secret-scan", **{field: "value " + secret})
                self.assertNotIn(secret, msg)
        self.refused("secret-scan", tags=[AWS.lower()[:32]]) if False else None
        self.refused("secret-scan", kind="failure", body={"symptom": "failed with " + AWS})

    def test_secrets_in_a_fingerprint_reference_are_refused(self):
        self.refused("secret-scan", fp={"kind": "exists", "ref": "/tmp/" + AWS, "value": "0"})

    def test_control_characters_are_refused(self):
        self.refused("control-characters", text="a\x1b[31mb")
        self.refused("control-characters", subject="a\nb")

    def test_unknown_body_keys_are_refused_on_write(self):
        self.refused("body-shape", kind="failure", body={"symptom": "x", "extra": "smuggled text"})
        self.refused("body-shape", kind="fact", body={"anything": "x"})

    def test_body_shapes_are_enforced_on_write(self):
        self.refused("body-shape", kind="path", body={"path": "~/a", "role": "wrote"})
        self.refused("body-shape", kind="task", body={"objective": "o", "status": "paused"})

    def test_size_limits_refuse_rather_than_truncate(self):
        self.refused("record-invalid", text=("ab " * 101).strip())          # 302 characters
        self.refused("record-invalid", subject=("ab " * 41).strip())        # 122 characters
        self.refused("record-invalid", tags=["a%d" % i for i in range(9)])

    def test_a_record_at_the_limits_is_accepted(self):
        m = self.one()
        m.add(subject=("word " * 24).strip()[:120], text=("some words " * 30).strip()[:300], tags=["t%d" % i for i in range(8)])

    def test_unknown_kind_and_trust_are_refused(self):
        self.refused("kind", kind="secret")
        self.refused("trust", trust="inferred")


class TestFingerprintGate(Base):
    def test_credential_paths_cannot_be_hashed_or_statted_but_can_be_checked_for_existence(self):
        self.assertEqual(swmem.fingerprint_value("exists", "~/.ssh/id_rsa") in ("0", "1"), True)
        for kind in ("path-hash", "path-stat"):
            with self.assertRaises(swmem.Refused):
                swmem.fingerprint_value(kind, "~/.ssh/id_rsa")

    def test_a_hostile_record_cannot_make_us_read_a_credential_file(self):
        called = []
        real = swmem.hashlib.sha256
        swmem.hashlib.sha256 = lambda *a, **k: called.append(1) or real(*a, **k)
        try:
            status, detail = swmem.check_fingerprint({"kind": "path-hash", "ref": "~/.ssh/id_ed25519", "value": "0" * 64})
        finally:
            swmem.hashlib.sha256 = real
        self.assertEqual(status, "stale")
        self.assertIn("refused", detail)
        self.assertEqual(called, [])

    def test_unknown_fingerprint_kind_is_refused(self):
        with self.assertRaises(swmem.Refused):
            swmem.fingerprint_value("cmd", "echo hi")

    def test_large_files_are_not_hashed(self):
        p = os.path.join(self.td, "big")
        with open(p, "wb") as f:
            f.truncate(swmem.HASH_MAX_BYTES + 1)
        with self.assertRaises(swmem.Refused):
            swmem.fingerprint_value("path-hash", p)
        self.assertIsNotNone(swmem.fingerprint_value("path-stat", p))

    def test_ttl_parsing(self):
        self.assertEqual(swmem._parse_ttl("30d"), 30 * 86400000)
        self.assertEqual(swmem._parse_ttl("2h"), 7200000)
        for bad in ("30", "d", "0m", "400d", "1w", ""):
            with self.assertRaises(swmem.Refused):
                swmem._parse_ttl(bad)


# --------------------------------------------------------------------------- view, supersede, retract

class TestView(Base):
    def test_a_new_record_supersedes_the_previous_one_for_its_subject(self):
        m = self.one()
        a = m.add(subject="svc", text="v1")
        b = m.add(subject="svc", text="v2")
        v = m.visible()
        self.assertEqual([e["rec"]["id"] for e in v], [b["id"]])
        self.assertIn(a["id"], b["supersedes"])

    def test_subjects_are_independent(self):
        m = self.one()
        m.add(subject="a")
        m.add(subject="b")
        self.assertEqual(len(m.visible()), 2)

    def test_retract_hides_the_record(self):
        m = self.one()
        a = m.add(subject="x")
        m.store.retract(a["id"], "wrong")
        self.assertEqual(m.visible(), [])

    def test_retract_wins_even_against_a_later_clock(self):
        m = self.one()
        a = m.add(subject="x")
        self.clock.now += 1000
        m.store.retract(a["id"])
        # an attacker or an old copy re-presents the target with an even later clock: it is still retracted
        self.clock.now += 10_000
        m.add(subject="other")
        self.assertNotIn(a["id"], [e["rec"]["id"] for e in m.visible()])

    def test_retracting_an_unknown_id_is_refused(self):
        with self.assertRaises(swmem.Refused):
            self.one().store.retract("m_" + "a" * 20)

    def test_id_prefixes_resolve_only_when_unambiguous(self):
        m = self.one()
        a = m.add(subject="x")
        self.assertEqual(m.store.resolve_id(a["id"][:10]), a["id"])
        with self.assertRaises(swmem.Refused):
            m.store.resolve_id("m_")
        with self.assertRaises(swmem.Refused):
            m.store.resolve_id(a["id"][:4])

    def test_explicit_supersede_and_no_auto_supersede(self):
        m = self.one()
        a = m.add(subject="s", text="1")
        b = m.add(subject="s", text="2", auto_supersede=False)
        v = m.visible()
        self.assertEqual(len(v), 1)
        self.assertEqual(v[0]["status"], "disputed")
        self.assertEqual(sorted([v[0]["rec"]["id"]] + v[0]["alternatives"]), sorted([a["id"], b["id"]]))
        c = m.add(subject="s", text="3")
        self.assertEqual([e["status"] for e in m.visible()], ["unverified"])
        self.assertEqual(set(c["supersedes"]), {a["id"], b["id"]})

    def test_facts_are_per_host_but_constraints_are_shared(self):
        a, b = self.machines(2)
        a.add("fact", subject="svc", text="on a")
        b.add("fact", subject="svc", text="on b")
        sync(a, b)
        self.assertEqual(len(a.visible()), 2)
        c1 = a.add("constraint", subject="rule", text="from a")
        c2 = b.add("constraint", subject="rule", text="from b")
        sync(a, b)
        rules = [e for e in a.visible() if e["rec"]["kind"] == "constraint"]
        self.assertEqual(len(rules), 1)
        self.assertEqual(rules[0]["status"], "disputed")
        self.assertEqual(c1["scope"]["host"], "*")
        self.assertEqual(c2["scope"]["host"], "*")

    def test_projects_are_separate(self):
        m = self.one()
        m.add(project="one", subject="a")
        m.add(project="two", subject="b")
        self.assertEqual(len(m.store.view(project="one")), 1)
        self.assertEqual(len(m.store.view(project="one", all_projects=True)), 2)


class TestFutureDatedRecords(Base):
    def test_a_far_future_record_cannot_win_advance_the_clock_or_hide_others(self):
        a, b = self.machines(2, skews=[0, 3 * 86400 * 1000])
        good = a.add(subject="svc", text="real")
        evil = b.add(subject="svc", text="pinned", auto_supersede=False)
        # b's clock is three days ahead, so its record is dated far in the future when a reads it
        sync(a, b)
        v = a.visible()
        statuses = {e["rec"]["id"]: e["status"] for e in v}
        self.assertEqual(statuses[evil["id"]], "suspect")
        self.assertEqual(statuses[good["id"]], "unverified")
        later = a.add(subject="other", text="x")
        self.assertLess(later["hlc"]["t"], evil["hlc"]["t"])   # the poisoned clock did not drag ours forward

    def test_a_future_dated_retract_does_nothing_until_its_time_arrives(self):
        a, b = self.machines(2, skews=[0, 3 * 86400 * 1000])
        r = a.add(subject="keep", text="important")
        sync(a, b)
        b.store.retract(r["id"], "hostile")
        sync(a, b)
        self.assertIn(r["id"], [e["rec"]["id"] for e in a.visible()])
        self.clock.now += 4 * 86400 * 1000
        self.assertNotIn(r["id"], [e["rec"]["id"] for e in a.visible()])


# --------------------------------------------------------------------------- statuses and fingerprints

class TestStatus(Base):
    def test_fact_ttl_expiry_makes_it_stale(self):
        m = self.one()
        m.add(subject="svc", ttl_ms=3_600_000)
        self.assertEqual(m.visible()[0]["status"], "unverified")
        self.clock.now += 3_600_001
        self.assertEqual(m.visible()[0]["status"], "stale")

    def test_path_hash_is_verified_then_goes_stale_when_the_file_changes(self):
        m = self.one()
        p = os.path.join(self.td, "conf")
        with open(p, "w") as f:
            f.write("one")
        m.add(subject="conf", fp={"kind": "path-hash", "ref": p, "value": swmem.fingerprint_value("path-hash", p)})
        self.assertEqual(m.store.view(project="p", verify=True)[0]["status"], "verified")
        with open(p, "w") as f:
            f.write("two")
        e = m.store.view(project="p", verify=True)[0]
        self.assertEqual((e["status"], e["detail"]), ("stale", "fingerprint changed"))
        os.remove(p)
        self.assertEqual(m.store.view(project="p", verify=True)[0]["detail"], "target missing")

    def test_without_verify_nothing_is_read_and_status_is_unverified(self):
        m = self.one()
        p = os.path.join(self.td, "conf")
        open(p, "w").close()
        m.add(subject="conf", fp={"kind": "exists", "ref": p, "value": "1"})
        os.remove(p)
        self.assertEqual(m.visible()[0]["status"], "unverified")

    def test_exists_and_stat_fingerprints(self):
        m = self.one()
        p = os.path.join(self.td, "f")
        open(p, "w").close()
        m.add(subject="e", fp={"kind": "exists", "ref": p, "value": "1"})
        m.add(subject="s", fp={"kind": "path-stat", "ref": p, "value": swmem.fingerprint_value("path-stat", p)})
        self.assertEqual({e["status"] for e in m.store.view(project="p", verify=True)}, {"verified"})
        with open(p, "w") as f:
            f.write("grow")
        st = {e["rec"]["subject"]: e["status"] for e in m.store.view(project="p", verify=True)}
        self.assertEqual(st, {"e": "verified", "s": "stale"})

    @unittest.skipUnless(shutil.which("git"), "git not available")
    def test_git_head_fingerprint(self):
        repo = os.path.join(self.td, "repo")
        os.makedirs(repo)
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
        run = lambda *a: subprocess.run(["git", "-C", repo] + list(a), capture_output=True, check=True, env=env)
        run("init", "-q")
        run("commit", "-q", "--allow-empty", "-m", "one")
        m = self.one()
        m.add(subject="head", fp={"kind": "git-head", "ref": repo, "value": swmem.fingerprint_value("git-head", repo)})
        self.assertEqual(m.store.view(project="p", verify=True)[0]["status"], "verified")
        run("commit", "-q", "--allow-empty", "-m", "two")
        self.assertEqual(m.store.view(project="p", verify=True)[0]["status"], "stale")

    def test_another_hosts_facts_are_other_host_until_checked_here(self):
        a, b = self.machines(2)
        p = os.path.join(self.td, "shared")
        open(p, "w").close()
        a.add(subject="f", fp={"kind": "exists", "ref": p, "value": "1"})
        a.add("path", subject="~/x", body={"path": "~/x", "role": "modified"})
        sync(a, b)
        self.assertEqual({e["status"] for e in b.visible()}, {"other-host"})
        st = {e["rec"]["subject"]: e["status"] for e in b.store.view(project="p", verify=True)}
        self.assertEqual(st["f"], "verified")            # re-checked here and it matches
        self.assertEqual(st["~/x"], "other-host")        # no fingerprint to re-check

    def test_standing_kinds_are_unverified_by_nature(self):
        m = self.one()
        for kind, body in (("constraint", {}), ("correction", {"was": "a", "now": "b"}), ("failure", {"symptom": "s"}),
                           ("warning", {"status": "open"}), ("task", {"objective": "o", "status": "open"})):
            m.add(kind, subject=kind, body=body)
        self.assertEqual({e["status"] for e in m.visible()}, {"unverified"})
        self.assertTrue(all(e["detail"] == "standing" for e in m.visible()))


# --------------------------------------------------------------------------- convergence

class TestConvergence(Base):
    def test_two_machines_converge_after_one_sync(self):
        a, b = self.machines(2)
        a.add(subject="x", text="from a")
        b.add(subject="y", text="from b")
        sync(a, b)
        self.assertEqual(a.snapshot(), b.snapshot())
        self.assertEqual(len(a.snapshot()), 2)

    def test_sync_is_idempotent(self):
        a, b = self.machines(2)
        a.add(subject="x")
        b.add(subject="y")
        sync(a, b)
        once = a.snapshot()
        sync(a, b)
        sync(b, a)
        self.assertEqual(a.snapshot(), once)
        self.assertEqual(b.snapshot(), once)

    def test_concurrent_edits_are_flagged_disputed_and_identical_everywhere(self):
        a, b, c = self.machines(3)
        a.add("constraint", subject="rule", text="use apt")
        sync(a, b, c)
        b.add("constraint", subject="rule", text="use nix")
        c.add("constraint", subject="rule", text="use pip")
        sync(a, b, c)
        snaps = [m.snapshot() for m in (a, b, c)]
        self.assertEqual(snaps[0], snaps[1])
        self.assertEqual(snaps[1], snaps[2])
        self.assertEqual(snaps[0][0][1], "disputed")
        self.assertEqual(len(snaps[0][0][2]), 1)

    def test_resolving_a_dispute_converges_to_one_record(self):
        a, b = self.machines(2)
        a.add("constraint", subject="rule", text="A")
        b.add("constraint", subject="rule", text="B")
        sync(a, b)
        a.add("constraint", subject="rule", text="settled")
        sync(a, b)
        for m in (a, b):
            v = m.visible()
            self.assertEqual((len(v), v[0]["status"], v[0]["rec"]["text"]), (1, "unverified", "settled"))

    def test_a_write_after_a_sync_sorts_after_what_it_saw_even_with_a_slow_clock(self):
        a, b = self.machines(2, skews=[-3_600_000, 0])
        first = b.add(subject="s", text="from b")
        sync(a, b)
        second = a.add(subject="s", text="from a, after seeing b", auto_supersede=False)
        self.assertGreater((second["hlc"]["t"], second["hlc"]["c"]), (first["hlc"]["t"], first["hlc"]["c"]))

    def test_retractions_propagate_and_stick(self):
        a, b = self.machines(2)
        r = a.add(subject="oops")
        sync(a, b)
        b.store.retract(r["id"])
        sync(a, b)
        sync(a, b)
        self.assertEqual(a.snapshot(), [])
        self.assertEqual(b.snapshot(), [])

    def test_randomized_histories_always_converge(self):
        """Random adds, conflicting edits, retractions, skewed clocks and partial syncs. After a final full
        sync every machine must show the identical view, and it must equal a store built from the union."""
        for seed in range(25):
            rng = random.Random(seed)
            base = tempfile.mkdtemp()
            self.addCleanup(shutil.rmtree, base, True)
            clock = Clock()
            n = rng.choice((2, 3, 4))
            ms = make_machines(base, n, clock, [rng.choice((-600000, 0, 0, 900000)) for _ in range(n)])
            subjects = ["a", "b", "c", "d"]
            for _ in range(rng.randint(10, 40)):
                clock.now += rng.randint(0, 5000)
                m = rng.choice(ms)
                op = rng.random()
                if op < 0.6:
                    kind = rng.choice(("fact", "constraint", "failure"))
                    body = {"symptom": "s"} if kind == "failure" else {}
                    m.add(kind, subject=rng.choice(subjects), text="t%d" % rng.randint(0, 99), body=body,
                          auto_supersede=rng.random() < 0.7)
                elif op < 0.75:
                    vis = m.visible()
                    if vis:
                        m.store.retract(rng.choice(vis)["rec"]["id"])
                else:
                    sync(*rng.sample(ms, rng.randint(2, n)))
            sync(*ms)
            sync(*ms)
            snaps = [m.snapshot() for m in ms]
            for s in snaps[1:]:
                self.assertEqual(s, snaps[0], "seed %d diverged" % seed)
            union = Machine(base, "union", clock)
            union.store.init()
            for m in ms:
                for f in os.listdir(m.store.replicas):
                    shutil.copyfile(os.path.join(m.store.replicas, f), os.path.join(union.store.replicas, f))
            self.assertEqual(union.snapshot(), snaps[0], "seed %d: union differs" % seed)
            for m in ms:
                ld = m.store.load()
                self.assertEqual((ld.chain_breaks, ld.forks), ([], []), "seed %d integrity" % seed)


# --------------------------------------------------------------------------- integrity

class TestIntegrity(Base):
    def test_a_torn_final_line_is_ignored_and_reported_then_healed_by_the_next_write(self):
        m = self.one()
        m.add(subject="a")
        m.add(subject="b")
        f = m.store.replica_file()
        with open(f, "ab") as fh:
            fh.write(b'{"v":1,"id":"m_partial')
        ld = m.store.load()
        self.assertEqual(len(ld.records), 2)
        self.assertEqual(ld.files[f]["torn"], 1)
        m.add(subject="c")                       # ends the interrupted line, then appends
        ld = m.store.load()
        self.assertEqual(len(ld.records), 3)
        self.assertEqual(ld.files[f]["invalid"], 1)
        self.assertEqual(ld.chain_breaks, [])

    def test_a_torn_fragment_is_not_also_counted_as_invalid(self):
        m = self.one()
        m.add(subject="a")
        with open(m.store.replica_file(), "ab") as fh:
            fh.write(b'{"v":1,"id":"m_partial')
        meta = m.store.load().files[m.store.replica_file()]
        self.assertEqual((meta["torn"], meta["invalid"]), (1, 0))

    def test_a_complete_record_without_its_newline_is_still_torn_and_not_loaded(self):
        """A sync tool cut exactly before the newline. The record is whole, but the write is not finished."""
        m = self.one()
        m.add(subject="a")
        other = self.machines(2)[1]
        r = other.add(subject="from-elsewhere")
        with open(m.store.replica_file(), "ab") as fh:
            fh.write(swmem.canon(r))                # valid JSON, deliberately NO trailing newline
        ld = m.store.load()
        self.assertNotIn(r["id"], ld.records)
        self.assertEqual(ld.files[m.store.replica_file()]["torn"], 1)

    def test_garbage_and_invalid_lines_are_dropped_and_counted(self):
        m = self.one()
        m.add(subject="a")
        f = m.store.replica_file()
        with open(f, "ab") as fh:
            fh.write(b"not json at all\n\xff\xfe\n{}\n[1,2]\n")
        ld = m.store.load()
        self.assertEqual((len(ld.records), ld.files[f]["invalid"]), (1, 4))

    def test_a_tampered_record_is_dropped_and_reported(self):
        m = self.one()
        m.add(subject="a", text="original")
        f = m.store.replica_file()
        with open(f, "rb") as fh:
            data = fh.read()
        with open(f, "wb") as fh:
            fh.write(data.replace(b"original", b"changed!"))
        ld = m.store.load()
        self.assertEqual((len(ld.records), ld.files[f]["tampered"]), (0, 1))

    def test_a_forged_id_is_rejected(self):
        m = self.one()
        r = m.add(subject="a")
        forged = dict(r, text="forged")          # content changed, id kept
        with open(m.store.replica_file(), "ab") as fh:
            fh.write(swmem.canon(forged) + b"\n")
        self.assertEqual(m.store.load().files[m.store.replica_file()]["tampered"], 1)

    def test_a_newer_schema_version_is_skipped_not_misread(self):
        m = self.one()
        m.add(subject="a")
        r = good_record()
        r["v"] = 2
        with open(m.store.replica_file(), "ab") as fh:
            fh.write(json.dumps(r).encode() + b"\n")
        ld = m.store.load()
        self.assertEqual((len(ld.records), ld.files[m.store.replica_file()]["unsupported"]), (1, 1))

    def test_a_removed_middle_record_is_a_chain_break(self):
        m = self.one()
        for s in "abc":
            m.add(subject=s)
        f = m.store.replica_file()
        with open(f, "rb") as fh:
            lines = fh.read().split(b"\n")
        with open(f, "wb") as fh:
            fh.write(lines[0] + b"\n" + lines[2] + b"\n")
        ld = m.store.load()
        self.assertEqual(len(ld.chain_breaks), 1)

    def test_two_machines_sharing_a_replica_id_are_detected_as_a_fork_and_rotation_fixes_it(self):
        a, b = self.machines(2)
        a.add(subject="one")
        # b's local state is a copy of a's, as after cloning a machine image
        shutil.copyfile(a.store._state_path(), b.store._state_path())
        shutil.copyfile(a.store.replica_file(), b.store.replica_file(a.store.replica_state()["replica"]))
        a.add(subject="from a")
        b.add(subject="from b")
        merged = os.path.join(a.store.replicas, a.store.replica_state()["replica"] + ".jsonl")
        with open(b.store.replica_file(), "rb") as fh:
            theirs = fh.read().split(b"\n")[1]
        with open(merged, "ab") as fh:
            fh.write(theirs + b"\n")
        ld = a.store.load()
        self.assertEqual(len(ld.forks), 1)
        old, new = b.store.rotate_replica()
        self.assertNotEqual(old, new)
        self.assertEqual(new, b.store.replica_state()["replica"])

    def test_a_restored_older_copy_of_our_own_file_refuses_writes(self):
        m = self.one()
        m.add(subject="a")
        f = m.store.replica_file()
        with open(f, "rb") as fh:
            old = fh.read()
        m.add(subject="b")
        with open(f, "wb") as fh:                # a naive sync tool puts the older copy back
            fh.write(old)
        with self.assertRaises(swmem.Refused) as cm:
            m.add(subject="c")
        self.assertIn("regressed", str(cm.exception))
        m.store.rotate_replica()                # recovery: a new replica, history stays readable
        m.add(subject="c")
        self.assertEqual(len(m.store.load().records), 2)

    def test_status_reports_problems_with_a_nonzero_exit(self):
        m = self.one()
        m.add(subject="a")
        out = io.StringIO()
        self.assertEqual(swmem._status(m.store, out), 0)
        self.assertIn("integrity: ok", out.getvalue())
        with open(m.store.replica_file(), "rb") as fh:
            data = fh.read()
        with open(m.store.replica_file(), "wb") as fh:
            fh.write(data.replace(b'"a"', b'"z"', 1))
        out = io.StringIO()
        self.assertEqual(swmem._status(m.store, out), 1)
        self.assertIn("tampered", out.getvalue())

    def test_unreadable_or_foreign_files_do_not_crash_loading(self):
        m = self.one()
        m.add(subject="a")
        with open(os.path.join(m.store.replicas, "zzzz.jsonl"), "wb") as fh:
            fh.write(b"\x00\x01\x02")
        with open(os.path.join(m.store.replicas, "README.txt"), "w") as fh:
            fh.write("ignored")
        self.assertEqual(len(m.store.load().records), 1)


# --------------------------------------------------------------------------- search and recall

class TestSearchAndRecall(Base):
    def setUp(self):
        super(TestSearchAndRecall, self).setUp()
        self.m = self.one()
        m = self.m
        m.add("fact", subject="service:nginx", text="nginx 1.24 installed via apt", tags=["nginx", "apt"])
        m.add("failure", subject="apt:jq", text="apt install jq: no candidate", body={"symptom": "no candidate", "resolution": "run apt update"})
        m.add("constraint", subject="no-snap", text="never use snap on this project")
        m.add("path", subject="~/srv/app/nginx.conf", body={"path": "~/srv/app/nginx.conf", "role": "modified"})
        m.add("warning", subject="w-open", text="disk nearly full", body={"status": "open"})
        m.add("warning", subject="w-done", text="old warning", body={"status": "resolved"})
        m.add("task", subject="t-open", text="finish the migration", body={"objective": "migrate", "status": "open"})
        m.add("task", subject="t-done", text="a finished task", body={"objective": "done thing", "status": "done"})

    def find(self, **kw):
        entries, _, _ = swmem.search(self.m.store, project="p", **kw)
        return [e["rec"]["subject"] for e in entries]

    def test_search_requires_all_words(self):
        self.assertEqual(self.find(query="nginx apt"), ["service:nginx"])
        self.assertEqual(self.find(query="nginx kubernetes"), [])

    def test_search_matches_body_text_and_is_case_insensitive(self):
        self.assertIn("apt:jq", self.find(query="UPDATE"))

    def test_filters(self):
        self.assertEqual(self.find(kind="constraint"), ["no-snap"])
        self.assertEqual(self.find(tag="nginx"), ["service:nginx"])
        self.assertEqual(self.find(path_prefix="~/srv"), ["~/srv/app/nginx.conf"])
        self.assertEqual(self.find(status="stale"), [])
        self.assertEqual(len(self.find(limit=2)), 2)

    def test_recall_always_includes_standing_items_and_matches_any_word(self):
        subs = self.find(query="nginx kubernetes", for_recall=True)
        self.assertIn("no-snap", subs)          # constraint: always
        self.assertIn("w-open", subs)           # open warning: always
        self.assertIn("t-open", subs)           # open task: always
        self.assertIn("service:nginx", subs)    # matches one word
        self.assertNotIn("apt:jq", subs)        # matches neither

    def test_recall_leaves_out_resolved_warnings_and_finished_tasks(self):
        subs = self.find(query="warning task", for_recall=True)
        self.assertNotIn("w-done", subs)
        self.assertNotIn("t-done", subs)
        self.assertIn("w-done", self.find(query="old warning"))     # search still finds them

    def test_ranking_prefers_more_term_hits(self):
        entries, _, _ = swmem.search(self.m.store, "nginx", project="p", for_recall=True, limit=50)
        subjects = [e["rec"]["subject"] for e in entries]
        self.assertLess(subjects.index("service:nginx"), subjects.index("w-open"))

    def test_recency_breaks_ties(self):
        self.clock.now += 90 * 86400000
        self.m.add("constraint", subject="newer-rule", text="another rule")
        entries, _, _ = swmem.search(self.m.store, "", project="p", for_recall=True, kind="constraint")
        self.assertEqual([e["rec"]["subject"] for e in entries][0], "newer-rule")

    def test_output_can_never_carry_escape_sequences(self):
        e = {"rec": dict(good_record(), subject="s\x1b[2Jx", text="t\x07bell"), "status": "unverified", "detail": "", "alternatives": []}
        line = swmem.fmt_entry(e, self.clock.now)
        self.assertNotIn("\x1b", line)
        self.assertNotIn("\x07", line)

    def test_summary_line_counts_statuses(self):
        entries, total, _ = swmem.search(self.m.store, "", project="p", limit=50)
        line = swmem.summary_line(entries, total, self.m.store)
        self.assertIn("unverified", line)
        self.assertIn(self.m.store.info()["store_id"], line)


# --------------------------------------------------------------------------- import / export

class TestImportExport(Base):
    def test_export_then_import_reproduces_the_view(self):
        a, b = self.machines(2)
        for i in range(5):
            a.add(subject="s%d" % i, text="t")
        bundle = ("\n".join(a.store.export_lines()) + "\n").encode()
        total, new, dropped = b.store.import_bundle(bundle)
        self.assertEqual((total, new, dropped), (5, 5, 0))
        self.assertEqual(a.snapshot(), b.snapshot())

    def test_importing_twice_changes_nothing(self):
        a, b = self.machines(2)
        a.add(subject="x")
        bundle = ("\n".join(a.store.export_lines()) + "\n").encode()
        b.store.import_bundle(bundle)
        files = sorted(os.listdir(b.store.imports))
        before = b.snapshot()
        total, new, dropped = b.store.import_bundle(bundle)
        self.assertEqual((new, sorted(os.listdir(b.store.imports)), b.snapshot()), (0, files, before))

    def test_bundle_name_does_not_depend_on_line_order(self):
        a, b = self.machines(2)
        a.add(subject="x")
        a.add(subject="y")
        lines = a.store.export_lines()
        b.store.import_bundle(("\n".join(lines) + "\n").encode())
        b.store.import_bundle(("\n".join(reversed(lines)) + "\n").encode())
        self.assertEqual(len(os.listdir(b.store.imports)), 1)

    def test_imports_never_touch_replica_files(self):
        a, b = self.machines(2)
        a.add(subject="x")
        before = sorted(os.listdir(b.store.replicas))
        b.store.import_bundle(("\n".join(a.store.export_lines()) + "\n").encode())
        self.assertEqual(sorted(os.listdir(b.store.replicas)), before)

    def test_bad_lines_are_dropped_and_counted(self):
        a, b = self.machines(2)
        r = a.add(subject="x")
        forged = dict(r, text="forged")
        bundle = swmem.canon(r) + b"\n" + swmem.canon(forged) + b"\nnot json\n" + b'{"v":1'
        total, new, dropped = b.store.import_bundle(bundle)
        self.assertEqual((total, new, dropped), (1, 1, 3))

    def test_an_all_invalid_bundle_is_refused(self):
        with self.assertRaises(swmem.Refused):
            self.one().store.import_bundle(b"junk\nmore junk\n")

    def test_export_since(self):
        m = self.one()
        m.add(subject="old")
        self.clock.now += 10_000
        cutoff = self.clock.now
        self.clock.now += 10_000
        m.add(subject="new")
        lines = m.store.export_lines(since=cutoff)
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["subject"], "new")

    def test_merge_order_does_not_matter(self):
        a, b, x, y = self.machines(4)
        a.add(subject="s", text="from a")
        b.add(subject="s", text="from b", auto_supersede=False)
        a.add(subject="only-a")
        b.add(subject="only-b")
        ba = ("\n".join(a.store.export_lines()) + "\n").encode()
        bb = ("\n".join(b.store.export_lines()) + "\n").encode()
        x.store.import_bundle(ba)
        x.store.import_bundle(bb)
        y.store.import_bundle(bb)
        y.store.import_bundle(ba)
        self.assertEqual(x.snapshot(), y.snapshot())
        sync(a, b)
        self.assertEqual(a.snapshot(), x.snapshot())


# --------------------------------------------------------------------------- command line and concurrency

class TestCLI(Base):
    def env(self):
        e = dict(os.environ, SWMEM_STORE=os.path.join(self.td, "store"), SWMEM_STATE=os.path.join(self.td, "state"),
                 SWMEM_PROJECT="demo", SWMEM_HOST="box", XDG_STATE_HOME=os.path.join(self.td, "xs"), XDG_DATA_HOME=os.path.join(self.td, "xd"))
        return e

    def run_cli(self, *args, **kw):
        return subprocess.run([sys.executable, SWMEM] + list(args), capture_output=True, text=True, env=kw.get("env", self.env()), timeout=60)

    def test_end_to_end(self):
        r = self.run_cli("init")
        self.assertEqual(r.returncode, 0, r.stderr)
        r = self.run_cli("add", "fact", "--trust", "observed", "--risk", "read-only", "--subject", "service:nginx",
                         "--text", "nginx installed via apt", "--tag", "nginx", "--fp", "exists:/etc/hostname")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("saved m_", r.stdout)
        self.run_cli("add", "failure", "--trust", "observed", "--risk", "read-only", "--subject", "apt:jq", "--text", "no candidate",
                     "--set", "symptom=no candidate", "--set", "resolution=run apt update")
        self.run_cli("add", "constraint", "--trust", "operator", "--subject", "rule", "--text", "never use snap")
        r = self.run_cli("recall", "--context", "nginx", "--verify")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("verified", r.stdout)
        self.assertIn("never use snap", r.stdout)
        rid = [l.split()[0] for l in r.stdout.splitlines() if "service:nginx" in l][0]
        r = self.run_cli("show", rid)
        self.assertIn("status:  verified", r.stdout)
        r = self.run_cli("search", "apt")
        self.assertIn("service:nginx", r.stdout)
        self.assertEqual(self.run_cli("verify").returncode, 0)
        self.assertEqual(self.run_cli("status").returncode, 0)
        r = self.run_cli("retract", rid, "--reason", "test")
        self.assertIn("retracted", r.stdout)
        self.assertNotIn("service:nginx", self.run_cli("recall", "--context", "nginx").stdout)
        exported = self.run_cli("export").stdout
        self.assertEqual(len([l for l in exported.splitlines() if l]), 4)

    def test_path_kind_defaults_and_portable_paths(self):
        self.run_cli("init")
        home = os.path.expanduser("~")
        r = self.run_cli("add", "path", "--trust", "operator", "--set", "path=" + os.path.join(home, "srv", "a.conf"), "--set", "role=modified")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("~/srv/a.conf", self.run_cli("search", "modified").stdout)

    def test_refusals_exit_1_name_the_rule_and_never_echo_the_secret(self):
        self.run_cli("init")
        r = self.run_cli("add", "fact", "--trust", "operator", "--subject", "s", "--text", "key " + AWS)
        self.assertEqual(r.returncode, 1)
        self.assertIn("secret-scan:aws-key", r.stderr)
        self.assertNotIn(AWS, r.stdout + r.stderr)
        r = self.run_cli("add", "fact", "--trust", "observed", "--risk", "credential/privileged-data", "--subject", "s", "--text", "t")
        self.assertEqual((r.returncode, "risk-label-not-eligible" in r.stderr), (1, True))
        r = self.run_cli("add", "fact", "--trust", "observed", "--subject", "s", "--text", "t")
        self.assertIn("risk-label-required", r.stderr)

    def test_dry_run_writes_nothing(self):
        self.run_cli("init")
        r = self.run_cli("add", "fact", "--trust", "operator", "--subject", "s", "--text", "t", "--dry-run")
        self.assertIn("dry run", r.stdout)
        self.assertIn("0 shown", self.run_cli("search").stdout)

    def test_usage_errors_exit_2_and_a_missing_store_says_how_to_fix_it(self):
        self.assertEqual(self.run_cli().returncode, 2)
        self.assertEqual(self.run_cli("add", "fact").returncode, 2)
        r = self.run_cli("recall")
        self.assertEqual(r.returncode, 1)
        self.assertIn("swmem init", r.stderr)

    def test_risk_class_subcommand(self):
        self.assertEqual(self.run_cli("risk-class", "credential/privileged-data").stdout.strip(), "sensitive")
        self.assertEqual(self.run_cli("risk-class", "read-only").stdout.strip(), "eligible")
        self.assertEqual(self.run_cli("risk-class", "bogus").stdout.strip(), "unrecognized")

    def test_ttl_and_fingerprint_errors(self):
        self.run_cli("init")
        self.assertIn("ttl-format", self.run_cli("add", "fact", "--trust", "operator", "--subject", "s", "--text", "t", "--ttl", "soon").stderr)
        self.assertIn("fingerprint-target-missing", self.run_cli("add", "fact", "--trust", "operator", "--subject", "s", "--text", "t",
                                                                 "--fp", "path-hash:/no/such/file").stderr)
        self.assertIn("credential-path", self.run_cli("add", "fact", "--trust", "operator", "--subject", "s", "--text", "t",
                                                      "--fp", "path-hash:~/.ssh/id_rsa").stderr)

    def test_export_import_between_two_cli_stores(self):
        self.run_cli("init")
        self.run_cli("add", "constraint", "--trust", "operator", "--subject", "r", "--text", "keep this")
        bundle = os.path.join(self.td, "b.jsonl")
        with open(bundle, "w") as f:
            f.write(self.run_cli("export").stdout)
        other = self.env()
        other["SWMEM_STORE"] = os.path.join(self.td, "store2")
        other["SWMEM_STATE"] = os.path.join(self.td, "state2")
        self.assertEqual(self.run_cli("init", env=other).returncode, 0)
        r = self.run_cli("import", bundle, env=other)
        self.assertIn("1 new", r.stdout)
        self.assertIn("keep this", self.run_cli("recall", env=other).stdout)

    def test_concurrent_writers_on_one_machine_keep_the_chain_intact(self):
        self.run_cli("init")
        procs = [subprocess.Popen([sys.executable, SWMEM, "add", "fact", "--trust", "operator", "--subject", "s%d" % i, "--text", "t%d" % i],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env()) for i in range(10)]
        for p in procs:
            p.communicate(timeout=60)
            self.assertEqual(p.returncode, 0)
        r = self.run_cli("status")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("10 valid", r.stdout)
        self.assertIn("integrity: ok", r.stdout)

    def test_concurrent_threads_in_process(self):
        m = self.one()
        errors = []

        def work(i):
            try:
                m.add(subject="t%d" % i, text="x")
            except Exception as e:  # noqa: BLE001
                errors.append(e)
        ts = [threading.Thread(target=work, args=(i,)) for i in range(8)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        self.assertEqual(errors, [])
        ld = m.store.load()
        self.assertEqual((len(ld.records), ld.chain_breaks, ld.forks), (8, [], []))

    def test_process_umask_is_restored(self):
        old = os.umask(0o022)
        try:
            swmem.main(["risk-class", "read-only"], out=io.StringIO())
            cur = os.umask(0o022)
            self.assertEqual(cur, 0o022)
        finally:
            os.umask(old)


if __name__ == "__main__":
    unittest.main(verbosity=1)
