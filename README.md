# Plain Support Plugin for Agents

A [Cursor]() and [Claude Code plugin](https://code.claude.com/docs/en/plugins) that gives your agents direct access to the [Plain](https://plain.com) customer support platform via its GraphQL API.

With this plugin, your agent can read customers, threads, conversations, help center articles, and more - directly from your terminal.

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

## Installation

### Option 1: Install via npx skills

```bash
npx skills add team-plain/plain-support
```

### Option 2: Install as a Claude Code plugin

```bash
# Try it locally first
claude --plugin-dir /path/to/plain-support

# Or install from a marketplace that includes this plugin
/plugin install plain-support@marketplace-name
```

### Option 3: Clone manually

```bash
git clone git@github.com:team-plain/plain-support.git
claude --plugin-dir ./plain-support
```

## Prerequisites

### API key

In Plain, go to **Settings > Machine users & API Keys** to create an API key. Then set it as an environment variable:

```bash
export PLAIN_API_KEY="plainApiKey_..."
```

Add it to your shell profile (`.bashrc`, `.zshrc`, etc.) to persist across sessions.

### Dependencies

The plugin requires `curl` and `jq`:

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

## License

MIT
