# Installing Azure DevOps MCP Server

The official [Azure DevOps MCP server](https://github.com/microsoft/azure-devops-mcp) (`@azure-devops/mcp` by Microsoft) gives AI agents access to Azure DevOps work items, repositories, iterations, pull requests, and more.

The bundled install script applies **two patches** required for self-hosted Azure DevOps Server:

1. **URL patch** — lets `ADO_MCP_ORG_URL` override the hardcoded `https://dev.azure.com/{org}` base URL.
2. **PAT-as-Basic-auth patch** — in `envvar` auth mode, the stock package wraps the PAT in an HTTP `Bearer` header, which Azure DevOps **Server** rejects as anonymous (`TF400813`). The patch switches `envvar` mode to `getPersonalAccessTokenHandler` (HTTP Basic). Cloud `dev.azure.com` accepts both, so the patch is safe for both cloud and self-hosted.

Cloud-only users do not strictly need the patches, but running the install script is still the recommended setup.

## Prerequisites

- Node.js LTS (`node` and `npm` on PATH)
- A Personal Access Token (PAT) for each Azure DevOps organization
  - Cloud: [dev.azure.com/{org}/_usersSettings/tokens](https://dev.azure.com/_usersSettings/tokens)
  - Self-hosted: `https://{your-server}/{collection}/_usersSettings/tokens`

## Installation

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-azure-devops-mcp.ps1
```

Installs to `%LOCALAPPDATA%\mcp-servers\azure-devops-mcp\` and patches for self-hosted URL support. Idempotent — safe to run again to update.

## Environment Variables

Set these as persistent user-level environment variables.

### Default (single org / primary org)

The unsuffixed names are the default and are compatible with common instructions found on the internet:

```powershell
# Required
[Environment]::SetEnvironmentVariable('AZDO_ORG', 'YourOrg', 'User')
[Environment]::SetEnvironmentVariable('AZDO_PAT', '<your-pat>', 'User')

# Only for self-hosted Azure DevOps Server (omit for dev.azure.com)
[Environment]::SetEnvironmentVariable('AZDO_URL', 'https://your-server.com', 'User')
```

### Non-default (additional orgs)

For additional organizations, add a suffix `_{OrgOrUser}` to each variable. The suffix should match the org name or a short identifier:

```powershell
# Additional org: JocysCom (self-hosted)
[Environment]::SetEnvironmentVariable('AZDO_ORG_JocysCom', 'JocysCom', 'User')
[Environment]::SetEnvironmentVariable('AZDO_PAT_JocysCom', '<pat>', 'User')
[Environment]::SetEnvironmentVariable('AZDO_URL_JocysCom', 'https://devops.jocys.com', 'User')

# Additional org: Contoso (cloud — no AZDO_URL needed)
[Environment]::SetEnvironmentVariable('AZDO_ORG_Contoso', 'Contoso', 'User')
[Environment]::SetEnvironmentVariable('AZDO_PAT_Contoso', '<pat>', 'User')
```

### Summary

| Variable | Default (primary) | Non-default (additional) |
|----------|-------------------|--------------------------|
| Organization | `AZDO_ORG` | `AZDO_ORG_{Suffix}` |
| PAT | `AZDO_PAT` | `AZDO_PAT_{Suffix}` |
| Server URL | `AZDO_URL` | `AZDO_URL_{Suffix}` |

After setting variables, **restart all VS Code instances**.

## MCP Configuration

### Single organization

The naming convention is `azure-devops` for a single org, or `azure-devops-{org}` for multiple.

```json
{
  "mcpServers": {
    "azure-devops": {
      "_comment": "Azure DevOps MCP server (@azure-devops/mcp, patched for self-hosted URL support).",
      "_source": "https://github.com/microsoft/azure-devops-mcp",
      "type": "stdio",
      "command": "node",
      "args": [
        "${env:LOCALAPPDATA}\\mcp-servers\\azure-devops-mcp\\node_modules\\@azure-devops\\mcp\\dist\\index.js",
        "${env:AZDO_ORG}",
        "--authentication", "envvar",
        "-d", "core", "work", "work-items"
      ],
      "env": {
        "ADO_MCP_AUTH_TOKEN": "${env:AZDO_PAT}",
        "ADO_MCP_ORG_URL": "${env:AZDO_URL}/${env:AZDO_ORG}"
      },
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
```

### Multiple organizations

Each MCP entry spawns its own process with its own `env` block. Use the `azure-devops-{org}` naming convention and per-org env vars:

```json
{
  "mcpServers": {
    "azure-devops-JocysCom": {
      "_comment": "Self-hosted Azure DevOps Server.",
      "_source": "https://github.com/microsoft/azure-devops-mcp",
      "type": "stdio",
      "command": "node",
      "args": [
        "${env:LOCALAPPDATA}\\mcp-servers\\azure-devops-mcp\\node_modules\\@azure-devops\\mcp\\dist\\index.js",
        "${env:AZDO_ORG_JocysCom}",
        "--authentication", "envvar",
        "-d", "core", "work", "work-items"
      ],
      "env": {
        "ADO_MCP_AUTH_TOKEN": "${env:AZDO_PAT_JocysCom}",
        "ADO_MCP_ORG_URL": "${env:AZDO_URL_JocysCom}/${env:AZDO_ORG_JocysCom}"
      },
      "disabled": false,
      "alwaysAllow": []
    },
    "azure-devops-Contoso": {
      "_comment": "Cloud Azure DevOps (dev.azure.com). No ADO_MCP_ORG_URL needed.",
      "_source": "https://github.com/microsoft/azure-devops-mcp",
      "type": "stdio",
      "command": "node",
      "args": [
        "${env:LOCALAPPDATA}\\mcp-servers\\azure-devops-mcp\\node_modules\\@azure-devops\\mcp\\dist\\index.js",
        "${env:AZDO_ORG_Contoso}",
        "--authentication", "envvar",
        "-d", "core", "work", "work-items"
      ],
      "env": {
        "ADO_MCP_AUTH_TOKEN": "${env:AZDO_PAT_Contoso}"
      },
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
```

**Key points:**

- Default (primary) org uses unsuffixed env vars: `AZDO_ORG`, `AZDO_PAT`, `AZDO_URL`
- Additional orgs use suffixed env vars: `AZDO_ORG_{Suffix}`, `AZDO_PAT_{Suffix}`, `AZDO_URL_{Suffix}`
- Each MCP entry has its own `env` block — different PATs, different URLs per process
- `ADO_MCP_ORG_URL` is **only needed for self-hosted** servers. Omit it for cloud `dev.azure.com` and the default URL is used
- The org name in `args` must match the actual Azure DevOps org/collection name

### Claude Code (`.mcp.json`)

```json
{
  "mcpServers": {
    "azure-devops": {
      "command": "node",
      "args": [
        "${env:LOCALAPPDATA}\\mcp-servers\\azure-devops-mcp\\node_modules\\@azure-devops\\mcp\\dist\\index.js",
        "YourOrg",
        "--authentication", "envvar",
        "-d", "core", "work", "work-items"
      ],
      "env": {
        "ADO_MCP_AUTH_TOKEN": "${env:AZDO_PAT}",
        "ADO_MCP_ORG_URL": "${env:AZDO_URL}/${env:AZDO_ORG}"
      }
    }
  }
}
```

## Available Domains

The `-d` flag controls which tool domains are loaded:

| Domain | Description |
|--------|-------------|
| `core` | Projects, teams, processes (always recommended) |
| `work` | Iterations, team settings, capacity |
| `work-items` | Work items CRUD, queries, batch operations |
| `repositories` | Repos, pull requests, branches, commits |
| `pipelines` | Build/release pipelines |
| `search` | Code and work item search |
| `test-plans` | Test plans, suites, cases |
| `wiki` | Wiki pages |
| `advanced-security` | Security alerts |

Use `-d all` to load everything, or list specific domains to reduce tool count.

## Authentication Methods

| Method | Flag | Description |
|--------|------|-------------|
| `envvar` | `--authentication envvar` | Reads PAT from `ADO_MCP_AUTH_TOKEN` env var. **Recommended for MCP.** |
| `interactive` | `--authentication interactive` | Opens browser for Azure AD login. Default on Windows. |
| `azcli` | `--authentication azcli` | Uses Azure CLI credentials (`az login`). |
| `env` | `--authentication env` | Uses `DefaultAzureCredential` from `@azure/identity`. |

For MCP servers, always use `envvar` — interactive auth doesn't work in headless stdio mode.

## Read-Only Configuration

To restrict write operations, use `disabledTools` in the MCP config:

```json
"disabledTools": [
    "build_run_build",
    "repo_create_pull_request",
    "repo_reply_to_comment",
    "repo_resolve_comment",
    "repo_update_pull_request_status",
    "testplan_add_test_cases_to_suite",
    "testplan_create_test_case",
    "testplan_create_test_plan",
    "wit_add_child_work_item",
    "wit_add_work_item_comment",
    "wit_close_and_link_workitem_duplicates",
    "wit_create_work_item",
    "wit_link_work_item_to_pull_request",
    "wit_update_work_item",
    "wit_update_work_items_batch",
    "wit_work_items_link",
    "work_assign_iterations",
    "work_create_iterations"
]
```

## Naming Convention

| Scenario | Name |
|----------|------|
| Single org | `azure-devops` |
| Multiple orgs | `azure-devops-{org}` (e.g., `azure-devops-JocysCom`, `azure-devops-Contoso`) |

## About the Self-Hosted Patches

The official `@azure-devops/mcp` package (as of v2.5.0) has two issues for self-hosted Azure DevOps Server. The install script patches both in `dist/index.js`.

### Patch 1 — Self-hosted URL support

The package hardcodes `https://dev.azure.com/{org}` as the base URL:

```diff
- const orgUrl = "https://dev.azure.com/" + orgName;
+ const orgUrl = process.env.ADO_MCP_ORG_URL || ("https://dev.azure.com/" + orgName);
```

- If `ADO_MCP_ORG_URL` is set → uses that URL (self-hosted)
- If not set → original `dev.azure.com` behavior (cloud)

### Patch 2 — PAT must use HTTP Basic auth

In `envvar` mode the package reads a PAT from `ADO_MCP_AUTH_TOKEN` but then wraps it in a Bearer header via `getBearerHandler`. Azure DevOps **Server** rejects this and returns:

```
TF400813: Resource not available for anonymous access. Client authentication required.
```

PATs must be sent as HTTP **Basic** auth. Fix:

```diff
- import { getBearerHandler, WebApi } from "azure-devops-node-api";
+ import { getBearerHandler, getPersonalAccessTokenHandler, WebApi } from "azure-devops-node-api";

  ...
  const accessToken = await getAzureDevOpsToken();
- const authHandler = getBearerHandler(accessToken);
+ const authHandler = argv.authentication === "envvar"
+     ? getPersonalAccessTokenHandler(accessToken)
+     : getBearerHandler(accessToken);
```

This only affects `envvar` mode (`interactive`, `azcli`, `env` still use Bearer, which is correct for AAD tokens). Cloud `dev.azure.com` accepts PATs via both Basic and Bearer, so the patch is safe for cloud users too.

### Re-patching after updates

When updating the package (`npm install @azure-devops/mcp@latest`), re-run `install-azure-devops-mcp.ps1` to reapply both patches. The script is idempotent and detects already-patched content.

### Harmless noise: tenant-lookup warning

On startup the patched server logs:

```
Failed to fetch tenant for ADO org {name}: x-vss-resourcetenant header not found in response
```

This is [org-tenants.js](https://github.com/microsoft/azure-devops-mcp) trying to reach Microsoft cloud (`vssps.dev.azure.com`) to resolve a tenant ID. Self-hosted Azure DevOps Server doesn't expose that header. The function returns `undefined`, and since `envvar` auth doesn't use the tenant ID, tool calls still succeed. Safe to ignore.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `ADO_MCP_AUTH_TOKEN is not set or empty` | PAT env var not passed | Verify `AZDO_PAT` is set; restart VS Code after setting env vars |
| 401/403 Unauthorized | PAT expired or wrong scope | Regenerate PAT; ensure it has the required scopes for the domains you're using |
| `The Personal Access Token used has expired` | PAT expired | Generate a new PAT and update the env var |
| Connection refused | Wrong URL or server down | Verify `AZDO_URL` is correct; check server is accessible |
| `TF400813: Resource not available for anonymous access` on self-hosted | PAT-as-Basic-auth patch missing (envvar mode wraps PAT as Bearer) | Re-run `install-azure-devops-mcp.ps1` to reapply Patch 2 |
| Patch not applied / self-hosted not working | Package was updated without re-patching | Re-run `install-azure-devops-mcp.ps1` |
| `Failed to fetch tenant for ADO org ... x-vss-resourcetenant header not found` | Self-hosted server doesn't emit Microsoft-cloud tenant header | Harmless — safe to ignore with `envvar` auth |
| Too many tools | All domains loaded | Use `-d core work work-items` instead of `-d all` |
