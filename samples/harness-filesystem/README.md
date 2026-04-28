# Harness + Session Storage (Filesystem) Sample

This sample demonstrates the behavior of `sessionStoragePath` in AgentCore Harness — a per-session persistent filesystem backed by S3. It clarifies what "persistent" means: files persist across **invocations within the same session**, but are **isolated between different sessions**.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     AgentCore Harness                        │
│                                                             │
│  Session A (session-id: "aaa...")                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  /mnt/data/          ← S3-backed, isolated per session │ │
│  │    ├── report.xlsx                                     │ │
│  │    └── output/                                         │ │
│  │  Invoke 1: write files  ──►  Invoke 2: files persist ✅│ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  Session B (session-id: "bbb...")                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  /mnt/data/          ← fresh empty directory           │ │
│  │    (empty)                                             │ │
│  │  Cannot see Session A's files ❌                        │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Key Behavior

| Scenario | File Visible? | Why |
|----------|---------------|-----|
| Same session-id, multiple invokes | Yes ✅ | Same S3-backed mount is restored |
| Different session-id | No ❌ | Each session gets an isolated empty directory |
| No session-id (auto-generated) | No ❌ | Every invoke creates a new session |
| Session idle > 14 days | No ❌ | Data is automatically deleted |
| Agent runtime version updated | No ❌ | All session storage data is deleted |

### Session Storage Specs

- **Max size**: 1 GB per session
- **Retention**: 14 days of idle (no invocations)
- **Mount path**: Must be under `/mnt/` with one subdirectory (e.g., `/mnt/data/`)
- **Filesystem**: Standard Linux filesystem (files, directories, symlinks)
- **Unsupported**: Hard links, device files, FIFOs, UNIX sockets, file locking across sessions

## Quick Start

### Step 1: Create a project

```bash
agentcore create --name my-fs-agent
```

### Step 2: Configure sessionStoragePath

Edit `app/MyHarness/harness.json`:

```json
{
  "name": "MyHarness",
  "model": {
    "provider": "bedrock",
    "modelId": "global.anthropic.claude-sonnet-4-6"
  },
  "tools": [
    { "type": "agentcore_code_interpreter", "name": "code-interpreter" }
  ],
  "sessionStoragePath": "/mnt/data/"
}
```

### Step 3: Deploy

```bash
agentcore deploy
```

### Step 4: Test Same-Session Persistence

```bash
SESSION_ID=$(uuidgen)

# Invoke 1: Write a file
agentcore invoke --harness MyHarness \
  --session-id "$SESSION_ID" \
  --prompt "Write 'hello from invoke 1' to /mnt/data/test.txt"

# Invoke 2 (same session): Read back
agentcore invoke --harness MyHarness \
  --session-id "$SESSION_ID" \
  --prompt "Read /mnt/data/test.txt and show the content"
# ✅ Output: "hello from invoke 1"
```

### Step 5: Verify Cross-Session Isolation

```bash
NEW_SESSION_ID=$(uuidgen)

# Different session: Try to read the same file
agentcore invoke --harness MyHarness \
  --session-id "$NEW_SESSION_ID" \
  --prompt "Read /mnt/data/test.txt. If not found, say FILE NOT FOUND."
# ❌ Output: "FILE NOT FOUND"
```

## Automated Test

Run the provided test script:

```bash
./scripts/test-filesystem.sh
```

This script runs three scenarios:
1. **Write** — writes a file to `/mnt/data/` in session A
2. **Same-session read** — reads the file back in session A (expects success)
3. **Cross-session read** — reads the file in session B (expects FILE NOT FOUND)

## Use Cases

### Good fit for sessionStoragePath

- **Multi-step workflows**: Agent generates code in invoke 1, runs tests in invoke 2, deploys in invoke 3 — all within one session
- **Iterative data processing**: Agent refines analysis across multiple invocations
- **Code generation with checkpoints**: Agent saves intermediate build artifacts

### Not a good fit (use these instead)

| Need | Solution |
|------|----------|
| Cross-session user data | [AgentCore Memory](../harness-memory/) with `--actor-id` |
| Cross-session file sharing | External storage (S3) accessed from agent code |
| Permanent artifacts | Upload to S3 within the agent workflow |

## File Structure

```
samples/harness-filesystem/
├── README.md                          # This file
├── agentcore/
│   ├── agentcore.json                 # Project config
│   └── aws-targets.json               # Deployment target
├── app/
│   └── MyHarness/
│       ├── harness.json               # Harness config with sessionStoragePath
│       └── system-prompt.md           # System prompt
└── scripts/
    └── test-filesystem.sh             # Automated test (3 scenarios)
```

## References

- [Persist session state across stop/resume](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-persistent-filesystems.html)
- [Use isolated sessions for agents](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-sessions.html)
- [Session storage announcement](https://aws.amazon.com/about-aws/whats-new/2026/03/bedrock-agentcore-runtime-session-storage/)
- [Persist memory and filesystem](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/harness-memory.html)
