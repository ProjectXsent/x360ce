# Install Claude Code Plugins (Claude-only)

This reference documents **Claude Code-specific plugins and built-ins** that cannot be cleanly copied to other agents because they rely on Claude's plugin system, slash commands, hooks, or session lifecycle. Plugins are installed via the `claude plugin` CLI subcommand — driven by [`scripts/install-claude-plugins.ps1`](../scripts/install-claude-plugins.ps1) in the onboarding skill — which writes to `~/.claude/plugins/` and is picked up by every Claude Code host (standalone CLI, VS Code native extension, JetBrains).

For **cross-agent skills** (plain `SKILL.md` folders that work in any agent), see [`install-agent-extensions.md`](install-agent-extensions.md).

## Scope: install globally (user-level)

All plugins below are intended to be installed **globally / user-scoped**, not per-project. The `claude plugin install` CLI defaults to user scope, so the install script as written already does the right thing — every project the user opens picks up the plugin without per-repo installation. The `npx get-shit-done-cc --claude --global` command makes this explicit with the `--global` flag.

## Quick install (recommended)

Run the wrapper from any terminal:

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-claude-plugins.ps1
```

Plus GSD separately:

```powershell
npx get-shit-done-cc --claude --global
```

Then **fully restart** all Claude Code hosts (close every VS Code window, terminate `claude` CLI sessions, reopen).

The wrapper reads [`install-claude-plugins.json`](../install-claude-plugins.json) and shells out to `claude plugin marketplace add` and `claude plugin install`. Edit the JSON to add or remove plugins. The CLI is required even if you primarily use the VS Code native extension — the extension cannot install plugins on its own; it only loads what the CLI registered.

The reference table below describes each plugin and equivalent slash-command-form (for users who prefer typing inside the standalone CLI prompt).

## When to use this vs. `install-agent-extensions.md`

| If you want… | Use… |
| ------------ | ---- |
| The full plugin (hooks, slash commands, MCP wiring) | This document — install via `/plugin install` inside Claude Code |
| Just the SKILL.md content, portable across agents | [`install-agent-extensions.md`](install-agent-extensions.md) |
| Both (when a project has both plugin form AND SKILL.md form) | Run the SKILL.md installer for non-Claude agents, then `/plugin install` inside Claude Code for Claude |

## Recommended plugins

Source: video [*I Tried 100+ Claude Code Skills. These 6 Are The Best*](https://www.youtube.com/watch?v=eRS3CmvrOvA) (Nate Herkelman).

### 1. skill-creator (Anthropic official)

Drafts, tests, and packages new `SKILL.md` files from plain-English descriptions. Recommended as global (user-scoped) so it is available in every project.

```text
/plugin install skill-creator@claude-plugins-official
```

> The same skill exists as a portable folder in [`anthropics/skills`](https://github.com/anthropics/skills) and is already cloned by [`install-anthropic-skills.json`](../install-anthropic-skills.json) for non-Claude agents.

### 2. superpowers (obra/superpowers)

Forces Claude into a senior-developer workflow: plan → write tests → write code → review (twice). Includes 14 sub-skills (brainstorming, TDD, subagent-driven development, systematic debugging, verification, etc.). Most-starred Claude Code skill repo at the time of writing (>150k stars).

```text
/plugin install superpowers@claude-plugins-official
```

> The underlying `skills/` folder is portable — see [`install-superpowers-skills.json`](../install-superpowers-skills.json). The plugin form adds Claude-only `commands/`, `hooks/`, and `agents/` wiring on top.

### 3. get-shit-done-cc (GSD)

Context engineering: spawns fresh sub-agents for each task with a clean context window. Adds scope-protection detection, security gates, and an autonomous mode. The `--claude` flag wires it specifically into Claude Code; remove it to run against other agents.

```powershell
npx get-shit-done-cc --claude --global
```

After install, type `/gsd-help` inside Claude Code to discover the slash commands.

### 4. /review and /ultrareview (built-in)

Built into Claude Code 2.1.86+. **No install needed.**

- `/review` — local structured code review (logic, edge cases, design issues). Cheap, runs in-session.
- `/ultrareview` — uploads the branch to Anthropic's cloud sandbox and runs a fleet of parallel reviewer agents. Each finding is independently reproduced before reporting. Free for the first three runs on Pro/Max, then ~$5–20 per run depending on size.

```text
/review
/ultrareview
```

### 5. context-mode (mksglu/context-mode)

Sandboxes every tool call so only the meaningful slice of output enters the context window (e.g. a 56 KB Playwright snapshot becomes ~299 bytes). Tracks every file edit, task, decision, and error in a local SQLite store and re-injects state after Claude compacts. Auto-installs the MCP server, hooks, and routing instructions.

```text
/plugin marketplace add mksglu/context-mode
/plugin install context-mode@context-mode
```

After install, restart Claude Code. Inspect savings with `/contextmode:ctx-stats`.

### 6. claude-mem (thedotmack/claude-mem)

Persistent memory **across sessions**. Hooks into Claude's session lifecycle, captures file edits / decisions / bug fixes / commands, summarises them via the Claude Agent SDK, and stores them in a local SQLite vector database. New sessions get the relevant slice injected automatically; folder-level `CLAUDE.md` files are auto-generated and updated as you work.

```text
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem
```

> **Warning from the repo:** do **not** run `npm install claude-mem` separately. That installs the SDK library only — the hooks never register and nothing actually works. Stick with the two `/plugin` commands above.

### Bonus: frontend-design (Anthropic official)

Makes generated UI look less AI-generated. Recommended as global. Useful inside Claude Code when you bring a Claude Design project back into the editor.

```text
/plugin install frontend-design@claude-plugins-official
```

> Also available as a portable SKILL.md in [`anthropics/skills`](https://github.com/anthropics/skills) and cloned by [`install-anthropic-skills.json`](../install-anthropic-skills.json).

## Verifying installation

From any terminal (works in CLI host and applies to VS Code extension state too — `~/.claude/plugins/` is shared):

```powershell
claude plugin list
```

Each plugin should show `Status: enabled`. The installer also runs an automatic MCP runtime validator that flags missing dependencies — see the trailing `── MCP server runtime validation ──` block.

Inside an interactive Claude Code session, slash commands should appear in `/` autocomplete. Some plugins (claude-mem, context-mode) require a host restart before hooks take effect.

## Troubleshooting

### `plugin:<name>:<mcp-name> not working`

A plugin's MCP server failed to start. Almost always a missing runtime. Check the plugin's `.mcp.json`:

```powershell
Get-ChildItem "$env:USERPROFILE\.claude\plugins\cache\<author>\<plugin>" -Recurse -Filter '.mcp.json' | ForEach-Object { Get-Content $_.FullName }
```

Look at the `command` field. If it's `bun`, `node`, `python`, `uv`, `deno`, etc., make sure that command is on PATH. Re-run `install-claude-plugins.ps1` — its validator block will list every missing runtime with an install hint. Common case: **claude-mem requires bun** (`winget install Oven-sh.Bun` or run [`scripts/install-bun.ps1`](../scripts/install-bun.ps1)).

After fixing, **fully restart** every Claude Code host (close all VS Code windows, terminate `claude` CLI sessions, reopen). MCP servers are spawned at host start; they don't auto-recover when a runtime appears later.

### `EACCES: permission denied, rm '...\plugins\cache\<plugin>'`

The plugin is currently running (its MCP server or hooks hold files open). Reinstall fails but the existing install is intact. Skip the reinstall (the installer is idempotent — it'll mark the plugin as "already installed" on the next run) or fully restart Claude Code hosts before rerunning.

### Plugin installed but slash commands missing

Restart was incomplete. "Reload Window" in VS Code is not enough — close every window and reopen. Same for `claude` CLI: exit and relaunch.

### `claude plugin list` works but VS Code extension shows nothing

Check the version: `claude --version`. Native extension and CLI must both be on a recent Claude Code build (2.1.x). Older extensions may not load plugins at all.

## Claude Code version requirements

| Feature | Minimum version |
| ------- | --------------- |
| `/plugin` marketplace and install | Claude Code 2.1.x |
| `/review` | Claude Code 2.1.x |
| `/ultrareview` | Claude Code 2.1.86+ (Opus 4.7-era release) |

Check with `claude --version` from a terminal.
