# Spec: Memory Schema

| | |
|---|---|
| Framework | 1.6.1 (unreleased) |
| Component | spec `memory-sync/schema` |
| Version | 1.6.1-dev |
| Parent feature | `feature:memory-sync` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

The persistent form of the StepWise memory fields. A record is one immutable JSON object on one line. Reference implementation: `v1/utils/swmem.py`.

## 1. Two locations

| | Path | Synced |
|---|---|---|
| **Store** | `${XDG_DATA_HOME:-~/.local/share}/stepwise/memory/<name>/`, or `--store DIR` / `SWMEM_STORE` | yes |
| **Local state** | `${XDG_STATE_HOME:-~/.local/state}/stepwise/memory/<store_id>/` | **never** |

The store holds `store.json` (schema version, `store_id`), `replicas/<replica>.jsonl`, and `imports/<hash>.jsonl`. Local state holds `replica.json` (this machine's replica id and the last record it wrote) and any derived index. Keeping machine-specific state out of the synced tree is what lets the whole store be copied anywhere. The store is never under the ledger's cache directory, which may be deleted. Directories are `0700`, files `0600`.

## 2. The record

| Field | Meaning |
|---|---|
| `v` | schema version, `1` |
| `id` | `m_` plus 20 characters of base32 `sha256` of the canonical record without `id`. It commits to the content and to `prev` |
| `prev` | `id` of the previous record this replica wrote, or `null`. Forms a hash chain |
| `op` | `put` or `retract` |
| `kind` | `fact`, `constraint`, `path`, `failure`, `correction`, `warning`, `task` |
| `scope` | `{project, host}`. `host` is a hostname tag, or `*` for all machines |
| `subject` | grouping key, at most 120 characters (`service:nginx`, a path, a failure signature) |
| `text` | one-line claim, at most 300 characters. This is what search matches |
| `tags` | at most 8, each `[a-z0-9:_-]{1,32}` |
| `body` | kind-specific fields (section 3) |
| `trust` | `observed` (derived from validated shell output) or `operator` (stated by the person). There is no `inferred` |
| `source` | `{replica, session?, ledger?}`. `ledger` is only a pointer such as `STEP 17` |
| `hlc` | `{t, c, r}`: milliseconds, counter, replica. A hybrid logical clock (see `memory-sync/sync`) |
| `valid` | `{until: UTC or null, fp: {kind, ref, value} or null}` |
| `supersedes` | ids this record replaces |
| `retracts` | the id withdrawn, on `op: retract` only |

Canonical JSON: keys sorted, no whitespace, UTF-8. Readers ignore unknown fields and skip records whose `v` is newer than they know. Writers write `v: 1`.

## 3. Kinds: what persists from the 1.5.0 fields

| Kind | Persists | `body` | Decays |
|---|---|---|---|
| `fact` | verified state | none (`text` is the claim) | yes: `valid.until` (default 30 days) and a fingerprint |
| `constraint` | constraints | none (`text` is the rule) | no |
| `path` | affected paths | `{path, role}`, role is `created`, `modified`, `deleted` or `read` | by fingerprint |
| `failure` | failures | `{symptom, cause?, resolution?}`, each at most 160 characters | no |
| `correction` | corrections | `{was, now}`, each at most 160 characters | no |
| `warning` | warnings | `{status}`, `open` or `resolved` | until resolved |
| `task` | Objective, CompletenessCriteria, remaining objectives | `{objective, status, remaining[], criteria_met, criteria_total}` | no |

`task.status` is `open`, `done` or `abandoned`. `remaining` has at most 8 items of 120 characters, and lets a later session resume. Criteria are kept as counts, not text.

**Deliberately not persisted:**

- **Human confirmations.** A confirmation authorizes one action in one session. Recalling one later would turn a stale approval into a live one.
- **Completed and skipped step lists.** The ledger holds steps. A `task` keeps counts and points at evidence.
- **Session state** and every 1.6.0 session field (`session_id`, `ledger_path`, `next_ledger_index`, `context_loaded`, the mode flags).
- **Raw output, file contents, commands.**

## 4. Validity: fingerprints and status

A fingerprint lets a recall re-check a claim cheaply instead of repeating discovery. Kinds are fixed, and none executes stored text:

| `fp.kind` | `ref` | `value` |
|---|---|---|
| `path-hash` | a path | `sha256` of the file (files up to 5 MB) |
| `path-stat` | a path | `size:mtime_ns` |
| `exists` | a path | `1` or `0` |
| `git-head` | a repository path | `HEAD` commit |
| none | | |

Paths are stored portably (`~/...` under the home directory) so a store moves between machines with different usernames. Fingerprinting is refused for credential-bearing paths (see `memory-sync/safety`).

**Status is computed at read time and never stored:**

| Status | Meaning |
|---|---|
| `verified` | the fingerprint matched when it was just checked |
| `unverified` | no fingerprint, and within `valid.until` or of a kind that does not decay |
| `stale` | past `valid.until`, the fingerprint no longer matches, or its target is gone |
| `disputed` | concurrent records for one subject disagree (see `memory-sync/sync`) |
| `other-host` | a `fact` or `path` recorded on a different host |
| `suspect` | dated far in the future (see `memory-sync/sync`) |

**Only `verified` may replace a discovery step. Everything else guides discovery and never satisfies a criterion.**

## 5. Limits

A record is at most 2,048 bytes serialized. `text` 300, `subject` 120, at most 8 tags. Anything larger is refused, not truncated, so that a tool can never be used to store output.

## 6. Search

`search` matches `subject`, `text`, `tags` and body text (case-insensitive, **all** terms) and filters by `kind`, `tag`, path prefix, project and status. `recall` is for starting a task: it **always** includes the project's constraints, corrections, open warnings and open tasks, and adds facts, paths and failures that match **any** context word. Ranking: terms matched, kind weight, recency, and proximity to the current directory. The file is line-oriented JSON, so plain `grep` also works.
