# Installing GitHub MCP Server

The official [GitHub MCP server](https://github.com/github/github-mcp-server) gives AI agents access to GitHub repositories, issues, pull requests, and more.

The recommended approach is the **pre-built binary** from official GitHub Releases — a single `.exe`, no Docker, no Go SDK, uses stdio transport (same as SQL MCP and other local MCP servers).

## Prerequisites

- A GitHub Personal Access Token (PAT)
  - Classic token: [github.com/settings/tokens](https://github.com/settings/tokens) — select `repo` scope
  - Fine-grained token: [github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens/new) — grant repository access as needed
- The token stored in the `GITHUB_PERSONAL_ACCESS_TOKEN` environment variable (user or system level)

### Setting the environment variable

```powershell
# Set as a persistent user-level environment variable
[Environment]::SetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', '<your-token>', 'User')
```

After setting the variable, **restart all VS Code instances** so the updated environment is picked up.

## Installation

The bundled script downloads the latest official binary from [github/github-mcp-server releases](https://github.com/github/github-mcp-server/releases) and extracts it to `%LOCALAPPDATA%\mcp-servers\github-mcp-server\`.

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-github-mcp.ps1
```

The script:
- Fetches the latest release tag from the GitHub API
- Downloads the correct Windows zip for your architecture (x86_64 or arm64)
- Extracts to `%LOCALAPPDATA%\mcp-servers\github-mcp-server\`
- Verifies the binary runs (`--version` check)

The script is idempotent — safe to run again to update to a newer version.

## MCP Configuration

The naming convention is `github-{user}` (e.g., `github-EJocys`, `github-octocat`).

### RooCode / Cline (`mcp_settings.json`)

```json
{
  "mcpServers": {
    "github-YourUser": {
      "_comment": "Official GitHub MCP server (pre-built binary from github/github-mcp-server releases).",
      "_source": "https://github.com/github/github-mcp-server",
      "type": "stdio",
      "command": "${env:LOCALAPPDATA}\\mcp-servers\\github-mcp-server\\github-mcp-server.exe",
      "args": ["stdio"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${env:GITHUB_PERSONAL_ACCESS_TOKEN}"
      },
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
```

### Claude Code (`.mcp.json`)

```json
{
  "mcpServers": {
    "github-YourUser": {
      "command": "${env:LOCALAPPDATA}\\mcp-servers\\github-mcp-server\\github-mcp-server.exe",
      "args": ["stdio"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${env:GITHUB_PERSONAL_ACCESS_TOKEN}"
      }
    }
  }
}
```

### VS Code native MCP (settings.json)

VS Code 1.101+ also supports the hosted remote server at `https://api.githubcopilot.com/mcp/` (uses Streamable HTTP transport). This works natively in VS Code but is **not compatible with RooCode/Cline** (which use SSE transport). Use the local binary for RooCode/Cline.

## Available Tools

The GitHub MCP server exposes tools across several toolsets:

| Toolset | Examples |
|---------|----------|
| **repos** | `get_file_contents`, `search_repositories`, `list_branches` |
| **issues** | `list_issues`, `create_issue`, `add_issue_comment` |
| **pull_requests** | `list_pull_requests`, `create_pull_request`, `merge_pull_request` |
| **code_search** | `search_code` |
| **users** | `get_me` |

Full tool list: [github.com/github/github-mcp-server#tools](https://github.com/github/github-mcp-server#tools)

## Read-Only Mode

To restrict the agent to read-only operations:

```json
"env": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${env:GITHUB_PERSONAL_ACCESS_TOKEN}",
    "GITHUB_READ_ONLY": "1"
}
```

Alternatively, use a fine-grained PAT with read-only permissions.

## Naming Convention

Use the pattern `github-{user}` for MCP server names:

- `github-EJocys` — Evaldas's GitHub access
- `github-octocat` — octocat's GitHub access

This keeps names predictable when multiple GitHub accounts are configured.

## Alternative Methods

### Docker

If Docker Desktop is available, the official container image works without downloading a binary:

```json
{
  "github-YourUser": {
    "command": "docker",
    "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN", "ghcr.io/github/github-mcp-server"],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "${env:GITHUB_PERSONAL_ACCESS_TOKEN}"
    }
  }
}
```

### Build from source

Requires Go SDK. Clone the repo and run `go build -o github-mcp-server.exe ./cmd/github-mcp-server`.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| 401 Unauthorized | PAT missing, expired, or wrong | Verify `$env:GITHUB_PERSONAL_ACCESS_TOKEN` is set and valid |
| Binary not found | Install script not run | Run `install-github-mcp.ps1` |
| SSE error / 400 Bad Request | Using hosted URL with RooCode | RooCode doesn't support Streamable HTTP; use the local binary with stdio |
| No tools appear | Server disabled or config syntax error | Verify `"disabled": false` and valid JSON |
| Rate limited | Too many API calls | Wait for rate limit reset; use a PAT with higher limits |
