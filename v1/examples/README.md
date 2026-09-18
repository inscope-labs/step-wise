# StepWise Example Transcripts

**Status: pending.** No worked transcript exists in this directory yet.

## What belongs here

A full end-to-end walkthrough of the protocol against a real (or realistic) task, showing:

1. A raw task description resolved through the **Objective Clarification Gate** — either passed straight through (already concrete) or resolved via a capped clarification exchange, ending in an operator-confirmed one-line Objective.
2. A proposed **CompletenessCriteria** list from the **Completeness Criteria Wizard**, with evidence types labeled, at least one `[human-confirmation-only]` item if applicable, and the operator's `accept` / `edit` / `reject` response.
3. At least one functional step presented in the standard format, including a numbered `BEGIN EXPECTED` / `END EXPECTED` block.
4. A deliberately mismatched paste-back, and the assistant's validation response citing the specific `[n]` marker(s) that failed.
5. A credential- or privileged-data-classified step showing the automatic clipboard-copy bypass notice from `v1/utils/clipcopy.sh`.
6. A final summary that checks completion against the confirmed CompletenessCriteria rather than "the last command succeeded."

## Why this is marked pending rather than omitted

The protocol in `v1/prompt.md` has been read for internal consistency but has not yet been exercised end-to-end against a real AI tool and a real operator. Per the versioning policy in `../../CHANGELOG.md`, StepWise stays on `1.x` — and doesn't move to `2.0.0` — until that testing, including a transcript like the one described above, actually happens. Treat the absence of an example here as "not yet verified," not as "verified to need no example."
