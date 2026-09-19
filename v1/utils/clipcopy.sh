#!/usr/bin/env bash
# StepWise — opt-in clipboard-copy wrapper 
#
# Usage:
#   source clipcopy.sh
#   runcopy -- <command> [args...]              # display + copy output
#   runcopy --no-copy -- <command> [args...]    # per-invocation skip, no copy
#   runcopy --risk=credential -- <command> ...  # auto-bypasses copy, shows notice
#   runcopy --risk=privileged-data -- <command> ...
#   runcopy --risk=credential/privileged-data -- <command> ...   # combined label
#
# Risk labels are fail-closed: only known non-sensitive labels (read-only,
# creates, modifies, network, destructive, ...) permit a copy. Sensitive labels
# and any unrecognized label bypass the copy. Omitting --risk entirely means
# the operator wrapped the command by hand and asked for a copy (1.5.0 behavior).
#
# Output is ALWAYS shown on the terminal, exactly as it would be without this
# wrapper. Clipboard copy is strictly additive and never replaces display.
#
# Clipboard backend priority: termux-clipboard-set > xclip > pbcopy > clip.exe
# If none are found, output still displays; a notice is printed and nothing
# is copied.

_sw_notice() {
  # Notices go to stderr so they never contaminate piped stdout.
  echo "[StepWise] $*" >&2
}

# --- Risk classification (fail-closed) ---------------------------------------
# A label is copy-eligible ONLY if every comma-separated part of it is a known
# non-sensitive label. Anything sensitive, empty, or unrecognized is treated as
# "do not copy". This is deliberate: a typo, a case variant, or a label this
# script has never heard of must never result in a copy.

_sw_norm_label() {
  # lowercase; spaces/underscores -> hyphens; trim leading/trailing hyphens.
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | sed -e 's/^-*//' -e 's/-*$//'
}

_sw_risk_class() {
  # Prints one of: eligible | sensitive | unrecognized
  local raw="$1" part norm result="eligible"
  while IFS= read -r part; do
    norm="$(_sw_norm_label "$part")"
    case "$norm" in
      *credential*|*privileged-data*|*secret*|*sensitive*)
        printf 'sensitive\n'
        return 0
        ;;
      read-only|creates|creates-files|modifies|modifies-files|changes-project-state|privileged|network|destructive|difficult-to-reverse|irreversible|eligible)
        : ;;
      *)
        result="unrecognized"
        ;;
    esac
  done <<< "$(printf '%s' "$raw" | tr ',' '\n')"
  printf '%s\n' "$result"
}

_sw_clipboard_copy() {
  # Reads stdin, writes it to whichever clipboard tool is available.
  if command -v termux-clipboard-set >/dev/null 2>&1; then
    termux-clipboard-set
    _sw_notice "Output copied to clipboard (termux-clipboard-set)."
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard
    _sw_notice "Output copied to clipboard (xclip)."
  elif command -v pbcopy >/dev/null 2>&1; then
    pbcopy
    _sw_notice "Output copied to clipboard (pbcopy)."
  elif command -v clip.exe >/dev/null 2>&1; then
    clip.exe
    _sw_notice "Output copied to clipboard (clip.exe)."
  else
    cat >/dev/null
    _sw_notice "No clipboard tool found (tried termux-clipboard-set, xclip, pbcopy, clip.exe). Output not copied."
    return 1
  fi
}

runcopy() {
  local risk=""
  local risk_set=0
  local no_copy=0
  local v

  # Parse leading flags; everything after -- is the command to run.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --risk=*)
        # Labels accumulate across repeated --risk flags, so a later benign
        # label can never override an earlier sensitive one. An explicitly
        # empty value is kept as a sentinel and classifies as unrecognized.
        v="${1#--risk=}"
        [[ -z "$v" ]] && v="<empty>"
        risk="${risk:+$risk,}$v"
        risk_set=1
        shift
        ;;
      --risk)
        _sw_notice "runcopy: --risk requires a value (use --risk=<label>)."
        return 2
        ;;
      --no-copy)
        no_copy=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -eq 0 ]]; then
    _sw_notice "runcopy: no command given. Usage: runcopy [--risk=<label>] [--no-copy] -- <command> [args...]"
    return 2
  fi

  # Automatic bypass (fail-closed). Sensitive labels, and any label this script
  # does not recognize, never get copied, regardless of operator request. This
  # check is independent of --no-copy and cannot be overridden by it.
  if [[ "$risk_set" -eq 1 ]]; then
    case "$(_sw_risk_class "$risk")" in
      sensitive)
        _sw_notice "Clipboard copy bypassed: command classified as '$risk' risk. Output is displayed only, not copied."
        "$@"
        return $?
        ;;
      unrecognized)
        _sw_notice "Clipboard copy bypassed: unrecognized risk label '$risk' (fail-closed). Output is displayed only, not copied."
        "$@"
        return $?
        ;;
    esac
  fi

  # Per-invocation skip requested by the operator.
  if [[ "$no_copy" -eq 1 ]]; then
    "$@"
    return $?
  fi

  # Default path: display normally AND copy.
  local tmp
  tmp="$(mktemp)"
  "$@" | tee "$tmp"
  local status=${PIPESTATUS[0]}
  _sw_clipboard_copy < "$tmp"
  rm -f "$tmp"
  return "$status"
}

# --- Session ledger (1.6.0 draft) ---------------------------------------------
# Spec: v1/specs/clipboard/ledger-format.md and extraction.md.
#
#   sw_session_start                       # once per shell; exports SW_SESSION_ID
#   runledger [--objective=..] [--step=..] [--risk=..] [--copy] -- <command> [args...]
#                                          # --copy = automatic clipboard duplication
#   sw_ledger_list                         # inspect: index, exit, risk, step
#   sw_copy_clip [--stdout] [spec]         # spec: N | A-B | N+ | (none = final)
#
# The ledger is auxiliary evidence. runledger never alters terminal display or
# the command's exit status, and a ledger failure never blocks the command.

_sw_state_root() { printf '%s' "${STEPWISE_HOME:-$HOME/.cache/stepwise}"; }

_sw_rand() {
  local r
  r="$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [[ ${#r} -eq 8 ]] || r="$(printf '%04x%04x' "$RANDOM" "$RANDOM")"
  printf '%s' "$r"
}

_sw_valid_id() {
  local re='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
  [[ "$1" =~ $re ]]
}

_sw_oneline() {
  # One line, no tabs/CRs, max 500 chars; empty becomes "-".
  local v
  v="$(printf '%s' "$1" | tr '\n\t\r' '   ' | cut -c1-500)"
  printf '%s' "${v:--}"
}

_sw_active_ledger() {
  # Prints the active session's ledger path, or fails with a notice.
  local id="${SW_SESSION_ID:-}" dir
  if [[ -z "$id" ]]; then
    _sw_notice "No active StepWise session (SW_SESSION_ID is unset). Run: sw_session_start"
    return 1
  fi
  if ! _sw_valid_id "$id"; then
    _sw_notice "Invalid SW_SESSION_ID '$id'. Refusing to use it."
    return 1
  fi
  dir="$(_sw_state_root)/sessions/$id"
  if [[ ! -f "$dir/ledger.log" ]]; then
    _sw_notice "Ledger not found for session '$id' ($dir/ledger.log)."
    return 1
  fi
  printf '%s\n' "$dir/ledger.log"
}

_sw_lock() {
  local i=0
  while ! mkdir "$1/.lock" 2>/dev/null; do
    i=$((i + 1))
    [[ $i -gt 100 ]] && return 1
    sleep 0.05 2>/dev/null || sleep 1
  done
}
_sw_unlock() { rmdir "$1/.lock" 2>/dev/null; }

sw_session_start() {
  local id root dir
  root="$(_sw_state_root)"
  id="$(date -u +%Y%m%dT%H%M%SZ)-$$-$(_sw_rand)"
  dir="$root/sessions/$id"
  (
    umask 077
    mkdir -p "$root/sessions" && mkdir "$dir" && : > "$dir/ledger.log" && {
      printf 'session: %s\n' "$id"
      printf 'created: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'shell_pid: %s\n' "$$"
      printf 'cwd: %s\n' "$PWD"
    } > "$dir/metadata"
  ) || { _sw_notice "Could not create session directory under '$root/sessions'."; return 1; }
  export SW_SESSION_ID="$id"
  _sw_notice "Session started: $id"
  _sw_notice "Ledger: $dir/ledger.log"
}

_sw_ledger_scan() {
  # Emits one TSV row per record: idx start end status risk exit withheld
  # bodystart nlines timestamp step. status is ok|bad|dup. Junk lines between
  # records emit "!<TAB>lineno". Bodies are length-prefixed, so body text that
  # looks like a header or footer is never misparsed. No field is ever empty.
  awk '
  function dflt(v) { gsub(/\t/, " ", v); return (v == "" ? "-" : v) }
  function begin(line,   f) {
    split(line, f, " ")
    idx = f[3]; nonce = f[5]; sub(/^nonce=/, "", nonce)
    risk = ""; ex = ""; wh = ""; ts = ""; stp = ""; nl = ""
    start = NR; bstart = 0; state = 1
  }
  function fin(status, endln) {
    if (status == "ok" && (idx in seen)) status = "dup"
    seen[idx] = 1
    printf "%s\t%d\t%d\t%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\n", idx, start, endln, status, dflt(risk), dflt(ex), dflt(wh), bstart, (nl ~ /^[0-9]+$/ ? nl + 0 : 0), dflt(ts), dflt(stp)
    state = 0
  }
  function handle(line) {
    if (state == 0) {
      if (line ~ /^=== STEP [1-9][0-9]* session=[A-Za-z0-9._-]+ nonce=[0-9a-f]+ ===$/) { begin(line); return }
      if (line != "") printf "!\t%d\n", NR
      return
    }
    if (state == 1) {
      if (line == "output:") {
        if (nl !~ /^[0-9]+$/) { fin("bad", NR); return }
        bstart = NR + 1
        if (nl + 0 == 0) { state = 3 } else { remaining = nl + 0; state = 2 }
        return
      }
      if (line ~ /^=== /) { fin("bad", NR - 1); handle(line); return }
      if (line ~ /^risk: /) risk = substr(line, 7)
      else if (line ~ /^exit_status: /) ex = substr(line, 14)
      else if (line ~ /^output_withheld: /) wh = substr(line, 18)
      else if (line ~ /^output_lines: /) nl = substr(line, 15)
      else if (line ~ /^timestamp: /) ts = substr(line, 12)
      else if (line ~ /^step: /) stp = substr(line, 7)
      return
    }
    if (state == 3) {
      if (line == "=== END STEP " idx " nonce=" nonce " ===") { fin("ok", NR); return }
      fin("bad", NR - 1); handle(line); return
    }
  }
  BEGIN { state = 0 }
  {
    if (state == 2) { remaining--; if (remaining == 0) state = 3; next }
    handle($0)
  }
  END { if (state != 0) fin("bad", NR) }
  ' "$1"
}

_sw_max_index() {
  # Highest index present in any record (ok, bad, or dup). 0 if none.
  _sw_ledger_scan "$1" | awk -F'\t' '$1 ~ /^[0-9]+$/ && $1 + 0 > m { m = $1 + 0 } END { print m + 0 }'
}

_sw_ledger_append() {
  # args: ledger objective step status risk withheld_reason bodyfile
  local ledger="$1" objective step status="$4" risk reason="$6" body="$7"
  local dir sid idx nonce ts nlines norm rc
  dir="$(dirname "$ledger")"
  sid="$(basename "$dir")"
  objective="$(_sw_oneline "$2")"
  step="$(_sw_oneline "$3")"
  risk="$(_sw_oneline "$5")"
  [[ "$5" == "" ]] && risk="unclassified"

  norm="$(mktemp "$dir/.body.XXXXXX")" || return 1
  if [[ -n "$reason" ]]; then
    printf '[StepWise] output withheld: %s risk classification\n' "$reason" > "$norm"
  else
    awk '{ print }' "$body" > "$norm"
  fi
  nlines="$(awk 'END { print NR }' "$norm")"

  if ! _sw_lock "$dir"; then
    rm -f "$norm"
    _sw_notice "Ledger not written: could not lock session (stale lock? try: rmdir '$dir/.lock')."
    return 1
  fi
  idx=$(( $(_sw_max_index "$ledger") + 1 ))
  nonce="$(_sw_rand)$(_sw_rand)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '=== STEP %s session=%s nonce=%s ===\n' "$idx" "$sid" "$nonce"
    printf 'timestamp: %s\n' "$ts"
    printf 'session: %s\n' "$sid"
    printf 'objective: %s\n' "$objective"
    printf 'step: %s\n' "$step"
    printf 'exit_status: %s\n' "$status"
    printf 'risk: %s\n' "$risk"
    printf 'output_withheld: %s\n' "$([[ -n "$reason" ]] && echo yes || echo no)"
    printf 'output_lines: %s\n' "$nlines"
    printf 'output:\n'
    cat "$norm"
    printf '=== END STEP %s nonce=%s ===\n' "$idx" "$nonce"
  } >> "$ledger"
  rc=$?
  _sw_unlock "$dir"
  rm -f "$norm"
  if [[ $rc -ne 0 ]]; then
    _sw_notice "Ledger write failed."
    return 1
  fi
  _sw_notice "Ledger: recorded STEP $idx (exit $status, risk $risk)."
}

runledger() {
  local objective="-" step="-" risk="" risk_set=0 v cls="eligible" reason="" copy=0 do_copy=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --copy)        copy=1; shift ;;
      --objective=*) objective="${1#--objective=}"; shift ;;
      --step=*)      step="${1#--step=}"; shift ;;
      --risk=*)
        v="${1#--risk=}"
        [[ -z "$v" ]] && v="<empty>"
        risk="${risk:+$risk,}$v"
        risk_set=1
        shift
        ;;
      --risk|--objective|--step)
        _sw_notice "runledger: $1 requires a value (use $1=<value>)."
        return 2
        ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if [[ $# -eq 0 ]]; then
    _sw_notice "runledger: no command given. Usage: runledger [--objective=..] [--step=..] [--risk=..] -- <command> [args...]"
    return 2
  fi

  [[ "$risk_set" -eq 1 ]] && cls="$(_sw_risk_class "$risk")"

  # Automatic clipboard duplication (--copy). Eligibility is decided HERE, before
  # the command runs, from the risk label alone (plan 3.2). Fail-closed: a
  # missing, sensitive, or unrecognized label means no copy, whatever the caller
  # asked for. Terminal display is never affected. This is duplication only;
  # nothing here treats clipboard state as authorization to execute anything.
  if [[ "$copy" -eq 1 ]]; then
    if [[ "$risk_set" -eq 0 ]]; then
      _sw_notice "Clipboard copy bypassed: --copy requires a --risk label (fail-closed). Output is displayed only, not copied."
    elif [[ "$cls" == "sensitive" ]]; then
      _sw_notice "Clipboard copy bypassed: command classified as '$risk' risk. Output is displayed only, not copied."
    elif [[ "$cls" == "unrecognized" ]]; then
      _sw_notice "Clipboard copy bypassed: unrecognized risk label '$risk' (fail-closed). Output is displayed only, not copied."
    else
      do_copy=1
    fi
  fi

  local ledger status dir tmp
  if ! ledger="$(_sw_active_ledger)"; then
    _sw_notice "Ledger not written. The command runs normally."
    if [[ "$do_copy" -eq 1 ]]; then
      tmp="$(mktemp)" || { "$@"; return $?; }
      "$@" 2>&1 | tee "$tmp"
      status=${PIPESTATUS[0]}
      _sw_clipboard_copy < "$tmp"
      rm -f "$tmp"
      return "$status"
    fi
    "$@"
    return $?
  fi
  dir="$(dirname "$ledger")"

  # Fail-closed: sensitive or unrecognized classification means the output is
  # never captured, so it can never reach the ledger or a temp file.
  if [[ "$cls" != "eligible" ]]; then
    reason="$cls"
    "$@"
    status=$?
    _sw_ledger_append "$ledger" "$objective" "$step" "$status" "$risk" "$reason" ""
    return "$status"
  fi

  tmp="$(mktemp "$dir/.capture.XXXXXX")" || { _sw_notice "Ledger not written (no temp file). The command runs normally."; "$@"; return $?; }
  "$@" 2>&1 | tee "$tmp"
  status=${PIPESTATUS[0]}
  _sw_ledger_append "$ledger" "$objective" "$step" "$status" "$risk" "" "$tmp"
  [[ "$do_copy" -eq 1 ]] && _sw_clipboard_copy < "$tmp"
  rm -f "$tmp"
  return "$status"
}

sw_ledger_list() {
  local ledger rows idx status risk ex ts stp junk=0 n=0
  ledger="$(_sw_active_ledger)" || return 1
  rows="$(_sw_ledger_scan "$ledger")"
  printf '%-5s %-20s %-5s %-27s %-6s %s\n' IDX TIMESTAMP EXIT RISK STATUS STEP
  while IFS=$'\t' read -r idx _ _ status risk ex _ _ _ ts stp; do
    [[ -z "$idx" ]] && continue
    if [[ "$idx" == "!" ]]; then junk=$((junk + 1)); continue; fi
    n=$((n + 1))
    printf '%-5s %-20s %-5s %-27s %-6s %s\n' "$idx" "$ts" "$ex" "$risk" "$status" "$stp"
  done <<< "$rows"
  [[ $n -eq 0 ]] && echo "(ledger is empty)"
  [[ $junk -gt 0 ]] && _sw_notice "$junk unparseable line(s) between records."
  return 0
}

_sw_parse_spec() {
  # Prints "<mode> <first> <last>" (mode: final|single|from|range). Returns 2
  # with a notice on any grammar error. No clamping, no guessing.
  local spec="$1"
  local r_single='^([1-9][0-9]{0,8})$'
  local r_from='^([1-9][0-9]{0,8})\+$'
  local r_range='^([1-9][0-9]{0,8})-([1-9][0-9]{0,8})$'
  if [[ "$spec" =~ $r_single ]]; then
    echo "single ${BASH_REMATCH[1]} ${BASH_REMATCH[1]}"; return 0
  elif [[ "$spec" =~ $r_from ]]; then
    echo "from ${BASH_REMATCH[1]} 0"; return 0
  elif [[ "$spec" =~ $r_range ]]; then
    if (( 10#${BASH_REMATCH[1]} > 10#${BASH_REMATCH[2]} )); then
      _sw_notice "Invalid range '$spec': start is greater than end (reversed range)."; return 2
    fi
    echo "range ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; return 0
  fi
  if [[ -z "$spec" ]]; then
    _sw_notice "Invalid index: empty string. Pass no argument to select the final entry."
  elif [[ "$spec" =~ ^-[0-9] ]]; then
    _sw_notice "Invalid index '$spec': negative numbers and open-start ranges are not supported."
  elif [[ "$spec" =~ ^[0-9]+-$ ]]; then
    _sw_notice "Invalid range '$spec': the end must be explicit. Use '${spec%-}+' for 'through the final entry'."
  elif [[ "$spec" =~ ^0 ]]; then
    _sw_notice "Invalid index '$spec': indexes are positive integers starting at 1 (no zero, no leading zeros)."
  elif [[ "$spec" =~ [0-9]{10,} ]]; then
    _sw_notice "Invalid index '$spec': more than 9 digits."
  else
    _sw_notice "Invalid index '$spec'. Expected N, A-B, N+, or no argument (final entry)."
  fi
  return 2
}

sw_copy_clip() {
  local to_stdout=0 spec="" have_spec=0 arg
  for arg in "$@"; do
    case "$arg" in
      --stdout) to_stdout=1 ;;
      *)
        if [[ $have_spec -eq 1 ]]; then
          _sw_notice "sw_copy_clip: at most one index spec is accepted."
          return 2
        fi
        spec="$arg"; have_spec=1
        ;;
    esac
  done

  local mode first last parsed
  if [[ $have_spec -eq 1 ]]; then
    parsed="$(_sw_parse_spec "$spec")" || return 2
    read -r mode first last <<< "$parsed"
  else
    mode="final"; first=0; last=0
  fi

  local ledger rows max
  ledger="$(_sw_active_ledger)" || return 1
  rows="$(_sw_ledger_scan "$ledger")"
  max="$(printf '%s\n' "$rows" | awk -F'\t' '$1 ~ /^[0-9]+$/ && $1 + 0 > m { m = $1 + 0 } END { print m + 0 }')"
  if [[ "$max" -eq 0 ]]; then
    _sw_notice "Ledger is empty; nothing to extract."
    return 1
  fi

  case "$mode" in
    final) first="$max"; last="$max" ;;
    from)  last="$max" ;;
  esac
  first=$((10#$first)); last=$((10#$last))
  if (( first > max || last > max )); then
    _sw_notice "Entry $(( first > max ? first : last )) does not exist (ledger has entries 1-$max). Nothing copied."
    return 1
  fi

  local dir out i row n idx status risk ex bs nl ts stp multi=0
  dir="$(dirname "$ledger")"
  (( last > first )) && multi=1
  out="$(mktemp "$dir/.extract.XXXXXX")" || { _sw_notice "Could not create temp file."; return 1; }

  for (( i = first; i <= last; i++ )); do
    row="$(printf '%s\n' "$rows" | awk -F'\t' -v i="$i" '$1 == i')"
    n="$(printf '%s\n' "$row" | awk 'NF { c++ } END { print c + 0 }')"
    if [[ "$n" -ne 1 ]]; then
      rm -f "$out"
      if [[ "$n" -eq 0 ]]; then _sw_notice "Entry $i is missing from the ledger. Nothing copied."
      else _sw_notice "Entry $i appears more than once in the ledger. Nothing copied."; fi
      return 1
    fi
    IFS=$'\t' read -r idx _ _ status risk ex _ bs nl ts stp <<< "$row"
    if [[ "$status" != "ok" ]]; then
      rm -f "$out"
      _sw_notice "Entry $i is not extractable (status: $status). Nothing copied."
      return 1
    fi
    # Defense in depth: re-check the stored label with the fail-closed classifier.
    if [[ "$risk" != "unclassified" && "$(_sw_risk_class "$risk")" != "eligible" ]]; then
      rm -f "$out"
      _sw_notice "Entry $i is classified '$risk' (sensitive or unrecognized). Extraction refused. Nothing copied."
      return 1
    fi
    [[ "$multi" -eq 1 ]] && printf '### STEP %s - %s (exit %s)\n' "$idx" "$stp" "$ex" >> "$out"
    [[ "$nl" -gt 0 ]] && sed -n "${bs},$((bs + nl - 1))p" "$ledger" >> "$out"
  done

  local rc=0 label count=$(( last - first + 1 ))
  if [[ "$to_stdout" -eq 1 ]]; then
    cat "$out"
  else
    _sw_clipboard_copy < "$out" || rc=1
  fi
  rm -f "$out"
  if [[ $rc -eq 0 ]]; then
    label="STEP $first"
    [[ $count -gt 1 ]] && label="STEPS $first-$last"
    _sw_notice "Extracted $label ($count entr$([[ $count -gt 1 ]] && echo ies || echo y))."
  fi
  return "$rc"
}

# --- Self-test -------------------------------------------------------------
# Verifies: (a) normal display+copy path runs without error, and
# (b) the bypass fires and prints the notice on a sample privileged-risk
# command, WITHOUT invoking the clipboard backend.
sw_selftest_clipboard_bypass() {
  local out
  out="$(runcopy --risk=credential -- echo "FAKE_SECRET=12345" 2>&1 1>/dev/null)"
  if [[ "$out" == *"Clipboard copy bypassed: command classified as 'credential' risk"* ]]; then
    echo "PASS: bypass notice fired for credential-risk command."
  else
    echo "FAIL: expected bypass notice not found. Got: $out"
    return 1
  fi

  local display
  display="$(runcopy --risk=credential -- echo "FAKE_SECRET=12345" 2>/dev/null)"
  if [[ "$display" == "FAKE_SECRET=12345" ]]; then
    echo "PASS: terminal display preserved during bypass."
  else
    echo "FAIL: expected display output missing. Got: $display"
    return 1
  fi

  # Fail-closed: the protocol's combined label and unknown labels must bypass too.
  local label
  for label in "credential/privileged-data" "Credential" "secret" "bogus-label" ""; do
    out="$(runcopy --risk="$label" -- echo "FAKE_SECRET=12345" 2>&1 1>/dev/null)"
    if [[ "$out" == *"Clipboard copy bypassed"* ]]; then
      echo "PASS: bypass fired for --risk='$label'."
    else
      echo "FAIL: no bypass for --risk='$label'. Got: $out"
      return 1
    fi
  done
}

# When executed directly (not sourced), run the self-test.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sw_selftest_clipboard_bypass
fi
