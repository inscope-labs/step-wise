# Spec: Ledger Extraction — Grammar, Validation & Delivery

| | |
|---|---|
| Framework | 1.6.0 (unreleased) |
| Component | spec `clipboard/extraction` |
| Version | 1.6.0-draft |
| Depends on | `clipboard/ledger-format` 1.6.0-draft |
| Supersedes | nothing |
| Status | **Draft.** Not referenced by `v1/prompt.md` yet. |

Implements plan sections 3.3 (Stage 2), 3.6, 3.7. Reference implementation: `sw_copy_clip` in `v1/utils/clipcopy.sh`. Per 3.7 this **extends** the existing clipboard abstraction. There is no second clipboard implementation.

## 1. Principle

Execution and clipboard transfer are separate operations. Extraction is a deliberate human act: the operator inspects, chooses an index, and invokes the extractor. The classifier is not the last line of defense against sensitive *output*; the human is (3.9).

## 2. Grammar

```
spec     = ""                 ; empty: the final entry
         | index              ; a single entry
         | index "-" index    ; closed range, inclusive
         | index "+"          ; from index through the final entry
index    = [1-9][0-9]{0,8}    ; positive, no leading zeros, at most 9 digits
```

| Input | Meaning |
|---|---|
| *(none)* | the final entry |
| `5` | entry 5 |
| `12-15` | entries 12, 13, 14, 15 |
| `18+` | entry 18 through the final entry |

At most one `spec` argument is accepted. "Empty" means **no argument**. An explicitly passed empty string (for example an unset shell variable expanded as `sw_copy_clip "$x"`) is a grammar error, so a scripting mistake can never silently copy the wrong entry.

## 3. Validation cases

Every case below **fails safely**: a message on stderr, a non-zero status, and **nothing copied or printed** as content. There is no clamping and no partial extraction.

| Input | Outcome | Reason |
|---|---|---|
| `0` | error | indexes start at 1 |
| `-3` | error | negative; also not in the grammar |
| `12-` | error, suggests `12+` | open end must be written explicitly as `+`; never left implicit |
| `-15` | error | open start is not supported |
| `15-12` | error | reversed range |
| `1-999999999` | error | valid syntax, but exceeds the final entry; nothing is clamped |
| `1000000000` | error | more than 9 digits |
| `007` | error | leading zeros rejected (avoids octal ambiguity) |
| `abc`, `1.5`, `1,2`, `5 6` | error | not in the grammar |
| `""` (explicit empty string) | error | see the note under the grammar |
| `3` when entry 3 is absent, `bad` or `dup` | error naming the index | only `ok` records are extractable |
| `1-5` where any entry in the range is not `ok` | error naming the index | all-or-nothing |
| any spec on an empty ledger | error | nothing to extract |
| no active session, or missing ledger | error | see section 6 |
| two or more arguments | error | one spec at most |

## 4. Output shape

- **Single entry:** the entry's output lines only, exactly as stored.
- **Multiple entries:** each entry is preceded by a separator line so the paste-back keeps its provenance:
  `### STEP <n> - <step> (exit <status>)`.
- Withheld entries (ledger-format §4.2) are refused under section 5. They hold no content, only a placeholder.

## 5. Sensitive and unrecognized entries (defense in depth)

The extractor re-classifies each selected entry's stored `risk:` label with the same fail-closed classifier as `runcopy`. If any selected entry is `sensitive` or `unrecognized`, **the whole extraction is refused**. No override flag exists. This holds even if a record was hand-edited to contain output.

Missing labels are stored as `unclassified` and are extractable. They come from operator-driven use without an agent-supplied classification. Agent-generated commands must always carry a label (plan 3.2 / 3.8).

## 6. Delivery

1. Validate the spec; scan the ledger; resolve and check every entry.
2. Assemble the full content.
3. Only then deliver it, to the clipboard via the existing `_sw_clipboard_copy` (`termux-clipboard-set` → `xclip` → `pbcopy` → `clip.exe`, no-op notice if none). `--stdout` writes the content to stdout instead of the clipboard, for piping and tests.

The clipboard state never authorizes anything. Extraction copies text; it does not execute it (3.8).

Exit codes: `0` success; `1` runtime failure (no session, missing ledger, entry not extractable, refused); `2` usage or grammar error.
