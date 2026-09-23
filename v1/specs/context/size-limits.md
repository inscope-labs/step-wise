# Spec: Context Size Limits

| | |
|---|---|
| Framework | 1.6.1-dev |
| Component | spec `context/size-limits` |
| Version | 1.6.1-dev |
| Parent feature | `feature:context` |
| Supersedes | nothing |
| Status | Released. Loaded on demand. |

Implements plan sections 1.3 and 1.9. Checked by `bash v1/utils/sw-lint.sh`, which reads the `limit:` lines below, so this file is the single source of truth for the numbers.

## 1. Three different measurements

```
source size  ≠  serialized context size  ≠  token cost
```

| Measurement | What it is | Where it is measured |
|---|---|---|
| Source size | bytes of the file in the repository | `sw-lint.sh` (**enforced**) |
| Serialized context size | bytes actually supplied to the model for a session: the prompt plus whatever optional items were loaded | `sw-lint.sh --report` (worst case) |
| Token cost | what the model's tokenizer charges | **estimated** as `bytes / 4`. The real figure depends on the tokenizer and must be measured with it |

Source bytes are the enforced metric because they are deterministic and checkable in CI. Token figures are an estimate and are labeled as one everywhere.

## 2. Limits

Each tier has its own independent limit, because the tiers have different jobs:

```
limit: prompt_bytes = 18000
limit: extended_bytes = 12000
limit: feature_bytes = 7000
limit: spec_section_bytes = 9000
limit: max_optional_bytes = 14000
```

| Limit | Applies to | Rule |
|---|---|---|
| `prompt_bytes` | the mandatory prompt file, always loaded | one fixed maximum |
| `extended_bytes` | `v1/extended.md`, loaded once after the operator's first message | one fixed maximum; independent of `prompt_bytes` so each can be reasoned about on its own |
| `feature_bytes` | each file in `v1/feature/` | per loaded feature |
| `spec_section_bytes` | each file in `v1/specs/*/` | per requested section; larger than a feature because specs hold detail |
| `max_optional_bytes` | the largest feature plus the largest spec section | the most optional context normally loaded at once, on top of prompt + extended (one feature and one spec section). The linter checks that this worst case fits |

Derived targets, expressed in the estimate unit:

- **Steady-state session** (prompt plus extended, before any feature/spec): 30,000 bytes, about 7,500 tokens estimated. This is the normal case once the operator has sent a first message, not an occasional one.
- **Total instruction context** (steady-state plus the optional maximum): 44,000 bytes, about 11,000 tokens estimated.
- **Contextual Memory**: keep it to roughly 2,000 tokens of validated state. This is a runtime target. It cannot be checked statically, and compaction (see the context feature) is how you stay under it.

A change that needs to exceed a limit must change the number here, in the same commit, with the reason. That is the point of a bound.

## 3. What the limits are for

The framework grew a ledger, extraction, modes and memory rules for 1.6.0. Without tiers, all of that would be part of the mandatory prompt. With tiers, it loads on demand. 1.6.1 added a fourth tier, the extended prompt (`v1/extended.md`), to hold the feature index, the full state machine, and other detail that is worth having in every session but does not need to be in the operator's very first exchange. At the time each was introduced:

| | Bytes | Est. tokens |
|---|---|---|
| 1.5.0 mandatory prompt | 18,003 | ~4,500 |
| 1.6.0 mandatory prompt | 19,001 | ~4,750 |
| 1.6.1 mandatory prompt (after the extended-prompt split) | ~18,000 | ~4,500 |
| 1.6.1 extended prompt (new) | ~8,000 | ~2,000 |
| Worst case with optional context (largest feature + largest spec) | ~31,000 | ~7,800 |
| Everything loaded at once, which the rules forbid | ~63,000 | ~15,750 |

Splitting the extended prompt out let the mandatory prompt shrink back toward its 1.5.0 size even after 1.6.1 added a welcome message, batching guidance, an operator-question allowance, and several protocol fixes: that new material is smaller than what moved to `extended.md` (the feature index, the full Default Pattern, and the full state machine). Run `bash v1/utils/sw-lint.sh --report` for current figures.

## 4. Failure behavior

A limit violation fails the lint. The remedy is to move detail down a tier or shorten it. Raising a limit needs a stated reason (section 2).
