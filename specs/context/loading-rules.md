# Spec: Context Loading Rules

| | |
|---|---|
| Framework | 1.6.0 |
| Component | spec `context/loading-rules` |
| Version | 1.6.0 |
| Parent feature | `feature:context` |
| Supersedes | nothing |
| Status | Released. Loaded on demand. |

Implements plan sections 1.2, 1.4, 1.5, 1.6, 1.7, 1.8. Enforced statically by `v1/utils/sw-lint.sh`.

## 1. Addresses

| Address | Resolves to |
|---|---|
| `feature:<name>` | `v1/feature/<name>.md` |
| `spec:<feature>/<section>` | `v1/specs/<feature>/<section>.md` |

A spec section is one file. Sections are small on purpose, so a rule can be loaded without a whole document. `<name>`, `<feature>` and `<section>` are lowercase letters, digits and hyphens.

Resolution is **relative to the location the prompt was loaded from**. Call the directory that holds the prompt `<base>`. Then `feature:<name>` is `<base>/feature/<name>.md`, and a spec is `<base>/specs/<feature>/<section>.md`. This keeps a pinned copy of the prompt (a tag or a commit) loading pinned features and specs, never a newer `main`.

## 2. Obtaining a reference

In order:

1. If you can fetch, fetch the resolved address.
2. If you cannot, ask the operator to paste the file, naming the address.
3. If neither works, state is `Blocked` for whatever depends on it. Say: *"Required reference information is unavailable. I will not infer the missing protocol rule."* Then stop or ask for it.

If the prompt itself was pasted with no location, ask for the base location or for pasted references. Do not guess a URL.

Never fill a gap from general knowledge. That also applies when a loaded feature says a deeper spec is required and it is unavailable.

## 3. Version compatibility

Each feature and spec declares `Framework`, `Version`, `Depends on`, `Supersedes` and `Status` in its header table.

- Load an item only if its `Framework` **major.minor** equals the prompt's `Version` major.minor. `1.6.0-dev` and `1.6.0` are compatible with each other; `1.5.x` and `1.7.x` are not.
- An incompatible or undeclared item is treated as unavailable (section 2, step 3). It never loads silently.
- A pre-release suffix (`-dev`, `-draft`) does not affect compatibility. Release (plan Phase 7) removes them.

## 4. Precedence

`Prompt > Feature > Specs`. A lower tier may add detail or restrict behavior further. It may not relax a prompt rule, unless the prompt explicitly delegates that rule to it.

- "Load the clipboard feature for details" is **not** delegation. It only says where more detail lives.
- If a feature or spec appears to relax a prompt rule (for example a looser confirmation requirement), keep the prompt's rule, and tell the operator that the reference conflicts with it.
- If a spec conflicts with the feature that points to it, the feature wins.

## 5. Escalation

```
1. Prompt only. Can the task be completed?  yes → proceed
2. No → load the ONE relevant feature.       Can it now?  yes → proceed
3. No, or the feature names a spec → load that spec section only.
```

Do not load Tier 3 because it exists. Do not load a second feature or a second spec section without a new, specific need. Record each load in `context_loaded` (see the context feature).

## 6. Hierarchy

Loading flows one way: `Prompt → Feature → Spec`.

| Edge | Allowed |
|---|---|
| Prompt → Feature | yes, through the index |
| Feature → its own Specs | yes, through its "Detailed references" |
| Feature → a Spec of another feature's directory | yes, if it lists it in its own references (still downward) |
| Prompt → Spec | **no** |
| Feature → another Feature | **no** |
| Spec → Prompt | **no** |

A spec's `Parent feature` row is metadata. It does not load anything.

## 7. Discovery

The prompt's feature index lists what exists and when to load it. Each feature's "Detailed references" section lists its specs. The agent never needs the whole file tree, and never scans directories.
