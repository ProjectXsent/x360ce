# Installing n8n MCP Server

The [n8n-mcp](https://github.com/czlonkowski/n8n-mcp) server (by czlonkowski) connects AI agents to a running [n8n](https://n8n.io/) workflow automation instance. It exposes documentation lookups (node and template search) plus full workflow CRUD — list, create, update, delete, validate, execute — against the n8n REST API.

Unlike the other MCP servers in this skill, n8n-mcp is **not installed to `%LOCALAPPDATA%\mcp-servers\`**. It runs on demand via `npx -y n8n-mcp`, and the install script only pre-warms the npx cache and verifies environment variables.

## Prerequisites

- Node.js LTS and npm on PATH
- A running n8n instance reachable from this machine (self-hosted or Docker)
- An n8n API key with full scope
  - In n8n: **Settings → n8n API → Create an API key**
  - Store it in the `N8N_API_KEY` user environment variable

### Setting environment variables

```powershell
# n8n base URL (adjust if not running on localhost:5678)
[Environment]::SetEnvironmentVariable('N8N_API_URL', 'http://127.0.0.1:5678', 'User')

# n8n API key (full scope)
[Environment]::SetEnvironmentVariable('N8N_API_KEY', '<your-token>', 'User')
```

After setting these, **restart all VS Code instances** so the integrated terminal and MCP host pick up the new environment.

## Installation

```powershell
# Defaults (expects n8n at http://127.0.0.1:5678)
.\.ai\skills\ai-agent-onboarding\scripts\install-n8n-mcp.ps1

# Custom URL and probe /healthz to verify n8n is reachable
.\.ai\skills\ai-agent-onboarding\scripts\install-n8n-mcp.ps1 -N8nUrl http://localhost:5678 -Probe
```

The script:

1. Verifies Node.js and npm are on PATH.
2. Removes any corrupt `npx` cache entries that contain a partial `n8n-mcp` package (no `package.json`, no bin shim). See **Troubleshooting** below for why this matters.
3. Pre-warms the npx cache by invoking `npx -y n8n-mcp` once with stdin closed, so first launch under the MCP host does not require a TTY.
4. Sets `N8N_API_URL` (User scope) if unset. Prompts for `N8N_API_KEY` if missing.
5. Optionally probes `{N8nUrl}/healthz` when `-Probe` is supplied.

The script is idempotent — safe to run again.

## MCP Configuration

The naming convention for this server is `n8n-mcp` (single canonical name — it is not parameterized per-org or per-database).

### RooCode / Cline (`mcp_settings.json`)

```json
{
  "mcpServers": {
    "n8n-mcp": {
      "_comment": "n8n-mcp server (czlonkowski). 7 documentation tools and 14 workflow-management tools.",
      "_source": "https://github.com/czlonkowski/n8n-mcp",
      "command": "npx",
      "args": ["-y", "n8n-mcp"],
      "env": {
        "MCP_MODE": "stdio",
        "LOG_LEVEL": "error",
        "DISABLE_CONSOLE_OUTPUT": "true",
        "WEBHOOK_SECURITY_MODE": "moderate",
        "N8N_MCP_TELEMETRY_DISABLED": "true",
        "N8N_API_URL": "${env:N8N_API_URL}",
        "N8N_API_KEY": "${env:N8N_API_KEY}"
      },
      "disabled": false,
      "alwaysAllow": [
        "n8n_list_workflows",
        "tools_documentation",
        "get_template",
        "search_nodes",
        "get_node",
        "validate_node",
        "search_templates",
        "validate_workflow",
        "n8n_health_check"
      ]
    }
  }
}
```

### Claude Code (`.claude.json`)

Same structure as above. The `-y` flag on `npx` is **required** — without it, `npx` prompts for interactive confirmation before installing, and MCP hosts launch servers with no TTY, which causes a silent zero-exit failure.

### Key configuration fields

| Field | Purpose |
|-------|---------|
| `args: ["-y", "n8n-mcp"]` | `-y` auto-accepts the npx install prompt (required for non-TTY launch). |
| `MCP_MODE` | `stdio` — required for local MCP hosts. |
| `LOG_LEVEL` | `error` keeps the server quiet on stderr. |
| `DISABLE_CONSOLE_OUTPUT` | `true` — prevents stray stdout that would corrupt JSON-RPC framing. |
| `WEBHOOK_SECURITY_MODE` | `moderate` is the recommended default; `strict` blocks more workflow patterns. |
| `N8N_API_URL` | Base URL of the n8n instance (e.g. `http://127.0.0.1:5678`). |
| `N8N_API_KEY` | n8n API token. Keep in a user env var, not the config file. |
| `alwaysAllow` | Safe read-only tools pre-approved. Add `n8n_update_partial_workflow` etc. after you trust the agent. |

## Available Tools

The server exposes two groups:

### Documentation tools (7 — work even without n8n running)

| Tool | Purpose |
|------|---------|
| `tools_documentation` | Index of all available MCP tools |
| `search_nodes` | Search n8n node catalogue by keyword |
| `get_node` | Full schema for one node |
| `validate_node` | Validate a node configuration |
| `search_templates` | Search community workflow templates |
| `get_template` | Fetch a template workflow JSON |
| `validate_workflow` | Validate a complete workflow JSON |

### Management tools (14 — require N8N_API_URL + N8N_API_KEY)

| Tool | Purpose |
|------|---------|
| `n8n_health_check` | Probe instance health |
| `n8n_list_workflows` | Paginated workflow listing |
| `n8n_get_workflow` | Read one workflow |
| `n8n_create_workflow` | Create a workflow |
| `n8n_update_full_workflow` | Replace a workflow (PUT) |
| `n8n_update_partial_workflow` | Targeted edits to one workflow |
| `n8n_delete_workflow` | Delete a workflow |
| `n8n_workflow_versions` | List version history |
| `n8n_generate_workflow` | Let the server compose a workflow |
| `n8n_validate_workflow` | Validate a workflow in the instance |
| `n8n_autofix_workflow` | Auto-repair common validation errors |
| `n8n_test_workflow` | Execute a workflow for testing |
| `n8n_executions` | Query execution history |
| `n8n_deploy_template` | Install a template into the instance |
| `n8n_manage_credentials` | CRUD on credential records |
| `n8n_manage_datatable` | CRUD on n8n data tables |
| `n8n_audit_instance` | Security/config audit |

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| MCP host reports zero tools and no error | Corrupt npx cache folder with partial package (`n8n-mcp/dist` but no `package.json` / bin shim). `npx n8n-mcp` silently exits 0 with `'n8n-mcp' is not recognized`. | Re-run `install-n8n-mcp.ps1` — it auto-deletes the bad cache. Or manually delete the hash folder under `%LOCALAPPDATA%\npm-cache\_npx\` that contains `node_modules\n8n-mcp\` without `package.json`. |
| `npx n8n-mcp` prompts for confirmation and fails | Cold cache + no TTY. MCP hosts spawn servers with no TTY, so the prompt never gets answered. | Use `"args": ["-y", "n8n-mcp"]` in the MCP config — `-y` auto-accepts. |
| `401 Unauthorized` on management tools | `N8N_API_KEY` missing, wrong, or expired. | Rotate the key in n8n **Settings → n8n API**, update the user env var, restart VS Code. |
| `ECONNREFUSED` or health probe fails | n8n not running or `N8N_API_URL` points to the wrong host/port. | Start n8n first. Verify `curl $N8N_API_URL/healthz` works from the same shell that spawns VS Code. |
| Documentation tools work but management tools don't | `N8N_API_URL` / `N8N_API_KEY` not visible to the MCP host. | Set them as **User** environment variables (not session-only), then restart VS Code fully (Reload Window is not enough). |
| Tools appear but JSON-RPC errors flood the log | Some other env var adds chatty stdout. | Keep `DISABLE_CONSOLE_OUTPUT=true` and `LOG_LEVEL=error` in the MCP config. |

## Naming Convention

Unlike `sql-{env}-{db}` or `github-{user}`, there is one canonical name: **`n8n-mcp`**. A given machine typically talks to a single n8n instance, and the env-var-driven `N8N_API_URL` / `N8N_API_KEY` are enough to point it anywhere. If you need multiple instances, create suffixed entries and use suffixed env vars:

```json
"n8n-mcp-home": {
  "command": "npx", "args": ["-y", "n8n-mcp"],
  "env": { "N8N_API_URL": "${env:N8N_API_URL_HOME}", "N8N_API_KEY": "${env:N8N_API_KEY_HOME}", "MCP_MODE": "stdio" }
},
"n8n-mcp-work": {
  "command": "npx", "args": ["-y", "n8n-mcp"],
  "env": { "N8N_API_URL": "${env:N8N_API_URL_WORK}", "N8N_API_KEY": "${env:N8N_API_KEY_WORK}", "MCP_MODE": "stdio" }
}
```

## Security Notes

- The API key grants full control of the n8n instance — treat it like a root credential. Store it only in user env vars, never in the MCP config file itself.
- `alwaysAllow` pre-approves tools so the agent can call them without asking. The default list in the config above only includes read/validate tools. Add write tools (`n8n_update_partial_workflow`, `n8n_create_workflow`, `n8n_delete_workflow`, `n8n_manage_credentials`) only after you trust the agent and the workflow-level blast radius.
- The server respects `WEBHOOK_SECURITY_MODE`. `moderate` is the recommended balance; `strict` rejects more patterns.
- For multi-user n8n instances, create a dedicated API key scoped to the minimum projects the agent needs to touch.
