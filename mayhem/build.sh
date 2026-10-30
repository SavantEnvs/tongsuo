#!/usr/bin/env bash
#
# mayhem/build.sh — Tongsuo (OpenSSL fork): build the libFuzzer harnesses from fuzz/ and the test oracle.
#
# Runs in the commit image as `mayhem` in /mayhem. Re-runnable and offline: only the in-tree Configure/make
# are used (no downloads); both build trees live in mayhem/_build/ (gitignored by mayhem/.gitignore).
#   mayhem/_build/fuzz : libcrypto.a/libssl.a built with $SANITIZER_FLAGS $DEBUG_FLAGS and coverage
#                        instrumentation, linked into every harness  -> /mayhem/fuzz_<name>[-standalone]
#   mayhem/_build/test : the NORMAL-flags build of the unit-test programs that mayhem/test.sh runs
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export CC CXX

cd "$SRC"
BUILD="$SRC/mayhem/_build"
mkdir -p "$BUILD/fuzz" "$BUILD/test"

# Options shared by both builds (static libs; Tongsuo's NTLS/SM stack on, legacy/weak algorithms on so the
# harnesses reach them).
COMMON_OPTS="no-shared enable-ntls enable-weak-ssl-ciphers enable-rc5 enable-ssl3 enable-ssl3-method enable-nextprotoneg enable-ec_nistp_64_gcc_128"

# ---------------------------------------------------------------------------------------------------------
# 1) Sanitized + coverage-instrumented library for the fuzz harnesses.
#    UBSan `alignment` and `function` checks are relaxed: the library does deliberate unaligned loads and calls
#    cast comparator/free callbacks through its safestack/lhash layer (benign by design; upstream's
#    fuzz/README.md relaxes alignment too). Everything else in ASan+UBSan stays on and halting.
# ---------------------------------------------------------------------------------------------------------
FUZZ_CFLAGS="$SANITIZER_FLAGS -fno-sanitize=alignment,function -fsanitize=fuzzer-no-link $DEBUG_FLAGS -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
cd "$BUILD/fuzz"
if [ ! -f Makefile ]; then
  "$SRC/config" enable-fuzz-libfuzzer $COMMON_OPTS $FUZZ_CFLAGS
fi
make -j"$MAYHEM_JOBS" build_generated >/dev/null
make -j"$MAYHEM_JOBS" libcrypto.a libssl.a

# ---------------------------------------------------------------------------------------------------------
# 2) Harnesses: every fuzz/*.c program that upstream's fuzz/build.info builds, each linked twice.
# ---------------------------------------------------------------------------------------------------------
# leak detection off at build time (see docs: ASan/UBSan stay active)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$BUILD/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/sancov_stubs.c" -o "$BUILD/sancov_stubs.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$BUILD/standalone_main.o"

HARNESSES="acert asn1 asn1parse bignum bndiv client cmp cms conf crl ct decoder dtlsclient dtlsserver hashtable ml-dsa ml-kem pem provider punycode quic-client quic-lcidm quic-rcidm quic-server quic-srtm server slh-dsa smime v3name x509"
INC="-I$BUILD/fuzz/include -I$SRC/include -I$SRC -I$SRC/fuzz"
LIBS="$BUILD/fuzz/libssl.a $BUILD/fuzz/libcrypto.a -ldl -pthread"

for h in $HARNESSES; do
  srcs=$(sed -n "s/^[[:space:]]*SOURCE\[$h\]=//p" "$SRC/fuzz/build.info" | head -1)
  [ -n "$srcs" ] || { echo "no SOURCE[$h] in fuzz/build.info" >&2; exit 1; }
  files=""
  for s in $srcs; do files="$files $SRC/fuzz/$s"; done
  out="/mayhem/fuzz_${h//-/_}"
  $CC $FUZZ_CFLAGS $INC $files "$BUILD/lsan_off.o" $LIBS $LIB_FUZZING_ENGINE -o "$out"
  $CC $FUZZ_CFLAGS $INC $files "$BUILD/lsan_off.o" "$BUILD/sancov_stubs.o" "$BUILD/standalone_main.o" $LIBS -o "$out-standalone"
done

# ---------------------------------------------------------------------------------------------------------
# 3) Test oracle: NORMAL flags, separate tree. mayhem/test.sh only runs these programs.
# ---------------------------------------------------------------------------------------------------------
cd "$BUILD/test"
if [ ! -f Makefile ]; then
  "$SRC/config" $COMMON_OPTS $COVERAGE_FLAGS
fi
make -j"$MAYHEM_JOBS" build_generated >/dev/null
make -j"$MAYHEM_JOBS" libcrypto.a libssl.a
TEST_PROGS="evp_test bntest sm2_internal_test sm3_internal_test sm4_internal_test asn1_internal_test asn1_encode_test asn1_decode_test asn1_time_test asn1_string_table_test"
make -j"$MAYHEM_JOBS" $(for t in $TEST_PROGS; do printf 'test/%s ' "$t"; done)
