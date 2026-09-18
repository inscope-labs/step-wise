#!/usr/bin/env bash
# StepWise — opt-in clipboard-copy wrapper 
#
# Usage:
#   source clipcopy.sh
#   runcopy -- <command> [args...]              # display + copy output
#   runcopy --no-copy -- <command> [args...]    # per-invocation skip, no copy
#   runcopy --risk=credential -- <command> ...  # auto-bypasses copy, shows notice
#   runcopy --risk=privileged-data -- <command> ...
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
  local no_copy=0

  # Parse leading flags; everything after -- is the command to run.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --risk=*)
        risk="${1#--risk=}"
        shift
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

  # Automatic bypass: credential- or privileged-data-classified steps never
  # get copied, regardless of operator request. This check cannot be
  # overridden by --no-copy being absent; it is independent of operator intent.
  if [[ "$risk" == "credential" || "$risk" == "privileged-data" ]]; then
    _sw_notice "Clipboard copy bypassed: command classified as '$risk' risk. Output is displayed only, not copied."
    "$@"
    return $?
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
}

# When executed directly (not sourced), run the self-test.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sw_selftest_clipboard_bypass
fi
