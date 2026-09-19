#!/usr/bin/env bash
# StepWise — static checks for the three-tier context system (plan Phases 1, 6.1).
#
# Usage:
#   bash v1/utils/sw-lint.sh            # run all checks; exit 1 if any fail
#   bash v1/utils/sw-lint.sh --report   # also print measured sizes
#   bash v1/utils/sw-lint.sh --v1=DIR   # lint a different v1/ directory (used by the tests)
#
# What it can check statically: file sizes against spec context/size-limits, tier
# headers and Framework compatibility, that the prompt's feature index and each
# feature's spec references resolve both ways, the one-way hierarchy
# (Prompt -> Feature -> Spec), that a curated list of 1.5.0 rules is still in the
# prompt, and that every risk label in the prompt is understood by clipcopy.sh.
# What it cannot check: how a model behaves. Behavioral acceptance tests
# (plan Phase 6) are separate.

set -u

V1="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT=0
for a in "$@"; do
  case "$a" in
    --report) REPORT=1 ;;
    --v1=*)   V1="${a#--v1=}" ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "sw-lint: unknown argument '$a'" >&2; exit 2 ;;
  esac
done

PROMPT="$V1/prompt.md"
FEAT="$V1/feature"
SPEC="$V1/specs"
LIMITS="$SPEC/context/size-limits.md"
INVARIANTS="$V1/utils/prompt-invariants.txt"
ERRS=0

err() { printf 'FAIL  %s\n' "$*"; ERRS=$((ERRS + 1)); }
ok()  { printf 'ok    %s\n' "$*"; }
fsize() { wc -c < "$1" | tr -d ' '; }
hdr() { grep -m1 -E "^\| $2 \|" "$1" | sed -E 's/^\| [^|]+\| *//; s/ *\|[[:space:]]*$//'; }

feature_files() { compgen -G "$FEAT/*.md" >/dev/null && ls "$FEAT"/*.md; }
spec_files()    { compgen -G "$SPEC/*/*.md" >/dev/null && ls "$SPEC"/*/*.md; }

# --- 1. Prompt and Framework version ------------------------------------------
if [[ ! -f "$PROMPT" ]]; then
  err "prompt not found: $PROMPT"; exit 1
fi
PV="$(sed -n '2p' "$PROMPT")"
re='^Version: ([0-9]+)\.([0-9]+)\.[0-9]+(-[A-Za-z0-9.]+)?$'
if [[ "$PV" =~ $re ]]; then
  PMM="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  ok "prompt version line: '$PV' (major.minor $PMM)"
else
  err "prompt line 2 is not a valid 'Version: X.Y.Z[-suffix]' line: '$PV'"; PMM=""
fi

# --- 2. Limits (single source of truth: the spec) -----------------------------
limit_of() { grep -E "^limit: $1 = [0-9]+\$" "$LIMITS" 2>/dev/null | head -1 | sed 's/.*= //'; }
if [[ ! -f "$LIMITS" ]]; then
  err "size-limits spec not found: $LIMITS"
  L_PROMPT=""; L_FEAT=""; L_SPEC=""; L_OPT=""
else
  L_PROMPT="$(limit_of prompt_bytes)"; L_FEAT="$(limit_of feature_bytes)"
  L_SPEC="$(limit_of spec_section_bytes)"; L_OPT="$(limit_of max_optional_bytes)"
  for pair in "prompt_bytes:$L_PROMPT" "feature_bytes:$L_FEAT" "spec_section_bytes:$L_SPEC" "max_optional_bytes:$L_OPT"; do
    [[ -z "${pair#*:}" ]] && err "missing 'limit: ${pair%%:*} = N' line in size-limits spec"
  done
fi

# --- 3. Sizes -----------------------------------------------------------------
PSIZE="$(fsize "$PROMPT")"
if [[ -n "$L_PROMPT" ]]; then
  if (( PSIZE <= L_PROMPT )); then ok "prompt size $PSIZE <= $L_PROMPT bytes"
  else err "prompt is $PSIZE bytes, limit is $L_PROMPT"; fi
fi
MAXF=0; MAXFN=""; MAXS=0; MAXSN=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  s="$(fsize "$f")"; n="$(basename "$f")"
  (( s > MAXF )) && { MAXF=$s; MAXFN=$n; }
  if [[ -n "$L_FEAT" ]] && (( s > L_FEAT )); then err "feature $n is $s bytes, limit is $L_FEAT"; fi
done < <(feature_files)
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  s="$(fsize "$f")"; n="${f#"$SPEC"/}"
  (( s > MAXS )) && { MAXS=$s; MAXSN=$n; }
  if [[ -n "$L_SPEC" ]] && (( s > L_SPEC )); then err "spec $n is $s bytes, limit is $L_SPEC"; fi
done < <(spec_files)
[[ -n "$L_FEAT" ]] && (( MAXF <= L_FEAT )) && ok "every feature <= $L_FEAT bytes (largest: $MAXFN, $MAXF)"
[[ -n "$L_SPEC" ]] && (( MAXS <= L_SPEC )) && ok "every spec section <= $L_SPEC bytes (largest: $MAXSN, $MAXS)"
OPT=$((MAXF + MAXS))
if [[ -n "$L_OPT" ]]; then
  if (( OPT <= L_OPT )); then ok "worst-case optional context $OPT <= $L_OPT bytes (largest feature + largest spec section)"
  else err "worst-case optional context is $OPT bytes ($MAXFN + $MAXSN), limit is $L_OPT"; fi
fi

# --- 4. Tier headers and Framework compatibility ------------------------------
check_header() { # file label kind
  local f="$1" label="$2" fw mm
  for k in Framework Version Supersedes Status; do
    [[ -z "$(hdr "$f" "$k")" ]] && err "$label: header row '$k' is missing"
  done
  if [[ -z "$(hdr "$f" 'Depends on')" && -z "$(hdr "$f" 'Parent feature')" ]]; then
    err "$label: header needs a 'Depends on' or 'Parent feature' row"
  fi
  fw="$(hdr "$f" Framework)"
  if [[ "$fw" =~ ^([0-9]+)\.([0-9]+) ]]; then
    mm="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    if [[ -n "$PMM" && "$mm" != "$PMM" ]]; then
      err "$label: Framework $mm is incompatible with the prompt ($PMM); it must not load"
    fi
  else
    err "$label: Framework row is not a version: '$fw'"
  fi
}
E4=$ERRS
NF=0; NS=0
while IFS= read -r f; do [[ -z "$f" ]] && continue; check_header "$f" "feature $(basename "$f")"; NF=$((NF+1)); done < <(feature_files)
while IFS= read -r f; do [[ -z "$f" ]] && continue; check_header "$f" "spec ${f#"$SPEC"/}"; NS=$((NS+1)); done < <(spec_files)
(( ERRS == E4 )) && ok "checked headers of $NF features and $NS specs"

# --- 5. Index integrity (prompt <-> features) ---------------------------------
E5=$ERRS
INDEXED="$(grep -oE '^\| `feature:[a-z0-9-]+`' "$PROMPT" | sed -E 's/^\| `feature://; s/`$//' | sort -u)"
MENTIONED="$(grep -oE 'feature:[a-z0-9-]+' "$PROMPT" | sed 's/^feature://' | sort -u)"
for n in $INDEXED; do [[ -f "$FEAT/$n.md" ]] || err "prompt index lists feature:$n but $FEAT/$n.md does not exist"; done
for n in $MENTIONED; do [[ -f "$FEAT/$n.md" ]] || err "prompt mentions feature:$n but $FEAT/$n.md does not exist"; done
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  n="$(basename "$f" .md)"
  grep -qE "^\| \`feature:$n\` \|" "$PROMPT" || err "feature $n.md exists but is not in the prompt's feature index"
done < <(feature_files)
(( ERRS == E5 )) && ok "prompt feature index matches the feature files ($(echo "$INDEXED" | wc -w | tr -d ' ') indexed)"

# --- 6. Spec references (features <-> specs) ----------------------------------
E6=$ERRS
REFERENCED=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  for a in $(grep -oE 'spec:[a-z0-9-]+/[a-z0-9-]+' "$f" | sort -u); do
    p="$SPEC/${a#spec:}.md"
    [[ -f "$p" ]] || err "feature $(basename "$f") references $a but $p does not exist"
    REFERENCED="$REFERENCED ${a#spec:}"
  done
done < <(feature_files)
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  rel="${f#"$SPEC"/}"; rel="${rel%.md}"
  case " $REFERENCED " in *" $rel "*) : ;; *) err "spec $rel.md is not referenced by any feature (unreachable)";; esac
done < <(spec_files)
(( ERRS == E6 )) && ok "every referenced spec resolves and every spec is reachable"

# --- 7. Hierarchy: Prompt -> Feature -> Spec, one way -------------------------
E7=$ERRS
if grep -qE 'spec:[a-z0-9-]+/[a-z0-9-]+' "$PROMPT"; then
  err "prompt references a spec directly (Prompt -> Spec is not allowed): $(grep -oE 'spec:[a-z0-9-]+/[a-z0-9-]+' "$PROMPT" | head -1)"
fi
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  self="$(basename "$f" .md)"
  for n in $(grep -oE 'feature:[a-z0-9-]+' "$f" | sed 's/^feature://' | sort -u); do
    [[ "$n" != "$self" ]] && err "feature $self.md points sideways to feature:$n (Feature -> Feature is not allowed)"
  done
done < <(feature_files)
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  rel="${f#"$SPEC"/}"
  grep -q 'prompt\.md' "$f" && err "spec $rel mentions the prompt file (Spec -> Prompt is not allowed)"
  if grep -v '^| Parent feature |' "$f" | grep -qE 'feature:[a-z0-9-]+'; then
    err "spec $rel contains a feature: address outside its 'Parent feature' row"
  fi
done < <(spec_files)
(( ERRS == E7 )) && ok "hierarchy checked (Prompt -> Feature -> Spec only)"

# --- 8. Curated 1.5.0 invariants still present in the prompt -------------------
if [[ ! -f "$INVARIANTS" ]]; then
  err "invariants list not found: $INVARIANTS"
else
  NI=0; MISSING=0
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    NI=$((NI + 1))
    if ! grep -qF -- "$line" "$PROMPT"; then err "prompt is missing required rule text: $line"; MISSING=$((MISSING+1)); fi
  done < "$INVARIANTS"
  (( MISSING == 0 )) && ok "all $NI required rule strings are present in the prompt"
fi

# --- 9. Risk labels in the prompt are understood by clipcopy.sh ----------------
CLIP="$V1/utils/clipcopy.sh"
if [[ ! -f "$CLIP" ]]; then
  err "clipcopy.sh not found: $CLIP"
else
  LABELS="$(
    { sed -n 's/^Risk: <\(.*\)>$/\1/p' "$PROMPT" | sed 's# / #\n#g'
      sed -n 's/.*Classify each functional step as applicable: \([^.]*\)\..*/\1/p' "$PROMPT" | sed 's/, or /, /; s/, /\n/g'
    } | sed 's/^ *//; s/ *$//' | sort -u
  )"
  NL=0; SENS=0
  while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    NL=$((NL + 1))
    # shellcheck source=/dev/null
    cls="$( source "$CLIP" >/dev/null 2>&1; _sw_risk_class "$label" )"
    case "$cls" in
      eligible) : ;;
      sensitive) SENS=$((SENS + 1)) ;;
      *) err "risk label '$label' in the prompt is '${cls:-unknown}' to clipcopy.sh (the two have drifted)" ;;
    esac
  done <<< "$LABELS"
  if (( NL == 0 )); then err "found no risk labels in the prompt to check"
  elif (( SENS == 0 )); then err "no risk label in the prompt classifies as sensitive in clipcopy.sh"
  else ok "all $NL prompt risk labels are understood by clipcopy.sh ($SENS sensitive)"; fi
fi

# --- Report -------------------------------------------------------------------
if (( REPORT == 1 )); then
  echo
  echo "== Measured sizes (source bytes; tokens are an ESTIMATE at bytes/4) =="
  printf '%-34s %8s %10s\n' item bytes est.tokens
  printf '%-34s %8s %10s\n' "prompt (always loaded)" "$PSIZE" "$((PSIZE / 4))"
  while IFS= read -r f; do [[ -z "$f" ]] && continue; s="$(fsize "$f")"; printf '%-34s %8s %10s\n' "feature/$(basename "$f")" "$s" "$((s / 4))"; done < <(feature_files)
  while IFS= read -r f; do [[ -z "$f" ]] && continue; s="$(fsize "$f")"; printf '%-34s %8s %10s\n' "specs/${f#"$SPEC"/}" "$s" "$((s / 4))"; done < <(spec_files)
  TOTAL=$PSIZE
  for f in $(feature_files) $(spec_files); do TOTAL=$((TOTAL + $(fsize "$f"))); done
  echo
  printf '%-34s %8s %10s\n' "normal session (prompt only)" "$PSIZE" "$((PSIZE / 4))"
  printf '%-34s %8s %10s\n' "worst case (+largest feature+spec)" "$((PSIZE + OPT))" "$(((PSIZE + OPT) / 4))"
  printf '%-34s %8s %10s\n' "everything (forbidden by the rules)" "$TOTAL" "$((TOTAL / 4))"
fi

echo
if (( ERRS == 0 )); then echo "sw-lint: all checks passed"; exit 0
else echo "sw-lint: $ERRS check(s) failed"; exit 1; fi
