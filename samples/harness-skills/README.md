# Harness + Skills Sample

This sample demonstrates how to configure an AgentCore Harness with [Agent Skills](https://github.com/anthropics/skills) — bundles of markdown and scripts that give the agent domain knowledge on demand.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    AgentCore Harness                      │
│  ┌─────────────┐  ┌───────────────┐  ┌───────────────┐  │
│  │ Claude Model │  │     Tools     │  │ System Prompt │  │
│  │ (Sonnet 4.6)│  │ (code-interp.)│  │               │  │
│  └──────┬──────┘  └───────────────┘  └───────────────┘  │
│         │                                                │
│         ▼                                                │
│  ┌──────────────────────────────────────────────────┐    │
│  │              Agent Skills                         │    │
│  │                                                   │    │
│  │  .agents/skills/xlsx/                             │    │
│  │    ├── SKILL.md          (instructions)           │    │
│  │    └── scripts/          (helper scripts)         │    │
│  │                                                   │    │
│  │  .agents/skills/frontend-design/                  │    │
│  │    └── SKILL.md          (instructions)           │    │
│  │                                                   │    │
│  │  Skills are loaded into the agent's context on    │    │
│  │  demand via the --skills flag at invoke time.     │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

## How Skills Work

Skills are **not** uploaded through `harness.json` or `agentcore.json`. The `skills` parameter is a **pointer** to a path inside the harness environment's filesystem. You must get the skill files into the environment first.

### Three-Tier Loading Model

```
1. Metadata (~100 tokens)     ← name + description, loaded at startup
2. Instructions (<5000 tokens) ← full SKILL.md body, loaded when skill activates
3. Resources (on demand)       ← scripts/, references/, assets/, loaded as needed
```

### Two Ways to Install Skills

| Method | When to Use | Pros | Cons |
|--------|-------------|------|------|
| **Bake into container** | Production | Always available, no per-session setup | Requires custom container image + redeploy |
| **Install at session start** | Development / testing | Fast iteration, no redeploy needed | Adds latency to first invocation |

## Quick Start

### Step 1: Create a project

```bash
agentcore create --name my-skills-agent
```

### Step 2: Configure the Harness

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

> **Note**: The `skills` field in `harness.json` is optional. You can persist skill paths on the harness, or pass them at invoke time via `--skills`.

### Step 3: Deploy

```bash
agentcore deploy
```

### Step 4: Install Skills into the Session

Generate a session ID and use `--exec` to install skills before invoking the agent:

```bash
SESSION_ID=$(uuidgen)

# Download and install skills from GitHub
agentcore invoke --exec --harness MyHarness \
  --session-id "$SESSION_ID" \
  --prompt "mkdir -p .agents/skills && curl -sL https://github.com/anthropics/skills/archive/refs/heads/main.tar.gz | tar xz -C /tmp && cp -r /tmp/skills-main/skills/xlsx .agents/skills/xlsx"
```

Verify the skill was installed:

```bash
agentcore invoke --exec --harness MyHarness \
  --session-id "$SESSION_ID" \
  --prompt "ls .agents/skills/xlsx/"
```

Expected output:

```
LICENSE.txt
SKILL.md
scripts
```

### Step 5: Invoke with Skills

```bash
agentcore invoke --harness MyHarness \
  --session-id "$SESSION_ID" \
  --skills ".agents/skills/xlsx" \
  --prompt "Create an Excel file at /tmp/sales.xlsx with a sheet named 'Q1 Sales'. Columns: Month, Product, Revenue, Units. Add rows: Jan/Widget/15000/300, Feb/Widget/17500/350, Mar/Widget/21000/420. Then read it back."
```

### Step 6: Use Multiple Skills

You can install and use multiple skills in the same session:

```bash
# Install multiple skills
agentcore invoke --exec --harness MyHarness \
  --session-id "$SESSION_ID" \
  --prompt "cp -r /tmp/skills-main/skills/frontend-design .agents/skills/frontend-design"

# Invoke with multiple skills (comma-separated)
agentcore invoke --harness MyHarness \
  --session-id "$SESSION_ID" \
  --skills ".agents/skills/xlsx,.agents/skills/frontend-design" \
  --prompt "Create a dashboard HTML page"
```

## Automated Test

Run the provided test script:

```bash
./scripts/test-skills.sh
```

This script:
1. Generates a session ID
2. Installs the `xlsx` skill via `--exec`
3. Invokes the harness with the skill to create an Excel file
4. Verifies the file was created

## Available Skills

The [anthropics/skills](https://github.com/anthropics/skills) repository provides these skills:

| Skill | Description | Requires |
|-------|-------------|----------|
| `xlsx` | Create, read, edit spreadsheets (.xlsx, .csv) | code-interpreter |
| `pdf` | Read, extract, merge, split, watermark PDFs | code-interpreter |
| `docx` | Create, read, edit Word documents | code-interpreter |
| `pptx` | Create, read, edit PowerPoint presentations | code-interpreter |
| `frontend-design` | Production-grade frontend interfaces | code-interpreter |
| `claude-api` | Build apps with Anthropic SDK | code-interpreter |
| `mcp-builder` | Build MCP servers in TS or Python | code-interpreter |
| `web-artifacts-builder` | Multi-component HTML artifacts | code-interpreter |
| `webapp-testing` | Test web apps with Playwright | code-interpreter |
| `algorithmic-art` | Generative art with p5.js | code-interpreter |
| `canvas-design` | Museum-quality visual art | code-interpreter |
| `slack-gif-creator` | Animated GIFs for Slack | code-interpreter |
| `skill-creator` | Meta-skill for creating other skills | code-interpreter |

## Skill File Structure

Each skill follows the [Agent Skills Specification](https://agentskills.io/specification):

```
xlsx/
├── SKILL.md           # Required: YAML frontmatter + markdown instructions
├── LICENSE.txt         # License file
└── scripts/           # Optional: helper scripts loaded on demand
    └── ...
```

### SKILL.md Format

```yaml
---
name: xlsx                              # lowercase + hyphens, must match dir name
description: |                          # what the skill does + when to use it
  Create, read, and edit spreadsheets
  (.xlsx, .xlsm, .csv, .tsv).
---

# Instructions for the agent
...
```

## Key Concepts

### Skills vs Tools

| | Skills | Tools |
|---|--------|-------|
| **What** | Domain knowledge (markdown + scripts) | Executable capabilities (APIs) |
| **When loaded** | On demand, into model context | Always available |
| **Token cost** | Consumes context window | No context cost until invoked |
| **Example** | "How to format Excel headers" | `code-interpreter` to run Python |

Skills tell the agent **how** to use tools effectively for specific domains.

### Skill Path Resolution

The `--skills` path is relative to the harness working directory (not `/`). The agent uses the path to find and load `SKILL.md` and any referenced resources.

### Session Scope

Skills installed via `--exec` exist only for the duration of that session. A new session starts with a clean environment. For persistent skills, bake them into a custom container image.

## File Structure

```
samples/harness-skills/
├── README.md                          # This file
├── agentcore/
│   ├── agentcore.json                 # Project config
│   └── aws-targets.json               # Deployment target
├── app/
│   └── MyHarness/
│       ├── harness.json               # Harness config (model, tools)
│       └── system-prompt.md           # System prompt
└── scripts/
    └── test-skills.sh                 # Automated test script
```

## References

- [Environment and Skills (AWS docs)](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/harness-environment.html)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)
- [Connect to tools](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/harness-tools.html)
