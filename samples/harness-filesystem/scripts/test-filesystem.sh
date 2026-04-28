#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# test-filesystem.sh — Test session storage persistence
# ─────────────────────────────────────────────────────────
# Runs 3 scenarios:
#   1. Write a file in session A
#   2. Read the file in session A (same session — expect success)
#   3. Read the file in session B (different session — expect not found)
#
# Usage:
#   ./scripts/test-filesystem.sh [harness-name]
# ─────────────────────────────────────────────────────────

HARNESS="${1:-MyHarness}"
TIMESTAMP=$(date +%s)
SESSION_A="fs-test-session-a-${TIMESTAMP}-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
SESSION_B="fs-test-session-b-${TIMESTAMP}-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
TEST_CONTENT="persistence-test-${TIMESTAMP}"

echo "============================================"
echo "  Session Storage Persistence Test"
echo "============================================"
echo "Harness:    $HARNESS"
echo "Session A:  $SESSION_A"
echo "Session B:  $SESSION_B"
echo "Content:    $TEST_CONTENT"
echo ""

# ── Scenario 1: Write file in Session A ─────────────────
echo "── Scenario 1: Write file in Session A"
agentcore invoke --harness "$HARNESS" \
  --session-id "$SESSION_A" \
  --prompt "Write exactly '${TEST_CONTENT}' to /mnt/data/test-persist.txt using the code interpreter. No extra text. Then confirm by reading it back."

echo ""
echo ""

# ── Scenario 2: Read in Session A (same session) ────────
echo "── Scenario 2: Read file in Session A (same session — expect SUCCESS)"
agentcore invoke --harness "$HARNESS" \
  --session-id "$SESSION_A" \
  --prompt "Read the file /mnt/data/test-persist.txt and show its exact content. If not found, say FILE NOT FOUND."

echo ""
echo ""

# ── Scenario 3: Read in Session B (different session) ───
echo "── Scenario 3: Read file in Session B (different session — expect NOT FOUND)"
agentcore invoke --harness "$HARNESS" \
  --session-id "$SESSION_B" \
  --prompt "Read the file /mnt/data/test-persist.txt and show its exact content. If not found, say FILE NOT FOUND."

echo ""
echo "============================================"
echo "  Expected results:"
echo "    Scenario 2: shows '${TEST_CONTENT}'"
echo "    Scenario 3: FILE NOT FOUND"
echo "============================================"
