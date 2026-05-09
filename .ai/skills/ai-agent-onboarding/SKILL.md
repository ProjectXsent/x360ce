---
name: ai-agent-onboarding
description: |
  Set up a Windows development environment and onboard a repository for
  multi-agent AI development.

  Installs or updates WinGet, Git, PowerShell 7, Python, and pip; enables
  long paths; copies core `.ai` skills into a target repo; creates agent
  folders; runs the sync pipeline; and can optionally install Qdrant plus MCP
  servers for SQL Server, GitHub, Azure DevOps, Playwright, and n8n.

  Use this skill whenever the user wants to set up a machine or repo for AI
  coding, install RooCode or Copilot prerequisites, bootstrap a repo with a
  `.ai/` folder, prepare agent folders, or install/configure GitHub, Azure
  DevOps, Playwright, SQL Server, Qdrant, or n8n MCP tooling on Windows.
---

# AI Agent Onboarding

This skill walks the user through a guided, multi-step setup process for onboarding AI agents (RooCode, GitHub Copilot, Cline, OpenAI Codex) onto a Windows machine and into any repository.

The `.ai/` folder is the single source of truth for all agent configurations. This skill spreads that infrastructure — along with `ai-self-improvement` and `repository-analysis` skills — into target repositories, then the `ai-self-improvement` sync pipeline keeps `.roo/`, `.github/`, `.cline/`, and `AGENTS.md` in sync with `.ai/` sources.

## Critical Rule: Always Ask Permission

**Ask the user for explicit permission before every install, copy, or system-modification step.** Present what you intend to do and why, then wait for approval. If the user declines a step, skip it and move to the next. Users have every right to object to unsolicited software installation or file system changes.

## Prerequisites

- Windows 10/11
- Internet access (for winget, git clone, package downloads)
- Administrator access (only for the long-paths registry change in Step 4)

## Step-by-Step Process

Work through these steps in order. Before each step, tell the user what it does and ask if they want to proceed.

---

### Step 1: Install WinGet (Windows Package Manager)

WinGet is the foundation — Steps 2 and 3 use it to install all other packages.

**What to tell the user:** WinGet (Windows Package Manager) is required to install Git and PowerShell 7. Most Windows 10/11 machines already have it via the App Installer package. This script checks whether WinGet is present and up-to-date, and installs or updates it if needed.

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-winget.ps1
```

---

### Step 2: Install Git

Git is required for repository operations and for cloning community skills in Step 7.

**What to tell the user:** Git is the version control system used by all AI coding agents. This script uses winget to install or update Git for Windows to the latest version.

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-git.ps1
```

Note: If Git was freshly installed, the user will need to restart all VS Code instances later (see Step 3 note).

---

### Step 3: Install PowerShell 7+

PowerShell 7 is the modern cross-platform shell. Sync scripts and many skills depend on it.

**What to tell the user:** PowerShell 7+ (pwsh) is the modern PowerShell used by RooCode scripts. Windows ships with PowerShell 5.1, but PowerShell 7 provides better performance and cross-platform compatibility. This script uses winget to install or update it.

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-powershell.ps1
```

**IMPORTANT — Restart VS Code:** After Steps 2 and 3, if either Git or PowerShell was freshly installed (not just updated), or if environment variables / PATH were changed, the user **must close and reopen all VS Code instances** so that the updated PATH takes effect. A `Developer: Reload Window` is NOT sufficient — VS Code's integrated terminal inherits PATH from the process that launched VS Code, so only a full restart picks up system PATH changes. Tell the user:

> "If Git or PowerShell 7 were freshly installed, or environment variables were changed, please **close all VS Code windows and reopen them**. A window reload is not enough — only a full restart picks up PATH changes in the terminal. If they were only updated (already on PATH), no restart is needed."

Wait for the user to confirm before proceeding.

---

### Step 4: Install Python 3

Python is used extensively by AI agents for tooling, scripts, and package management.

**What to tell the user:** Python 3 is the runtime used by most AI agent tools, MCP servers, and data-processing scripts. This script detects the current Python version, checks whether a newer stable series is available in winget, and installs or upgrades accordingly.

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-python.ps1
```

Note: If Python was freshly installed, the user will need to restart all VS Code instances (see Step 3 note).

---

### Step 5: Update pip

pip is the standard Python package manager used to install libraries that AI agents depend on.

**What to tell the user:** pip ships with Python but can become outdated. This script upgrades pip to the latest version using Python's built-in module installer.

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-pip.ps1
```

---

### Step 6: Enable Long Paths (Windows + Git)

Windows has a legacy 260-character path limit that causes failures with deep directory structures common in Node.js, .NET, and AI projects.

**What to tell the user:** This enables long path support in both the Windows registry (requires Administrator elevation) and Git global configuration. The existing script handles prompting and elevation internally.

**Action:** Ask permission, then run:

```powershell
.\.ai\scripts\Setup_Util_EnableLongPaths_WindowsAndGit.ps1
```

This script is already present in the repo at `.ai/scripts/` — no wrapper is needed.

---

### Step 7: Copy Core Skills into Target Repository

This copies the `repository-analysis` and `ai-self-improvement` skills into the target repo's `.ai/skills/` folder. These are the minimum required for any repo to participate in the multi-agent ecosystem.

**What to tell the user:**
- **repository-analysis** — generates a comprehensive map of the repo's architecture, tech stack, and dependencies
- **ai-self-improvement** — manages the sync pipeline that keeps `.roo/`, `.github/`, `.cline/`, and `AGENTS.md` in sync with the `.ai/` source of truth

**Action:** Ask permission. If the target repo differs from the current workspace, ask for its path. Then copy:

```powershell
$targetRepo = "<user-provided-path-or-current-workspace>"
$sourceBase = ".\.ai\skills"
$targetBase = Join-Path $targetRepo ".ai\skills"

# Create targets
New-Item -ItemType Directory -Force -Path (Join-Path $targetBase "repository-analysis") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $targetBase "ai-self-improvement") | Out-Null

# Mirror skills
robocopy "$sourceBase\repository-analysis" "$targetBase\repository-analysis" /MIR /NFL /NDL /NJH /NJS /NP
robocopy "$sourceBase\ai-self-improvement" "$targetBase\ai-self-improvement" /MIR /NFL /NDL /NJH /NJS /NP
```

After copying, load the `ai-self-improvement` skill so its workflow becomes available for Step 8.

---

### Step 8: Create Agent Folders and Run Sync

Create `.roo/` and `.github/` directories in the target repo (if missing), then execute the sync pipeline to propagate `.ai/` sources into all agent output folders.

**What to tell the user:** This creates the agent-specific directories that RooCode (`.roo/`), GitHub Copilot (`.github/`), and others use, then runs the sync script to populate them from the `.ai/` source of truth. The `--global` flag also activates skills from `.ai/.global/skills/` by copying them into user-level paths like `~/.claude/skills/` so they're available across every project. Skills listed in `.ai/.global/removed-skills.json` are deleted from those user-level paths — additive otherwise (won't touch unrelated user-installed skills like GSD's `gsd-*` set).

**Action:** Ask permission, then:

```powershell
$targetRepo = "<user-provided-path-or-current-workspace>"

New-Item -ItemType Directory -Force -Path (Join-Path $targetRepo ".roo") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $targetRepo ".github") | Out-Null

Push-Location $targetRepo
python .\.ai\skills\ai-self-improvement\scripts\sync_agent_assets.py AUTO --global
Pop-Location
```

---

### Step 9 (Optional): Install Qdrant Vector Database

Qdrant is the vector database used by RooCode for persistent memory. This step is optional but recommended for users who want long-term memory across sessions.

**What to tell the user:** Qdrant runs locally on port 6333 as a user-level Windows Task that starts automatically at login. No Administrator rights are required at runtime.

**Action:** Ask permission, then follow the full instructions in [`references/install-qdrant.md`](references/install-qdrant.md). The summary is:

1. Copy the two bundled setup scripts to `C:\ProgramData\Qdrant\`
2. Run `Setup_App_5a_Qdrant_Core_Windows.ps1` and select menu options: **1** (Install App), **4** (Install User Task), **5** (Start Task)
3. Verify at `http://localhost:6333/dashboard#/collections` — bookmark this URL

---

### Step 10: Download Community Skills

This step installs skills from four community sources. Each source has a JSON config file that defines which skills to install and where (global vs project level):

- **Global skills** → `.ai/.global/skills/{skill}/` — shared across the repo, not synced to agent-specific folders
- **Project skills** → `.ai/skills/{skill}/` — synced to `.roo/skills/`, `.claude/skills/`, `.github/skills/` by the sync pipeline

All installers use a shared `install-core.ps1` that reads the JSON config, clones the source repo (shallow), and copies the selected skill folders. Each JSON config has `"global"` and `"project"` arrays — edit these to control which skills are installed and at which tier.

These cross-agent skills are documented end-to-end in [`references/install-agent-extensions.md`](references/install-agent-extensions.md). For Claude Code-specific plugins (hooks, slash commands, MCP wiring) that cannot be cleanly extracted as portable SKILL.md, see Step 16 and [`references/install-claude-extensions.md`](references/install-claude-extensions.md).

**What to tell the user:** This downloads AI agent skills from four sources — Anthropic, Superpowers (obra), Microsoft, and n8n — into your repository's `.ai/` folder. Skills are organized by tier: global skills are available across the repo; project skills are synced to all agent configurations. You can customise which skills are installed by editing the JSON config files.

#### Step 10a: Anthropic Community Skills

Source: [github.com/anthropics/skills](https://github.com/anthropics/skills) — document skills, design, art, MCP building.

Config: [`install-anthropic-skills.json`](install-anthropic-skills.json)

Default global skills: `algorithmic-art`, `doc-coauthoring`, `docx`, `frontend-design`, `mcp-builder`, `pdf`, `pptx`, `xlsx`

**Action:** Ask permission, then run:

```powershell
# Install all (global + project)
.\.ai\skills\ai-agent-onboarding\scripts\install-anthropic-skills.ps1

# Preview what would be installed
.\.ai\skills\ai-agent-onboarding\scripts\install-anthropic-skills.ps1 -DryRun

# Install only global tier
.\.ai\skills\ai-agent-onboarding\scripts\install-anthropic-skills.ps1 -Tier global
```

#### Step 10b: Superpowers Skills

Source: [github.com/obra/superpowers](https://github.com/obra/superpowers) — Jesse Vincent's agentic-skills framework. Repo bundles a Claude plugin AND a portable `skills/` folder; this installer copies only the portable folder.

Config: [`install-superpowers-skills.json`](install-superpowers-skills.json)

Default global skills (14): `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`.

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-superpowers-skills.ps1
```

> If the user is on Claude Code and wants the full plugin (with `commands/`, `hooks/`, `agents/` wiring), point them at Step 16 instead — `/plugin install superpowers@claude-plugins-official`. Both can coexist: SKILL.md folders for non-Claude agents, plugin for Claude Code.

#### Step 10c: Microsoft Skills

Source: [github.com/microsoft/skills](https://github.com/microsoft/skills) — Azure, .NET, cloud architecture, SDK skills.

Config: [`install-microsoft-skills.json`](install-microsoft-skills.json)

Microsoft skills come from two locations in the repo:
- **Core skills** — `.github/skills/{name}/` (10 skills: cloud-solution-architect, copilot-sdk, microsoft-docs, etc.)
- **Plugin-wrapped skills** — `.github/plugins/{plugin}/skills/{name}/` (166+ skills across azure-skills, azure-sdk-dotnet, azure-sdk-java, azure-sdk-python, azure-sdk-typescript, azure-sdk-rust)

Both use standard `SKILL.md` format — no conversion needed. The JSON config maps each skill to its repo path. Edit the JSON to add/remove skills from specific plugins.

Default global skills: core Microsoft skills + selected Azure skills (deploy, diagnostics, compute, storage, kubernetes, AI, cost, RBAC) + selected Azure SDK .NET skills (OpenAI, identity, Playwright).

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-microsoft-skills.ps1
```

#### Step 10d: n8n Workflow Skills

Source: [github.com/czlonkowski/n8n-skills](https://github.com/czlonkowski/n8n-skills) — n8n workflow automation, expressions, validation, node configuration.

Config: [`install-n8n-skills.json`](install-n8n-skills.json)

Default global skills: `n8n-code-javascript`, `n8n-code-python`, `n8n-expression-syntax`, `n8n-mcp-tools-expert`, `n8n-node-configuration`, `n8n-validation-expert`, `n8n-workflow-patterns`

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-n8n-skills.ps1
```

#### JSON Config Format

Each JSON config follows this structure:

```json
{
  "source": {
    "organisation": "microsoft",
    "repo": "skills",
    "branch": "main"
  },
  "global": [
    { "skill": "skill-name", "path": "path/in/repo/to/skill-folder" }
  ],
  "project": [
    { "skill": "skill-name", "path": "path/in/repo/to/skill-folder" }
  ]
}
```

- `"path"` is the folder inside the cloned repo containing `SKILL.md`. If omitted, defaults to `"skills/{skill}"`.
- Move entries between `"global"` and `"project"` arrays to change the install tier.
- All scripts support `-Tier global|project|all`, `-DryRun`, and `-RepoRoot` parameters.

---

### Step 11 (Optional): Install SQL Server MCP (MssqlMcp)

MssqlMcp gives AI agents read-only, structured access to SQL Server databases — listing tables, describing schemas, and reading data — without allowing arbitrary SQL execution.

**What to tell the user:** This installs the Azure-Samples MssqlMcp server, which provides safe SQL Server access for AI agents. It clones the source from GitHub, builds it with the .NET SDK, and installs the binaries to a location you choose (global per-user, committed to repo, or git-ignored local). After installation, you configure an MCP entry per database with a connection string.

**Prerequisites:** .NET 8 SDK and Git (both installed in earlier steps).

**Action:** Ask permission, then run:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-sql-mcp.ps1
```

The script presents an interactive menu to choose the install location:
1. **Global** — `%LOCALAPPDATA%\mcp-servers\MssqlMcp\` (recommended for most users)
2. **Project** — `{repo}\.ai\MCP\MssqlMcp\` (committed to git)
3. **ProjectLocal** — `{repo}\.ai\MCP\MssqlMcp\.bin\` (git-ignored)

After installation, help the user add an MCP entry to their agent config. See [`references/install-sql-mcp.md`](references/install-sql-mcp.md) for full configuration examples and the naming convention (`sql-{environment}-{database}`).

---

### Step 12 (Optional): Install GitHub MCP Server

The official [GitHub MCP server](https://github.com/github/github-mcp-server) gives AI agents access to repositories, issues, pull requests, code search, and more. Uses pre-built official binaries from GitHub Releases (stdio transport).

**What to tell the user:** This downloads the official GitHub MCP server binary and connects your AI agent to GitHub. The agent will be able to browse repos, read files, search code, list issues and PRs, and more. You need a GitHub Personal Access Token (PAT).

**Prerequisites:** A GitHub Personal Access Token stored in the `GITHUB_PERSONAL_ACCESS_TOKEN` environment variable.

**Action:** Ask permission, then:

1. **Check for an existing PAT:**

```powershell
if ([Environment]::GetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', 'User')) {
    Write-Host "GITHUB_PERSONAL_ACCESS_TOKEN is set." -ForegroundColor Green
} else {
    Write-Host "GITHUB_PERSONAL_ACCESS_TOKEN is NOT set." -ForegroundColor Red
    Write-Host "Create a token at: https://github.com/settings/tokens" -ForegroundColor Yellow
    Write-Host "Required scope: repo (classic) or repository access (fine-grained)" -ForegroundColor Yellow
}
```

2. **If not set**, guide the user to create a PAT at `https://github.com/settings/tokens` and set it:

```powershell
[Environment]::SetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', '<token>', 'User')
```

Remind the user to **restart all VS Code instances** after setting the variable.

3. **Install the binary:**

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-github-mcp.ps1
```

4. **Add the MCP entry** to the agent's MCP config. The naming convention is `github-{user}`:

```json
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
```

For read-only access, add `"GITHUB_READ_ONLY": "1"` to the `env` block, or use a fine-grained PAT with read-only permissions.

See [`references/install-github-mcp.md`](references/install-github-mcp.md) for full details, alternative methods (Docker), and troubleshooting.

---

### Step 13 (Optional): Install Azure DevOps MCP Server

The official [Azure DevOps MCP server](https://github.com/microsoft/azure-devops-mcp) (`@azure-devops/mcp` by Microsoft) gives AI agents access to work items, repositories, iterations, pull requests, and more. The install script patches the package to support self-hosted Azure DevOps Server URLs in addition to cloud `dev.azure.com`.

**What to tell the user:** This installs the official Microsoft Azure DevOps MCP server and patches it to work with both cloud (dev.azure.com) and self-hosted Azure DevOps Server instances. You need a Personal Access Token (PAT) for each organization. Multiple organizations are supported — each gets its own MCP entry.

**Prerequisites:** Node.js LTS and a PAT for the target Azure DevOps organization.

**Action:** Ask permission, then:

1. **Run the install script:**

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-azure-devops-mcp.ps1
```

2. **Set environment variables** (if not already set):

```powershell
# Required
[Environment]::SetEnvironmentVariable('AZDO_ORG', 'YourOrg', 'User')
[Environment]::SetEnvironmentVariable('AZDO_PAT', '<your-pat>', 'User')

# Only for self-hosted Azure DevOps Server (omit for dev.azure.com)
[Environment]::SetEnvironmentVariable('AZDO_URL', 'https://your-server.com', 'User')
```

Remind the user to **restart all VS Code instances** after setting variables.

3. **Add the MCP entry.** For a single org, use `azure-devops`. For multiple orgs, use `azure-devops-{org}`:

**Single org:**

```json
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
```

**Multiple orgs** — add a `_{Suffix}` to each env var. Each entry gets its own `env` block:

```powershell
# Non-default org env vars (suffixed)
[Environment]::SetEnvironmentVariable('AZDO_ORG_JocysCom', 'JocysCom', 'User')
[Environment]::SetEnvironmentVariable('AZDO_PAT_JocysCom', '<pat>', 'User')
[Environment]::SetEnvironmentVariable('AZDO_URL_JocysCom', 'https://devops.jocys.com', 'User')
```

```json
"azure-devops-JocysCom": {
    "type": "stdio",
    "command": "node",
    "args": ["...index.js", "${env:AZDO_ORG_JocysCom}", "--authentication", "envvar", "-d", "core", "work", "work-items"],
    "env": {
        "ADO_MCP_AUTH_TOKEN": "${env:AZDO_PAT_JocysCom}",
        "ADO_MCP_ORG_URL": "${env:AZDO_URL_JocysCom}/${env:AZDO_ORG_JocysCom}"
    }
},
"azure-devops-Contoso": {
    "type": "stdio",
    "command": "node",
    "args": ["...index.js", "${env:AZDO_ORG_Contoso}", "--authentication", "envvar", "-d", "core", "work", "work-items"],
    "env": {
        "ADO_MCP_AUTH_TOKEN": "${env:AZDO_PAT_Contoso}"
    }
}
```

**Convention:** Default (primary) org uses unsuffixed `AZDO_ORG`, `AZDO_PAT`, `AZDO_URL`. Additional orgs add `_{Suffix}` (e.g., `AZDO_PAT_JocysCom`). `ADO_MCP_ORG_URL` is only needed for self-hosted — omit it for cloud `dev.azure.com`.

See [`references/install-azure-devops-mcp.md`](references/install-azure-devops-mcp.md) for full details, available domains, authentication methods, and troubleshooting.

---

### Step 14 (Optional): Install Playwright MCP Server

The official [Playwright MCP server](https://github.com/microsoft/playwright-mcp) by Microsoft gives AI agents the ability to interact with web pages — navigating, clicking, filling forms, taking screenshots, and reading page content. It also supports Playwright Test with a visual UI mode for debugging tests.

**What to tell the user:** This installs the Playwright MCP server, which lets AI agents browse the web, interact with pages, and extract content. It uses Microsoft Edge by default (recommended on Windows, pre-installed), but Chrome, Firefox, and WebKit are also supported. Optionally installs `@playwright/test` so you can run and debug tests with a visual UI (`npx playwright test --ui`).

**Prerequisites:** Node.js LTS and npm on PATH. A Chromium-based browser (Edge is pre-installed on Windows).

**Recommended VS Code extension:** **Playwright Test for VSCode** (`ms-playwright.playwright`) — provides in-editor test running, debugging, trace viewing, and test recording. The user may already have this installed.

**Action:** Ask permission, then:

1. **Choose the browser.** Recommend Microsoft Edge (pre-installed on Windows, Chromium-based). Ask if they prefer Chrome or another browser:

| Option | Description |
|--------|-------------|
| `msedge` | **Microsoft Edge** (recommended) — pre-installed on Windows |
| `chrome` | Google Chrome — must be installed separately |
| `chromium` | Playwright's bundled Chromium |
| `firefox` | Firefox (Gecko engine) |
| `webkit` | WebKit (Safari engine) |

2. **Run the install script:**

```powershell
# Default: Edge + test runner
.\.ai\skills\ai-agent-onboarding\scripts\install-playwright-mcp.ps1

# Or specify browser
.\.ai\skills\ai-agent-onboarding\scripts\install-playwright-mcp.ps1 -Browser chrome
```

3. **Add the MCP entry** to the agent's MCP config:

```json
"playwright": {
    "_comment": "Playwright MCP server — web automation for AI agents.",
    "_source": "https://github.com/microsoft/playwright-mcp",
    "type": "stdio",
    "command": "npx",
    "args": ["@playwright/mcp@latest", "--browser", "msedge"],
    "disabled": false,
    "alwaysAllow": []
}
```

For headless mode (no visible browser window), add `"--headless"` to `args`. For vision mode (screenshots instead of accessibility snapshots), add `"--caps", "vision"`.

4. **Optional: Playwright Test UI mode.** If `@playwright/test` was installed (default), the user can run tests with a visual interface:

```bash
npx playwright test --ui
```

UI mode provides a test explorer, timeline visualization, DOM snapshots, network inspector, watch mode, and locator picker. See [`references/install-playwright-mcp.md`](references/install-playwright-mcp.md) for full details.

5. **Optional: Connect to existing browser.** For authenticated sessions, install the **Playwright MCP Bridge** extension in Edge/Chrome, then use `"--extension"` in `args` instead of `"--browser"`.

See [`references/install-playwright-mcp.md`](references/install-playwright-mcp.md) for full configuration examples, all CLI options, and troubleshooting.

---

### Step 15 (Optional): Install n8n MCP Server

The [n8n-mcp](https://github.com/czlonkowski/n8n-mcp) server (by czlonkowski) connects AI agents to a running [n8n](https://n8n.io/) workflow automation instance. It exposes 7 documentation tools (node/template search, schema lookup, workflow validation) plus 14 management tools (list/get/create/update/delete/execute workflows via the n8n REST API).

**What to tell the user:** This installs the n8n-mcp server so your AI agent can browse node documentation and read, create, or modify workflows on your n8n instance. Unlike the other MCP servers, n8n-mcp runs on demand via `npx -y n8n-mcp` — nothing is installed to `%LOCALAPPDATA%\mcp-servers\`. The install script only pre-warms the npx cache (to avoid a known silent-launch failure on cold cache) and verifies the required environment variables.

**Prerequisites:** Node.js LTS, a running n8n instance, and an n8n API key (Settings → n8n API → Create an API key).

**Action:** Ask permission, then:

1. **Create and store the API key.** In n8n, open **Settings → n8n API → Create an API key**, copy the token, then:

```powershell
[Environment]::SetEnvironmentVariable('N8N_API_URL', 'http://127.0.0.1:5678', 'User')
[Environment]::SetEnvironmentVariable('N8N_API_KEY', '<your-token>', 'User')
```

Remind the user to **restart all VS Code instances** after setting these.

2. **Run the install script:**

```powershell
# Defaults (expects n8n at http://127.0.0.1:5678)
.\.ai\skills\ai-agent-onboarding\scripts\install-n8n-mcp.ps1

# Custom URL + verify the instance is reachable
.\.ai\skills\ai-agent-onboarding\scripts\install-n8n-mcp.ps1 -N8nUrl http://localhost:5678 -Probe
```

The script cleans corrupt npx cache entries for `n8n-mcp` (a known failure mode where a partial install yields a silent zero-exit "not recognized" error), then pre-warms the cache so the MCP host can launch the server without a TTY.

3. **Add the MCP entry.** The canonical name is `n8n-mcp`. The `-y` flag on `npx` is required — without it, npx prompts interactively on cold cache and MCP hosts launch with no TTY.

```json
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
```

The default `alwaysAllow` list covers read/validate tools. Add write tools (`n8n_update_partial_workflow`, `n8n_create_workflow`, `n8n_delete_workflow`, `n8n_manage_credentials`) only after the agent has proven trustworthy — those commands can mutate credentials and production workflows.

See [`references/install-n8n-mcp.md`](references/install-n8n-mcp.md) for the full tool catalogue, multi-instance configuration, and troubleshooting (including the corrupt-cache silent-launch failure).

---

### Step 16 (Optional, Claude Code only): Install Claude Code Plugins

This step covers plugins that hook into Claude Code's plugin system, slash commands, lifecycle hooks, or MCP wiring. **Skip this step if the user is not a Claude Code user.**

The recommended set comes from the video [*I Tried 100+ Claude Code Skills. These 6 Are The Best*](https://www.youtube.com/watch?v=eRS3CmvrOvA) (Nate Herkelman, 2026). Plugins install at **user (global) scope** so they follow the user across every project, every host (CLI, VS Code native extension, JetBrains).

**What to tell the user:** This installs six Claude Code plugins that the community has converged on as the highest-value: a skill builder, the Superpowers agentic framework, a context-engineering layer (GSD), a sandboxed tool-call router (context-mode), a session-spanning memory store (claude-mem), and a frontend-design skill. Plus the built-in `/review` and `/ultrareview` commands, which need no install on Claude Code 2.1.86+.

**Prerequisites:**

- Claude Code CLI 2.1+ on PATH (`claude --version` should report 2.1.x or later). Install via `npm install -g @anthropic-ai/claude-code`. Required *even if the user normally uses the VS Code native extension* — the CLI's `claude plugin` subcommand is what registers plugins into `~/.claude/plugins/`, which the VS Code extension then loads.
- **Bun** runtime on PATH — required by `claude-mem`'s MCP server (`mcp-search`), which is wired with `"command": "bun"` in its `.mcp.json`. Without Bun the plugin installs but its MCP tools fail at startup with `plugin:claude-mem:mcp-search not working`. Install with:

  ```powershell
  .\.ai\skills\ai-agent-onboarding\scripts\install-bun.ps1
  ```

  Other plugins may add similar runtime requirements; the installer auto-validates and reports anything missing.

**Action:** Ask permission, then run the wrapper that drives `claude plugin` non-interactively from a JSON config:

```powershell
# Preview without changing anything
.\.ai\skills\ai-agent-onboarding\scripts\install-claude-plugins.ps1 -DryRun

# Install all configured marketplaces and plugins
.\.ai\skills\ai-agent-onboarding\scripts\install-claude-plugins.ps1
```

The script reads [`install-claude-plugins.json`](install-claude-plugins.json), runs `claude plugin marketplace add <source>` for each marketplace, then `claude plugin install <plugin>` for each plugin. Edit the JSON to add/remove plugins.

Then run the GSD installer separately (it's an `npx` package, not a Claude marketplace plugin):

```powershell
npx get-shit-done-cc --claude --global
```

**After install — restart all Claude Code hosts.** A VS Code "Reload Window" is not enough; close all VS Code windows and reopen. The native extension and CLI both rescan `~/.claude/plugins/` only on full restart.

**Verify**: the installer ends with two checks — `claude plugin list` (every plugin should show `Status: enabled`) and an **MCP runtime validator** that scans every plugin's `.mcp.json` and confirms each declared `command` resolves on PATH. Output looks like:

```text
── MCP server runtime validation ──
  [OK]   thedotmack/claude-mem  -> mcp-search (command: bun)
  [OK]   mksglu/context-mode    -> context-mode (command: node)
```

A `[FAIL]` line means a plugin will not work until you install the listed runtime and restart Claude Code hosts. The validator includes install hints for `bun`, `node`, `python`, `uv`, `deno`, `dotnet`.

Inspect context-mode savings with `/contextmode:ctx-stats`. GSD discovery: `/gsd-help`.

**Warning — claude-mem:** Do **not** run `npm install claude-mem`. That installs the SDK only and the hooks never register. The `claude plugin install` route is correct.

**Why a CLI script and not slash commands inside Claude Code?**

`/plugin install` is a slash command exposed only by the standalone Claude Code CLI prompt. The VS Code native extension intentionally has a more restricted command set and emits `/plugin isn't available in this environment`. The `claude plugin install` shell command works from any terminal regardless of which Claude Code host is in use, and the resulting `~/.claude/plugins/` state is shared across hosts.

See [`references/install-claude-extensions.md`](references/install-claude-extensions.md) for full descriptions, when to prefer the plugin form vs. the cross-agent SKILL.md form, and version requirements.

---

## Bundled Scripts

All scripts live under `.ai/skills/ai-agent-onboarding/scripts/`:

| Script | Purpose |
|--------|---------|
| [`install-winget.ps1`](scripts/install-winget.ps1) | Check, install, or update WinGet via Microsoft Store. Detects upgrade failures. |
| [`install-git.ps1`](scripts/install-git.ps1) | Install or update Git for Windows via winget. Shows available version and detects technology mismatches. |
| [`install-powershell.ps1`](scripts/install-powershell.ps1) | Install or update PowerShell 7 via winget. Shows available version and detects technology mismatches. |
| [`install-python.ps1`](scripts/install-python.ps1) | Install or update Python 3 (latest stable series) via winget. Detects newer minor series. |
| [`install-pip.ps1`](scripts/install-pip.ps1) | Upgrade pip to the latest version using python -m pip. |
| [`install-bun.ps1`](scripts/install-bun.ps1) | Install or update Bun via winget. Required by claude-mem's MCP server. Falls back to baseline build on non-AVX2 CPUs. |
| [`install-core.ps1`](scripts/install-core.ps1) | Shared functions for config-driven skill installation (global/project tiers) |
| [`install-anthropic-skills.ps1`](scripts/install-anthropic-skills.ps1) | Install Anthropic community skills from JSON config |
| [`install-superpowers-skills.ps1`](scripts/install-superpowers-skills.ps1) | Install Superpowers (obra) skill folders from JSON config |
| [`install-microsoft-skills.ps1`](scripts/install-microsoft-skills.ps1) | Install Microsoft skills (core + plugin-wrapped) from JSON config |
| [`install-n8n-skills.ps1`](scripts/install-n8n-skills.ps1) | Install n8n workflow automation skills from JSON config |
| [`install-claude-plugins.ps1`](scripts/install-claude-plugins.ps1) | Drive `claude plugin marketplace add` / `claude plugin install` from JSON config (Claude Code-only plugins) |
| [`Setup_App_5a_Qdrant_Core_Windows.ps1`](scripts/Setup_App_5a_Qdrant_Core_Windows.ps1) | Interactive Qdrant installer and service manager |
| [`Setup_Helper_CoreFunctions.ps1`](scripts/Setup_Helper_CoreFunctions.ps1) | Shared helper functions used by the Qdrant installer |
| [`install-sql-mcp.ps1`](scripts/install-sql-mcp.ps1) | Clone, build, and install Azure-Samples MssqlMcp (SQL Server MCP server) |
| [`install-github-mcp.ps1`](scripts/install-github-mcp.ps1) | Download and install official GitHub MCP server binary from GitHub Releases |
| [`install-azure-devops-mcp.ps1`](scripts/install-azure-devops-mcp.ps1) | Install and patch Azure DevOps MCP server for self-hosted URL support |
| [`install-playwright-mcp.ps1`](scripts/install-playwright-mcp.ps1) | Install Playwright MCP server, browser binaries, and optional test runner |
| [`install-n8n-mcp.ps1`](scripts/install-n8n-mcp.ps1) | Pre-warm the npx cache for n8n-mcp, clean corrupt cache entries, and check N8N_API_URL / N8N_API_KEY env vars |

The long-paths script already exists at `.ai/scripts/Setup_Util_EnableLongPaths_WindowsAndGit.ps1` and is referenced directly — not duplicated.

## References

| File | Purpose |
|------|---------|
| [`references/install-qdrant.md`](references/install-qdrant.md) | Step-by-step guide for installing and verifying Qdrant |
| [`references/install-sql-mcp.md`](references/install-sql-mcp.md) | SQL Server MCP installation, configuration, and naming conventions |
| [`references/install-github-mcp.md`](references/install-github-mcp.md) | GitHub MCP server setup, PAT configuration, and naming conventions |
| [`references/install-azure-devops-mcp.md`](references/install-azure-devops-mcp.md) | Azure DevOps MCP setup, self-hosted URL patch, multi-org configuration |
| [`references/install-playwright-mcp.md`](references/install-playwright-mcp.md) | Playwright MCP setup, browser selection, UI test mode, CLI options |
| [`references/install-n8n-mcp.md`](references/install-n8n-mcp.md) | n8n MCP setup, API key configuration, tool catalogue, corrupt-cache troubleshooting |
| [`references/install-claude-extensions.md`](references/install-claude-extensions.md) | Claude Code-only plugins (skill-creator, superpowers, GSD, context-mode, claude-mem, frontend-design) installed via `/plugin install` |
| [`references/install-agent-extensions.md`](references/install-agent-extensions.md) | Cross-agent SKILL.md installers (Anthropic, Superpowers folders, Microsoft, n8n) — work in any agent |

## Skill Config Files

JSON configs that define which skills to install per source and tier. Edit these to customise your installation.

| File | Source | Default Skills |
|------|--------|----------------|
| [`install-anthropic-skills.json`](install-anthropic-skills.json) | [anthropics/skills](https://github.com/anthropics/skills) | 9 global (docx, pdf, pptx, xlsx, skill-creator, frontend-design, etc.) |
| [`install-superpowers-skills.json`](install-superpowers-skills.json) | [obra/superpowers](https://github.com/obra/superpowers) | 14 global (TDD, brainstorming, plan/execute, code review, etc.) |
| [`install-microsoft-skills.json`](install-microsoft-skills.json) | [microsoft/skills](https://github.com/microsoft/skills) | 21 global (core + Azure + Azure SDK .NET) |
| [`install-n8n-skills.json`](install-n8n-skills.json) | [czlonkowski/n8n-skills](https://github.com/czlonkowski/n8n-skills) | 7 global (all n8n workflow skills) |
| [`install-claude-plugins.json`](install-claude-plugins.json) | Claude Code marketplaces + plugin names | 5 plugins: skill-creator, superpowers, frontend-design, context-mode, claude-mem |

## Notes

- Each script is idempotent — safe to run repeatedly. It checks current state before acting.
- The skill never runs anything without user approval.
- If the user declines a step, skip it and continue. Steps are independent (except winget must exist before Steps 2–4 can use it, and Python must exist before Step 5).
- After package installs that modify PATH or environment variables, remind the user to **close and reopen all VS Code instances**. A `Developer: Reload Window` is not sufficient — the integrated terminal inherits PATH from the process that launched VS Code, so only a full restart picks up changes.
- **Upgrade error handling:** All install scripts capture winget output and exit codes. They detect common failures such as installer technology mismatches (e.g. MSI vs MSIX) and report actionable instructions instead of silently reporting "up-to-date". For existing installs, scripts use `winget upgrade` (not `winget install`) and query the available version via `winget show` for accurate comparison.
