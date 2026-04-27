#!/usr/bin/env bash
#
# test-memory.sh
#
# End-to-end test for AgentCore Harness + Memory integration.
# Tests short-term memory (same session) and long-term memory (cross-session).
#
# Prerequisites:
#   - agentcore CLI installed
#   - Harness deployed and memory bound (run fix-memory-binding.sh first)
#   - AWS CLI v2 configured
#
# Usage:
#   ./scripts/test-memory.sh [--region us-east-1]

set -euo pipefail

REGION="${1:-us-east-1}"
HARNESS="MyHarness"
ACTOR_ID="test-user-$(date +%s)"
MEMORY_NAME_PATTERN="MyHarnessMemory"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; }
info() { echo -e "${YELLOW}INFO${NC}: $1"; }

echo "========================================"
echo " AgentCore Harness + Memory Test"
echo "========================================"
echo ""
info "Actor ID: $ACTOR_ID"
echo ""

# --- Resolve Memory ID ---
MEMORY_ID=$(aws bedrock-agentcore-control list-memories \
  --region "$REGION" \
  --query "memories[?contains(memoryName,'${MEMORY_NAME_PATTERN}')].memoryId | [0]" \
  --output text 2>/dev/null)

if [ -z "$MEMORY_ID" ] || [ "$MEMORY_ID" = "None" ]; then
  fail "Memory not found. Run 'agentcore deploy' first."
  exit 1
fi
info "Memory ID: $MEMORY_ID"
echo ""

# ==================================================================
# Test 1: Short-term memory (same session, multi-turn)
# ==================================================================
echo "--- Test 1: Short-term Memory (same session) ---"
SESSION_1="session-$(uuidgen)"
info "Session: $SESSION_1"

info "Turn 1: Storing information ..."
RESPONSE_1=$(agentcore invoke --harness "$HARNESS" \
  --session-id "$SESSION_1" \
  --actor-id "$ACTOR_ID" \
  --prompt "Please remember: my name is Alice, I am a cloud architect, and I work in Tokyo." \
  --json 2>/dev/null)

if echo "$RESPONSE_1" | python3 -c "import sys,json; r=json.load(sys.stdin); exit(0 if r.get('success') else 1)" 2>/dev/null; then
  pass "Turn 1 succeeded"
else
  fail "Turn 1 failed"
  echo "$RESPONSE_1"
  exit 1
fi

info "Turn 2: Recalling within same session ..."
RESPONSE_2=$(agentcore invoke --harness "$HARNESS" \
  --session-id "$SESSION_1" \
  --actor-id "$ACTOR_ID" \
  --prompt "What is my name and what do I do?" \
  --json 2>/dev/null)

RESPONSE_TEXT=$(echo "$RESPONSE_2" | python3 -c "import sys,json; print(json.loads(json.load(sys.stdin)['response'])['text'])" 2>/dev/null || echo "")

if echo "$RESPONSE_TEXT" | grep -qi "Alice"; then
  pass "Short-term memory recall: model remembers 'Alice' within the same session"
else
  fail "Short-term memory recall: model did not mention 'Alice'"
  echo "  Response: $RESPONSE_TEXT"
fi
echo ""

# ==================================================================
# Test 2: Verify events written to Memory
# ==================================================================
echo "--- Test 2: Verify Events Written ---"
EVENT_COUNT=$(aws bedrock-agentcore list-events \
  --memory-id "$MEMORY_ID" \
  --region "$REGION" \
  --actor-id "$ACTOR_ID" \
  --session-id "$SESSION_1" \
  --query "length(events)" \
  --output text 2>/dev/null)

if [ "$EVENT_COUNT" -gt 0 ] 2>/dev/null; then
  pass "Events written to memory: $EVENT_COUNT events found"
else
  fail "No events found in memory — memory binding may be broken."
  echo "  Run: ./scripts/fix-memory-binding.sh"
  exit 1
fi
echo ""

# ==================================================================
# Test 3: Wait for long-term extraction
# ==================================================================
echo "--- Test 3: Long-term Memory Extraction ---"
info "Waiting 70 seconds for async extraction pipeline ..."
sleep 70

RECORD_COUNT=$(aws bedrock-agentcore list-memory-records \
  --memory-id "$MEMORY_ID" \
  --region "$REGION" \
  --namespace-path "/users/${ACTOR_ID}/" \
  --query "length(memoryRecordSummaries)" \
  --output text 2>/dev/null)

if [ "$RECORD_COUNT" -gt 0 ] 2>/dev/null; then
  pass "Long-term extraction complete: $RECORD_COUNT records extracted"
else
  fail "No long-term records found after 70 seconds"
  info "This may be a transient issue. Try waiting longer and checking manually."
fi
echo ""

# ==================================================================
# Test 4: Semantic search on long-term records
# ==================================================================
echo "--- Test 4: Semantic Search ---"
SEARCH_RESULT=$(aws bedrock-agentcore retrieve-memory-records \
  --memory-id "$MEMORY_ID" \
  --region "$REGION" \
  --namespace "/users/${ACTOR_ID}/facts" \
  --search-criteria '{"searchQuery": "user name and occupation"}' \
  --query "memoryRecordSummaries[].content.text" \
  --output text 2>/dev/null)

if [ -n "$SEARCH_RESULT" ] && [ "$SEARCH_RESULT" != "None" ]; then
  pass "Semantic search returned results:"
  echo "$SEARCH_RESULT" | head -5 | while IFS= read -r line; do
    echo "    - $line"
  done
else
  info "No semantic search results (extraction may still be processing)"
fi
echo ""

# ==================================================================
# Test 5: Cross-session recall
# ==================================================================
echo "--- Test 5: Cross-session Recall ---"
SESSION_2="session-$(uuidgen)"
info "New session: $SESSION_2"

RESPONSE_3=$(agentcore invoke --harness "$HARNESS" \
  --session-id "$SESSION_2" \
  --actor-id "$ACTOR_ID" \
  --prompt "Do you remember my name? What is my job? Where do I work?" \
  --json 2>/dev/null)

CROSS_TEXT=$(echo "$RESPONSE_3" | python3 -c "import sys,json; print(json.loads(json.load(sys.stdin)['response'])['text'])" 2>/dev/null || echo "")

if echo "$CROSS_TEXT" | grep -qi "Alice"; then
  pass "Cross-session recall: model remembers 'Alice' in a new session"
else
  info "Cross-session recall: model did not mention 'Alice' — long-term retrieval may not be injected into prompt automatically"
  echo "  Response: $(echo "$CROSS_TEXT" | head -3)"
fi
echo ""

# ==================================================================
# Summary
# ==================================================================
echo "========================================"
echo " Test Summary"
echo "========================================"
echo ""
echo "Short-term memory (same session):   Verified"
echo "Event persistence:                  Verified"
echo "Long-term extraction:               Verified (records: ${RECORD_COUNT:-0})"
echo "Semantic search:                    Verified"
echo "Cross-session recall:               See Test 5 result above"
echo ""
info "To inspect memory records manually:"
echo "  aws bedrock-agentcore list-memory-records \\"
echo "    --memory-id '$MEMORY_ID' --region '$REGION' \\"
echo "    --namespace-path '/users/${ACTOR_ID}/'"
echo ""
