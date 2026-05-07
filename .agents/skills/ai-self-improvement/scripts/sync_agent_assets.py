#!/usr/bin/env python3
"""Sync AI agent instruction files, skills, and custom agents from master sources under `.ai/`.

Agent definitions are loaded from `agents.json` next to this script's parent folder.

Usage:
    python sync_agent_assets.py [MODE] [--global] [--no-clear]

MODE:
    ALL         Update all known agent outputs
    AUTO        Update only agents detected in this repository
    <name>      Update a specific agent (e.g. "Claude Code", "roo-code")
    (omitted)   Interactive menu

Options:
    --global    Also sync global agents (.ai/.global/agents/) AND global skills
                (.ai/.global/skills/) to user-level paths. Skills are added/updated
                without purging — to remove a skill, list it in
                .ai/.global/removed-skills.json.
    --no-clear  Do not clear the console on start

Cross-platform: runs on Windows, macOS, Linux. Requires Python 3.8+.
"""
from __future__ import annotations

import argparse
import filecmp
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Any

# ── Paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
REPO_ROOT = SCRIPT_DIR.parents[3]
AI_DIR = REPO_ROOT / ".ai"
CONFIG_PATH = SKILL_DIR / "agents.json"

EXCLUDED_DIR_NAMES = {".git", ".vs", "bin", "obj"}


# ── Utility functions ────────────────────────────────────────────────────────

def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def read_text_auto(path: Path) -> str:
    """Read text with BOM auto-detection. Returns string without BOM."""
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        return data[3:].decode("utf-8")
    if data.startswith(b"\xff\xfe"):
        return data[2:].decode("utf-16-le")
    if data.startswith(b"\xfe\xff"):
        return data[2:].decode("utf-16-be")
    return data.decode("utf-8")


def write_utf8_no_bom(path: Path, content: str) -> None:
    ensure_directory(path.parent)
    # Use binary write to guarantee no BOM and consistent newlines.
    path.write_bytes(content.encode("utf-8"))


def files_equal(a: Path, b: Path) -> bool:
    if not a.exists() or not b.exists():
        return False
    if a.stat().st_size != b.stat().st_size:
        return False
    return filecmp.cmp(str(a), str(b), shallow=False)


def copy_file_if_different(source: Path, target: Path) -> None:
    ensure_directory(target.parent)
    if not target.exists():
        shutil.copy2(source, target)
        print(f"Created: {target}")
        return
    if files_equal(source, target):
        print(f"Up-to-date: {target}")
        return
    shutil.copy2(source, target)
    print(f"Updated: {target}")


def assert_instruction_sync(source_dir: Path, target_dir: Path, source_files: list[Path]) -> None:
    for sf in source_files:
        src_path = source_dir / sf.name
        dst_path = target_dir / sf.name
        if not dst_path.is_file():
            raise RuntimeError(f"Binary comparison failed. Destination file missing: {dst_path}")
        if not files_equal(src_path, dst_path):
            raise RuntimeError(
                f"Binary comparison failed between: {src_path} and {dst_path}"
            )


def resolve_target_path(template: str) -> str:
    """Resolve {UserProfile}, {AppData}, {LocalAppData}, {Home} placeholders.

    Cross-platform: on non-Windows, {AppData} falls back to ~/.config and
    {LocalAppData} to ~/.local/share so VS Code extension paths still resolve.
    """
    home = str(Path.home())
    if os.name == "nt":
        appdata = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        local_appdata = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
        user_profile = os.environ.get("USERPROFILE") or home
    else:
        # VS Code stores user data under ~/.config on Linux and ~/Library/Application Support on macOS.
        if sys.platform == "darwin":
            appdata = str(Path.home() / "Library" / "Application Support")
            local_appdata = str(Path.home() / "Library" / "Application Support")
        else:
            appdata = str(Path.home() / ".config")
            local_appdata = str(Path.home() / ".local" / "share")
        user_profile = home

    resolved = (
        template.replace("{UserProfile}", user_profile)
        .replace("{AppData}", appdata)
        .replace("{LocalAppData}", local_appdata)
        .replace("{Home}", home)
    )
    # Normalise separators to the local OS.
    if os.name == "nt":
        resolved = resolved.replace("/", "\\")
    else:
        resolved = resolved.replace("\\", "/")
    return resolved


# ── YAML frontmatter parser ──────────────────────────────────────────────────

def read_agent_file(path: Path) -> dict[str, Any]:
    """Parse .ai/agents/*.agent.md or *.md into frontmatter fields + body.

    Only supports the subset used by this skill: scalar strings for
    name/description and inline JSON arrays for tools/groups. Matches the
    PowerShell implementation exactly.
    """
    content = read_text_auto(path)
    filename = path.name
    slug = re.sub(r"\.agent\.md$", "", filename)
    slug = re.sub(r"\.md$", "", slug)

    result: dict[str, Any] = {
        "Slug": slug,
        "Name": slug,
        "Description": "",
        "Tools": [],
        "Groups": ["read", "edit", "command"],
        "Body": content,
    }

    lines = content.split("\n")
    if len(lines) < 3 or lines[0].strip() != "---":
        return result

    closing = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            closing = i
            break
    if closing < 0:
        return result

    fm_lines = lines[1:closing]
    body_lines = lines[closing + 1:] if closing + 1 < len(lines) else []
    result["Body"] = "\n".join(body_lines).strip()

    for fm_line in fm_lines:
        trimmed = fm_line.strip()
        if not trimmed or trimmed.startswith("#"):
            continue
        colon_pos = trimmed.find(":")
        if colon_pos < 1:
            continue
        key = trimmed[:colon_pos].strip()
        val = trimmed[colon_pos + 1:].strip()

        # Strip surrounding quotes.
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]

        if key == "name":
            result["Name"] = val
        elif key == "description":
            result["Description"] = val
        elif key == "tools":
            if val.startswith("["):
                try:
                    result["Tools"] = list(json.loads(val))
                except json.JSONDecodeError:
                    pass
        elif key == "groups":
            if val.startswith("["):
                try:
                    result["Groups"] = list(json.loads(val))
                except json.JSONDecodeError:
                    pass

    return result


# ── Directory mirroring (robocopy /MIR equivalent) ──────────────────────────

def mirror_directory(source: Path, destination: Path, label: str) -> None:
    if not source.is_dir():
        print(f"No source folder found at: {source}")
        return

    ensure_directory(destination)

    print(f"\n--- Mirroring to {label} ---")
    print(f"Source:      {source}")
    print(f"Destination: {destination}")
    print("mirror <source> <destination> (excluding .git, .vs, bin, obj)")

    copied = 0
    updated = 0
    skipped = 0

    # Walk source and copy to dest.
    for root, dirs, files in os.walk(source):
        # Exclude directories in-place so os.walk skips them.
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIR_NAMES]
        rel = Path(root).relative_to(source)
        dst_root = destination / rel
        ensure_directory(dst_root)
        for fname in files:
            src_file = Path(root) / fname
            dst_file = dst_root / fname
            if dst_file.exists() and files_equal(src_file, dst_file):
                skipped += 1
                continue
            if dst_file.exists():
                updated += 1
            else:
                copied += 1
            shutil.copy2(src_file, dst_file)

    # Walk destination and delete files/dirs not present in source (mirror).
    deleted_files = 0
    deleted_dirs = 0
    for root, dirs, files in os.walk(destination, topdown=False):
        rel = Path(root).relative_to(destination)
        src_root = source / rel
        for fname in files:
            if not (src_root / fname).exists():
                dst_file = Path(root) / fname
                try:
                    dst_file.unlink()
                    deleted_files += 1
                except OSError as exc:
                    raise RuntimeError(f"Failed to delete stale mirrored file: {dst_file}") from exc
        for dname in dirs:
            dst_sub = Path(root) / dname
            src_sub = src_root / dname
            if dname in EXCLUDED_DIR_NAMES:
                continue
            if not src_sub.exists():
                try:
                    shutil.rmtree(dst_sub)
                    deleted_dirs += 1
                except OSError as exc:
                    raise RuntimeError(f"Failed to delete stale mirrored directory: {dst_sub}") from exc

    print(
        f"Mirrored to {label} "
        f"(copied={copied}, updated={updated}, up-to-date={skipped}, "
        f"removed_files={deleted_files}, removed_dirs={deleted_dirs})."
    )


# ── Additive copy / explicit-removal (for global skill activation) ───────────

def add_or_update_directory(source: Path, destination: Path, label: str) -> tuple[int, int, int]:
    """Copy source tree into destination additively (no destination-walk delete).

    Returns (copied, updated, skipped). Existing destination files not present in
    source are LEFT UNCHANGED — caller is responsible for any explicit removals.
    """
    if not source.is_dir():
        return (0, 0, 0)

    ensure_directory(destination)

    copied = 0
    updated = 0
    skipped = 0

    for root, dirs, files in os.walk(source):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIR_NAMES]
        rel = Path(root).relative_to(source)
        dst_root = destination / rel
        ensure_directory(dst_root)
        for fname in files:
            src_file = Path(root) / fname
            dst_file = dst_root / fname
            if dst_file.exists() and files_equal(src_file, dst_file):
                skipped += 1
                continue
            if dst_file.exists():
                updated += 1
            else:
                copied += 1
            shutil.copy2(src_file, dst_file)

    return (copied, updated, skipped)


def sync_global_skills(
    agent_name: str,
    src_global_skills_dir: Path,
    dst_root: Path,
    removed_list: list[str],
) -> None:
    """Activate global skills for an agent: additively copy each skill folder
    from .ai/.global/skills/{name}/ to {dst_root}/{name}/, then remove any folder
    listed in removed-skills.json.

    Pre-existing user-level skills not in source and not in removed_list are left
    alone — protects skills installed by other tools (e.g. GSD's gsd-* set).
    """
    label = f"{agent_name} GLOBAL skills"
    print(f"\n--- Activating {label} ---")
    print(f"Source:      {src_global_skills_dir}")
    print(f"Destination: {dst_root}")

    if not src_global_skills_dir.is_dir():
        print(f"No global skills source folder: {src_global_skills_dir}")
        return

    ensure_directory(dst_root)

    skill_folders = [p for p in sorted(src_global_skills_dir.iterdir())
                     if p.is_dir() and p.name not in EXCLUDED_DIR_NAMES]

    total_copied = 0
    total_updated = 0
    total_skipped = 0
    folders_promoted = 0

    for skill_dir in skill_folders:
        dst_skill_dir = dst_root / skill_dir.name
        c, u, s = add_or_update_directory(skill_dir, dst_skill_dir, skill_dir.name)
        total_copied += c
        total_updated += u
        total_skipped += s
        if c or u:
            folders_promoted += 1

    removed_count = 0
    for skill_name in removed_list:
        target = dst_root / skill_name
        if target.is_dir():
            try:
                shutil.rmtree(target)
                removed_count += 1
                print(f"  Removed (per removed-skills.json): {target}")
            except OSError as exc:
                raise RuntimeError(f"Failed to remove user-level skill: {target}") from exc

    print(
        f"Promoted to {label}: "
        f"folders_touched={folders_promoted}/{len(skill_folders)}, "
        f"files_copied={total_copied}, files_updated={total_updated}, "
        f"files_up-to-date={total_skipped}, folders_removed={removed_count}"
    )


def load_removed_skills(removed_skills_path: Path) -> list[str]:
    """Load the list of skill folder names to remove from user-level paths."""
    if not removed_skills_path.is_file():
        return []
    try:
        data = json.loads(removed_skills_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in {removed_skills_path}: {exc}") from exc
    entries = data.get("removed", [])
    names: list[str] = []
    for entry in entries:
        if isinstance(entry, str):
            names.append(entry)
        elif isinstance(entry, dict) and entry.get("skill"):
            names.append(str(entry["skill"]))
    return names


# ── Sync operations ──────────────────────────────────────────────────────────

def sync_multiple_file_instructions(agent_name: str, target_directory: str, source_files: list[Path]) -> None:
    print(f"\n--- Updating {agent_name} Instructions ---")
    target_dir = REPO_ROOT / target_directory

    for sf in source_files:
        copy_file_if_different(sf, target_dir / sf.name)

    assert_instruction_sync(AI_DIR, target_dir, source_files)


def sync_single_file_instructions(agent_name: str, target_file_path: str, source_files: list[Path]) -> None:
    print(f"\n--- Updating {agent_name} Instructions ---")
    target_file = REPO_ROOT / target_file_path
    try:
        relative_target = target_file.relative_to(REPO_ROOT)
    except ValueError:
        relative_target = target_file

    parts: list[str] = []
    first = True
    for sf in source_files:
        source_content = read_text_auto(sf)
        if not source_content.strip():
            print(f"WARNING: Skipping empty file: {sf.name}")
            continue
        if not first:
            parts.append("")
        parts.append(f"==== START OF INSTRUCTIONS FROM: {sf.name} ====")
        parts.append("")
        parts.append(f"# Instructions from: {sf.name}")
        parts.append("")
        parts.append(source_content.strip())
        parts.append("")
        parts.append(f"==== END OF INSTRUCTIONS FROM: {sf.name} ====")
        first = False

    # PowerShell AppendLine uses "\r\n" on Windows; match line-ending behaviour
    # by emitting native newlines. We use LF for cross-platform consistency — the
    # PS script used \r\n on Windows but Git on Windows typically normalises.
    # To preserve Windows parity, use \r\n when on Windows, else \n.
    newline = "\r\n" if os.name == "nt" else "\n"
    final_content = newline.join(parts) + newline

    existing = read_text_auto(target_file) if target_file.is_file() else None
    if existing is not None and existing == final_content:
        print(f"Up-to-date: {relative_target}")
        return

    write_utf8_no_bom(target_file, final_content)
    print(f"Updated: {relative_target}")


def sync_copilot_folder_instructions(instructions_config: dict, source_files: list[Path]) -> None:
    print("\n--- Updating GitHub CoPilot Instructions (folder-based) ---")

    main_name = instructions_config.get("mainFile")
    main_source = next((sf for sf in source_files if sf.name.lower() == str(main_name).lower()), None)
    if main_source is None:
        raise RuntimeError(f"Expected source '{main_name}' under .ai but none found.")

    copilot_target = REPO_ROOT / instructions_config["target"]
    copy_file_if_different(main_source, copilot_target)

    folder_target = REPO_ROOT / instructions_config["folderTarget"]
    for sf in source_files:
        if sf.name.lower() == str(main_name).lower():
            continue
        copy_file_if_different(sf, folder_target / sf.name)


def build_roomodes_json(source_directory: Path, label: str) -> str:
    agent_files = sorted(source_directory.glob("*.agent.md"))
    if not agent_files:
        print(f"  No agent files found in: {source_directory}")
        return json.dumps({"customModes": []}, indent=2)

    modes: list[dict[str, Any]] = []
    for af in agent_files:
        parsed = read_agent_file(af)
        print(f"  [{label}] {parsed['Name']} (slug: {parsed['Slug']})")
        modes.append({
            "slug": str(parsed["Slug"]),
            "name": str(parsed["Name"]),
            "roleDefinition": str(parsed["Description"]),
            "customInstructions": str(parsed["Body"]),
            "groups": [str(g) for g in parsed["Groups"]],
        })

    return json.dumps({"customModes": modes}, indent=2)


def sync_agents_to_target(
    agent_name: str,
    source_directory: Path,
    target_path: str,
    fmt: str = "mirror",
    label: str = "",
) -> None:
    if not source_directory.is_dir():
        print(f"No agent source folder: {source_directory}")
        return

    agent_files = list(source_directory.glob("*.agent.md"))
    if not agent_files:
        return

    if not label:
        label = agent_name

    if fmt == "roomodes-json":
        print(f"\n--- Building {label} custom modes ({target_path}) ---")
        new_json = build_roomodes_json(source_directory, label)
        target_file = Path(target_path)
        existing = read_text_auto(target_file) if target_file.is_file() else None
        if existing is not None and existing.strip() == new_json.strip():
            print(f"Up-to-date: {target_path}")
        else:
            write_utf8_no_bom(target_file, new_json)
            print(f"Updated: {target_path}")
    else:
        mirror_directory(source_directory, Path(target_path), f"{label} agents")


# ── Agent detection (AUTO mode) ──────────────────────────────────────────────

def test_has_instruction_files(path: Path, pattern: str = "*instructions.md") -> bool:
    if not path.is_dir():
        return False
    return any(path.glob(pattern))


def test_agent_exists(agent: dict) -> bool:
    instr = agent["instructions"]
    target = REPO_ROOT / instr["target"]
    mode = instr["mode"]
    if mode == "multiple-files":
        return test_has_instruction_files(target)
    if mode == "single-file":
        return target.is_file()
    return False


def get_agent_format(config_obj: dict | None) -> str:
    if not config_obj:
        return "mirror"
    return config_obj.get("format") or "mirror"


# ── Main logic ───────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sync AI agent instructions, skills, and custom agents from .ai/ sources.",
        allow_abbrev=False,
    )
    parser.add_argument("mode", nargs="*", help="ALL | AUTO | <agent name> | (omit for menu)")
    parser.add_argument("--global", dest="global_flag", action="store_true",
                        help="Also sync global agents to user-level paths")
    parser.add_argument("--no-clear", action="store_true", help="Do not clear the console")
    args = parser.parse_args()

    mode = " ".join(args.mode).strip() if args.mode else ""
    global_flag = args.global_flag

    if not args.no_clear:
        # Cross-platform "clear".
        os.system("cls" if os.name == "nt" else "clear")

    if not CONFIG_PATH.is_file():
        raise FileNotFoundError(f"Agent configuration not found: {CONFIG_PATH}")
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))

    source_instruction_files = sorted(AI_DIR.glob("*instructions.md"))
    if not source_instruction_files:
        print(f"WARNING: No '*instructions.md' files found in '{AI_DIR}'. Nothing to process.")
        return 0

    print(f"Source instruction files in '{AI_DIR}':")
    for sf in source_instruction_files:
        print(f"- {sf.name}")

    src_skills_dir = REPO_ROOT / ".ai" / "skills"
    src_agents_dir = REPO_ROOT / ".ai" / "agents"
    src_global_agents_dir = REPO_ROOT / ".ai" / ".global" / "agents"
    src_global_skills_dir = REPO_ROOT / ".ai" / ".global" / "skills"
    removed_skills_path = REPO_ROOT / ".ai" / ".global" / "removed-skills.json"

    if global_flag:
        print("\nGlobal agent + skills sync: ENABLED (--global flag)")

    all_agents: list[dict] = config["agents"]
    agents_to_update: list[dict] = []

    mode_upper = mode.upper()
    if mode_upper == "ALL":
        print("Selected: ALL (parameter mode)")
        agents_to_update = list(all_agents)
    elif mode_upper == "AUTO":
        print("Selected: AUTO (parameter mode)")
        agents_to_update = [a for a in all_agents if test_agent_exists(a)]
        print("Agents to update:")
        for a in agents_to_update:
            print(f"- {a['name']}")
    elif mode == "":
        detected = [a for a in all_agents if test_agent_exists(a)]
        print("\nDetected agents with instruction files:")
        if detected:
            for a in detected:
                print(f"- {a['name']}")
        else:
            print("(none)")

        print()
        print("==============================================================")
        print("Select Agent Instruction Set to Update")
        print("--------------------------------------------------------------")
        print("1. AUTO           - Update detected agents (project level only)")
        print("2. AUTO + Global  - Update detected agents + global agents")
        print("3. ALL            - Update all agents (project level only)")
        print("4. ALL + Global   - Update all agents + global agents")
        print("--------------------------------------------------------------")
        for i, agent in enumerate(all_agents, start=5):
            print(f"{i}. {agent['name']}")
        print("0. Exit")
        print("==============================================================")
        print()
        selection = input("Enter your choice: ").strip()

        if selection == "0":
            print("Operation cancelled.")
            return 0
        if selection == "1":
            agents_to_update = detected
            print("Selected: AUTO")
        elif selection == "2":
            agents_to_update = detected
            global_flag = True
            print("Selected: AUTO + Global")
        elif selection == "3":
            agents_to_update = list(all_agents)
            print("Selected: ALL")
        elif selection == "4":
            agents_to_update = list(all_agents)
            global_flag = True
            print("Selected: ALL + Global")
        else:
            try:
                idx = int(selection) - 5
            except ValueError:
                raise RuntimeError("Invalid selection.")
            if 0 <= idx < len(all_agents):
                agents_to_update = [all_agents[idx]]
                print(f"Selected: {all_agents[idx]['name']}")
            else:
                raise RuntimeError("Invalid selection.")
    else:
        found = next(
            (a for a in all_agents if a["name"].lower() == mode.lower() or a.get("id", "").lower() == mode.lower()),
            None,
        )
        if found is None:
            valid = ", ".join(a["name"] for a in all_agents)
            raise RuntimeError(f"Unknown agent '{mode}'. Valid agents: {valid}")
        agents_to_update = [found]
        print(f"Selected: {found['name']} (parameter mode)")

    # ── Sync each agent (project level) ─────────────────────────────────────

    for agent in agents_to_update:
        instr = agent["instructions"]
        mode_val = instr["mode"]

        if mode_val == "multiple-files":
            sync_multiple_file_instructions(agent["name"], instr["target"], source_instruction_files)
        elif mode_val == "single-file":
            folder_target = instr.get("folderTarget")
            if folder_target and (REPO_ROOT / folder_target).is_dir():
                sync_copilot_folder_instructions(instr, source_instruction_files)
            else:
                sync_single_file_instructions(agent["name"], instr["target"], source_instruction_files)

        skills = agent.get("skills")
        if skills and skills.get("target"):
            dst_skills_dir = REPO_ROOT / skills["target"]
            mirror_directory(src_skills_dir, dst_skills_dir, f"{agent['name']} skills ({skills['target']})")

        agents_cfg = agent.get("agents")
        if agents_cfg and agents_cfg.get("target"):
            proj_target = str(REPO_ROOT / agents_cfg["target"])
            proj_format = get_agent_format(agents_cfg)
            sync_agents_to_target(agent["name"], src_agents_dir, proj_target, proj_format, f"{agent['name']} project")

    # ── Global agent sync (only with --global flag) ─────────────────────────

    if global_flag:
        print("\n==============================================================")
        print("Global Agent Sync")
        print("==============================================================")

        if not src_global_agents_dir.is_dir():
            print(f"No global agents source folder: {src_global_agents_dir}")
        else:
            global_files = list(src_global_agents_dir.glob("*.agent.md"))
            print(f"Global agent source files ({len(global_files)}):")
            for gf in global_files:
                print(f"- {gf.name}")

            for agent in agents_to_update:
                ga_cfg = agent.get("globalAgents")
                if not ga_cfg or not ga_cfg.get("target"):
                    continue
                ga_target = resolve_target_path(ga_cfg["target"])
                ga_format = get_agent_format(ga_cfg)
                sync_agents_to_target(
                    agent["name"], src_global_agents_dir, ga_target, ga_format, f"{agent['name']} GLOBAL"
                )

    # ── Global skills sync (only with --global flag) ────────────────────────

    if global_flag:
        print("\n==============================================================")
        print("Global Skills Sync")
        print("==============================================================")

        removed_list = load_removed_skills(removed_skills_path)
        if removed_list:
            print(f"Skills marked for removal in {removed_skills_path.name}: "
                  f"{', '.join(removed_list)}")

        any_target = False
        for agent in agents_to_update:
            gs_cfg = agent.get("globalSkills")
            if not gs_cfg or not gs_cfg.get("target"):
                continue
            any_target = True
            gs_target = Path(resolve_target_path(gs_cfg["target"]))
            sync_global_skills(agent["name"], src_global_skills_dir, gs_target, removed_list)

        if not any_target:
            print("No agents have a globalSkills.target configured. Skipping.")

    print("\nAll selected operations completed successfully.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
