---
name: pr-review
description: AI-assisted pull request review workflow for Azure DevOps Git repositories. Use when the user asks to review a pull request, perform a PR review, analyse PR changes, or run the PR review pipeline. Provides a complete scripted workflow to fetch PR metadata, prepare a local branch folder, export diffs, generate review reports and checklists, and post review comments back to Azure DevOps. Requires Python 3.9+ and Git.
---

# AI Pull Request Review Agent SOP (Azure DevOps + Python)

Purpose-built standard operating procedures and minimal workspace structure for an AI-assisted PR review workflow targeting Azure DevOps Git repositories using Python as the cross-platform scripting language.

For script invocation guidance, see [references/tool-instructions.md](references/tool-instructions.md).

1. Objectives

   - Provide a reproducible, minimal workspace for offline PR review artifacts.
   - Fetch and normalize diffs and changed files against a base branch.
   - Drive a consistent, checklist-led review that is easy to audit.
   - Keep authentication safe and avoid leaking PATs or secrets into logs.
   - Always confirm the existence of `pr-review.json` by first calling list_files on the workspace directory before using read_file or asking follow-up questions. This prevents assumptions about its presence.

2. Workspace layout

   The repository is organized into the following structure:

   ```text
   .
   ├── pr-review.json                      Read-only user configuration (NEVER modified)
   ├── .ai/
   │   └── skills/
   │       └── pr-review/
   │           ├── SKILL.md                         This SOP file
   │           ├── scripts/                         Python workflow scripts
   │           │   ├── review_config.py             Helper module for merged configuration
   │           │   ├── invoke_build.py              Cross-platform build wrapper (dotnet msbuild / MSBuild)
   │           │   ├── Setup_Util_TrustedRootCertificates_Save.ps1  Windows corporate cert helper
   │           │   ├── s01_reset_workspace.py       Clean previous review artifacts
   │           │   ├── s02_get_azure_devops_info.py Fetch PR and work item metadata
   │           │   ├── s03_fetch_repository.py      Prepare BranchFolder and fetch branches when PullBranch is true
   │           │   ├── s04_reset_templates.py       Create review templates with actual PR data
   │           │   ├── s05_export_diff_artifacts.py Export per-file diffs and changed files
   │           │   ├── s06_consolidate_diffs_and_content.py Consolidate patches and snapshots
   │           │   ├── s07_upsert_review_comment.py Post review comment to Pull Request
   │           │   └── s08_upsert_suggestion_threads.py Post suggestion threads to Pull Request
   │           ├── assets/                          Templates (SSOT)
   │           │   ├── review.template.md           Template for review.md
   │           │   ├── checklist.template.md        Template for checklist.md
   │           │   └── config.template.json         Template for pr-review.json
   │           └── references/
   │               └── tool-instructions.md         Python invocation rules
   └── {WorkFolder}/                    Configurable via WorkFolder in pr-review.json
       ├── review.md                    Consolidated findings and verdict (generated)
       ├── checklist.md                 Checklist and scoring rubric (generated)
       ├── context.json                 Dynamic Azure DevOps data (written by scripts)
       ├── meta.json                    Git repository metadata (written by scripts)
       ├── changes/                     Working tree copies of changed files
       ├── diffs/                       Per-file unified diff patches (path.patch)
       ├── base/                        Optional base versions of changed files
       └── branch/                      Default local PR branch folder when BranchFolder is not `.`
   ```

3. PR configuration and file structure

   The configuration system uses three separate files to maintain clean separation between user input, fetched data, and Git metadata:

   **pr-review.json** - Read-only user configuration (root of workspace)
   - This file is NEVER modified by scripts
   - Can be version controlled without dynamic data
   - Should contain as little as possible. Scripts derive Azure DevOps values from the current Git checkout first, then ask the user only for values that cannot be derived.
   - Default derived values:
     - `BaseUrl`, `OrganizationName`, `ProjectName`, and `RepoName` are parsed from `git remote get-url origin` for Azure DevOps HTTPS or SSH remotes.
     - `BranchName` is derived from the current Git branch.
     - `TargetBranchName` is derived from `origin/HEAD` and falls back to `master`.
     - `PullRequestId` is optional. If omitted, `s02_get_azure_devops_info.py` finds the active PR whose source branch is the current branch. If none or multiple active PRs are found, the workflow stops with a clear message and asks for `PullRequestId`.
     - `WorkItemIds` is optional. If omitted, `s02_get_azure_devops_info.py` reads linked work items from the PR.
     - `AzureApiVersion` defaults to `7.1`.
     - `WorkFolder` defaults to `.tmp/pr-review`.
     - `PullBranch` defaults to `false` and `BranchFolder` defaults to `.` so reviewing the current branch is the default workflow.
   - Optional override fields:
     - `BaseUrl`, `OrganizationName`, `ProjectName`, `RepoName` - only set these when the Git remote cannot be parsed.
     - `PullRequestId` - only set this when multiple/no active PRs are found for the current branch.
     - `WorkItemIds` - only set this when PR work item links are absent or incomplete.
     - `BranchName`, `TargetBranchName` - only set these when Git branch/default-branch detection is wrong.
     - `PullBranch` - set to `true` only when the scripts should clone/fetch the PR branch into a disposable checkout.
     - `BranchFolder` - local repository folder for the PR branch; use `.` to review the current workspace branch, or `.tmp/pr-review/branch` for a disposable checkout.
     - `BranchPath` - legacy alias for `BranchFolder`; prefer `BranchFolder` for new configurations.

   All artifact paths below (context.json, meta.json, review.md, diffs/, etc.) are relative to the configured `WorkFolder`. `BranchFolder` is resolved relative to the repository root unless it is absolute.

   **{WorkFolder}/context.json** - Dynamic Azure DevOps data (written by s02_get_azure_devops_info.py)
   - Created/updated by `s02_get_azure_devops_info.py`
   - Cleaned by `s01_reset_workspace.py`
   - Contains fetched PR and work item details:
     - `BranchName`, `TargetBranchName` - Branch names from PR or Git-derived defaults
     - `PullRequestId`, `PullRequestTitle`, `PullRequestDescription`, `PullRequestStatus`
     - `PullRequestCreatedBy`, `PullRequestCreatedDate`
     - `WorkItemTitle`, `WorkItemType`, `WorkItemState`, `WorkItemAssignedTo` (based on first Work Item)
     - `PullRequest` - Full PR API response object
     - `WorkItems` - Full work item API response objects
     - `WorkItem` - First work item object (for backward compatibility)

   **{WorkFolder}/meta.json** - Git repository metadata (written by s03_fetch_repository.py)
   - Created/updated by `s03_fetch_repository.py`
   - Cleaned by `s01_reset_workspace.py`
   - Contains Git-specific information for the prepared branch folder:
     - `baseCommit`, `featureCommit` - Commit SHAs
     - `timestamp` - When repository was fetched
     - `workDir` - Local repository path resolved from `BranchFolder`
     - `baseRef`, `featureRef` - Git refs used for diff export (`featureRef` is `HEAD` when `PullBranch` is `false`)
     - `pullBranch` - Effective branch-pulling mode used by `s03_fetch_repository.py`
   - Note: Branch names originate from {WorkFolder}/context.json (single source of truth from Azure DevOps API) and are copied into metadata with the effective Git refs.

   **Configuration Merging:**
   Scripts automatically derive Git/Azure DevOps defaults, then merge pr-review.json + {WorkFolder}/context.json using the `review_config.py` helper module. Context values take precedence over config values, allowing runtime overrides.

4. Prerequisites

   - Python 3.9 or newer
   - Git 2.35 or newer with Git Credential Manager enabled
   - .NET SDK (for building solutions via `invoke_build.py`)
   - Access to Azure DevOps repositories
   - Install dependencies: `pip install -r .ai/skills/pr-review/scripts/requirements.txt`
   - Current Python dependencies include `requests` and `requests-ntlm` because the Windows Integrated Authentication fallback uses NTLM helpers when no PAT or Azure CLI token is available

   Authentication methods (scripts try in this order):

   1. **Personal Access Token (PAT)** - Set `AZDO_PAT` environment variable with a PAT that has Code (Read) scope. Works on all platforms.
   2. **Azure CLI** - Uses `az account get-access-token` if Azure CLI is installed and authenticated. Cross-platform.
   3. **Windows Integrated Authentication** - Final fallback for domain-joined Windows machines.

5. Quick start using scripts

   Use the Python scripts in the `.ai/skills/pr-review/scripts/` directory to prepare the workspace and export diffs and changed files. Scripts are prefixed with execution order (s01, s02, etc.). Run them in the following order:

   Run each script as a separate command and wait for it to finish before invoking the next script. Do not chain multiple scripts together on a single command line.

   - `python .ai/skills/pr-review/scripts/s01_reset_workspace.py` - Clean previous review artifacts
   - `python .ai/skills/pr-review/scripts/s02_get_azure_devops_info.py` - Fetch PR and work item metadata
   - `python .ai/skills/pr-review/scripts/s03_fetch_repository.py` - Prepare the local branch folder; clones/fetches only when `PullBranch` is `true`
   - `python .ai/skills/pr-review/scripts/s04_reset_templates.py` - Create review templates with actual data
   - `python .ai/skills/pr-review/scripts/s05_export_diff_artifacts.py` - Export diffs and changed files
   - `python .ai/skills/pr-review/scripts/s06_consolidate_diffs_and_content.py` - Consolidate patches and generate before-and-after content snapshots
   - `python .ai/skills/pr-review/scripts/s07_upsert_review_comment.py` - Upsert review comment to Pull Request

   ## Analysis Preparation

   After running the scripts above, decide what to load based on *your available context window*.

   - If you do **not** know your context limit, assume a conservative budget of **~300KB** total input.
   - Check the output of `python .ai/skills/pr-review/scripts/s06_consolidate_diffs_and_content.py` — it prints:
     - consolidated artifact sizes, and
     - the split **part files** (names + sizes) when an artifact was too large.

   Recommended loading strategy:

   1. If it fits, load [`{WorkFolder}/all-pre-content.txt`]({WorkFolder}/all-pre-content.txt:1) (before) then [`{WorkFolder}/all-post-content.txt`]({WorkFolder}/all-post-content.txt:1) (after).
   2. If pre/post does not fit, load **part files** in order and summarize incrementally:
      - `{WorkFolder}/all-pre-content.txt.part001` → summarize → `...part002` → summarize → ...
      - then `{WorkFolder}/all-post-content.txt.part001` → summarize → ...
   3. For a diff-centric overview, load [`{WorkFolder}/all-diffs.txt`]({WorkFolder}/all-diffs.txt:1) or its parts instead of pre/post.

   Use per-file patches under `{WorkFolder}/diffs/**` or files under `{WorkFolder}/changes/**` only when you need to zoom into specific files.

   Refer to each script's `--help` for usage details.

6. Review flow
    - Think through upcoming steps deliberately and verify instructions (e.g., consult .github/copilot-instructions.md) before executing commands.
    - Prepare workspace using the quick start scripts. The s01_reset_workspace.py script cleans artifacts, then s02_get_azure_devops_info.py fetches PR data, then s03_fetch_repository.py prepares `BranchFolder` and writes Git metadata, then s04_reset_templates.py creates {WorkFolder}/review.md and {WorkFolder}/checklist.md from their respective template files with actual PR data.
    - When `PullBranch` is `false`, `BranchFolder` is treated as the already checked-out PR branch and the head ref is `HEAD`; set `BranchFolder` to `.` to review the current workspace branch.
    - If present, read `.github/copilot-instructions.md` from the target repository (`BranchFolder`) and incorporate any guidance it contains into the review process, such as which projects to test.
    - Load {WorkFolder}/all-pre-content.txt – full "before" state of all changed files
    - Load {WorkFolder}/all-post-content.txt – full "after" state of all changed files
    - Use {WorkFolder}/all-diffs.txt – concise summary of changed lines and statuses
    - Skim {WorkFolder}/diffs/changed-files.tsv to understand scope.
    - Read per-file patches under {WorkFolder}/diffs and the corresponding working files under {WorkFolder}/changes.
    - Restore/build the solution:
      - Restore first (prevents NETSDK1004 missing project.assets.json during MSBuild):
        - `dotnet restore {solution|project}`
      - Then build:
        - `python .ai/skills/pr-review/scripts/invoke_build.py {solution|project} /v:minimal /clp:Summary`
        - The build wrapper resolves the first argument to an absolute path before invoking MSBuild so the command works reliably when launched from the repository root on Windows
      - Note: `invoke_build.py` uses `dotnet msbuild` cross-platform, with full MSBuild via vswhere on Windows as an optimization for multi-targeting solutions
    - Based on guidance (e.g., copilot-instructions or changed projects), find and run the most directly related automated tests you can identify; widen scope only as risk requires.
      - Prefer repository-specific conventions first (existing test projects, test roots, framework config, and naming patterns).
      - Use one canonical mirror pattern as the first guess for both locating related tests and suggesting new ones when the repo does not expose a stronger convention:
        - Code: `{repo_path}/{project_name_path}/{code_path}/{source_name}.{source_ext}`
        - Test: `{repo_path}/Tests/{project_name_path}.Tests/{code_path}/{source_name}{test_suffix}`
        - Mirror `{code_path}` exactly under the test project.
        - Keep `{project_name_path}` stable and append `.Tests`.
        - Choose `{test_suffix}` from the source language or the repo's dominant test framework convention.
        - If the repo has a generic source container such as `src`, `Source`, `app`, or `lib`, treat that container as outside `{project_name_path}` and do not mirror it under `Tests`.
        - Default `{test_suffix}` values:
          - C#: `Tests.cs`
          - TypeScript/JavaScript: `.test.ts`, `.test.tsx`, `.test.js`, or `.test.jsx`
          - Python: `_test.py`
          - Go: `_test.go`
          - Java/Kotlin: `Test.java` or `Test.kt`
        - Example: `Repo/src/Payments/Calculations/VatCalculator.cs` -> `Repo/Tests/Payments.Tests/Calculations/VatCalculatorTests.cs`
        - Example: `Repo/web/components/Button.tsx` -> `Repo/Tests/web.Tests/components/Button.test.tsx`
      - Existing codebases often contain older tests that do not follow the canonical pattern. Use the canonical pattern as the first guess, then search for nearby deviations before concluding that no related tests exist:
        - mirror-path candidates in existing test locations
        - test files or projects named after the changed class, component, module, route, or feature
        - broader integration or UI tests only when the change crosses boundaries that unit or component tests cannot cover confidently
      - Record the exact test commands you ran and whether they passed, failed, or were blocked.
      - If no suitable automated tests exist, say so explicitly and recommend the smallest durable set of new tests that covers stable behaviour rather than the PR diff itself.
        - For each recommendation, specify the test type (for example unit, integration, UI, data, calculation), the behaviour to cover, and the most likely file or project path where it should be created, using the canonical mirror pattern unless the repo clearly uses another established layout.
        - Prefer broad, reusable regression tests over narrow temporary tests.
    - Capture findings into {WorkFolder}/review.md following the structure in assets/review.template.md.
      - **Rule**: Include actual code change suggestions (using code blocks) in the `### Suggestions` section if they are small and instantly solve a problem. Do not suggest changes just for the sake of changes.
      - In the `## Testing` section, list related tests found, tests actually run, build or validation evidence, and coverage adequacy. If no suitable automated test exists, add a `Recommended durable tests:` sub-list in that same section.
    - Complete {WorkFolder}/checklist.md following the structure in assets/checklist.template.md and compute the score.
    - Record verdict and any required follow-ups.
    - Ask user to review {WorkFolder}/review.md content before posting.
    - Upon user confirmation, run `python .ai/skills/pr-review/scripts/s07_upsert_review_comment.py` to post review comment to the Pull Request (automatically marked as resolved if approved).
    - If the review contains suggestions, run `python .ai/skills/pr-review/scripts/s08_upsert_suggestion_threads.py` to post each suggestion as a dedicated inline PR comment thread with file/line context.
      - To remove previously posted suggestion threads: `python .ai/skills/pr-review/scripts/s08_upsert_suggestion_threads.py --remove-posted`
      - Threads are identified by an agent marker so only threads created by this script are affected.

7. Review checklist

   The review checklist template is maintained in assets/checklist.template.md. This is the single source of truth for the checklist structure.

   The s04_reset_templates.py script creates {WorkFolder}/checklist.md from the template, replacing placeholders with actual values from the configuration and fetched data.

   **Template placeholders:**
   - `{PR_LINK}` - Pull request URL
   - `{BASE_BRANCH}` - Base branch name
   - `{FEATURE_BRANCH}` - Feature branch name
   - `{REPO_NAME}` - Repository name
   - `{PROJECT_NAME}` - Project name
   - `{WORK_ITEM_LINK}` - Link(s) to associated work item(s)

   The checklist includes sections for:
   - Preparation - workspace setup verification
   - Scope - change description and dependencies
   - Code quality - readability, maintainability, structure
   - Correctness - logic, edge cases, error handling
   - Security - credentials, validation, authorization
   - Performance - efficiency, algorithms, data access
   - Testing - unit tests, integration tests, coverage
   - Operations - migrations, configs, observability
   - Documentation - README, changelog, comments
   - Scoring rubric (0-5 per dimension)
   - Decision and follow-ups

8. Review report

   The review report template is maintained in assets/review.template.md. This is the single source of truth for the report structure.

   The s04_reset_templates.py script creates {WorkFolder}/review.md from the template, replacing placeholders with actual values from the configuration and fetched data.

   **Template placeholders:**
   - `{PR_LINK}` - Pull request URL
   - `{REPO_NAME}` - Repository name
   - `{PROJECT_NAME}` - Project name
   - `{BASE_BRANCH}` - Base branch name
   - `{FEATURE_BRANCH}` - Feature branch name
   - `{WORK_ITEM_LINK}` - Link(s) to associated work item(s)

   The report includes sections for:
   - Context - PR link, repository, branches
   - Summary - change overview, primary risk
   - Scope - files changed, key areas, notable changes
   - Findings - strengths, issues/risks, suggestions
   - Testing - related tests, tests run, coverage, gaps, and durable recommendations when automated coverage is missing
   - Security - credentials posture, validation, CVEs
   - Performance - hot paths, complexity, I/O patterns
   - Operations - migrations, configs, observability
   - Documentation - README, changelog, comments
   - Diff overview - references to artifacts
   - Decision - verdict and required follow-ups

9. Script interfaces specification

   **review_config.py** - Helper module for configuration management

   Functions:
   - `get_review_config()` - Load and merge pr-review.json + {WorkFolder}/context.json
   - `get_git_repository_root()` - Find Git repository root for a path
   - `assert_standalone_git_repository()` - Ensure path is a standalone Git repo root
   - `get_workspace_root()` - Locate workspace root by walking up to pr-review.json
   - `get_work_folder()` - Resolve artifact output directory from config
   - `get_branch_folder()` - Resolve the local PR branch repository folder from `BranchFolder` or legacy `BranchPath`
   - `should_pull_branch()` - Normalize the `PullBranch` setting to a boolean
   - `get_auth_headers()` - Build Azure DevOps authentication headers (PAT / Azure CLI / fallback)

   **s02_get_azure_devops_info.py** - Fetch PR and work item metadata

   Purpose: Query Azure DevOps REST API and populate {WorkFolder}/context.json with dynamic data.
   Uses settings from `pr-review.json`.

   **s03_fetch_repository.py** - Prepare the local branch folder and fetch branches when configured

   Purpose: Clone or update `BranchFolder` and fetch base/feature refs when `PullBranch` is `true`; otherwise use `BranchFolder` as an existing local checkout and compare base against `HEAD`.
   Uses settings from `pr-review.json` and `{WorkFolder}/context.json`.

   **s04_reset_templates.py** - Create review templates with actual PR data

   Purpose: Create review.md and checklist.md from templates with actual PR data.
   Uses settings from `pr-review.json` and `{WorkFolder}/context.json`.

   **s05_export_diff_artifacts.py** - Export diffs and changed files

   Purpose: Export per-file diffs, patches, and changed files for base..feature comparison.
   Uses settings from `pr-review.json` and `{WorkFolder}/context.json`.

   **s01_reset_workspace.py** - Clean previous review artifacts

   Purpose: Remove generated artifacts from previous review to prepare for new review.

   Parameters:
   - `--keep-repo` - Keep repository checkout in `BranchFolder` when it is under {WorkFolder} (faster for same repo)

   **s07_upsert_review_comment.py** - Upsert review comment to Pull Request

   Purpose: Post the content of {WorkFolder}/review.md as a comment thread on the PR.
   Uses settings from `pr-review.json` and `{WorkFolder}/context.json`.

   Parameters:
   - `--dry-run` - Print payload without posting

   **s08_upsert_suggestion_threads.py** - Upsert suggestion threads to Pull Request

   Purpose: Post suggestions as dedicated inline PR comment threads.
   Uses settings from `pr-review.json` and `{WorkFolder}/context.json`.

   Parameters:
   - `--remove-posted` - Remove previously posted suggestion threads
   - `--dry-run` - Print payloads without posting

   **invoke_build.py** - Build solutions or projects

   Purpose: Cross-platform build wrapper. Uses `dotnet msbuild` (all platforms) or full MSBuild via vswhere (Windows with Visual Studio).

   Parameters:
   - All arguments are passed through to the build tool (solution/project file path and any MSBuild switches).
   - The first argument is normalized to an absolute solution/project path before invocation.

   Examples:

   ```bash
   python .ai/skills/pr-review/scripts/invoke_build.py {solution|project} /v:minimal /clp:Summary
   python .ai/skills/pr-review/scripts/invoke_build.py MyApp.sln /p:Configuration=Release /t:Rebuild
   ```

10. Python guidance

    - Run scripts with `python script.py` from the repository root.
    - All scripts use UTF-8 without BOM for text output.
    - All scripts accept `--help` for usage information.
    - Use `pathlib.Path` for cross-platform path handling.
    - Avoid writing secrets to disk or to logs.
    - Platform-specific: `Setup_Util_TrustedRootCertificates_Save.ps1` is automatically invoked on Windows by API scripts for corporate certificate environments using a direct `powershell -File` invocation.

11. Mermaid overview

    ```mermaid
    flowchart TD
      A[Start] --> B[Setup workspace dirs]
      B --> C{PullBranch?}
      C -->|true| D[Clone/update BranchFolder and fetch base and feature]
      C -->|false| E[Use current BranchFolder HEAD]
      D --> F[List changed files]
      E --> F
      F --> G[Export diffs]
      F --> H[Export changed files]
      G --> I[Review diffs and files]
      H --> I
      I --> J[Complete checklist]
      J --> K[Record verdict]
    ```

12. Quality bar for approvals

    - No known correctness issues.
    - Security and secrets posture unchanged or improved.
    - Risk appropriate tests present or clearly ticketed with timeline.
    - Operational concerns documented and migration risks addressed.
    - Code clarity acceptable or improved.

13. Known edge cases

    - Large binary or generated files should be excluded from export; skip via --max-file-bytes.
    - Line-ending normalization may affect patch readability; set core.autocrlf consistently.
    - Submodules and LFS objects require additional steps not covered here.

14. Maintenance

    - Keep this instructions file aligned with the scripts contract.
    - Update defaults when the target repository or branches change.
    - Consider adding a small validation script to lint the exported artifacts.
