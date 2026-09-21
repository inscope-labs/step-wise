# 07. Change types

Not every change needs every phase. Pick the row that fits (step P0.04) and follow its phase list. If nothing fits, say so and ask. The rules in [00-principles.md](00-principles.md) apply to every row.

| Change type | Examples | Phases | Extra requirements |
|---|---|---|---|
| **New feature** | A new opt-in capability with its own feature file and specs | P0 to P9 (P5 only if code is needed) | Survey and design documents. Opt-in and default off. A threat model if it stores, reads back, executes, or touches a network |
| **Rule correction** | Fixing wording that changes behavior in the prompt, a feature, or a spec | P0, P1, reduced P2, P4, P6.05, P6.06, P7, P8, P9 | In the reduced survey, search for **every** use of the rule. Update `v1/utils/prompt-invariants.txt` deliberately if a protected rule changes. Add or update a scenario if a model's behavior is involved. Record it under `Fixed` in `## Unreleased` |
| **Safety fix** | A fail-open gate, a leak, a way around a limit | P0, P1, then: a test that fails first, the minimal patch, P6.01, P7, P8, P9 | Do nothing else in the same branch. Say plainly in the PR what was unsafe and since when. Add a parity or regression check so it cannot return |
| **Tooling change** | Changes under `v1/utils/` or `v1/tests/` | P0, P1, P5.05 to P5.08, P6.01, P6.02, P6.04, P7, P8, P9 | Tests must not depend on the repository's current state. Injected bugs for each behavior you change |
| **Documentation only** | README, `docs/` | P0, P1.01 to P1.03, P7.04, P8, P9 | No version change and no survey. Run `bash v1/utils/sw-docs-lint.sh` if you touched this guide. Never write a number without a source |
| **Budget change** | Raising or lowering a tier limit | P0, P1, P3.09, P4, P7, P8, P9 | The `limit:` line in `v1/specs/context/size-limits.md` and the change that needs it go in the **same commit**, with the reason in the message. It is a human decision |
| **Scenario or evaluation only** | New or changed acceptance scenarios | P0, P1, P6.05, P6.06, P7, P8, P9 | Recorded acceptance results are tied to the exact prompt, tiers, and scenarios by hash. Any change to those makes existing results stale, and you must say so |
| **Release** | Removing `-dev`, dating a changelog entry | **Not this guide's branch flow** | Use `v1/utils/sw-release.sh` as documented in `docs/1.6.0-plan/compatibility.md`, section 6. Never mix a release with feature commits. A waiver is recorded and scoped, and is the operator's decision |
| **Changing this guide** | Adding a step, fixing a step, adding a pitfall | P0, P1.01 to P1.03, P7.04, P8, P9 | Keep every step atomic with its fields. Run the docs linter. Add a pitfall only for something that actually happened, with the step that prevents it |

## Version rules

- **Only `v1/utils/sw-release.sh` removes a `-dev` suffix.** A feature branch never does.
- After a release, the next cycle starts by setting the prompt's line 2 to the next `-dev` version and adding an `## Unreleased` section to `CHANGELOG.md`.
- An additive opt-in feature is a patch-level cycle unless the operator chooses a minor bump. A minor bump forces every tier file's `Framework` to change, because major.minor must match the prompt's (`v1/specs/context/loading-rules.md`, section 3).
- Record the choice and its reason. It is a P3.09 decision.

## When the change touches more than one row

Split it into separate branches by row when you can. A safety fix does not ride along with a feature. If you cannot split it, name the strictest row's requirements as the ones that apply to the whole branch.
