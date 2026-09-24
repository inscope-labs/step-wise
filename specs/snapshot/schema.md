# Spec: Snapshot Schema

| | |
|---|---|
| Framework | 1.6.1 (unreleased) |
| Component | spec `snapshot/schema` |
| Version | 1.6.1-dev |
| Parent feature | `feature:snapshot` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

Canonical schema identifier:

```yaml
schema:
  id: stepwise.snapshot
  version: 1
```

Framework version recorded on a snapshot is informational and must not be the sole compatibility test.

## 1. Top-level shape

A snapshot is a single YAML document. Required top-level keys:

- `schema` (id + version)
- `snapshot` (id, created_at, writer_version, revision, optional parent_snapshot_id)
- `task` (id, name, objective, scope, exclusions, repository, task_state)
- `progress` (current_step, next_action, completed_steps)
- `criteria` (list)
- `facts` (list)
- `warnings` (list)
- `environment` (profile, fingerprint)
- `paths` (affected)
- `captured_session_metadata` (informational only)

`captured_session_metadata` is never restored into Session State.

## 2. Identities

Three identities remain separate:

- `task.id` — persistent identity of the work
- `session_id` (recorded inside evidence references and events) — one interactive session
- `snapshot.id` — one immutable saved state

Task IDs are immutable and collision-resistant. Human-readable names are metadata only.

## 3. Evidence references

Evidence is reference-based. Never serialize raw command output, credentials, privileged output, or full transcripts.

Preferred form:

```yaml
evidence_ref:
  type: ledger_step
  session_id: session_01J...
  step: 14
```

Allowed types include: `ledger_step`, `artifact`, `git_object`, `test_result`, `operator_note`.

If the referenced evidence is unavailable at resume time, the corresponding claim must not remain silently `verified`.

## 4. Fact lifecycle states

```
historical_verified
current_verified
stale
invalidated
unknown
```

A timestamp alone does not determine validity. Revalidation requirements depend on fact class (repository identity and HEAD are always revalidated; historical decisions are normally preserved as historical).

## 5. Allow-list serialisation

The snapshot uses an allow-list model. It must never intentionally serialize:

- passwords, API keys, OAuth tokens, private keys, cookies
- credential-bearing or privileged command output
- arbitrary environment dumps
- full terminal transcripts

Redaction is defence-in-depth, not the primary protection.

## 6. Integrity metadata (optional)

A SHA-256 checksum may be supplied as a corruption detector. It is not an authenticated security boundary. If only a checksum is present, an attacker who can modify both state and checksum can bypass it.
