#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────
# test-skills.sh — Install and test the xlsx skill
# ─────────────────────────────────────────────────────────
# Usage:
#   ./scripts/test-skills.sh [harness-name]
#
# Prerequisites:
#   - agentcore CLI installed
#   - Harness deployed (agentcore deploy)
# ─────────────────────────────────────────────────────────

HARNESS="${1:-MyHarness}"
SESSION_ID="skills-test-$(date +%s)-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

echo "============================================"
echo "  AgentCore Skills Test"
echo "============================================"
echo "Harness:    $HARNESS"
echo "Session ID: $SESSION_ID"
echo ""

# ── Step 1: Install xlsx skill ──────────────────────────
echo "── Step 1: Installing xlsx skill into session..."
agentcore invoke --exec --harness "$HARNESS" \
  --session-id "$SESSION_ID" \
  --prompt "mkdir -p .agents/skills && curl -sL https://github.com/anthropics/skills/archive/refs/heads/main.tar.gz | tar xz -C /tmp && cp -r /tmp/skills-main/skills/xlsx .agents/skills/xlsx && echo 'INSTALLED' && ls .agents/skills/xlsx/"

echo ""

# ── Step 2: Verify skill structure ──────────────────────
echo "── Step 2: Verifying skill structure..."
agentcore invoke --exec --harness "$HARNESS" \
  --session-id "$SESSION_ID" \
  --prompt "test -f .agents/skills/xlsx/SKILL.md && echo 'SKILL.md: OK' || echo 'SKILL.md: MISSING'"

echo ""

# ── Step 3: Invoke with xlsx skill ──────────────────────
echo "── Step 3: Invoking harness with xlsx skill..."
agentcore invoke --harness "$HARNESS" \
  --session-id "$SESSION_ID" \
  --skills ".agents/skills/xlsx" \
  --prompt "Create an Excel file at /tmp/test-output.xlsx with a sheet named 'TestData' containing columns: Name, Score, Grade. Add 3 rows: Alice/95/A, Bob/82/B, Charlie/71/C. Then read the file back and confirm the data."

echo ""

# ── Step 4: Verify file was created ─────────────────────
echo "── Step 4: Verifying output file..."
agentcore invoke --exec --harness "$HARNESS" \
  --session-id "$SESSION_ID" \
  --prompt "test -f /tmp/test-output.xlsx && echo 'OUTPUT FILE: OK' && ls -lh /tmp/test-output.xlsx || echo 'OUTPUT FILE: MISSING'"

echo ""
echo "============================================"
echo "  Test complete"
echo "============================================"
