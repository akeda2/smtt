#!/usr/bin/env bash

set -u

pass=0
fail=0
skip=0
verbose=0

usage() {
  echo "Usage: ./selftest.sh [-v|--verbose] [-h|--help]"
  echo "  -v, --verbose  Print command output for passing tests"
  echo "  -h, --help     Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      verbose=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

print_indented() {
  local line
  while IFS= read -r line; do
    echo "    $line"
  done <<< "$1"
}

run_case() {
  local name=$1 expected_rc=$2
  shift 2

  local out rc
  out=$("$@" 2>&1)
  rc=$?

  if [[ $rc -eq $expected_rc ]]; then
    echo "PASS: $name"
    if (( verbose == 1 )); then
      echo "  Command: $*"
      if [[ -n $out ]]; then
        echo "  Output:"
        print_indented "$out"
      fi
    fi
    (( pass++ ))
  else
    echo "FAIL: $name (expected rc=$expected_rc, got rc=$rc)"
    echo "  Command: $*"
    echo "  Output:"
    print_indented "$out"
    (( fail++ ))
  fi
}

run_state_case() {
  local name=$1
  shift

  local out rc
  out=$("$@" 2>&1)
  rc=$?

  if [[ $rc -eq 0 || $rc -eq 1 ]]; then
    echo "PASS: $name (rc=$rc)"
    if (( verbose == 1 )); then
      echo "  Command: $*"
      if [[ -n $out ]]; then
        echo "  Output:"
        print_indented "$out"
      fi
    fi
    (( pass++ ))
  else
    echo "FAIL: $name (expected rc=0|1, got rc=$rc)"
    echo "  Command: $*"
    echo "  Output:"
    print_indented "$out"
    (( fail++ ))
  fi
}

echo "Running CLI self-tests..."

run_case "bash syntax" 0 bash -n inst.sh smtt.sh turbot.sh sockt.sh
run_case "sockt help" 0 ./sockt.sh -h
run_case "sockt invalid option" 1 ./sockt.sh -z
run_case "sockt dry-run offline non-zero" 0 ./sockt.sh -n -s
run_case "sockt dry-run mapped limits" 0 ./sockt.sh -n -m 0:1
run_case "sockt conflict guard" 1 ./sockt.sh -n -r -m 0:1

run_case "smtt help" 0 ./smtt.sh h
run_case "smtt invalid arg" 1 ./smtt.sh invalid
run_state_case "smtt status boolean exit" ./smtt.sh

if [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
  run_case "turbot help" 0 ./turbot.sh h
  run_case "turbot invalid arg" 1 ./turbot.sh invalid
  run_state_case "turbot status boolean exit" ./turbot.sh
else
  echo "SKIP: turbot tests (intel_pstate no_turbo not available)"
  (( skip++ ))
fi

echo
echo "Summary: pass=$pass fail=$fail skip=$skip"

if [[ $fail -gt 0 ]]; then
  exit 1
fi

exit 0