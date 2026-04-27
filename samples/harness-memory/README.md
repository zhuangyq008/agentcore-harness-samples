# Harness + Memory Sample

This sample demonstrates how to configure an AgentCore Harness with AgentCore Memory to enable conversation persistence across sessions.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                   AgentCore Harness                   │
│  ┌─────────────┐  ┌──────────┐  ┌─────────────────┐ │
│  │ Claude Model │  │  Tools   │  │  System Prompt  │ │
│  │ (Sonnet 4.6)│  │(browser, │  │                 │ │
│  │             │  │ code-int.)│  │                 │ │
│  └──────┬──────┘  └──────────┘  └─────────────────┘ │
│         │                                            │
│         ▼                                            │
│  ┌──────────────────────────────────────────────┐    │
│  │            AgentCore Memory                   │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────┐ │    │
│  │  │ Short-   │ │ Long-term│ │  Extraction  │ │    │
│  │  │ term     │ │ Records  │ │  Pipeline    │ │    │
│  │  │ Events   │ │          │ │  (async)     │ │    │
│  │  └──────────┘ └──────────┘ └──────────────┘ │    │
│  │                                              │    │
│  │  Strategies: SEMANTIC | USER_PREFERENCE |    │    │
│  │              SUMMARIZATION | EPISODIC        │    │
│  └──────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────┘
```

## Memory Types

| Type | Scope | Purpose |
|------|-------|---------|
| **Short-term** | Within a session | Raw events (messages, tool calls) for multi-turn context |
| **Long-term** | Across sessions | Durable knowledge extracted via configurable strategies |

### Long-term Memory Strategies

| Strategy | Namespace | What It Extracts |
|----------|-----------|------------------|
| `SEMANTIC` | `/users/{actorId}/facts` | Factual information (name, role, location) |
| `USER_PREFERENCE` | `/users/{actorId}/preferences` | Preferences and choices |
| `SUMMARIZATION` | `/summaries/{actorId}/{sessionId}` | Session summaries |
| `EPISODIC` | `/episodes/{actorId}/{sessionId}` | Event sequences with reflections |

## Quick Start

### Step 1: Create the project

```bash
agentcore create --name my-memory-agent
```

This creates a project with memory enabled by default.

### Step 2: Configure Memory in agentcore.json

Edit `agentcore/agentcore.json` to define the memory resource and link it to the harness:

```json
{
  "$schema": "https://schema.agentcore.aws.dev/v1/agentcore.json",
  "name": "my-memory-agent",
  "version": 1,
  "memories": [
    {
      "name": "MyHarnessMemory",
      "eventExpiryDuration": 30,
      "strategies": [
        {
          "type": "SEMANTIC",
          "namespaces": ["/users/{actorId}/facts"]
        },
        {
          "type": "USER_PREFERENCE",
          "namespaces": ["/users/{actorId}/preferences"]
        },
        {
          "type": "SUMMARIZATION",
          "namespaces": ["/summaries/{actorId}/{sessionId}"]
        },
        {
          "type": "EPISODIC",
          "namespaces": ["/episodes/{actorId}/{sessionId}"],
          "reflectionNamespaces": ["/episodes/{actorId}"]
        }
      ]
    }
  ],
  "harnesses": [
    {
      "name": "MyHarness",
      "path": "app/MyHarness"
    }
  ]
}
```

### Step 3: Configure the Harness

Edit `app/MyHarness/harness.json` to reference the memory:

```json
{
  "name": "MyHarness",
  "model": {
    "provider": "bedrock",
    "modelId": "global.anthropic.claude-sonnet-4-6"
  },
  "tools": [
    { "type": "agentcore_code_interpreter", "name": "code-interpreter" },
    { "type": "agentcore_browser", "name": "browser" }
  ],
  "memory": {
    "name": "MyHarnessMemory"
  },
  "sessionStoragePath": "/mnt/data/"
}
```

### Step 4: Deploy

```bash
agentcore deploy
```

### Step 5: Fix Memory Binding (Important!)

After `agentcore deploy`, the memory binding may not be correctly set on the harness. You **must** run `update-harness` to properly attach the memory:

```bash
# Get the deployed ARNs
HARNESS_ID=$(aws bedrock-agentcore-control list-harnesses \
  --region us-east-1 --query "harnesses[?contains(harnessName,'MyHarness')].harnessId" \
  --output text)

MEMORY_ARN=$(aws bedrock-agentcore-control list-memories \
  --region us-east-1 --query "memories[?contains(memoryName,'MyHarnessMemory')].arn" \
  --output text)

# Attach memory to harness
aws bedrock-agentcore-control update-harness \
  --harness-id "$HARNESS_ID" \
  --region us-east-1 \
  --memory "{\"optionalValue\": {\"agentCoreMemoryConfiguration\": {\"arn\": \"$MEMORY_ARN\"}}}"
```

> **Note**: This step is required after every `agentcore deploy` as the CDK deployment may overwrite the memory configuration. See the [scripts/fix-memory-binding.sh](scripts/fix-memory-binding.sh) helper script.

### Step 6: Test

Run the automated test script:

```bash
./scripts/test-memory.sh
```

Or test manually:

```bash
# Session 1: Store information
SESSION1="session-$(uuidgen)"
agentcore invoke --harness MyHarness \
  --session-id "$SESSION1" \
  --actor-id "user-alice" \
  --prompt "My name is Alice, I'm a DevOps engineer in Shanghai. I prefer Terraform for IaC."

# Wait 60+ seconds for async long-term memory extraction
sleep 70

# Session 2 (new session, same actor): Test recall
SESSION2="session-$(uuidgen)"
agentcore invoke --harness MyHarness \
  --session-id "$SESSION2" \
  --actor-id "user-alice" \
  --prompt "What do you know about me?"
```

### Step 7: Verify Memory Records

Check that events and long-term records were created:

```bash
MEMORY_ID="<your-memory-id>"  # e.g. my-memory-agent_MyHarnessMemory-abc123

# List actors
aws bedrock-agentcore list-actors \
  --memory-id "$MEMORY_ID" --region us-east-1

# Retrieve long-term semantic records
aws bedrock-agentcore retrieve-memory-records \
  --memory-id "$MEMORY_ID" --region us-east-1 \
  --namespace "/users/user-alice/facts" \
  --search-criteria '{"searchQuery": "user name and job"}'

# Retrieve user preferences
aws bedrock-agentcore retrieve-memory-records \
  --memory-id "$MEMORY_ID" --region us-east-1 \
  --namespace "/users/user-alice/preferences" \
  --search-criteria '{"searchQuery": "user tool preferences"}'
```

## File Structure

```
samples/harness-memory/
├── README.md                          # This file
├── agentcore/
│   ├── agentcore.json                 # Project config (memory + harness)
│   └── aws-targets.json               # Deployment target
├── app/
│   └── MyHarness/
│       ├── harness.json               # Harness config (model, tools, memory)
│       └── system-prompt.md           # System prompt
└── scripts/
    ├── fix-memory-binding.sh          # Fix memory binding after deploy
    └── test-memory.sh                 # Automated test script
```

## Key Concepts

### Actor ID

The `--actor-id` parameter scopes memory per user. Each actor gets isolated memory namespaces. Always pass `--actor-id` when invoking the harness to enable personalized memory.

```bash
agentcore invoke --harness MyHarness \
  --session-id "$(uuidgen)" \
  --actor-id "user-alice" \       # Alice's memory
  --prompt "Hello"

agentcore invoke --harness MyHarness \
  --session-id "$(uuidgen)" \
  --actor-id "user-bob" \         # Bob's memory (isolated from Alice)
  --prompt "Hello"
```

### Memory Pipeline

```
Conversation → Short-term Events → Async Extraction → Long-term Records
                  (immediate)        (30-90 seconds)     (persistent)
```

1. **Immediate**: Each invoke writes conversation events to short-term memory
2. **Async**: The extraction pipeline processes events in the background (~60s)
3. **Persistent**: Long-term records are stored and retrievable via semantic search

### Event Expiry

The `eventExpiryDuration` (in days) controls how long raw short-term events are retained. Long-term extracted records persist independently.

## Troubleshooting

### Memory events not being written

Check that memory is correctly bound to the harness:

```bash
# This should NOT error — if it does, re-run fix-memory-binding.sh
aws bedrock-agentcore-control get-harness \
  --harness-id "<harness-id>" --region us-east-1 \
  --query "harness.memory"
```

### Long-term records not appearing

Long-term memory extraction is asynchronous. Wait at least 60 seconds after the conversation, then check:

```bash
aws bedrock-agentcore list-memory-extraction-jobs \
  --memory-id "<memory-id>" --region us-east-1
```

### Memory lost after redeploy

`agentcore deploy` may overwrite the memory configuration. Always run `fix-memory-binding.sh` after each deployment.

## References

- [Persist memory and filesystem](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/harness-memory.html)
- [Memory types](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-types.html)
- [Long-term memory deep dive](https://aws.amazon.com/blogs/machine-learning/building-smarter-ai-agents-agentcore-long-term-memory-deep-dive/)
- [Customer support scenario](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory-customer-scenario.html)
