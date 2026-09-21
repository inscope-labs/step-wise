# Spec: Snapshot Integrity

| | |
|---|---|
| Framework | 1.6.1 (unreleased) |
| Component | spec `snapshot/integrity` |
| Version | 1.6.1-dev |
| Parent feature | `feature:snapshot` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

## 1. Corruption detection

A SHA-256 checksum may be provided over the canonical representation of a snapshot (including its revision). It functions solely as an accidental-corruption detector.

It must not be described as an authenticated security boundary. An attacker able to modify both the state file and the checksum can bypass it.

## 2. Compatibility

Compatibility is based primarily on the snapshot schema version:

- Same schema version → load subject to validation
- Older supported schema → explicit migration function
- Newer or unknown schema → block

Heuristic parsing is forbidden. Framework version is recorded for provenance only.

## 3. Feature compatibility

A historical list of features present when the snapshot was written is informational. It does not force-load a feature or establish that the current implementation has identical semantics. The current feature registry and prompt remain authoritative.

## 4. Crash recovery

On startup, detect incomplete state transitions using temporary files, revision numbers, event sequence numbers and lock metadata. Present the discrepancy to the operator; never silently fabricate a missing event or discard a newer state revision.
