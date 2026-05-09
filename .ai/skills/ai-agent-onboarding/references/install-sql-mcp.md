# Installing SQL Server MCP (MssqlMcp)

MssqlMcp is a read-only SQL Server MCP server from the [Azure-Samples/SQL-AI-samples](https://github.com/Azure-Samples/SQL-AI-samples/tree/main/MssqlMcp) repository. It gives AI agents safe, structured access to SQL Server databases — listing tables, describing schemas, and reading data — without allowing arbitrary SQL execution.

## Prerequisites

- .NET 8 SDK (`dotnet` on PATH)
- Git for Windows (`git` on PATH)
- SQL Server instance accessible via Windows Authentication or connection string

## Installation

The bundled script clones the Azure-Samples repository, builds MssqlMcp, and copies the published output to one of three locations:

| Target | Path | Use case |
|--------|------|----------|
| **Global** | `%LOCALAPPDATA%\mcp-servers\MssqlMcp\` | Per-user, shared across all projects |
| **Project** | `{repo}\.ai\MCP\MssqlMcp\` | Committed to git, shared with team |
| **ProjectLocal** | `{repo}\.ai\MCP\MssqlMcp\.bin\` | Git-ignored, machine-local |

### Run the install script

```powershell
# Interactive — prompts for install location
.\.ai\skills\ai-agent-onboarding\scripts\install-sql-mcp.ps1

# Non-interactive
.\.ai\skills\ai-agent-onboarding\scripts\install-sql-mcp.ps1 -Target Global
```

The script is idempotent — safe to run again to update to a newer version.

## MCP Configuration

After installation, register the MCP server in your agent's MCP settings. The naming convention is `sql-{environment}-{database}` (e.g., `sql-dev-n8n`, `sql-local-MyApp`).

### Example: RooCode / Cline (`mcp_settings.json`)

```json
{
  "mcpServers": {
    "sql-dev-MyDatabase": {
      "_comment": "Read-only SQL Server MCP (Azure-Samples MssqlMcp). Prefer this for schema/data inspection and validation.",
      "_source": "https://github.com/Azure-Samples/SQL-AI-samples/tree/main/MssqlMcp",
      "type": "stdio",
      "command": "dotnet",
      "args": [
        "${env:LOCALAPPDATA}\\mcp-servers\\MssqlMcp\\MssqlMcp.dll"
      ],
      "disabled": false,
      "env": {
        "CONNECTION_STRING": "Server=localhost;Database=MyDatabase;Trusted_Connection=True;TrustServerCertificate=True;ApplicationIntent=ReadOnly;",
        "READONLY": "true"
      },
      "alwaysAllow": [
        "ListTables",
        "DescribeTable",
        "ReadData"
      ]
    }
  }
}
```

### Example: Claude Code (`claude_desktop_config.json` / `.mcp.json`)

```json
{
  "mcpServers": {
    "sql-dev-MyDatabase": {
      "command": "dotnet",
      "args": [
        "${env:LOCALAPPDATA}\\mcp-servers\\MssqlMcp\\MssqlMcp.dll"
      ],
      "env": {
        "CONNECTION_STRING": "Server=localhost;Database=MyDatabase;Trusted_Connection=True;TrustServerCertificate=True;ApplicationIntent=ReadOnly;",
        "READONLY": "true"
      }
    }
  }
}
```

### Key configuration fields

| Field | Purpose |
|-------|---------|
| `CONNECTION_STRING` | Standard SQL Server connection string. Use `Trusted_Connection=True` for Windows Auth or add `User ID=...;Password=...` for SQL Auth. |
| `READONLY` | Set to `"true"` to restrict MssqlMcp to read-only operations. |
| `ApplicationIntent=ReadOnly` | SQL Server hint to route to read-only replicas if available. |
| `alwaysAllow` | Tools to auto-approve: `ListTables`, `DescribeTable`, `ReadData`. |

### DLL path by install target

| Target | DLL path in `args` |
|--------|---------------------|
| Global | `${env:LOCALAPPDATA}\\mcp-servers\\MssqlMcp\\MssqlMcp.dll` |
| Project | `.ai\\MCP\\MssqlMcp\\MssqlMcp.dll` (relative to repo root) |
| ProjectLocal | `.ai\\MCP\\MssqlMcp\\.bin\\MssqlMcp.dll` (relative to repo root) |

## Available MCP Tools

| Tool | Description |
|------|-------------|
| `ListTables` | Lists all tables in the connected database |
| `DescribeTable` | Shows column names, types, and constraints for a table |
| `ReadData` | Reads rows from a table (with optional filtering) |

## Naming Convention

Use the pattern `sql-{environment}-{database}` for MCP server names:

- `sql-dev-n8n` — local dev SQL Server, n8n database
- `sql-ci-MyApp` — CI environment SQL Server, MyApp database
- `sql-local-AdventureWorks` — localhost, AdventureWorks database

This keeps names predictable when multiple databases or environments are configured.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `dotnet` not found | .NET SDK not on PATH | Install .NET 8 SDK: `winget install Microsoft.DotNet.SDK.8` |
| Build fails | Missing SDK or wrong version | Ensure `dotnet --version` shows 8.x |
| Connection refused | SQL Server not running or wrong server name | Check SQL Server is running, verify `Server=` in connection string |
| Access denied | Windows Auth doesn't work for this user | Add the user to the database or switch to SQL Auth in the connection string |
| MssqlMcp.dll not found | Install script not run or wrong target | Re-run `install-sql-mcp.ps1` and note the install path |

## Security Notes

- Always set `READONLY=true` unless you have a specific need for write access.
- Use `ApplicationIntent=ReadOnly` to route to read-only replicas where available.
- The `alwaysAllow` list controls which tools the agent can use without asking permission. Start with `ListTables` and `DescribeTable` only; add `ReadData` after verifying the database contains no sensitive data the agent shouldn't access.
- Connection strings with passwords should use environment variables, not hardcoded values.
