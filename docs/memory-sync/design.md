# Contextual Memory Sync: design

Rationale for the feature in `v1/feature/memory-sync.md` and `v1/specs/memory-sync/`. The survey of what it touches is in [`repository-survey.md`](repository-survey.md). This document says why the design is the way it is, what was rejected, and what is still undecided.

## 1. Goal, and what it must not become

**Goal.** A persistent, searchable implementation of the StepWise memory fields that survives sessions and synchronizes between machines, so an operator stops paying for repeated discovery and keeps constraints, affected paths and past failures.

**Constraints that shaped everything:**

1. **The assistant cannot run anything.** StepWise's human execution boundary means recall and save are operator-run steps with pasted output. That is a feature: the person sees exactly what is persisted before it is.
2. **Shell output is primary evidence.** A memory is a *claim*. A design that lets an old claim stand in for a fresh check would break the protocol's central rule, however convenient.
3. **Memory is an attack surface.** Whatever is stored gets read back into an assistant's context, possibly from a store other people can write to.
4. **It must work on a phone.** Termux, no server, no daemon, files only.

## 2. Decisions, with the alternatives rejected

| Decision | Chosen | Rejected, and why |
|---|---|---|
| Sync model | Grow-only set of immutable records; merge is set union | *A database with a sync server*: needs infrastructure the constraint 4 rules out. *Last-writer-wins on a mutable file*: silently loses one side of a concurrent edit |
| File layout | One append-only file **per replica**, written only by its owner | *One shared file*: two machines editing it means merge conflicts inside a file. Single-writer files make git, rsync, Syncthing or a cloud folder all work unmodified |
| Record identity | Content hash that includes `prev`, so records form a hash chain | *Random ids*: cannot detect a tampered or reordered record. *Timestamps*: collide and lie |
| Ordering | Hybrid logical clock `(ms, counter, replica)` | *Wall clock only*: phones drift, and a write after a sync could sort before what it saw. *Vector clocks*: heavier than this needs |
| Conflicts | Keep both, flag the subject `disputed`, force a re-verify | *Silently pick the latest*: hides that two machines disagree about the same fact |
| Deletion | Tombstone that wins regardless of clock | *Hard delete*: an old copy arriving later resurrects it. The cost is that removal never erases (section 4) |
| Freshness | Fingerprint plus expiry, checked **at recall**, status computed and never stored | *Trust the stored claim*: violates constraint 2. *Store a status*: goes stale the moment it is written |
| What may skip discovery | Only `verified` (fingerprint matched just now) | *`unverified` within its TTL*: still just a claim |
| Local vs synced state | Replica id and cursors live outside the synced tree | *Everything in one directory*: copying the directory to a second machine would clone its replica id |
| Search | Linear scan of the JSONL, `grep`-able | *SQLite FTS*: not guaranteed on every Termux Python, and adds a second source of truth. Measured limits are in section 5 |
| Implementation | Python, standard library only | *bash and awk*: escaping JSON and merging by hand is where the bugs would be, and the merge properties are only testable with real tooling. The dependency is stated and optional |
| `inferred` trust | Does not exist | *Let the agent store its guesses*: it would turn its own hypotheses into later "memory" |

## 3. The memory fields, and what is deliberately not kept

The 1.5.0 prompt lists the fields. Persisting each one raised the same question: does a later session benefit, or does it become a hazard?

| Field | Persists as | Reason |
|---|---|---|
| verified state | `fact` | main saving, but only with a fingerprint and expiry |
| constraints | `constraint` | highest-value and slowest-changing |
| affected paths | `path` | with a fingerprint so a later session can tell if the file moved |
| failures | `failure` | stops repeating a diagnosed dead end |
| corrections | `correction` | the operator's own corrections outrank the agent's beliefs |
| warnings | `warning` | open ones are recalled |
| Objective, criteria, remaining objectives | `task` | so a session can resume; criteria kept as counts |
| **human confirmations** | **never** | a confirmation authorizes one action in one session. Persisting it turns a stale approval into a live one. This is the single most important omission |
| completed and skipped steps | never | the ledger holds them |
| session state and all 1.6.0 session fields | never | they reset with the session by design |

## 4. Threat model

The trust boundary is **whoever can write files into the store**. There is no authentication in v1, so the design assumes a hostile writer is possible and limits what one can achieve.

- **What a hostile record can do:** appear in recall, waste attention, or carry an instruction.
- **What it cannot do:** authorize anything, relax a rule, satisfy a criterion, count as evidence, or run. Recalled text is data. Anything that would shape a plan is shown to the operator, who keeps or drops it. Fingerprint kinds are a fixed list and no stored command is ever executed.
- **A far-future timestamp** cannot win, cannot pull the clock forward, and cannot hide other records until its time arrives.
- **Secrets** are kept out by three layers that do not depend on each other: the fail-closed risk gate (the same rule as the ledger, with a lint check that the two classifiers agree), a heuristic secret scanner, and a path denylist that refuses to read credential files. The last layer is the person who runs the save command and sees what it stores.
- **What remains:** the scanner is heuristic and will miss novel formats. Nothing is encrypted at rest. Erasing a record means deleting its line from every replica and import file everywhere. A leaked secret must be rotated. Signing records would close the hostile-writer gap and is left for a later version.

## 5. Scale, measured

Linear cost, measured on the development sandbox with one replica file. `add` also reads the whole store, because it checks integrity and sets the clock.

| Records | load | recall | add | file |
|---|---|---|---|---|
| 500 | 0.02 s | 0.02 s | 0.02 s | 0.2 MB |
| 2,000 | 0.08 s | 0.09 s | 0.09 s | 0.7 MB |
| 10,000 | 0.41 s | 0.50 s | 0.44 s | 3.8 MB |
| 50,000 | 2.2 s | 2.9 s | 2.7 s | 18.8 MB |

That is comfortable for a person saving a few records per task. Beyond roughly 20,000 records a local index (never synced) would be the next step. It is not built, because guessing at scale that nobody has reached is how features get heavier than they need to be. A phone will be slower than these numbers.

## 6. Verification

- `v1/tests/test_swmem.py`: 108 tests. They include randomized multi-machine histories (skewed clocks, concurrent edits, retractions, partial syncs) that must always converge to the same visible records and disputes, torn and corrupt writes, rollback and replica-id reuse, the write gate, and the terminal-safety of every printed field.
- **30 injected bugs**, each caught by a named test. Three were *not* caught at first, and each exposed a real gap (a valid record cut just before its newline, the default state directory never being exercised, and risk classifiers compared only on fixed probes). All three are now covered.
- Writing the tests also found **two real bugs**: the store root was created world-readable, and unknown body fields were being stored.
- `sw-lint.sh` checks that the Python and shell risk classifiers agree in both directions, and that no feature teaches double-quoted free text.
- Four acceptance scenarios cover the behavior that only a model can show. **No model has run them.**

## 7. Not verified

- How any model behaves with the feature. Regex checks on replies are evidence, not proof.
- Termux and macOS bash 3.2, and Python versions other than the sandbox's.
- Concurrent sync tools racing a writer. The design tolerates a torn read but this was simulated, not observed against a real Syncthing or git.

## 8. Decisions for you

1. **Version.** New feature, so arguably a minor release. I used `1.6.1-dev` because the compatibility rule requires every tier file's `Framework` to match the prompt's major.minor, and `1.7.0-dev` would mean editing every existing file's header for no behavioral reason. Say so if you would rather bump.
2. **Python as a dependency of an opt-in feature.** The core protocol stays bash-only and Python-free.
3. **`MEMORY_ENABLED` as a prompt-level session key.** It costs about 90 bytes of the prompt's remaining headroom (506 bytes).
4. **No authentication or encryption in v1.**
5. **Whether saves should ever be automatic.** They are not: every save is a step the operator runs. Automatic saves would be faster and would remove the visible-before-persisted property.
