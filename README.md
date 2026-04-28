# AgentCore Harness Samples

A collection of hands-on examples demonstrating how to build, configure, and deploy AI agents using [Amazon Bedrock AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/).

## Samples

| Sample | Description |
|--------|-------------|
| [harness-memory](samples/harness-memory/) | Configure a Harness with AgentCore Memory for short-term and long-term conversation persistence |
| [harness-skills](samples/harness-skills/) | Configure a Harness with Agent Skills for domain-specific knowledge (xlsx, frontend-design, etc.) |
| [harness-filesystem](samples/harness-filesystem/) | Session storage (`sessionStoragePath`) behavior — per-session isolation and cross-session limitations |

## Prerequisites

- AWS CLI v2.34+
- [AgentCore CLI](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/cli-install.html) installed
- AWS credentials configured with sufficient permissions for Bedrock AgentCore
- Node.js 18+ (for CDK deployment)

## Getting Started

Each sample is self-contained under `samples/`. Navigate to a sample directory and follow its README.

```bash
cd samples/harness-memory
cat README.md
```

## License

This project is licensed under the MIT License.
