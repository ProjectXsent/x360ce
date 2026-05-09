# Installing Playwright MCP Server

The official [Playwright MCP server](https://github.com/microsoft/playwright-mcp) by Microsoft gives AI agents the ability to interact with web pages — navigating, clicking, filling forms, taking screenshots, and reading page content via accessibility snapshots.

The recommended approach uses `npx @playwright/mcp@latest` (stdio transport) with **Microsoft Edge** as the default browser on Windows. Chrome, Chromium, Firefox, and WebKit are also supported.

## Prerequisites

- Node.js LTS and npm on PATH (installed via `winget install OpenJS.NodeJS.LTS`)
- A Chromium-based browser for best results: **Microsoft Edge** (recommended, pre-installed on Windows) or Google Chrome

### Optional: VS Code extensions

- **Playwright Test for VSCode** (`ms-playwright.playwright`) — run, debug, and record Playwright tests from the editor
- **Playwright MCP Bridge** — connect the MCP server to an existing Edge/Chrome browser tab (useful for authenticated sessions)

## Installation

The bundled script installs `@playwright/mcp` globally, downloads the selected browser binaries, and optionally installs `@playwright/test` for UI mode testing.

```powershell
# Default: Edge browser + test runner
.\.ai\skills\ai-agent-onboarding\scripts\install-playwright-mcp.ps1

# Chrome instead of Edge
.\.ai\skills\ai-agent-onboarding\scripts\install-playwright-mcp.ps1 -Browser chrome

# Skip @playwright/test (MCP only, no UI test mode)
.\.ai\skills\ai-agent-onboarding\scripts\install-playwright-mcp.ps1 -SkipTest
```

The script is idempotent — safe to run again to update to a newer version.

## MCP Configuration

The MCP server name is simply `playwright`.

### RooCode / Cline (`mcp_settings.json`)

**Default (Edge, headed):**

```json
{
  "mcpServers": {
    "playwright": {
      "_comment": "Playwright MCP server — web automation for AI agents.",
      "_source": "https://github.com/microsoft/playwright-mcp",
      "type": "stdio",
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--browser", "msedge"],
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
```

**Headless mode** (no visible browser window):

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--browser", "msedge", "--headless"],
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
```

**With vision mode** (screenshots instead of accessibility snapshots):

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--browser", "msedge", "--caps", "vision"],
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
```

### Claude Code (`.mcp.json` or `claude mcp add`)

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--browser", "msedge"]
    }
  }
}
```

Or via CLI:

```bash
claude mcp add playwright npx @playwright/mcp@latest -- --browser msedge
```

### VS Code native MCP (`settings.json`)

```json
{
  "mcp": {
    "servers": {
      "playwright": {
        "command": "npx",
        "args": ["@playwright/mcp@latest", "--browser", "msedge"]
      }
    }
  }
}
```

Or one-click install via the VS Code command palette, or:

```bash
code --add-mcp '{"name":"playwright","command":"npx","args":["@playwright/mcp@latest","--browser","msedge"]}'
```

## Browser Selection

Use the `--browser` flag to choose the browser engine:

| Value | Browser | Notes |
|-------|---------|-------|
| `msedge` | Microsoft Edge | **Recommended on Windows.** Pre-installed, Chromium-based. |
| `chrome` | Google Chrome | Chromium-based. Must be installed separately. |
| `chromium` | Playwright's Chromium | Downloaded by `npx playwright install chromium`. |
| `firefox` | Firefox | Gecko engine. |
| `webkit` | WebKit | Safari engine. |

## Key CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `--browser <name>` | Browser to use | `chrome` |
| `--headless` | Run without visible window | Off (headed) |
| `--caps <list>` | Capabilities: `vision`, `pdf`, `devtools` | None |
| `--viewport-size <WxH>` | Viewport dimensions | `1280x720` |
| `--device <name>` | Emulate device (e.g., `"iPhone 15"`) | None |
| `--user-data-dir <path>` | Persistent browser profile | Auto |
| `--isolated` | Ephemeral profile (discarded after session) | Off |
| `--storage-state <path>` | Load cookies/localStorage from file | None |
| `--proxy-server <url>` | HTTP proxy | None |
| `--timeout-action <ms>` | Action timeout | 5000 |
| `--timeout-navigation <ms>` | Navigation timeout | 60000 |
| `--config <path>` | Load options from JSON config file | None |
| `--codegen <lang>` | Generate code: `typescript` or `none` | None |

All flags have corresponding environment variables prefixed with `PLAYWRIGHT_MCP_` (e.g., `PLAYWRIGHT_MCP_BROWSER`, `PLAYWRIGHT_MCP_HEADLESS`).

## Playwright Test UI Mode

When `@playwright/test` is installed, developers can run tests with a visual UI:

```bash
# Open UI mode
npx playwright test --ui

# Bind to external interface (Docker, Codespaces)
npx playwright test --ui-host=0.0.0.0

# Specify port
npx playwright test --ui-port=8080 --ui-host=0.0.0.0
```

UI mode provides:
- **Test explorer** — browse, run, watch, and debug individual tests
- **Timeline** — color-coded navigation and action visualization with hover snapshots
- **Actions tab** — locators, timing, Before/After DOM snapshots
- **Network tab** — request details (headers, body, status, size, duration)
- **Watch mode** — auto-re-run tests on file changes (eye icon per test)
- **Locator picker** — hover over elements to identify and test locators
- **"Open in VS Code"** — jump to source from any action

## Connecting to Existing Browser (MCP Bridge Extension)

To connect the MCP server to an already-running Edge or Chrome instance (useful for authenticated sessions):

1. Install the **Playwright MCP Bridge** extension in Edge or Chrome
2. Use the `--extension` flag:

```json
{
  "args": ["@playwright/mcp@latest", "--extension"]
}
```

This reuses the browser's existing cookies, sessions, and extensions.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `npx` not found | Node.js not installed | Install via `winget install OpenJS.NodeJS.LTS` |
| Browser not found | Browser not installed | Run `npx playwright install msedge` (or `chrome`, etc.) |
| Timeout errors | Slow page load | Increase `--timeout-navigation 120000` |
| Permission denied | Sandbox issue | Try `--no-sandbox` flag |
| Can't connect to existing browser | Extension not installed | Install Playwright MCP Bridge extension in Edge/Chrome |
| `--ui` not working | `@playwright/test` not installed | Run `npm install -g @playwright/test@latest` |
