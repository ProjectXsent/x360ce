---
name: vscode-mcp-bridge
description: Bridge VS Code extension-provided MCP servers (e.g. ms-azuretools.vscode-azure-mcp-server/azmcp.exe) into Roo/Cline by discovering available VS Code MCP servers, extracting their stdio/SSE launch details, and registering them into Roo’s MCP config (mcp_settings.json). Use when a user asks to list VS Code-native MCP servers, register one or more of them for Roo, or troubleshoot why an extension MCP works for Copilot but not for Roo.
---

# VS Code MCP Bridge (Copilot  Roo)

## Goal

Make MCP servers that are available to **VS Code/Copilot** also available to **Roo** by:

1. Discovering which MCP servers VS Code can start.
2. Mapping each server to a runnable `stdio`/`sse` server definition.
3. Registering selected servers into Roo’s MCP settings.
4. Verifying by calling the corresponding MCP tool(s).

## Key constraint (must remember)

VS Code extensions often expose MCP servers via the **VS Code extension host**. That means the extension entrypoint (often JavaScript like `main.js`) may require `vscode` and **cannot be started as a standalone process**.

Instead, look for the **actual MCP server binary/script** the extension starts (e.g. Azure MCP ships `azmcp.exe`). Roo must run that binary/script directly.

### Common pitfall

- WRONG: register an extension entrypoint (e.g. `...\main.js`) as a stdio MCP server.
  - Symptom: `Cannot find module 'vscode'`.
- RIGHT: register the real server binary/script the extension host starts.

## Step 0  Gather local facts (PowerShell)

### 0.1 Confirm VS Code CLI is available

```powershell
code --version
```

If `code` is not found, VS Code may be installed per-user and not on PATH.

### 0.2 Find where VS Code is installed (user vs machine)

```powershell
(Get-Command code -ErrorAction SilentlyContinue).Source
```

If that returns nothing, check common install locations:

```powershell
Test-Path "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\bin\code.cmd"
Test-Path "${env:ProgramFiles}\Microsoft VS Code\bin\code.cmd"
Test-Path "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.cmd"
```

### 0.3 Confirm the target extension is installed

```powershell
code --list-extensions --show-versions | Select-String -Pattern "mcp|azure|copilot" -CaseSensitive:$false
```

## Step 1  List MCP servers available to VS Code

There are two practical discovery routes:

### Route A (preferred): inspect installed extensions that contribute MCP server definitions

1. Locate extension install folder:

```powershell
$extId = "ms-azuretools.vscode-azure-mcp-server"
$extPath = code --locate-extension $extId
$extPath
```

2. Read the extension manifest:

```powershell
Get-Content (Join-Path $extPath "package.json")
```

3. Look for contributions related to MCP:

- `contributes.mcpServerDefinitionProviders`
- `contributes.configuration` keys mentioning MCP

If the extension uses a provider, it often *generates* definitions at runtime. Then proceed to Route B.

### Route B: open VS Code UI and list servers

Use VS Code Command Palette:

- `MCP: List Servers`

Then capture:

- Server display name(s)
- If it shows a command/binary path
- Server mode or namespaces

(If you cannot copy from the UI, fall back to Route A and decompile the extension behavior by inspecting its bundled JS.)

## Step 2  Extract a runnable server command (stdio/SSE)

### Azure MCP example: `ms-azuretools.vscode-azure-mcp-server`

This extension’s entrypoint requires VS Code:

- Do NOT run `main.js`.

Instead, locate the shipped MCP server binary:

```powershell
$extId = "ms-azuretools.vscode-azure-mcp-server"
$extPath = code --locate-extension $extId
$serverExe = Join-Path $extPath "server\azmcp.exe"
Test-Path $serverExe
$serverExe
```

Typical invocation (stdio):

```powershell
& $serverExe server start --mode namespace --read-only
```

Notes:

- Prefer `--mode namespace` (good balance of tool count vs routing).
- Add `--read-only` by default unless user explicitly requests write operations.

## Step 3  Register the server in Roo MCP config

### 3.1 Identify Roo MCP settings file

On Windows for Roo, it is commonly located under VS Code global storage:

```powershell
$rooMcpSettings = Join-Path $env:APPDATA "Code\User\globalStorage\rooveterinaryinc.roo-cline\settings\mcp_settings.json"
Test-Path $rooMcpSettings
$rooMcpSettings
```

### 3.2 Add an `mcpServers` entry

Add a new server definition that uses environment variables instead of hard-coded usernames.

Example entry for Azure MCP (`azure-mcp`):

```json
{
  "mcpServers": {
    "azure-mcp": {
      "notes": [
        "Azure MCP server shipped with the VS Code extension ms-azuretools.vscode-azure-mcp-server. Uses azmcp.exe (stdio)."
      ],
      "type": "stdio",
      "command": "${env:USERPROFILE}\\.vscode\\extensions\\ms-azuretools.vscode-azure-mcp-server-1.0.1-win32-x64\\server\\azmcp.exe",
      "args": [
        "server",
        "start",
        "--mode",
        "namespace",
        "--read-only"
      ],
      "disabled": false,
      "timeout": 60,
      "alwaysAllow": []
    }
  }
}
```

Important:

- Keep the server key stable: `azure-mcp`.
- Ensure the `command` matches the actual extension folder name present on disk.
  - The folder includes the version suffix (e.g. `...-1.0.1-win32-x64`).
- Prefer `${env:USERPROFILE}` / `${env:LOCALAPPDATA}` / `${env:APPDATA}` in paths.

## Step 4  Restart and verify

1. Restart Roo (or reload VS Code window) so Roo reloads MCP settings.

2. Verify via an MCP call (example for Azure):

- Call [`mcp--azure-mcp--subscription_list()`](mcp--azure-mcp--subscription_list:1) and confirm it returns subscriptions.

If tools are namespaced differently (depending on server mode), search for the available tool namespaces in the agent runtime and use the subscription tool that exists.

## Troubleshooting

### Symptom: `Cannot find module 'vscode'`

Cause: you tried to run the extension host entrypoint.

Fix: find the real server binary/script (e.g. `server/azmcp.exe`) and register that.

### Symptom: Roo does not show the server / tools

- Confirm the MCP settings file path is correct.
- Confirm JSON is valid.
- Confirm `disabled` is `false`.
- Restart Roo/VS Code window.

### Symptom: server starts but returns auth errors

- Ensure the user is signed in to Azure in a way the server can access.
  - The Azure MCP server typically uses existing Azure identity context from VS Code/Azure tooling.
- As a diagnostic (only if allowed), verify Azure identity via MCP subscription calls.

## Safety defaults

- Prefer `--read-only` unless explicitly instructed otherwise.
- Avoid registering unknown servers without first identifying their executable/script and reviewing what operations they can perform.
