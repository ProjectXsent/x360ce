# Sub-project B — Test Database Scaffolding (design)

**Date:** 2026-05-12 (initial); current cycle 2026-05-16.
**Status:** Draft — awaiting user review.
**Parent:** `docs/plans/README.md` (A → **B** → C → D decomposition)
**Skill anchors:** `qa-tester` §3 (database integration), `solution-patterns` (SQL Data project is canonical).

## 1. Goal

Provide scripts that **create, refresh, seed, and drop** a local test database called `x360ce_Tests`, sitting beside the developer's live-clone `x360ce` database on the same Microsoft SQL Server Developer Edition instance at `localhost`.

The test DB is the prerequisite for sub-project C.2 (`Web.Tests`). The live-clone `x360ce` database is **read-only reference**; no test ever writes to it.

This sub-project ships as a one-milestone PR (no UI surface, no test code — just deployment infrastructure).

## 2. Why this sub-project exists

Sub-project C's test harness needs a DB to talk to. The developer's live-clone database:
- Contains real (if anonymized) user data — IDs we must not expose, never modify in tests.
- Runs on Developer Edition with CLR registered, full SQL Server feature surface — `SqlLocalDB` would not run CLR procs.
- Is too valuable to risk a fat-finger from a test.

So we build a second DB (`x360ce_Tests`) from the same canonical schema source, seeded with synthetic fixtures, with **hard guardrails** preventing any script from writing to `x360ce`.

## 3. Tooling — what we use and why

| Concern | Tool | Why |
|---|---|---|
| Schema package format | **DACPAC** | Industry standard; handles tables, views, procs, UDTs, CLR assemblies, and seed scripts (pre-/post-deploy) in one file. |
| Schema build | **MSBuild against `Data/x360ce.Data.sqlproj`** | The sqlproj is the canonical source (per `solution-patterns`). Build emits `Data/bin/{Config}/x360ce.Data.dacpac`. |
| Deploy / drop / diff | **`SqlPackage.exe`** | Ships with Visual Studio (SSDT) or as standalone Microsoft download. Same tool Microsoft uses internally. Supports `/Action:Publish`, `/Action:DeployReport`, `/Action:Extract`. |
| Orchestration | **PowerShell** (.ps1) | Native to Windows dev env (per user memory: terminal is PowerShell). No extra runtime. |
| Live-clone read-only diff | `SqlPackage /Action:DeployReport` against live | Read-only — produces an HTML diff without modifying live. Optional safety check. |

**No NuGet packages, no Python, no Docker.** Everything is in-box on a dev machine that already has Visual Studio + SQL Server Developer Edition installed.

## 4. Scripts shipped

All under `scripts/db/`. Each is independently runnable from a PowerShell prompt at the repo root. Each prints its action in plain English before executing.

| Script | Action | Targets `x360ce` (live)? | Targets `x360ce_Tests`? |
|---|---|---|---|
| `Build-TestDbDacpac.ps1` | Builds `Data/x360ce.Data.sqlproj` in Release; locates the DACPAC | No | No |
| `Deploy-TestDb.ps1` | Publishes DACPAC to `x360ce_Tests`; runs seed scripts | NEVER (guardrail) | Write |
| `Refresh-TestDb.ps1` | Re-publish DACPAC (incremental — SqlPackage handles diff) + re-seed | NEVER | Write |
| `Drop-TestDb.ps1` | Drops `x360ce_Tests` with confirmation prompt | NEVER | Drop |
| `Seed-TestDb.ps1` | Runs SQL files in `scripts/db/seed/*.sql` against `x360ce_Tests` | NEVER | Write |
| `Compare-TestDbToLive.ps1` | Diffs `x360ce_Tests` schema vs `x360ce` schema; prints/HTMLs the report | Read-only | Read-only |
| `Verify-TestDbName.ps1` | Internal helper imported by all write scripts; throws if target db name fails allow-list | n/a | n/a |

### 4.1 The guardrail

`Verify-TestDbName.ps1` exports `Assert-TestDbAllowed`:

```powershell
function Assert-TestDbAllowed {
    param([Parameter(Mandatory)][string]$Database)
    if ($Database -notmatch '^x360ce_Tests(_\w+)?$') {
        throw "REFUSED. Database name '$Database' is not in the test allow-list (^x360ce_Tests(_\w+)?$). " +
              "This guard prevents tests from writing to the live x360ce database."
    }
}
```

Every write script imports this and calls it before any destructive `SqlPackage` or `Invoke-Sqlcmd` action. The check is also wired into MSTest's `[AssemblyInitialize]` in `Web.Tests` (sub-project C) — the test harness aborts at startup if the resolved connection-string database isn't allow-listed.

### 4.2 Connection string contract

Test DB connection (used by `Web.Tests/app.config` and the scripts):

```
data source=localhost;initial catalog=x360ce_Tests;persist security info=True;Integrated Security=True;multipleactiveresultsets=True
```

Identical to the user's dev connection except `initial catalog=x360ce_Tests`.

## 5. Seed strategy

Minimal **synthetic** fixtures only. **No real captured data.** Files committed under `scripts/db/seed/`.

> **Interim status (user note 2026-05-16):** `Data/x360ce.Data.sqlproj` is the canonical SSOT (per `solution-patterns`) and currently contains **schema only**. The user plans to add default data (content) into the sqlproj later via post-deployment scripts, shared with the installer (so a user can reset their installation DB the same way our tests reset `x360ce_Tests`). When that happens:
> - `scripts/db/seed/*.sql` is **deprecated**.
> - `Deploy-TestDb.ps1` stops calling `Seed-TestDb.ps1` — the sqlproj's post-deploy already seeds.
> - The synthetic-only invariant remains: any content added to the sqlproj must be synthetic, suitable for both tests and a fresh installer.
>
> Until then, the seed files below are the temporary mechanism.

Files committed under `scripts/db/seed/`:

| File | Inserts | Notes |
|---|---|---|
| `01_vendors.sql` | 3 fake vendor rows: `0xDEAD/Test Vendor A`, `0xBEEF/Test Vendor B`, `0xC0DE/Test Vendor C` | Synthetic VIDs that obviously don't match any real manufacturer |
| `02_products.sql` | 3 products, one per fake vendor | PIDs equally fake |
| `03_users.sql` | 1 test computer + 1 test user account `TestUserAccount` with a fixed GUID `00000000-0000-0000-0000-000000000001` | Single-user scenario; tests that need more create users on the fly with random GUIDs |
| `04_programs.sql` | 3 fake game entries: `TestGame.A`, `TestGame.B`, `TestGame.C` | For SearchPrograms / SetProgram tests |

All inserts wrapped in `IF NOT EXISTS` so re-running `Seed-TestDb.ps1` is idempotent.

### Why this matters
Tests in `Web.Tests` need referenced rows (FK constraints across `UserSetting → UserDevice → UserComputer`, etc.). Seeding once at deploy time + per-test random GUIDs keeps tests isolated **and** lets us assert on stable IDs when we want to (e.g. `TestUserAccount`).

### What's NOT seeded
- No `UserSetting` / `UserGame` / `PadSetting` rows — those are created and torn down per test.
- No data from the live clone, ever. The seed scripts are checked in; live data is not.

## 6. Script behaviour details

### `Build-TestDbDacpac.ps1`
```
$msbuild = "$env:VSINSTALLDIR\MSBuild\Current\Bin\MSBuild.exe"
& $msbuild "Data\x360ce.Data.sqlproj" /p:Configuration=Release /v:minimal
Get-ChildItem "Data\bin\Release\x360ce.Data.dacpac"
```
Exits non-zero on build failure. Locates and prints the DACPAC absolute path.

### `Deploy-TestDb.ps1`
Steps:
1. Import `Verify-TestDbName.ps1` and call `Assert-TestDbAllowed -Database "x360ce_Tests"`.
2. Locate `SqlPackage.exe` (search known VS install paths; fall back to `Get-Command sqlpackage`).
3. If DACPAC is missing, run `Build-TestDbDacpac.ps1`.
4. `SqlPackage /Action:Publish /SourceFile:...x360ce.Data.dacpac /TargetServerName:localhost /TargetDatabaseName:x360ce_Tests /TargetTrustServerCertificate:True`
5. Call `Seed-TestDb.ps1`.
6. Print "Deployed x360ce_Tests at <timestamp>" — caller-visible success line.

Exit codes: 0 success, 1 build/deploy failure, 2 guardrail trip.

### `Drop-TestDb.ps1`
Steps:
1. Call `Assert-TestDbAllowed -Database "x360ce_Tests"`.
2. Prompt: `Drop database x360ce_Tests on localhost? (yes/NO)`. Unless `-Force` is passed.
3. `Invoke-Sqlcmd -ServerInstance localhost -Query "ALTER DATABASE x360ce_Tests SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE x360ce_Tests;"`

### `Refresh-TestDb.ps1`
Just runs `Drop-TestDb.ps1 -Force` then `Deploy-TestDb.ps1`. Convenience.

### `Compare-TestDbToLive.ps1` (read-only on live)
1. `Assert-TestDbAllowed -Database "x360ce_Tests"` — paranoid check we aren't comparing the wrong way around.
2. `SqlPackage /Action:DeployReport /SourceFile:...x360ce.Data.dacpac /TargetServerName:localhost /TargetDatabaseName:x360ce /OutputPath:report.xml`
   This produces a *report* of what would change if we were to deploy. We never run `/Action:Publish` against `x360ce`.
3. Parses report.xml and prints a human-readable summary: "Operations: 14 (Create: 0, Alter: 12, Drop: 2)" — drift signal.

Output: `scripts/db/reports/drift-<timestamp>.xml` + console summary. Suggests running `Refresh-TestDb.ps1` if drift detected against test DB.

## 7. CLR assemblies caveat

If the live `x360ce` database has CLR assemblies registered that are **not** in `Data/x360ce.Data.sqlproj`, those won't be in the DACPAC and won't be in `x360ce_Tests`. Tests that call those procs will fail.

**Recovery procedure (documented, not automated):**
1. `Compare-TestDbToLive.ps1` reveals the missing CLR.
2. User adds the CLR (`CREATE ASSEMBLY ...`) to the sqlproj — `Data/dbo/Assemblies/` is the conventional location.
3. Rebuild sqlproj; redeploy.

This keeps the sqlproj as canonical SSOT (per `solution-patterns`) without manual deviation.

## 8. Prerequisites (documented, not enforced by scripts)

- **SQL Server Developer Edition** (or higher) running on `localhost`. Express won't work — no CLR.
- **`SqlPackage.exe`** in PATH or at a known VS install location. Standalone download: https://learn.microsoft.com/sql/tools/sqlpackage-download.
- **Windows authentication** with sysadmin (or at least `dbcreator`) on the local instance.
- **Visual Studio with SQL Server Data Tools (SSDT)** to build the sqlproj. (Already required by the repo.)

Scripts auto-detect SqlPackage; if missing, they print an actionable error: "Install SqlPackage from https://aka.ms/sqlpackage-windows or via `winget install Microsoft.SqlPackage`."

## 9. Out of scope for B

- Test code. That's sub-project C.
- Modifying `Data/x360ce.Data.sqlproj` schema. If drift is detected, **user** updates the sqlproj.
- Encryption / sanitization of fixture data. The seed scripts are committed source — keep them synthetic.
- Cross-machine portability. Hard-coded `localhost`. If you ever switch to a remote dev server, the scripts add a `-Server` parameter.

## 10. Failure modes and recovery

| Failure | Detection | Recovery |
|---|---|---|
| `SqlPackage.exe` not found | Script logs path search results | Install per §8 prereq |
| Build of sqlproj fails | MSBuild exit code | Open Data project in VS; fix; rerun |
| Deploy fails on permission | SqlPackage error | Grant `dbcreator` to the dev account; rerun |
| Drift detected vs live | `Compare-TestDbToLive.ps1` summary | User updates sqlproj; rebuilds; redeploys |
| `x360ce` (live) appears anywhere a write is attempted | `Assert-TestDbAllowed` throws | Script aborts; no DB change |
| Test mid-flight leaves rows in `x360ce_Tests` | n/a | `Refresh-TestDb.ps1` clean-slates the test DB in ~30 s |

## 11. Spec self-review

- [x] No TBDs / placeholders.
- [x] All write scripts gated by `Assert-TestDbAllowed`.
- [x] Live DB never written to (only `/Action:DeployReport` against live, which is read-only).
- [x] Schema source named (sqlproj-built DACPAC).
- [x] Seed strategy explicitly synthetic.
- [x] Recovery procedures specified for the known failure modes.
- [x] Out-of-scope items listed explicitly so C's design can reference them.

## 12. Open question

- **CLR assemblies in the sqlproj** — confirm whether `Data/x360ce.Data.sqlproj` currently includes them. If yes, B is straightforward. If no, B's first task is to **add the CLR to the sqlproj** before any deploy makes sense. I haven't read every file in `Data/` yet — I'll grep during implementation to find out.

## 13. Next steps

1. User reviews this design.
2. Update C's design.md to reference B (replace prior SqlLocalDB plan with B's scripts + `x360ce_Tests` connection string). Already queued.
3. Invoke `writing-plans` skill for B's implementation plan.
4. Implement B (single milestone). Verify on user's dev machine: `Deploy-TestDb.ps1` produces a working `x360ce_Tests`, tests run against it, `Drop-TestDb.ps1` cleans up.
5. Unblock C.2 (Web.Tests).
