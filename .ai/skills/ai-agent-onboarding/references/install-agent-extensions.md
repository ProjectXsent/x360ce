# Install Cross-Agent Skills (any agent)

This reference documents skills distributed as plain `SKILL.md` folders that any agent can consume — Claude Code, RooCode, GitHub Copilot, Cline, Codex, Cursor, etc. Installation is "clone the source repo and copy the skill folder into `.ai/.global/skills/` or `.ai/skills/`"; the existing sync pipeline then mirrors them into agent-specific folders (`.roo/skills/`, `.claude/skills/`, `.github/skills/`).

For **Claude-only plugins** (hooks, slash commands, MCP wiring) that cannot be cleanly extracted, see [`install-claude-extensions.md`](install-claude-extensions.md).

## When to use this vs. `install-claude-extensions.md`

| If you want… | Use… |
| ------------ | ---- |
| Skills that work on every agent in the repo | This document |
| Just the SKILL.md content, even from a Claude plugin repo | This document — only the `skills/` folders are copied |
| The full Claude plugin with hooks and slash commands | [`install-claude-extensions.md`](install-claude-extensions.md) |

## How cross-agent installation works

All cross-agent installers follow the same pattern, driven by a JSON config:

1. JSON config lists `source.organisation`, `source.repo`, `source.branch`, plus `global` and `project` arrays of `{ "skill": "name", "path": "skills/name" }` entries.
2. The PowerShell wrapper calls a shared `install-core.ps1` that shallow-clones the source repo into a temp directory.
3. Each skill folder is copied to:
   - `.ai/.global/skills/{skill}/` — global tier, available repo-wide, **not** synced to agent folders
   - `.ai/skills/{skill}/` — project tier, synced to `.roo/skills/`, `.claude/skills/`, `.github/skills/` by `ai-self-improvement`'s sync pipeline
4. Move entries between `global` and `project` arrays to change the install tier.

Common parameters on every installer:

- `-Tier global|project|all` (default `all`)
- `-DryRun` (preview without copying)
- `-RepoRoot <path>` (override target repo)

## Available installers

### Anthropic skills

Source: [`anthropics/skills`](https://github.com/anthropics/skills) — official Anthropic skill library.

Config: [`install-anthropic-skills.json`](../install-anthropic-skills.json)

Default global skills: `algorithmic-art`, `doc-coauthoring`, `docx`, `frontend-design`, `mcp-builder`, `pdf`, `pptx`, `skill-creator`, `xlsx`.

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-anthropic-skills.ps1
```

`skill-creator` and `frontend-design` are also recommended in their plugin form for Claude users — see [`install-claude-extensions.md`](install-claude-extensions.md).

### Superpowers skills

Source: [`obra/superpowers`](https://github.com/obra/superpowers) — Jesse Vincent's agentic-skills framework. Repo bundles a Claude plugin AND a portable `skills/` folder; this installer copies only the portable folder.

Config: [`install-superpowers-skills.json`](../install-superpowers-skills.json)

Default global skills (14): `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`.

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-superpowers-skills.ps1
```

> If you want the Claude plugin form (with `commands/`, `hooks/`, `agents/` wiring), use `/plugin install superpowers@claude-plugins-official` instead — see [`install-claude-extensions.md`](install-claude-extensions.md). You can run both: SKILL.md folders for non-Claude agents, plugin for Claude Code.

### Microsoft skills

Source: [`microsoft/skills`](https://github.com/microsoft/skills) — Azure, .NET, cloud architecture, SDK skills.

Config: [`install-microsoft-skills.json`](../install-microsoft-skills.json)

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-microsoft-skills.ps1
```

### n8n skills

Source: [`czlonkowski/n8n-skills`](https://github.com/czlonkowski/n8n-skills) — n8n workflow automation, expressions, validation, node configuration.

Config: [`install-n8n-skills.json`](../install-n8n-skills.json)

```powershell
.\.ai\skills\ai-agent-onboarding\scripts\install-n8n-skills.ps1
```

## Customising

Edit the JSON config to:

- Add/remove skills (look in the source repo's `skills/` folder for the available names).
- Move entries between `global` (repo-wide, not synced) and `project` (synced to all agent folders).
- Override a skill's `path` when the source repo doesn't follow `skills/{name}/`.

Example entry:

```json
{ "skill": "my-skill", "path": "custom/path/in/repo/my-skill" }
```

If `path` is omitted, defaults to `skills/{skill}`.

## Verifying installation

After running an installer, check:

```powershell
Get-ChildItem .ai\.global\skills, .ai\skills -Directory | Select-Object FullName
```

Project-tier skills should appear in the agent-specific folders after the sync pipeline runs:

```powershell
python .\.ai\skills\ai-self-improvement\scripts\sync_agent_assets.py AUTO
```

## Activating global skills (user-level)

Skills installed into `.ai/.global/skills/{name}/` by the installers above are NOT yet active — they're staged in the repo. To activate them so an agent loads them across every project, copy them up to user-level paths:

```powershell
python .\.ai\skills\ai-self-improvement\scripts\sync_agent_assets.py AUTO --global
```

This walks each agent's `globalSkills.target` from `agents.json` (e.g. Claude Code → `{UserProfile}/.claude/skills/`) and copies each skill folder additively. Pre-existing user-installed skills not present in `.ai/.global/skills/` are **left alone** — `/MIR/PURGE` is intentionally not used because tools like GSD install their own skills directly into the same user-level folder.

### Removing a global skill

To drop a skill from user-level paths, add it to `.ai/.global/removed-skills.json`:

```json
{
  "removed": [
    { "skill": "old-skill-name", "reason": "no longer needed", "date": "2026-05-03" }
  ]
}
```

The next `--global` sync deletes the folder from every agent's `globalSkills.target` (idempotent — entries can stay forever). Removing the entry from the JSON does NOT restore the skill; rerun the corresponding `install-*-skills.ps1` to put it back into `.ai/.global/skills/`.

### Per-agent target paths (`globalSkills.target`)

Set in [`.ai/skills/ai-self-improvement/agents.json`](../../ai-self-improvement/agents.json):

| Agent | `globalSkills.target` |
| ----- | --------------------- |
| Claude Code | `{UserProfile}/.claude/skills` |
| Roo Code | `null` (path TBD — verify before enabling) |
| Cline | `null` (path TBD — verify before enabling) |
| GitHub Copilot | `null` (no user-level skills folder concept) |
| OpenAI Codex | `null` (no skills concept) |

Set the path for an agent and rerun `--global` to extend coverage.
