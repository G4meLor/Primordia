#!/bin/sh
# Failure-path test for tools/ab_test.sh (M2 final-review carry-forward #1).
# The M2 defect: the evidence write sat ABOVE the FAIL verdict, so a failing
# A-B run rewrote tests/fixtures/ab/evidence.txt with its OWN diff sha as
# sanctioned_diff_sha256 — and the SECOND failing run (same stable diff) then
# read that sha back and laundered into SANCTIONED_MATCH (exit 0). The fix
# moved the write below the FAIL check; this test pins the failure path:
#
#   run 1  stable non-matching diff → exit 1 (AB_TEST_FAIL), evidence untouched
#   run 2  same diff                → exit 1 AGAIN (NOT SANCTIONED_MATCH),
#                                     evidence still untouched
#
# GODOT is stubbed (the env override ab_test.sh already honors): the head
# invocation (cwd = repo root) and the base invocation (cwd = the A-B
# worktree) print fixed distinct lines, so the diff — and therefore its
# sha256 — is byte-identical across the two runs. That stability is exactly
# the laundering precondition. Shell-only: the real godot never runs, the
# A-B worktree add/remove is the only repo side effect (ab_test.sh cleans it).
#
# Run: tools/test_ab.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

EVIDENCE="tests/fixtures/ab/evidence.txt"
LAST_DIFF="tests/fixtures/ab/last_diff.txt"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
	echo "AB_FAILOPEN_FAIL: $1"
	exit 1
}

# keep the real fixtures safe no matter how this test exits
cp "$EVIDENCE" "$WORK/evidence.bak" || fail "no $EVIDENCE to back up"
if [ -f "$LAST_DIFF" ]; then
	cp "$LAST_DIFF" "$WORK/last_diff.bak"
fi
restore() {
	cp "$WORK/evidence.bak" "$EVIDENCE"
	if [ -f "$WORK/last_diff.bak" ]; then
		cp "$WORK/last_diff.bak" "$LAST_DIFF"
	fi
}
trap 'restore; rm -rf "$WORK"' EXIT

# sentinel baseline: a sanctioned sha that NO diff can ever match
cat > "$EVIDENCE" <<'EOF'
# A-B evidence — test sentinel (tools/test_ab.sh)
generated=1970-01-01T00:00:00Z
base_commit=869e83b
head_commit=test
base_dump_sha256=0
head_dump_sha256=0
diff_lines=4
sanctioned_diff_sha256=0000000000000000000000000000000000000000000000000000000000000000
verdict=SANCTIONED_MATCH
EOF
cp "$EVIDENCE" "$WORK/sentinel.bak"

# the stub godot: head dump (repo root cwd) vs base dump (worktree cwd) print
# FIXED distinct lines — stable non-empty diff, stable sha across runs.
# $ROOT is baked in at creation; $PWD stays live for the stub's own runtime.
cat > "$WORK/godot-stub" <<EOF
#!/bin/sh
if [ "\$PWD" = "$ROOT" ]; then
	echo "AB_STUB_HEAD"
else
	echo "AB_STUB_BASE"
fi
EOF
chmod +x "$WORK/godot-stub"

# run 1 — the clobbering run (pre-fix it rewrote evidence.txt here)
GODOT="$WORK/godot-stub" sh tools/ab_test.sh > "$WORK/run1.out" 2>&1
R1=$?
grep -q "AB_TEST_FAIL" "$WORK/run1.out" \
	|| fail "run 1 did not reach the FAIL verdict (exit $R1): $(tail -2 "$WORK/run1.out")"
[ "$R1" -ne 0 ] || fail "run 1 exited 0 on a non-matching diff"
grep -q "sanctioned_diff_sha256=00000000" "$EVIDENCE" \
	|| fail "run 1 rewrote evidence.txt (fail-open clobber)"

# run 2 — the laundering run (pre-fix: SANCTIONED_MATCH, exit 0)
GODOT="$WORK/godot-stub" sh tools/ab_test.sh > "$WORK/run2.out" 2>&1
R2=$?
if grep -q "SANCTIONED_MATCH" "$WORK/run2.out"; then
	fail "run 2 LAUNDERED into SANCTIONED_MATCH (fail-open)"
fi
[ "$R2" -ne 0 ] || fail "run 2 exited 0 — the second failing run laundered"
grep -q "AB_TEST_FAIL" "$WORK/run2.out" \
	|| fail "run 2 did not reach the FAIL verdict (exit $R2): $(tail -2 "$WORK/run2.out")"
grep -q "sanctioned_diff_sha256=00000000" "$EVIDENCE" \
	|| fail "run 2 rewrote evidence.txt (fail-open clobber)"
diff -q "$WORK/sentinel.bak" "$EVIDENCE" > /dev/null 2>&1 \
	|| fail "evidence.txt differs from the sentinel after both runs (fail-open clobber)"

echo "AB_FAILOPEN_OK (two failing runs both exit 1, sanctioned baseline untouched)"
exit 0
