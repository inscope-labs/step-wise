# Feature: <Name>

| | |
|---|---|
| Framework | <major.minor.patch> (unreleased) |
| Component | feature `<feature>` (Tier 2) |
| Version | <major.minor.patch>-dev |
| Depends on | specs `<feature>/<section>`, `<feature>/<section>` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

Precedence: Prompt > Feature > Specs. Nothing here relaxes a rule in the mandatory prompt.

Load this when <one concrete condition>.

## 1. What it is

<What the capability is, that it is opt-in, and what it does not do.>

## 2. Session state

<If opt-in: the key, its default (`false`), the operator commands `sw:<feature>/<action>` that change it, that it is session-scoped and never persistent, and what to do on enable.>

## 3. Commands

<Each command the operator runs, and the rule for free text: single quotes, and no single quote, backslash, or newline in it.>

## 4. The protocol you follow

<Numbered behavior for the agent: when to use it, what to show the operator, what never to do.>

## 5. Invariants

- <One line each. Every line here is a candidate for `prompt-invariants.txt` if it must survive edits.>

## 6. Failure behavior

<Missing optional tool: continue without it and say so. Missing spec this feature points to: `Blocked` for the behavior that depends on it. Never infer the missing rule.>

## Detailed references

- `spec:<feature>/<section>`: <what it holds>
