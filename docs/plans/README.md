# Plans — Reapply Bug Fixes from 4.17.0.0..master

**Context:** This branch (`revert-to-4.17.0.0-reapply-bugfixes`) was reverted to the very old `4.17.0.0` tag (Nov 2020) because the intervening UI/WPF rewrite (~371 commits) left the application in an unworkable state. The goal of this work is to cherry-pick **bug fixes only** from those 371 commits while preserving full backwards compatibility:

- **Settings file format** — millions of users have existing `Settings.xml` / `Settings.xml.gz` files; they must continue to load.
- **WebService API** — the SOAP/ASMX endpoints in `Web/WebServices/x360ce.asmx[.v3/.v4].cs` are consumed by deployed clients; the wire contract is frozen.
- **Data model** — `Data/x360ce.Data.sqlproj` is the canonical schema source of truth; Engine EDMX entities (`Engine/Data/x360ceModel.edmx`) shape is frozen.

Any commit that changes any of the above is excluded. UI changes are tolerated only if isolated and clearly bug-fix in intent.

## Decomposition (A → B → C → D)

The work is decomposed into four sub-projects, each with its own design doc and implementation plan:

| # | Sub-project | Purpose | Design |
|---|---|---|---|
| **A** | Commit Triage | Enumerate the 371 commits, auto-classify by path-bucket + risk, then (gated on C) sub-agent verdict per commit | [A-triage/design.md](A-triage/design.md) |
| **B** | Test DB Scaffolding | PowerShell scripts that build/deploy/refresh/drop `x360ce_Tests` on local SQL Server Developer Edition. DACPAC built from `Data/x360ce.Data.sqlproj` (canonical SSOT). Hard guardrail allow-list prevents writing to live `x360ce` | [B-db/design.md](B-db/design.md) |
| **C** | Test Harness | Engine.Tests + Web.Tests + App.v4.Tests + App.v3.Tests (qa-tester framework). Baselines current behaviour AND gates cherry-picks. Web.Tests depends on B; the others don't | [C-tests/design.md](C-tests/design.md) |
| **D** | First 10-fix PR | Pick 10 low-risk backwards-compatible bug fixes from A's output, cherry-pick onto current branch, validate against C, open PR | (TBD — written after C's design is approved) |

## Ordering principle

- **A.1** (heuristic triage): non-destructive, can be done any time.
- **B**: prerequisite for any DB-touching test. Implemented first because "you can't test without a database."
- **C-M1** (Engine.Tests): non-destructive AND teaches us the code. No DB dependency — can run in parallel with B.
- **C-M2** (Web.Tests): gated on B being complete (needs `x360ce_Tests` to exist).
- **C-M3 / C-M4** (App tests): no DB dependency, can run after B+C-M1.
- **A.2** (sub-agent verdicts on all 371 commits): gated on C being green.
- **D** (cherry-pick PR): gated on C being green for the relevant surface:
  - D may pick Engine-only fixes after **C-M1**.
  - D may pick Web-touching fixes after **C-M2** (and therefore B).
  - D may pick App-touching fixes after **C-M3** / **C-M4** as appropriate.

## Status

- [x] A design — drafted, user-reviewed
- [x] B design — drafted, awaiting review
- [x] C design — drafted, awaiting review
- [ ] B writing-plans → `B-db/plan.md`
- [ ] C writing-plans → `C-tests/plan.md`
- [ ] B implementation (scripts + first deploy of `x360ce_Tests`)
- [ ] C-M1 (Engine.Tests) — can begin in parallel with B
- [ ] C-M2 (Web.Tests) — after B
- [ ] C-M3 (App.v4.Tests)
- [ ] C-M4 (App.v3.Tests + full coverage + perf piggyback)
- [ ] A.1 implementation (heuristic script) — can run any time
- [ ] A.2 implementation (sub-agent verdicts) — after C green
- [ ] D design + first PR

## Key constraints baked into all sub-projects

- **`Data/x360ce.Data.sqlproj` is the canonical schema SSOT.** Any drift discovered against live is a sqlproj defect to fix; do not work around in test scripts.
- **Live `x360ce` is never written to.** All B scripts use an allow-list guardrail (`^x360ce_Tests(_\w+)?$`). The C harness re-verifies at `[AssemblyInitialize]`.
- **No real captured data in git.** Fixtures are synthetic; user-supplied real fixtures (if any) go into `Engine.Tests/Fixtures/Real/` which is initially empty.
- **Settings XML wire format is frozen.** `[XmlType("Setting")]` on `UserSetting` is a hard contract for v3.x clients still in the wild.
- **net462 reality.** EventPipe / `Microsoft.Diagnostics.NETCore.Client` don't work on .NET Framework. Use ETW (`wpr.exe`) + BenchmarkDotNet for perf instead. Microsoft.Testing.Platform is not available — VSTest only.
