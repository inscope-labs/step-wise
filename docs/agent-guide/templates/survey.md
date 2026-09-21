# <Feature>: repository survey

Deliverable of P2. It lists every area of the repository that relates to <feature>, whether directly or indirectly, and says what each constrains or must change. Based on the tree at `<branch>` `<sha>`. Line numbers are for that commit.

**Method.** <How you scored the files: the concepts you searched for, and how you then read the definitions directly.>

**Relation key.** **Direct**: defines or implements it. **Produces**: generates the content or evidence. **Governs**: constrains how it may be loaded, sized, versioned, or trusted. **Enforces**: tooling that must be extended so it cannot drift. **Adjacent**: related, and deliberately kept separate. **Outside**: the environment.

## 1. Direct

| Area | What it says now | What the change must do |
|---|---|---|
| <file and line> | <what it says> | <extend, avoid, or reconcile> |

## 2. Produces

| Area | Relevance | Consequence |
|---|---|---|

## 3. Governs

| Area | Relevance | Consequence |
|---|---|---|

## 4. Enforces

| Area | Consequence |
|---|---|

## 5. Adjacent

| Area | Why separate |
|---|---|

## 6. Outside the repository

| Area | Relevance |
|---|---|

## 7. Conclusions

1. **What already exists** and should be extended, not duplicated: <...>
2. **What collides** with the proposal: <...>
3. **What must be reused, not reimplemented:** <...>
4. **Boundary constraints** that shape the design: <...>
5. **Budgets that bind:** <...>
