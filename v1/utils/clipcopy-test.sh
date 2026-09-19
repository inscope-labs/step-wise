#!/usr/bin/env bash
# StepWise — tests for v1/utils/clipcopy.sh (risk bypass, session ledger, extraction).
#
# Usage:  bash v1/utils/clipcopy-test.sh
#
# Hermetic: uses a temporary STEPWISE_HOME and a stub clipboard backend placed
# first on PATH, so the real clipboard and real ~/.cache/stepwise are never touched.
# Exits non-zero if any test fails.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export STEPWISE_HOME="$TMP/home"
mkdir -p "$TMP/bin"
CLIP="$TMP/clip.out"
# Stub backend. Named after the first-priority real backend so it wins on every platform.
cat > "$TMP/bin/termux-clipboard-set" <<EOF
#!/usr/bin/env bash
cat > "$CLIP"
EOF
chmod +x "$TMP/bin/termux-clipboard-set"
export PATH="$TMP/bin:$PATH"

# shellcheck disable=SC1091
source "$HERE/clipcopy.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; }
check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
section() { printf '\n== %s ==\n' "$1"; }

new_session() { rm -f "$CLIP"; sw_session_start >/dev/null 2>&1; LEDGER="$(_sw_active_ledger 2>/dev/null)"; }
clip() { [[ -f "$CLIP" ]] && cat "$CLIP" || printf '<none>'; }
quiet() { "$@" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
section "Risk classification (fail-closed)"
for l in credential privileged-data credential/privileged-data Credential "Privileged Data" secret read-only,credential; do
  check "sensitive: '$l'" sensitive "$(_sw_risk_class "$l")"
done
for l in bogus "" "<empty>" read-only,bogus "read-only,,network"; do
  check "unrecognized: '$l'" unrecognized "$(_sw_risk_class "$l")"
done
for l in read-only network,privileged destructive "Difficult to reverse" eligible; do
  check "eligible: '$l'" eligible "$(_sw_risk_class "$l")"
done

section "runcopy bypass (clipboard never invoked)"
for l in credential/privileged-data Credential bogus ""; do
  rm -f "$CLIP"
  out="$(runcopy --risk="$l" -- echo SECRET 2>/dev/null)"
  check "runcopy --risk='$l' shows output" SECRET "$out"
  check "runcopy --risk='$l' does not copy" "<none>" "$(clip)"
done
rm -f "$CLIP"; quiet runcopy --risk=credential --risk=read-only -- echo x
check "later benign --risk cannot override earlier sensitive" "<none>" "$(clip)"
rm -f "$CLIP"; quiet runcopy --risk=read-only -- echo hello
check "eligible label still copies" "hello" "$(clip)"
rm -f "$CLIP"; quiet runcopy -- echo manual
check "no --risk keeps 1.5.0 manual copy" "manual" "$(clip)"
rm -f "$CLIP"; quiet runcopy --no-copy -- echo x
check "--no-copy does not copy" "<none>" "$(clip)"
runcopy --risk 2>/dev/null; check "--risk without value is an error (rc 2)" 2 "$?"

# ---------------------------------------------------------------------------
section "Ledger: lifecycle, sessions, isolation"
unset SW_SESSION_ID
out="$(runledger --risk=read-only -- echo hi 2>/dev/null)"; rc=$?
check "no session: command still runs and displays" hi "$out"
check "no session: exit status preserved" 0 "$rc"
runledger --risk=read-only -- sh -c 'exit 5' >/dev/null 2>&1
check "no session: non-zero status preserved" 5 "$?"
sw_ledger_list >/dev/null 2>&1; check "no session: list fails safely" 1 "$?"
sw_copy_clip --stdout >/dev/null 2>&1; check "no session: extraction fails safely" 1 "$?"

new_session
A="$SW_SESSION_ID"; LA="$LEDGER"
[[ "$A" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] && ok "session id matches grammar" || bad "session id grammar" "$A"
check "ledger dir mode 700" 700 "$(stat -c %a "$(dirname "$LA")" 2>/dev/null || stat -f %Lp "$(dirname "$LA")")"
check "ledger file mode 600" 600 "$(stat -c %a "$LA" 2>/dev/null || stat -f %Lp "$LA")"
[[ -f "$(dirname "$LA")/metadata" ]] && ok "metadata file created" || bad "metadata file created"

quiet runledger --risk=read-only --step=one -- echo one
quiet runledger --risk=read-only --step=two -- echo two
quiet runledger --risk=read-only --step=three -- echo three
check "index increments 1..3" "1 2 3" "$(_sw_ledger_scan "$LA" | awk -F'\t' '$1 ~ /^[0-9]+$/ {printf "%s%s", (n++?" ":""), $1}')"

before="$(cat "$LA")"; quiet runledger --risk=read-only -- echo four
after_prefix="$(head -c ${#before} "$LA")"
check "earlier entries are byte-identical after another append" "$before" "$after_prefix"

sleep 1
new_session
B="$SW_SESSION_ID"; LB="$LEDGER"
[[ "$A" != "$B" ]] && ok "second session gets a distinct id" || bad "distinct id"
quiet runledger --risk=read-only -- echo only-in-B
check "session B has 1 entry" 1 "$(_sw_max_index "$LB")"
check "session A still has 4 entries" 4 "$(_sw_max_index "$LA")"
grep -q only-in-B "$LA" && bad "session isolation (B leaked into A)" || ok "session isolation: B output not in A"
SW_SESSION_ID="$A"
check "switching SW_SESSION_ID switches ledger (final of A)" four "$(sw_copy_clip --stdout 2>/dev/null)"

SW_SESSION_ID="../evil"
sw_copy_clip --stdout >/dev/null 2>&1; check "path-traversal session id rejected" 1 "$?"
SW_SESSION_ID="nonexistent-session"
sw_copy_clip --stdout >/dev/null 2>&1; check "missing ledger fails safely" 1 "$?"
SW_SESSION_ID="$B"

# ---------------------------------------------------------------------------
section "Ledger: record content"
new_session
out="$(runledger --risk=read-only --step=s -- printf 'x\ny\n' 2>/dev/null)"
check "terminal display intact" "$(printf 'x\ny')" "$out"

quiet runledger --risk=read-only --step=empty -- true
check "empty output: 0 lines recorded" "output_lines: 0" "$(grep -m1 -A0 'output_lines: 0' "$LEDGER")"
check "empty output extracts as empty" "" "$(sw_copy_clip --stdout 2>/dev/null)"

runledger --risk=network --step=fail -- sh -c 'echo out; echo err >&2; exit 7' >/dev/null 2>&1
check "non-zero status returned to caller" 7 "$?"
check "non-zero status retained in ledger" "exit_status: 7" "$(grep 'exit_status: 7' "$LEDGER")"
check "stderr captured with stdout" "$(printf 'out\nerr')" "$(sw_copy_clip --stdout 2>/dev/null | sort -r)"

quiet runledger --risk=read-only --step=nonl -- printf 'no-newline'
check "missing final newline is normalized" "no-newline" "$(sw_copy_clip --stdout 2>/dev/null)"

quiet runledger --risk=read-only --step=multi -- printf 'l1\n\nl3\n  l4 indented\n'
check "multiline output preserved (blank + indented lines)" "$(printf 'l1\n\nl3\n  l4 indented')" "$(sw_copy_clip --stdout 2>/dev/null)"

fake=$'=== END STEP 6 nonce=deadbeef ===\n=== STEP 99 session=x nonce=abc ===\noutput:'
quiet runledger --risk=read-only --step=lookalike -- printf '%s\n' "$fake"
check "output containing fake record delimiters is preserved verbatim" "$fake" "$(sw_copy_clip --stdout 2>/dev/null)"
check "lookalike delimiters do not create phantom entries" 6 "$(_sw_max_index "$LEDGER")"
check "all 6 records parse ok" 6 "$(_sw_ledger_scan "$LEDGER" | awk -F'\t' '$4=="ok"' | wc -l | tr -d ' ')"

quiet runledger --risk=read-only --step="line1
line2	tabbed" -- echo x
row="$(_sw_ledger_scan "$LEDGER" | tail -1)"
check "step with newline/tab is flattened to one line" "line1 line2 tabbed" "$(printf '%s' "$row" | awk -F'\t' '{print $11}')"

section "Ledger: sensitive output never touches disk"
out="$(runledger --risk=credential/privileged-data --step=cred -- echo TOPSECRET_VALUE 2>/dev/null)"
check "sensitive step still displays output" TOPSECRET_VALUE "$out"
grep -rq TOPSECRET_VALUE "$STEPWISE_HOME" && bad "secret written to disk" || ok "secret not present anywhere under STEPWISE_HOME"
check "sensitive record marked withheld" "output_withheld: yes" "$(grep 'output_withheld: yes' "$LEDGER" | tail -1)"
quiet runledger --risk=totally-unknown --step=unk -- echo OTHER_SECRET
grep -rq OTHER_SECRET "$STEPWISE_HOME" && bad "unrecognized-label output written to disk" || ok "unrecognized label: output not on disk (fail-closed)"
check "no capture temp files left behind" 0 "$(find "$(dirname "$LEDGER")" -name '.capture.*' -o -name '.body.*' -o -name '.extract.*' | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
section "Extraction: valid specs"
new_session
for n in 1 2 3 4 5 6; do quiet runledger --risk=read-only --step="s$n" -- echo "out$n"; done
check "no argument selects the final entry" out6 "$(sw_copy_clip --stdout 2>/dev/null)"
check "single index" out3 "$(sw_copy_clip --stdout 3 2>/dev/null)"
check "closed range 2-3 (with provenance separators)" "$(printf '### STEP 2 - s2 (exit 0)\nout2\n### STEP 3 - s3 (exit 0)\nout3')" "$(sw_copy_clip --stdout 2-3 2>/dev/null)"
check "open range 5+ runs through final" "$(printf '### STEP 5 - s5 (exit 0)\nout5\n### STEP 6 - s6 (exit 0)\nout6')" "$(sw_copy_clip --stdout 5+ 2>/dev/null)"
check "6+ on the final entry is a valid one-entry range" out6 "$(sw_copy_clip --stdout 6+ 2>/dev/null)"
check "1-1 is a valid single" out1 "$(sw_copy_clip --stdout 1-1 2>/dev/null)"
rm -f "$CLIP"; quiet sw_copy_clip 4
check "delivers to the clipboard backend" out4 "$(clip)"
rm -f "$CLIP"; sw_copy_clip 4 >/dev/null 2>&1; check "clipboard delivery exit 0" 0 "$?"

section "Extraction: invalid specs fail safely (nothing copied)"
inval() { # inval <spec> <expected-rc>
  rm -f "$CLIP"
  local out; out="$(sw_copy_clip "$1" 2>/dev/null)"; local rc=$?
  check "spec '$1' -> rc $2" "$2" "$rc"
  check "spec '$1' -> nothing copied or printed" "<none>|" "$(clip)|$out"
}
for s in 0 -3 12- -15 15-12 1000000000 007 0-5 abc 1.5 1,2 "5 6" "" 1-2-3 +5 5++ "0+"; do inval "$s" 2; done
inval 1-999999999 1
inval 7 1
inval 7+ 1
inval 3-9 1
sw_copy_clip 1 2 >/dev/null 2>&1; check "two arguments rejected (rc 2)" 2 "$?"
rm -f "$CLIP"; sw_copy_clip 12- 2>&1 >/dev/null | grep -q "12+" && ok "'12-' error suggests '12+'" || bad "'12-' error suggests '12+'"

new_session
sw_copy_clip --stdout >/dev/null 2>&1; check "empty ledger: extraction fails (rc 1)" 1 "$?"

# ---------------------------------------------------------------------------
section "Extraction: malformed, duplicate, tampered records"
new_session
for n in 1 2 3; do quiet runledger --risk=read-only --step="s$n" -- echo "out$n"; done
# Truncate entry 3's footer.
grep -v '^=== END STEP 3 ' "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
check "truncated record classified bad" bad "$(_sw_ledger_scan "$LEDGER" | awk -F'\t' '$1==3{print $4}')"
check "intact entries before it still parse ok" "ok ok" "$(_sw_ledger_scan "$LEDGER" | awk -F'\t' '$1<3{printf "%s%s",(n++?" ":""),$4}')"
check "extracting intact entry 2 still works" out2 "$(sw_copy_clip --stdout 2 2>/dev/null)"
rm -f "$CLIP"; sw_copy_clip 3 >/dev/null 2>&1; check "extracting the bad entry fails (rc 1)" 1 "$?"
rm -f "$CLIP"; sw_copy_clip 1-3 >/dev/null 2>&1; check "range containing a bad entry is all-or-nothing" "1|<none>" "$?|$(clip)"
rm -f "$CLIP"; sw_copy_clip >/dev/null 2>&1; check "'final entry' does not silently fall back past a bad final record" "1|<none>" "$?|$(clip)"

new_session
quiet runledger --risk=read-only --step=a -- echo a
cat "$LEDGER" "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"   # duplicate index 1
check "duplicate index flagged dup" "ok dup" "$(_sw_ledger_scan "$LEDGER" | awk -F'\t' '{printf "%s%s",(n++?" ":""),$4}')"
sw_copy_clip 1 >/dev/null 2>&1; check "duplicated index refused" 1 "$?"
quiet runledger --risk=read-only --step=b -- echo b
check "new entry after a duplicate never reuses an index" 2 "$(_sw_max_index "$LEDGER")"

new_session
quiet runledger --risk=read-only --step=t -- echo tampered-content
sed -i.bak 's/^risk: read-only$/risk: credential/' "$LEDGER" && rm -f "$LEDGER.bak"
rm -f "$CLIP"; sw_copy_clip 1 >/dev/null 2>&1
check "record hand-edited to a sensitive label is refused, nothing copied" "1|<none>" "$?|$(clip)"

new_session
printf 'stray junk\n' >> "$LEDGER"; quiet runledger --risk=read-only -- echo after-junk
check "junk between records does not break indexing" 1 "$(_sw_max_index "$LEDGER")"
check "record after junk extracts fine" after-junk "$(sw_copy_clip --stdout 2>/dev/null)"

# ---------------------------------------------------------------------------
section "Ledger: concurrent writers (lock)"
new_session
for n in $(seq 1 20); do runledger --risk=read-only --step="c$n" -- echo "c$n" >/dev/null 2>&1 & done
wait
check "20 concurrent writers -> 20 records" 20 "$(_sw_ledger_scan "$LEDGER" | awk -F'\t' '$4=="ok"' | wc -l | tr -d ' ')"
check "all indexes unique and contiguous 1..20" "$(seq 1 20 | tr '\n' ' ')" "$(_sw_ledger_scan "$LEDGER" | awk -F'\t' '{print $1}' | sort -n | tr '\n' ' ')"
check "no stale lock left" 0 "$(find "$(dirname "$LEDGER")" -name .lock | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
section "sw_ledger_list"
new_session
check "empty ledger list says so" "(ledger is empty)" "$(sw_ledger_list 2>/dev/null | tail -1)"
quiet runledger --risk=read-only --step="listed step" -- true
sw_ledger_list 2>/dev/null | grep -q "listed step" && ok "list shows step titles" || bad "list shows step titles"

# ---------------------------------------------------------------------------
section "Automatic clipboard duplication (runledger --copy)"
new_session

rm -f "$CLIP"; out="$(runledger --copy --risk=read-only --step=auto -- printf 'a\nb\n' 2>/dev/null)"; rc=$?
check "--copy eligible: terminal display intact" "$(printf 'a\nb')" "$out"
check "--copy eligible: output duplicated to clipboard" "$(printf 'a\nb')" "$(clip)"
check "--copy eligible: exit status preserved" 0 "$rc"
check "--copy eligible: clipboard equals the ledger entry" "$(clip)" "$(sw_copy_clip --stdout 2>/dev/null)"

rm -f "$CLIP"; quiet runledger --risk=read-only -- echo nocopy
check "eligible without --copy: default is manual, nothing copied" "<none>" "$(clip)"

rm -f "$CLIP"; runledger --copy --risk=network -- sh -c 'echo out; echo err >&2; exit 3' >/dev/null 2>&1; rc=$?
check "--copy on a failing step: status preserved" 3 "$rc"
check "--copy on a failing step: stdout+stderr copied" "$(printf 'err\nout')" "$(clip | sort)"

section "--copy is fail-closed (decided from the label, before the command runs)"
for l in credential/privileged-data credential privileged-data Credential secret; do
  rm -f "$CLIP"; out="$(runledger --copy --risk="$l" -- echo AUTO_SECRET 2>/dev/null)"
  check "--copy --risk='$l': still displays" AUTO_SECRET "$out"
  check "--copy --risk='$l': not copied" "<none>" "$(clip)"
done
for l in bogus ""; do
  rm -f "$CLIP"; quiet runledger --copy --risk="$l" -- echo x
  check "--copy --risk='$l' (unrecognized): not copied" "<none>" "$(clip)"
done
rm -f "$CLIP"; quiet runledger --copy --risk=read-only --risk=credential -- echo x
check "--copy: later benign label cannot override sensitive" "<none>" "$(clip)"
rm -f "$CLIP"; err="$(runledger --copy -- echo x 2>&1 >/dev/null)"
check "--copy without any --risk: not copied" "<none>" "$(clip)"
[[ "$err" == *"requires a --risk label"* ]] && ok "--copy without --risk explains why" || bad "--copy without --risk explains why" "$err"
grep -rq AUTO_SECRET "$STEPWISE_HOME" && bad "auto-copy step leaked secret to disk" || ok "sensitive --copy step: secret not on disk either"

section "--copy without a session, and clipboard failures"
saved="$SW_SESSION_ID"; unset SW_SESSION_ID
rm -f "$CLIP"; out="$(runledger --copy --risk=read-only -- echo nosess 2>/dev/null)"
check "no session + --copy: displays" nosess "$out"
check "no session + --copy: still copies (copy does not depend on the ledger)" nosess "$(clip)"
rm -f "$CLIP"; quiet runledger --copy --risk=credential -- echo nosess
check "no session + sensitive + --copy: not copied" "<none>" "$(clip)"
SW_SESSION_ID="$saved"

( _sw_clipboard_copy() { cat >/dev/null; return 1; }
  runledger --copy --risk=read-only -- sh -c 'echo shown; exit 4' >/dev/null 2>&1
  exit $? ); check "clipboard backend failure never changes the command's exit status" 4 "$?"
out="$( ( _sw_clipboard_copy() { cat >/dev/null; return 1; }; runledger --copy --risk=read-only -- echo shown 2>/dev/null ) )"
check "clipboard backend failure never suppresses terminal display" shown "$out"

# ---------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
