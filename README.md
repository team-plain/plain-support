# Plain Support Skill for Claude Code

A [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code) that gives Claude direct access to the [Plain](https://plain.com) customer support platform via its GraphQL API.

With this skill, Claude can read customers, threads, conversations, help center articles, and more — directly from your terminal.

## What can it do?

| Resource | Read | Write |
|----------|------|-------|
| **Customers** | List, get, search by name/email/external ID | - |
| **Threads** | List, get, search, read full timeline | Add internal notes |
| **Help Center** | List centers, articles, groups | Create/update articles and groups |
| **Companies** | List, get | - |
| **Tenants** | List, get | - |
| **Labels** | List | - |
| **Tiers & SLAs** | List, get with SLA configs | - |
| **Workspace** | Get info | - |

### Example use cases

- "What are the open support threads for customer john@example.com?"
- "Read the full conversation on thread th_01ABC and summarize it"
- "Add a note to thread th_01ABC with my investigation findings"
- "Create a help center article about how to reset passwords"
- "Which customers are in the Enterprise tier?"

## Setup

### 1. Install the skill

Clone this repo into your project (or anywhere you use Claude Code):

```bash
# Option A: Clone into your project's .claude/skills directory
git clone git@github.com:team-plain/plain-support.git .claude/skills/plain-support

# Option B: Clone to a shared location and symlink
git clone git@github.com:team-plain/plain-support.git ~/plain-support
ln -s ~/plain-support/.claude/skills/plain-support .claude/skills/plain-support
```

### 2. Set your API key

Get an API key from your [Plain workspace settings](https://app.plain.com) and set it as an environment variable:

```bash
export PLAIN_API_KEY="plainApiKey_..."
```

Add it to your shell profile (`.bashrc`, `.zshrc`, etc.) to persist across sessions.

### 3. Dependencies

The skill requires `curl` and `jq`, which are available on most systems:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# curl is pre-installed on most systems
```

## Usage

Once installed, invoke the skill in Claude Code:

```
/plain-support
```

Claude will then have access to all Plain API commands. You can ask questions naturally:

- "List my open threads"
- "Find the customer with email support@acme.com"
- "Show me the timeline for thread th_01H..."
- "Create a draft article about our refund policy"

## Configuration

| Environment Variable | Required | Description |
|---------------------|----------|-------------|
| `PLAIN_API_KEY` | Yes | Your Plain API key |
| `PLAIN_API_URL` | No | Custom API endpoint (default: `https://core-api.uk.plain.com/graphql/v1`) |

## API Reference

For detailed documentation on all Plain entities (customers, threads, timeline entries, etc.), see [references/ENTITIES.md](.claude/skills/plain-support/references/ENTITIES.md).

## License

MIT
