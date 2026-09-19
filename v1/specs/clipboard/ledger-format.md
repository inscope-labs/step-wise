# Spec: Session Ledger — Format & Lifecycle

| | |
|---|---|
| Framework | 1.6.0 (unreleased) |
| Component | spec `clipboard/ledger-format` |
| Version | 1.6.0-draft |
| Parent feature | `feature:clipboard` / `feature:inspection` (not yet written) |
| Supersedes | nothing (v1.5.0 has no ledger) |
| Status | **Draft.** Not referenced by `v1/prompt.md` yet. The prompt stays at `1.5.0` until the Phase 6 tests pass (plan 7.2). |

Implements plan sections 3.4, 3.5, 3.9, 3.10. Reference implementation: `v1/utils/clipcopy.sh` (`sw_session_start`, `runledger`, `sw_ledger_list`).

## 1. Role of the ledger

The ledger is **auxiliary historical evidence**. It is never authoritative state (3.10):

```
terminal output ──┬──► StepWise validation   (authoritative)
                  └──► session ledger        (auxiliary)
```

- Terminal display is always primary and is never altered by ledger capture.
- A ledger failure never blocks or changes the step: the command still runs, output is still displayed, and the exit status is preserved. The operator gets a notice that nothing was recorded.
- Ledger contents are not copied into contextual memory (plan 4.1). Memory holds *state*; the ledger holds *evidence*.

## 2. Sessions and paths

```
${STEPWISE_HOME:-$HOME/.cache/stepwise}/
└── sessions/
    └── <SESSION_ID>/
        ├── ledger.log     append-only records (section 4)
        └── metadata       key: value lines (session, created, shell_pid, cwd)
```

- **There is no global `ledger.log`.** Each session has its own directory (3.5).
- **Session ID grammar:** `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`. Generated IDs look like `20260919T072600Z-4242-a1b2c3d4` (UTC start time, shell PID, random suffix). The grammar exists so a hostile or mistyped value can never traverse out of `sessions/`.
- **The active session is the environment variable `SW_SESSION_ID`.** It is per shell, on purpose. A shared "current session" pointer file would reintroduce exactly the cross-session contamination this layout exists to prevent.
- `sw_session_start` creates the directory, ledger and metadata, and exports `SW_SESSION_ID`. It must be run in the current shell, not in a subshell or command substitution.
- Sourcing `clipcopy.sh` has no side effects. It creates no session and writes nothing.
- The session ends when the shell ends. Ledgers are not deleted automatically.
- Directories are created mode `0700` and files `0600`.

## 3. Lifecycle

```
sw_session_start
      ↓
runledger … -- <command>     (repeat per step)
      ↓  execute → display → capture → assign index → append record
sw_ledger_list               (human inspects)
      ↓
sw_copy_clip [spec]          (optional extraction; see extraction.md)
```

## 4. Record format

Each step appends exactly one record:

```
=== STEP 17 session=<SESSION_ID> nonce=<hex> ===
timestamp: 2026-09-19T07:26:41Z
session: <SESSION_ID>
objective: <one line>
step: <one line>
exit_status: 0
risk: read-only
output_withheld: no
output_lines: 3
output:
<exactly 3 lines>
=== END STEP 17 nonce=<hex> ===
```

Field rules:

- `objective`, `step`: one line each. Newlines, tabs and carriage returns become spaces; values are truncated to 500 characters. Missing values are recorded as `-`.
- `exit_status`: the command's exit status. Non-zero statuses are retained as-is.
- `risk`: the label as supplied, or `unclassified` if none was supplied.
- `nonce`: 8+ lowercase hex characters, unique per record. The header and footer of one record carry the same nonce.
- **The command line is deliberately not recorded.** Commands can embed secrets; `step` carries the human-readable description.

### 4.1 Length-prefixed body

`output_lines: N` is authoritative. A parser reads exactly `N` lines after `output:` and treats them as opaque data, **even if they contain text that looks like a record header or footer**. Delimiters alone are never trusted (3.4). The record then must end with the matching `=== END STEP <n> nonce=<hex> ===` line.

Normalization at write time:

- Output is captured as combined stdout and stderr, as the operator saw it on the terminal.
- If the final output line lacks a trailing newline, one is added. The line count reflects the normalized output.
- Empty output is `output_lines: 0`, with `output:` immediately followed by the footer.
- Binary output (NUL bytes) is not supported and may be truncated by the platform's `awk`.

### 4.2 Withheld output (sensitive and unrecognized labels)

If the risk label classifies as `sensitive` or `unrecognized` (fail-closed, see `extraction.md` §5), **the output is never captured or written to disk**:

```
output_withheld: yes
output_lines: 1
output:
[StepWise] output withheld: <sensitive|unrecognized> risk classification
```

The command still runs and displays normally. The exit status is still recorded. Rationale: the clipboard bypass is meaningless if the same secret is written in plaintext to the ledger.

This covers only the *command* classification. It cannot detect sensitive output from a command classified as non-sensitive (3.9 A vs. B). For that gap, the human inspecting and selecting an index is the final authorization.

## 5. Index assignment and immutability

- Indexes are positive integers, starting at `1`, strictly increasing, and **never reused**.
- The next index is `max(all indexes present in the ledger, including malformed records) + 1`, computed under a lock. There is no separate counter file that could drift from the ledger.
- Records are appended, never rewritten. The writer never seeks or truncates.
- Lock: `mkdir <session>/.lock`. Retried for about 5 seconds, then the write fails safely (section 1). A stale lock left by a killed process is cleared with `rmdir <session>/.lock`.

## 6. Malformed and duplicate records

A scanner classifies every record as `ok`, `bad` or `dup`:

| Condition | Result |
|---|---|
| Header with no valid `output:` / footer (truncated, wrong footer index or nonce) | `bad` |
| Missing or non-numeric `output_lines` | `bad` |
| Same index appears twice | second and later are `dup` |
| Text between records that is not a header | ignored for indexing; reported as junk |

Only `ok` records can be extracted. A `bad` or `dup` index is reported by name and nothing is copied. Damaged records never prevent extraction of other, intact records.
