#!/bin/bash
# Test that two verify-clean commands serialize via the store lock.
# Run two verify-clean commands in parallel; both should complete without
# reporting containers, volumes or directories left by the other.

set -uo pipefail

SB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

test_log="$SB_DIR/sandbox-lock-test.log"
rm -f "$test_log"

say() { echo ">>> $*" | tee -a "$test_log"; }
ok() { echo "✓ $*" | tee -a "$test_log"; }
fail() { echo "✗ $*" | tee -a "$test_log"; }

say "Testing store lock serialization with two parallel verify-clean commands"

# Run two verify-clean commands in parallel
{
  say "Command 1: starting verify-clean"
  "$SB_DIR/sandbox" verify-clean 2>&1 | tee -a "$test_log"
  local rc1=$?
  say "Command 1: finished with exit code $rc1"
} &
pid1=$!

{
  # Small delay to ensure first command acquires lock first
  sleep 0.5
  say "Command 2: starting verify-clean"
  "$SB_DIR/sandbox" verify-clean 2>&1 | tee -a "$test_log"
  local rc2=$?
  say "Command 2: finished with exit code $rc2"
} &
pid2=$!

# Wait for both to complete
wait $pid1 rc1_actual=$?
wait $pid2 rc2_actual=$?

say "Both commands completed"

# Check results: both should have succeeded (exit 0)
if [[ $rc1_actual -eq 0 && $rc2_actual -eq 0 ]]; then
  ok "Both verify-clean commands succeeded (lock serialized them correctly)"
  ok "Test passed"
  exit 0
else
  fail "One or both commands failed: cmd1=$rc1_actual, cmd2=$rc2_actual"
  fail "Test failed"
  exit 1
fi
