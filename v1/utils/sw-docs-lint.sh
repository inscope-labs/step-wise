#!/usr/bin/env bash
# StepWise: linter for the agent guide in docs/agent-guide/.
#
#   bash v1/utils/sw-docs-lint.sh [--root DIR]
#
# The guide is a prerequisite for changing StepWise, so it must not rot. This checks that:
#   1. every relative Markdown link resolves
#   2. every repository path it names (v1/... or docs/...) exists. A placeholder such as <feature> or
#      a wildcard is checked only up to its last complete directory
#   3. every guide file and template is linked from the guide's README
#   4. every step heading has the form "### P<phase>.<nn> Title", and step IDs are unique
#   5. every step has all six fields (Needs, Do, Verify, Record, If it fails, Risk)
#   6. every Risk is one of the protocol's labels
#   7. every step ID mentioned anywhere is defined, and every Needs names only steps that exist and
#      come strictly earlier, so the plan graph has no dangling reference and no cycle
#   8. every step appears in templates/task-plan.md, so the template cannot drift from the steps
#
# Exit status: 0 if all checks pass, 1 otherwise. A tree without a guide passes with a note.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for a in "$@"; do
  case "$a" in
    --root=*) ROOT="${a#--root=}" ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "sw-docs-lint: unknown argument '$a'" >&2; exit 2 ;;
  esac
done

GUIDE="$ROOT/docs/agent-guide"
ERRS=0
err() { printf 'FAIL  %s\n' "$*"; ERRS=$((ERRS + 1)); }
ok()  { printf 'ok    %s\n' "$*"; }

if [[ ! -d "$GUIDE" ]]; then
  ok "no agent guide at docs/agent-guide; nothing to check"
  echo; echo "sw-docs-lint: all checks passed"; exit 0
fi

mapfile -t FILES < <(find "$GUIDE" -type f -name '*.md' | sort)
mapfile -t PHASE_FILES < <(find "$GUIDE" -maxdepth 1 -type f -name '[0-9][0-9]-*.md' | sort)
RISKS='read-only|creates|modifies|changes project state|privileged|credential/privileged-data|network|destructive|difficult to reverse|irreversible'

# --- 1. Relative links resolve ------------------------------------------------
E=$ERRS
for f in "${FILES[@]}"; do
  dir="$(dirname "$f")"
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    case "$target" in http://*|https://*|mailto:*|\#*) continue ;; esac
    path="${target%%#*}"
    [[ -z "$path" ]] && continue
    [[ -e "$dir/$path" ]] || err "${f#"$ROOT"/}: link target does not exist: $target"
  done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//')
done
(( ERRS == E )) && ok "every relative link resolves (${#FILES[@]} guide files)"

# --- 2. Repository paths exist ------------------------------------------------
E=$ERRS
for f in "${FILES[@]}"; do
  while IFS= read -r cand; do
    [[ -z "$cand" ]] && continue
    p="$cand"
    if [[ "$p" == *'*'* || "$p" == *'<'* || "$p" == *'{'* ]]; then
      p="${p%%[*<\{]*}"; p="${p%/*}/"          # a placeholder: check only up to its last complete directory
    else
      p="$(printf '%s' "$p" | sed -E 's/[.,:;)]+$//')"
    fi
    [[ -e "$ROOT/$p" ]] || err "${f#"$ROOT"/}: names a path that does not exist: $p"
  done < <(grep -oE '(^|[^A-Za-z0-9_./@-])(v1|docs)/[A-Za-z0-9_./@*<>{}-]*' "$f" | sed -E 's/^[^vd]*//')
done
(( ERRS == E )) && ok "every repository path named in the guide exists"

# --- 3. Everything is linked from the README ----------------------------------
E=$ERRS
if [[ -f "$GUIDE/README.md" ]]; then
  for f in "${FILES[@]}" "$GUIDE"/templates/*.sh; do
    [[ -f "$f" ]] || continue
    rel="${f#"$GUIDE"/}"
    [[ "$rel" == "README.md" ]] && continue
    grep -qF "]($rel)" "$GUIDE/README.md" || err "$rel is not linked from docs/agent-guide/README.md"
  done
else
  err "docs/agent-guide/README.md is missing"
fi
(( ERRS == E )) && ok "every guide file and template is linked from the README"

# --- 4-6. Step headings, unique IDs, required fields, risk labels --------------
E=$ERRS
: > /tmp/.swdocs.$$.ids
for f in "${PHASE_FILES[@]}"; do
  rel="${f#"$GUIDE"/}"
  # malformed step headings
  while IFS= read -r bad; do
    err "$rel: malformed step heading (expected '### P<phase>.<nn> Title'): $bad"
  done < <(grep -E '^###+ P[0-9]' "$f" | grep -vE '^### P[0-9]+\.[0-9]{2} .+')
  awk -v file="$rel" -v risks="$RISKS" '
    function flush(   i, need) {
      if (id == "") return
      split("Needs|Do|Verify|Record|If it fails|Risk", need, "|")
      for (i = 1; i <= 6; i++) if (!(need[i] in seen)) printf "MISSING %s %s %s\n", file, id, need[i]
      if (("Risk" in seen) && risk !~ "^(" risks ")$") printf "BADRISK %s %s [%s]\n", file, id, risk
      printf "ID %s %s\n", id, file
      printf "NEEDS %s %s\n", id, needs
    }
    /^### P[0-9]+\.[0-9][0-9] / { flush(); id = $2; delete seen; risk = ""; needs = ""; next }
    /^##? / { flush(); id = ""; next }
    id != "" && /^- \*\*Needs:\*\*/ { seen["Needs"] = 1; s = $0; sub(/^- \*\*Needs:\*\* */, "", s); sub(/ *\(.*$/, "", s); needs = s; next }
    id != "" && /^- \*\*Do:\*\*/ { seen["Do"] = 1; next }
    id != "" && /^- \*\*Verify:\*\*/ { seen["Verify"] = 1; next }
    id != "" && /^- \*\*Record:\*\*/ { seen["Record"] = 1; next }
    id != "" && /^- \*\*If it fails:\*\*/ { seen["If it fails"] = 1; next }
    id != "" && /^- \*\*Risk:\*\*/ { seen["Risk"] = 1; s = $0; sub(/^- \*\*Risk:\*\* */, "", s); sub(/ *$/, "", s); risk = s; next }
    END { flush() }
  ' "$f" >> /tmp/.swdocs.$$.ids
done
while IFS= read -r line; do
  case "$line" in
    "MISSING "*) set -- $line; shift; err "$1: step $2 is missing its '${*:3}' field" ;;
    "BADRISK "*) err "step ${line#BADRISK * * } has a Risk that is not a protocol label (${line#BADRISK }): use one of: read-only, creates, modifies, changes project state, privileged, credential/privileged-data, network, destructive, difficult to reverse, irreversible" ;;
  esac
done < /tmp/.swdocs.$$.ids
DUPS="$(grep '^ID ' /tmp/.swdocs.$$.ids | awk '{print $2}' | sort | uniq -d)"
for d in $DUPS; do err "step ID $d is defined more than once"; done
NSTEPS="$(grep -c '^ID ' /tmp/.swdocs.$$.ids)"
(( ERRS == E )) && ok "$NSTEPS steps: unique IDs, all six fields present, every Risk is a protocol label"

# --- 7. Step references are defined, and Needs points strictly backwards --------
E=$ERRS
DEFINED="$(grep '^ID ' /tmp/.swdocs.$$.ids | awk '{print $2}' | sort -u)"
key() { local p="${1#P}"; printf '%03d%03d' "${p%%.*}" "$((10#${p##*.}))"; }
while IFS= read -r line; do
  id="$(printf '%s' "$line" | awk '{print $2}')"
  needs="${line#NEEDS "$id" }"
  [[ "$needs" == "NEEDS $id" || -z "$needs" ]] && continue
  [[ "$needs" == "nothing" ]] && continue
  for n in $(printf '%s' "$needs" | tr ',' ' '); do
    if ! grep -qxF "$n" <<< "$DEFINED"; then err "step $id needs $n, which is not defined"
    elif [[ "$(key "$n")" > "$(key "$id")" || "$(key "$n")" == "$(key "$id")" ]]; then err "step $id needs $n, which does not come strictly earlier (the plan must be acyclic)"; fi
  done
done < <(grep '^NEEDS ' /tmp/.swdocs.$$.ids)
for f in "${FILES[@]}"; do
  for t in $(grep -oE '\bP[0-9]+\.[0-9]{2}\b' "$f" | sort -u); do
    grep -qxF "$t" <<< "$DEFINED" || err "${f#"$ROOT"/}: mentions step $t, which is not defined"
  done
done
(( ERRS == E )) && ok "every step reference is defined, and every dependency points strictly backwards"

# --- 8. The task-plan template covers every step -------------------------------
E=$ERRS
PLAN="$GUIDE/templates/task-plan.md"
if [[ -f "$PLAN" ]]; then
  for s in $DEFINED; do
    grep -qE "(^|[^0-9A-Za-z.])${s//./\\.}([^0-9]|$)" "$PLAN" || err "templates/task-plan.md does not list step $s"
  done
else
  err "templates/task-plan.md is missing"
fi
(( ERRS == E )) && ok "templates/task-plan.md lists every step"

rm -f /tmp/.swdocs.$$.ids
echo
if (( ERRS == 0 )); then echo "sw-docs-lint: all checks passed"; exit 0
else echo "sw-docs-lint: $ERRS check(s) failed"; exit 1; fi
