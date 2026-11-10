#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Tongsuo's own unit tests (test/*.c, built by mayhem/build.sh into mayhem/_build/test with NORMAL flags).
# Each program prints TAP; the top-level `ok N - ...` / `not ok N - ...` lines are the assertions (evp_test
# checks the data files' known-answer vectors for SM3/SM4/SM2/SHA/AES/HKDF/..., bntest checks bignum
# arithmetic, the *_internal_test programs check SM2/SM3/SM4/ASN.1 behavior). A program that exits 0 but
# prints no `ok` line (a neutered/no-op binary) counts as a failure.
T="$SRC/mayhem/_build/test"
D="$SRC/test/recipes"
[ -x "$T/test/evp_test" ] || { echo "missing $T/test/evp_test: run mayhem/build.sh first" >&2; emit_ctrf "tongsuo-tap" 0 1; exit 1; }
cd "$T"

passed=0; failed=0
run_tap() {            # run_tap <label> <program> [args...]
  local label="$1"; shift
  local out rc n_ok n_bad
  out=$("$@" 2>&1); rc=$?
  n_ok=$(printf '%s\n' "$out" | grep -c '^ok ')
  n_bad=$(printf '%s\n' "$out" | grep -c '^not ok ')
  if [ "$rc" -eq 0 ] && [ "$n_bad" -eq 0 ] && [ "$n_ok" -gt 0 ]; then
    passed=$((passed + n_ok)); echo "PASS $label ($n_ok ok)"
  else
    failed=$((failed + 1)); echo "FAIL $label (rc=$rc ok=$n_ok not_ok=$n_bad)"; printf '%s\n' "$out" | tail -15
  fi
}

E="$T/test/evp_test"
for f in 30-test_evp_data/evpmd_sm3.txt 30-test_evp_data/evpmd_sha.txt 30-test_evp_data/evpmd_md.txt \
         30-test_evp_data/evpciph_sm4.txt 30-test_evp_data/evpciph_aes_common.txt 30-test_evp_data/evpciph_chacha.txt \
         30-test_evp_data/evpmac_sm3.txt 30-test_evp_data/evpmac_common.txt \
         30-test_evp_data/evpkdf_hkdf.txt 30-test_evp_data/evpkdf_pbkdf2.txt 30-test_evp_data/evpkdf_tls12_prf.txt \
         30-test_evp_data/evppkey_sm2.txt 30-test_evp_data/evppkey_ecc.txt 30-test_evp_data/evppkey_rsa.txt; do
  run_tap "evp_test $f" "$E" "$D/$f"
done
for f in bnexp bngcd bnmod bnmul bnshift bnsum; do
  run_tap "bntest $f" "$T/test/bntest" "$D/10-test_bn_data/$f.txt"
done
run_tap "bntest" "$T/test/bntest"
for t in sm2_internal_test sm3_internal_test sm4_internal_test asn1_internal_test asn1_encode_test \
         asn1_decode_test asn1_time_test asn1_string_table_test; do
  run_tap "$t" "$T/test/$t"
done

emit_ctrf "tongsuo-tap" "$passed" "$failed" 0
