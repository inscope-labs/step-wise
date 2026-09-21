# 02. Survey and design

Phases P2 and P3. Nothing is written into `v1/` yet. The survey and the design are the two documents that make a proposal reviewable.

## P2. Survey: find everything the change touches

### P2.01 Inventory the tracked files
- **Needs:** P1.07
- **Do:** `git ls-files | while read f; do printf '%7s  %s\n' "$(wc -c < "$f")" "$f"; done`
- **Verify:** You can name every top-level area (`v1/prompt.md`, `v1/feature/`, `v1/specs/`, `v1/utils/`, `v1/tests/`, `docs/`, root files).
- **Record:** The list, for the survey.
- **If it fails:** Nothing to fix. Re-run in the repository root.
- **Risk:** read-only

### P2.02 Score every file against the feature's concepts
- **Needs:** P2.01
- **Do:** List 8 to 14 concepts the feature involves, as regular expressions (for a memory feature: memory, persist, session, ledger, evidence, secret, hash, compaction; for a network feature: network, fetch, download, remote). Count matches per file with a short script and print a matrix. Exclude generated fixtures such as the scenario JSON files, which would drown the signal.
- **Verify:** The matrix has one row per file and every concept is a column. High counts are a lead, not a conclusion.
- **Record:** The concepts and the matrix summary.
- **If it fails:** If everything scores zero, your concepts are wrong. Choose again from the protocol's own vocabulary.
- **Risk:** read-only

### P2.03 Read the definitions in the high-scoring files
- **Needs:** P2.02
- **Do:** Read the paragraphs and code that *define* each concept, not only grep hits. Note line numbers.
- **Verify:** For each lead you can say what the file currently says and what it constrains.
- **Record:** File, line, and what it says.
- **If it fails:** A count with no reading behind it is not a finding. Read it.
- **Risk:** read-only

### P2.04 Classify every relevant area
- **Needs:** P2.03
- **Do:** Sort each area into one class:
  - **Direct:** defines or implements what you are changing
  - **Produces:** generates the content or evidence involved
  - **Governs:** constrains how it may be loaded, sized, versioned, or trusted
  - **Enforces:** tooling that must be extended so it cannot drift
  - **Adjacent:** related but deliberately kept separate
  - **Outside the repository:** environment, transport, other assistants
- **Verify:** Every tracked area is either classified or explicitly judged unrelated.
- **Record:** The table.
- **If it fails:** An area you cannot place is a question for the operator.
- **Risk:** read-only

### P2.05 Write the survey's conclusions
- **Needs:** P2.04
- **Do:** State five things: what already exists and should be extended; what **collides** with the proposal; which existing mechanisms must be reused rather than reimplemented; which boundary constraints shape the design (for example that the assistant cannot run anything); and which budgets bind.
- **Verify:** Each conclusion points at a specific file and line from P2.03.
- **Record:** The conclusions.
- **If it fails:** A conclusion without a source is an assumption. Verify it or drop it.
- **Risk:** read-only

### P2.06 Write the survey document
- **Needs:** P2.05
- **Do:** Fill in [templates/survey.md](templates/survey.md) at `docs/<feature>/repository-survey.md`.
- **Verify:** Every path in it exists (the docs linter checks the guide, so check yours by hand: `git ls-files <path>`), and line numbers are for the base commit you named.
- **Record:** The file.
- **If it fails:** Fix the reference. Do not leave a plausible-looking path that does not exist.
- **Risk:** creates

## P3. Design: decide, and say what you rejected

### P3.01 Write the decision table
- **Needs:** P2.05
- **Do:** For each real choice write the option chosen and the alternatives rejected with the reason. Choices that always deserve a row: the storage or transport, the identity and ordering scheme, how conflicts are handled, what happens on deletion, what is freshness-checked, the implementation language, and what is deliberately **not** kept.
- **Verify:** A reviewer can tell *why* from the table without asking.
- **Record:** The table.
- **If it fails:** A row with no rejected alternative was not a decision. Find one or drop the row.
- **Risk:** read-only

### P3.02 Classify what data is kept
- **Needs:** P3.01
- **Do:** If the feature stores or reads back anything, list each item as kept, kept with conditions, or never kept, with a reason. Anything that could be a credential, an approval, raw output, or a command defaults to never kept.
- **Verify:** The "never kept" list exists and is non-empty for any feature that persists data.
- **Record:** The list.
- **If it fails:** A persisting feature with no never-list has not been thought through.
- **Risk:** read-only

### P3.03 Write the threat model
- **Needs:** P3.02
- **Do:** Mandatory when the feature stores data, reads it back into an assistant's context, executes anything, or touches a network. For each threat give the defense. Always consider: text that instructs the assistant, a hostile writer, stale claims believed as true, secrets leaking, terminal escape sequences in stored text, injection through a command that carries free text, and a clock or ordering attack.
- **Verify:** Every threat names a defense that is specific and testable, or is listed under "remaining risk".
- **Record:** The table and the remaining risks.
- **If it fails:** A defense you cannot test becomes a remaining risk. Say so honestly.
- **Risk:** read-only

### P3.04 Design the failure behavior
- **Needs:** P3.01
- **Do:** Decide, per dependency, whether its absence means `Blocked` or "continue without it". A missing optional tool means continue and say so. A missing rule the feature depends on means `Blocked`. Never infer a missing rule.
- **Verify:** Each dependency has one stated behavior.
- **Record:** The list.
- **If it fails:** An unstated failure behavior will be improvised by whichever model reads it.
- **Risk:** read-only

### P3.05 Make it opt-in and reversible
- **Needs:** P3.01
- **Do:** Default the feature off. If it needs session state, follow the existing pattern: a key defaulting to `false`, changed only by operator commands of the form `sw:<feature>/<action>`, session-scoped, never persistent. Confirm nothing changes for someone who never enables it.
- **Verify:** You can state, in one sentence, what an operator who ignores the feature experiences.
- **Record:** The sentence.
- **If it fails:** If it cannot be off by default, the operator must decide that. Surface it in P3.09.
- **Risk:** read-only

### P3.06 Plan the tier placement and the bytes
- **Needs:** P1.04, P3.05
- **Do:** Decide what is Tier 1 (only what every session needs, and anything safety-critical), Tier 2 (the agent-facing behavior), and Tier 3 (detail and schemas). Use [03-tier-artifacts.md](03-tier-artifacts.md). Write the byte target for each new file next to the headroom from P1.04.
- **Verify:** The plan fits the limits with margin, and Tier 1 additions are the smallest that work.
- **Record:** The plan.
- **If it fails:** If it does not fit, move detail down a tier. Raising a limit needs a stated reason in the same commit and a human's agreement.
- **Risk:** read-only

### P3.07 Measure anything that scales
- **Needs:** P3.01
- **Do:** If the feature's cost grows with data, measure it at several sizes (for example 500, 2,000, 10,000, and 50,000 records) with a throwaway script, and state the cost in real numbers. Do not guess.
- **Verify:** A table of measured times exists and says on what machine.
- **Record:** The table and the machine.
- **If it fails:** If you cannot measure, say "unmeasured" in the design, not "fine".
- **Risk:** read-only

### P3.08 Write the design document
- **Needs:** P3.01, P3.02, P3.03, P3.04, P3.05, P3.06
- **Do:** Write `docs/<feature>/design.md`: goals and what it must not become, the decision table, the data classification, the threat model, scale, verification plan, what is not verified, and decisions for the human.
- **Verify:** It contains every item just listed, and every number in it has a source or a measurement.
- **Record:** The file.
- **If it fails:** Fill the gap. A design that omits its own weaknesses will be trusted too much.
- **Risk:** creates

### P3.09 Surface the decisions that belong to a human
- **Needs:** P3.08
- **Do:** List choices that are not yours to make silently: a version number, a new dependency, use of the last bytes of Tier 1, a security trade-off, an irreversible choice, anything that changes the default. For each give your recommendation and the cost of the alternative.
- **Verify:** The list is in the design document and will appear in the PR body.
- **Record:** The list.
- **If it fails:** If a decision is expensive to reverse and the operator asked only for a proposal, ask before building on it.
- **Risk:** read-only
