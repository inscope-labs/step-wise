# Feature: Logging

| | |
|---|---|
| Framework | 1.6.0 (unreleased) |
| Component | feature `logging` (Tier 2) |
| Version | 1.6.0-dev |
| Depends on | nothing |
| Supersedes | the **Logging** paragraph in `v1/prompt.md` 1.5.0 (moved here verbatim) |
| Status | Draft. Loaded on demand. |

Precedence: Prompt > Feature > Specs. Nothing here relaxes a rule in the mandatory prompt.

Load this only when the operator requests or requires a session log.

**Logging:** Logging is optional support, not the fundamental protocol. If requested/required, establish it before substantive execution, preserve interaction where practical, and do not obscure commands or compromise clarity. Do not wrap every command in logging machinery unnecessarily. Core model remains: functional step → human execution → output → analysis.

A session log is not the session ledger. The log preserves the interaction where practical. The ledger (see the clipboard and inspection features) holds per-step raw output for selective extraction, and the two do not replace each other.

## Detailed references

None. This feature has no Tier 3 specs.
