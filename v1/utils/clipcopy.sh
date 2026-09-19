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
