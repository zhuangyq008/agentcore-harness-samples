#!/usr/bin/env bash
#
# fix-memory-binding.sh
#
# After `agentcore deploy`, the CDK deployment may write an incomplete memory
# configuration to the harness. This script re-attaches the memory correctly
# via the update-harness API.
#
# Usage:
#   ./scripts/fix-memory-binding.sh [--region us-east-1]

set -euo pipefail

REGION="${1:-us-east-1}"
HARNESS_NAME_PATTERN="MyHarness"
MEMORY_NAME_PATTERN="MyHarnessMemory"

echo "==> Looking up harness ID (pattern: $HARNESS_NAME_PATTERN) ..."
HARNESS_ID=$(aws bedrock-agentcore-control list-harnesses \
  --region "$REGION" \
  --query "harnesses[?contains(harnessName,'${HARNESS_NAME_PATTERN}')].harnessId | [0]" \
  --output text)

if [ -z "$HARNESS_ID" ] || [ "$HARNESS_ID" = "None" ]; then
  echo "ERROR: Harness not found. Deploy first with: agentcore deploy"
  exit 1
fi
echo "    Harness ID: $HARNESS_ID"

echo "==> Looking up memory ARN (pattern: $MEMORY_NAME_PATTERN) ..."
MEMORY_ARN=$(aws bedrock-agentcore-control list-memories \
  --region "$REGION" \
  --query "memories[?contains(memoryName,'${MEMORY_NAME_PATTERN}')].arn | [0]" \
  --output text)

if [ -z "$MEMORY_ARN" ] || [ "$MEMORY_ARN" = "None" ]; then
  echo "ERROR: Memory not found. Deploy first with: agentcore deploy"
  exit 1
fi
echo "    Memory ARN: $MEMORY_ARN"

echo "==> Attaching memory to harness ..."
aws bedrock-agentcore-control update-harness \
  --harness-id "$HARNESS_ID" \
  --region "$REGION" \
  --memory "{\"optionalValue\": {\"agentCoreMemoryConfiguration\": {\"arn\": \"${MEMORY_ARN}\"}}}" \
  --no-cli-pager \
  --query "harness.{status:status,memory:memory}" \
  --output json

echo ""
echo "==> Waiting for harness to become READY ..."
for i in $(seq 1 12); do
  STATUS=$(aws bedrock-agentcore-control list-harnesses \
    --region "$REGION" \
    --query "harnesses[?harnessId=='${HARNESS_ID}'].status | [0]" \
    --output text)
  if [ "$STATUS" = "READY" ]; then
    echo "    Harness is READY."
    break
  fi
  echo "    Status: $STATUS (attempt $i/12) ..."
  sleep 5
done

echo ""
echo "Done. Memory '$MEMORY_NAME_PATTERN' is now bound to harness '$HARNESS_NAME_PATTERN'."
