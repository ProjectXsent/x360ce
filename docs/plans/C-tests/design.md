# Sub-project C — Test Harness (design)

**Date:** 2026-05-12 (initial); current cycle 2026-05-16 (renumbered from B → C after inserting B = DB scaffolding).
**Status:** Draft — awaiting user review.
**Parent:** `docs/plans/README.md` (A → B → **C** → D decomposition)
**Skill anchors:** `qa-tester`, `solution-patterns`
**Depends on:** sub-project **B** (`docs/plans/B-db/design.md`) for the `x360ce_Tests` database used by `Web.Tests`. Other test projects (`Engine.Tests`, `App.v3.Tests`, `App.v4.Tests`) do not depend on B and can begin immediately.

## 1. Goal

Build a test harness that establishes a **baseline of current behaviour** AND acts as the **gate** that every cherry-picked bug fix (sub-project D) must pass.

Two roles in one suite:

1. **Baseline.** The reverted-to-4.17.0.0 code has known issues (e.g. crashes on rapid clicks). Tests capture the current state — including what doesn't work — so we know what we're starting from.
2. **Gate.** No commit from sub-project D lands unless it passes the relevant tests on the current branch and on the post-fix branch. Settings and API are the hard contracts (millions of users).

Per user direction: **settings + data services are the highest priority** (`Engine.Tests`, `Web.Tests`). UI stress and perf come after.

## 2. Test projects (qa-tester §5.1 + solution-patterns)

Four sibling projects, mirroring the four product projects:

| Test project | Product project | Target | Purpose |
|---|---|---|---|
| `Engine.Tests/` | `Engine/` | net462 | Settings XML round-trip; data-model shape; pure-business-rule unit tests |
| `Web.Tests/` | `Web/` | net462 | `x360ce.asmx[.v3/.v4].cs` WebMethods, full CRUD round-trip against SqlLocalDB |
| `App.v4.Tests/` | `App.v4/` | net462 | `System.Windows.Automation` UIA, golden flows, rapid-click stress |
| `App.v3.Tests/` | `App.v3/` | net462 | UIA parity with App.v4.Tests (per user: full parity, not smoke) |

**Naming:** csproj files keep the org prefix (`x360ce.Engine.Tests.csproj`, `x360ce.Web.Tests.csproj`, `x360ce.App.v3.Tests.csproj`, `x360ce.App.v4.Tests.csproj`) — matches the existing repo convention (project filenames are dotted, folder names are stripped of the `x360ce.` prefix per the May 2026 rename).

**Folder mirror (qa-tester §5.2):** test files mirror product paths 1:1 with `Tests.cs` appended.
- `Engine/Data/UserSetting.cs` → `Engine.Tests/Data/UserSettingTests.cs`
- `Web/WebServices/x360ce.asmx.v3.cs` → `Web.Tests/WebServices/SaveSettingTests.cs`, `DeleteSettingTests.cs` (one file per WebMethod, since each is its own concern)
- `App.v4/MainWindow.xaml.cs` → `App.v4.Tests/MainWindowSmokeTests.cs`

**`@under-test` header (qa-tester §5.3):** every test file declares the product file it covers. Mandatory.

**Namespace rule (qa-tester §5.2):** single root namespace per test project (`x360ce.Engine.Tests`, etc.). No sub-namespacing per folder.

## 3. Tooling — what we use and what we don't

| Concern | Tool | Why |
|---|---|---|
| Test runner | **MSTest (VSTest)** — `Microsoft.NET.Test.Sdk` + `MSTest.TestFramework` + `MSTest.TestAdapter` | qa-tester §2 default. VSTest is the runner for net462 (Microsoft.Testing.Platform requires modern .NET). |
| Web UI smoke | **NOT Playwright** | Web project is classic ASP.NET ASMX SOAP — no browser-UI surface worth Playwright. Reject unless we later add a real web UI. |
| Desktop UI | **`System.Windows.Automation` (in-box)** | qa-tester §3 default for WPF/WinForms. Zero NuGet beyond MSTest. No WinAppDriver/Appium/FlaUI. |
| Database integration | **Local SQL Server Developer Edition + `x360ce_Tests` DB built from sqlproj DACPAC** | Provided by sub-project B (`docs/plans/B-db/`). Test harness assumes `x360ce_Tests` already exists; `[AssemblyInitialize]` aborts if it doesn't. SqlLocalDB is **not** used (no CLR support; user's stack requires Developer Edition). |
| Perf piggyback | **ETW via `wpr.exe`** (instead of EventPipe, which is .NET Core+ only) plus **BenchmarkDotNet** for microbenchmarks | qa-tester §6a piggyback adapted for net462. EventPipe doesn't work on .NET Framework. ETW does and is in-box. |
| Mock framework | **None** for DB tests (qa-tester §1.9 — integration tests must hit a real DB). Minimal stub for `HttpContext` only when a WebMethod genuinely uses `Session`. | Strict. |

## 4. Milestones (4 PRs)

Phased delivery. PR boundaries:

| # | Milestone | Scope | Gates |
|---|---|---|---|
| **C-M1** | Engine.Tests P1 | Test project scaffold; settings XML round-trip with **synthetic** fixtures for `UserSetting`, `PadSetting`, `UserGame`, `Layout` — including demo controllers (Generic Xbox-style Pad, Generic PS-style Pad with X/O swap, Steering Wheel, Arcade Stick) built by a `TestDataFactory`; data-model shape tests for all `Engine/Data/*.cs` entities. **No DB needed — independent of sub-project B.** Sub-project D unlocked for Engine-only cherry-picks once C-M1 is green. | Builds; all tests pass on dev machine |
| **C-M2** | Web.Tests P1 | Test project scaffold; `[AssemblyInitialize]` verifies `x360ce_Tests` exists via sub-project B's scripts (calling `Assert-TestDbAllowed` C#-side); 3 critical WebMethods covered: `SearchSettings`, `SaveSetting (v3)`, `DeleteSetting (v3)`. **Depends on sub-project B being complete.** Sub-project D unlocked for Web-touching cherry-picks once C-M2 is green. | Builds; tests pass against `x360ce_Tests` on dev machine |
| **C-M3** | App.v4.Tests P1 | Test project scaffold; `AutomationId` audit + additions to App.v4 XAML (`Screen.Element` convention); launch+close smoke; one golden flow (Add Game → Edit Settings → Save); rapid-click stress on `MainWindow` top-level navigation. **No DB needed.** | Builds; tests pass on dev machine; AutomationId additions reviewed |
| **C-M4** | App.v3.Tests parity + full coverage | App.v3.Tests parity scaffold + AutomationId additions to App.v3 XAML; remaining WebMethods in Web.Tests (`LoadSetting`, `GetSettingsData`, `Execute(CloudMessage)`, `GetProgram`, `SetProgram`, `SignIn`/`SignOut`); perf piggyback wiring (ETW + BenchmarkDotNet) per qa-tester §6a; any real captured settings fixtures the user later supplies (initial state: synthetic-only, since user can generate them). | Full C suite green |

Each milestone is its own PR. Sub-project D can start after **C-M1** (Engine-only fixes only). Web-touching fixes wait for **C-M2** (and therefore B). App-touching fixes wait for **C-M3** / **C-M4** as appropriate.

## 5. C.1 — Engine.Tests (C-M1)

### 5.1 Scope
- Settings XML round-trip (golden file) for every settings-bearing class.
- Data-model shape contract: every entity in `Engine/Data/*.cs` has its public properties enumerated; a snapshot file (committed) is compared against reflection-read shape on each run. Drift fails the test.

### 5.2 Settings round-trip

**Synthetic-only fixtures** (per user 2026-05-16: "You can generate Settings.xml. Create some test demo controllers, map them."). No real captured Settings ship in the initial PR; if a user later contributes a real `Settings.xml.gz` we add it under `Engine.Tests/Fixtures/Real/` in C-M4.

A `TestDataFactory` class in `Engine.Tests/TestInfrastructure/` builds typed objects in code, serializes them to fixture XML, and the same code asserts round-trip. Generated demo controllers:

| Demo controller name | `PadSetting` shape | What it tests |
|---|---|---|
| `Generic Xbox-style Pad` | Standard Xbox layout: A/B/X/Y, two triggers as axes, two sticks with default deadzones | Baseline / happy-path |
| `Generic PS-style Pad (X/O swap)` | A↔B mapped to swap X/O semantics | Button-remapping path |
| `Steering Wheel` | One steering axis, two pedal axes, no sticks | Sparse-mapping path (most fields null/default) |
| `Arcade Stick` | All buttons, no axes | Inverse sparse path |

Committed fixtures under `Engine.Tests/Fixtures/Synthetic/`:
- `user-setting-default.xml` — `UserSetting` with all defaults.
- `user-setting-full.xml` — every nullable populated, every numeric non-default.
- `pad-setting-xbox.xml` — Generic Xbox-style Pad (from factory).
- `pad-setting-ps-swap.xml` — Generic PS-style Pad with X/O swap.
- `pad-setting-wheel.xml` — Steering Wheel.
- `pad-setting-arcade.xml` — Arcade Stick.
- `pad-setting-axis-edges.xml` — `PadSetting` with axis deadzone/sensitivity at extremes (0, 1, negative).
- `pad-setting-buttons-full.xml` — every button mapped.
- `user-game-with-overrides.xml` — `UserGame` with per-game overrides.
- `layout-keyboard-mouse.xml` — `Layout` for KB+M mapping.

Each fixture has a paired `*.cs` test:
```csharp
// @under-test: Engine/Data/UserSetting.cs
// @area: settings   @layer: unit
[TestMethod]
public void UserSetting_default_round_trips_unchanged()
{
    var path = Path.Combine(FixtureDir, "user-setting-default.xml");
    var original = XmlSerializerHelper.Load<UserSetting>(path);
    var serialized = XmlSerializerHelper.Save(original);
    var reloaded = XmlSerializerHelper.LoadFromString<UserSetting>(serialized);
    Assert.AreEqual(original, reloaded, "Round-trip changed the object");
    // Also: load again from fixture and verify byte-equal XML output (canonicalized).
    Assert.AreEqual(File.ReadAllText(path), CanonicalizeXml(serialized));
}
```

The canonicalized-byte-equal check catches **any** changes to serialization shape — element renames, attribute insertions, namespace shifts. That's the contract we owe millions of users.

**Real captured fixtures** — folder `Engine.Tests/Fixtures/Real/` is created but initially **empty**. Populated only if/when the user contributes a real `Settings.xml.gz`. Same test pattern when present.

### 5.3 Data-model shape

One snapshot file: `Engine.Tests/Fixtures/Shape/entities.shape.txt`. Each line: `<Type>::<PropertyName>::<PropertyType>`, sorted. Generated once via a `[TestMethod]` that, if the env var `UPDATE_SHAPE_SNAPSHOT=1` is set, writes the current shape to the file; otherwise, reads the file and asserts equality.

Why this matters: the EDMX is regenerable. If someone reruns the designer and the schema drifts, this test catches it before sub-project D cherry-picks one of the 371 commits and silently breaks the wire format.

### 5.4 Pure-business-rule unit tests

`UserSetting.GetCompletionPoints(...)`, etc. — direct method calls, no fixture, no DB. Each adds a `[TestMethod]` per branch. These are the cheapest tests in the suite and exist mainly to anchor coverage on hand-authored partial-class code (versus EDMX-generated).

## 6. C.2 — Web.Tests (C-M2 + C-M4)

### 6.1 Database harness — uses sub-project B's `x360ce_Tests`

Web.Tests does **not** create or destroy the test database. Sub-project B's scripts own the lifecycle. Web.Tests verifies the DB exists at startup and refuses to run otherwise.

```csharp
[TestClass]
public static class TestDbHarness
{
    public const string ExpectedDatabase = "x360ce_Tests";

    public static string ConnectionString =>
        ConfigurationManager.ConnectionStrings["x360ceModelContainer"]
            .ConnectionString;  // resolved from Web.Tests/app.config

    [AssemblyInitialize]
    public static void Setup(TestContext _)
    {
        var csb = new EntityConnectionStringBuilder(ConnectionString);
        var inner = new SqlConnectionStringBuilder(csb.ProviderConnectionString);

        // Allow-list guardrail — mirrors B's Assert-TestDbAllowed (defense in depth).
        if (!Regex.IsMatch(inner.InitialCatalog, @"^x360ce_Tests(_\w+)?$"))
            throw new InvalidOperationException(
                $"REFUSED. Web.Tests resolved DB '{inner.InitialCatalog}' which is not " +
                "in the test allow-list (^x360ce_Tests(_\\w+)?$). " +
                "Test harness will not run against the live x360ce database.");

        // Confirm DB exists. If not, instruct user to run B's Deploy-TestDb.ps1.
        using var c = new SqlConnection(inner.ConnectionString);
        try { c.Open(); }
        catch (SqlException ex) when (ex.Number == 4060)  // "cannot open database"
        {
            throw new InvalidOperationException(
                $"Database '{inner.InitialCatalog}' is missing on '{inner.DataSource}'. " +
                "Run `scripts\\db\\Deploy-TestDb.ps1` to create it (see docs/plans/B-db/).");
        }
    }

    // No [AssemblyCleanup] DB drop — B's Drop-TestDb.ps1 is user-controlled.
}
```

`Web.Tests/app.config` connection string:

```xml
<add name="x360ceModelContainer"
     connectionString="metadata=res://*/Data.x360ceModel.csdl|res://*/Data.x360ceModel.ssdl|res://*/Data.x360ceModel.msl;
                       provider=System.Data.SqlClient;
                       provider connection string=&quot;data source=localhost;initial catalog=x360ce_Tests;
                       persist security info=True;Integrated Security=True;
                       multipleactiveresultsets=True;application name=x360ce.Web.Tests&quot;"
     providerName="System.Data.EntityClient"/>
```

### 6.2 WebService invocation pattern

WebMethods are plain C# methods on a class deriving from `System.Web.Services.WebService`. **Direct instantiation works** for methods that don't use `Session`:

```csharp
// @under-test: Web/WebServices/x360ce.asmx.v3.cs
// @area: webservice   @layer: integration-api
[TestMethod]
public void SaveSetting_inserts_new_row_and_returns_ok()
{
    var s  = TestData.MakeUserSetting();
    var ps = TestData.MakePadSetting();
    var svc = new x360ce.Web.WebServices.x360ce();

    var result = svc.SaveSetting(s, ps);

    Assert.AreEqual("OK", result, "Service did not return OK for valid save");
    // Verify via direct EF query that the row landed.
    using var db = new x360ceModelContainer();
    Assert.IsTrue(db.UserSettings.Any(x => x.SettingId == s.SettingId));
}
```

For Session-using methods (`SignIn`, `SignOut`), a small helper builds an `HttpContext` with a fake Session — see `Web.Tests/Helpers/HttpContextStub.cs`. This is the minimum mocking allowed under qa-tester §1.9 (we still hit the real DB; only the HTTP envelope is stubbed).

### 6.3 Per-test isolation

Each test creates its own data with unique GUIDs and **does not clean up** by default — at end-of-class `[ClassCleanup]` deletes all rows where `SettingId LIKE 'TEST_%'`. This pattern matches the user's stated intent: "tests must do all the tests and leave database in the state it left at the end."

The state left at end is **the seeded fixture, not empty** — restoring the test DB to a snapshot would be safer but slower. Acceptable trade-off for a single-developer scenario; if flakiness shows up in C-M4, sub-project B's `Refresh-TestDb.ps1` becomes the per-class reset.

### 6.4 WebMethod coverage matrix

| Method | File | C-M2? | C-M4? | Test pattern |
|---|---|---|---|---|
| `SearchSettings` | asmx.cs | ✓ | | Search returns expected rows for known fixture |
| `LoadSetting` | asmx.cs | | ✓ | Load by ID returns the row |
| `SaveSetting` (v3) | asmx.v3.cs | ✓ | | Insert + assert via EF |
| `DeleteSetting` (v3) | asmx.v3.cs | ✓ | | Delete + assert gone |
| `GetSettingsData` | asmx.v4.cs | | ✓ | Returns shape |
| `Execute(CloudMessage)` | asmx.v4.cs | | ✓ | Per-action: round-trip the command |
| `GetProgram` | asmx.v4.cs | | ✓ | Search programs |
| `SetProgram` | asmx.v4.cs | | ✓ | Insert program |
| `SignIn` / `SignOut` | asmx.v4.cs | | ✓ | Auth flow with HttpContext stub |

C-M2 covers the three highest-impact methods that exercise the core read/write path. C-M4 fills the rest.

## 7. C.3 — App.v4.Tests (C-M3) and C.4 — App.v3.Tests (C-M4)

### 7.1 AutomationId convention

Per qa-tester §6.4: every interactive control gets `AutomationProperties.AutomationId` in format `Screen.Element` (e.g. `MainWindow.AddGameButton`, `GameSettings.DeadzoneSlider`).

C-M3 includes a **discovery pass**: read every XAML in `App.v4/`, build a list of controls with no `AutomationId`, fix in bulk. Bulk-edit is mechanical (XAML namespace import + attribute addition).

App.v3 gets the same treatment in C-M4.

This is **modifying app code purely to enable testing** — the user explicitly authorized this:
> "you are free to modify apps and add automation ids or what is necessary to help make testing code simpler."

### 7.2 App lifecycle

```csharp
[TestInitialize]
public void Launch()
{
    var exe = Path.GetFullPath(@"..\..\..\..\App.v4\bin\Release\x360ce.App.exe");
    _proc = Process.Start(exe);
    _proc.WaitForInputIdle();
    _window = WaitFor(() => AutomationElement.FromHandle(_proc.MainWindowHandle), TimeSpan.FromSeconds(5));
}

[TestCleanup]
public void Close()
{
    if (!_proc.HasExited) _proc.Kill();
    _proc.Dispose();
}
```

`WaitFor` is the qa-tester §6.4 in-box polling helper — the only place sleeps are allowed.

### 7.3 Golden flows (one per app, in C-M3 then C-M4)

- Add Game → Edit Settings → Save → Verify settings file written.
- Switch between top-level tabs five times → no crash.

### 7.4 Rapid-click stress (the user's stated bug)

A dedicated test category `[TestCategory("stress")]`:
```csharp
[TestMethod, TestCategory("stress")]
public void Rapid_click_on_settings_tabs_does_not_crash()
{
    var tabs = new[] { "MainWindow.GamesTab", "MainWindow.SettingsTab", "MainWindow.DevicesTab" };
    for (int i = 0; i < 200; i++) {
        var id = tabs[i % tabs.Length];
        ById(id).Invoke();
        // No sleep — let UIA queue the requests as fast as the framework accepts them.
    }
    Assert.IsFalse(_proc.HasExited, "App crashed during rapid tab switching");
}
```

This is the **baseline** test that documents whether the current state already crashes. If it does on the current branch, the test is marked `[Ignore("Baseline crash — fixed by D-PR-XXX")]` with a TODO link to the cherry-pick PR that resolves it.

That's the formal mechanism for tracking known-broken baselines through sub-project D.

### 7.5 Why App.v3 gets full parity (not just smoke)

User picked full parity. Rationale they implied: a cherry-picked fix that touches shared Engine code could silently break v3 in ways smoke tests miss. Doubling UIA coverage is expensive but justified for backwards compatibility.

## 8. C.5 — Performance piggyback (C-M4, qa-tester §6a adapted for net462)

### 8.1 What's different on net462
- **No EventPipe.** The `Microsoft.Diagnostics.NETCore.Client` library doesn't target net462. Use **ETW via `wpr.exe`** (Windows-in-box) instead — same goal, different transport.
- BenchmarkDotNet **does** support net462 — use it for microbench of hot paths (e.g. `UserSetting.GetCompletionPoints`).
- `SQL Server Extended Events` works the same regardless of client framework.

### 8.2 Piggyback layout

```
Web.Tests/TestInfrastructure/
  PerfCapture.cs             # [AssemblyInitialize]: starts XEvent session if QA_PERF_CAPTURE=1
  SqlXEventCapture.cs        # per-test SQL telemetry
App.v4.Tests/TestInfrastructure/
  WprCapture.cs              # [AssemblyInitialize]: starts wpr.exe GeneralProfile+CPU if QA_PERF_CAPTURE=1
Engine.Tests/TestInfrastructure/
  WprCapture.cs              # same
```

Artifact directory per qa-tester §6a.2: `TestResults/{run}/{FullTestName}/perf/`.

**Default behaviour:** `QA_PERF_CAPTURE=0` — perf collectors are off, tests run at full speed. Set `QA_PERF_CAPTURE=1` in CI's perf job (or on demand locally) to emit perf artifacts.

### 8.3 Dedicated load suite — out of scope for C

qa-tester §6a.5 talks about a `{Project}.Tests.Perf/` for sustained load. Not needed for x360ce — there's no high-concurrency surface to soak. If we ever do, it goes in `Web.Tests.Perf/` later.

## 9. Solution-patterns CSV update

After C-M1, regenerate `.ai/solution-patterns.csv` so every code file gets its `ExpectedTestPath` populated. After each subsequent milestone, regenerate.

The CSV becomes the answer to "does this file have a test?" for the cherry-pick pass (sub-project D).

## 10. Out of scope for C
- Creating / refreshing / dropping the test DB. That's sub-project B.
- Cherry-picking commits. That's sub-project D.
- Modifying app code beyond AutomationId additions and any bug fix picked up by sub-project D.
- Migrating from .NET Framework 4.6.2 to modern .NET. We deliberately stay on 4.6.2 to keep API compat (millions of users).
- Rewriting the data layer from EDMX/ObjectContext to modern EF Core.
- New WebMethods. We only test the existing surface.

## 11. Open questions

1. **App.v3 launch path.** I see `App.v3/x360ce.App.v3.csproj` referenced during exploration but haven't read the project file yet. C-M4 implementation will verify the `AssemblyName` / launch path matches what `App.v3.Tests` expects.
2. **Real captured Settings.** Per user 2026-05-16, we generate synthetic fixtures (including demo controllers). `Engine.Tests/Fixtures/Real/` stays empty until the user later contributes captured `Settings.xml.gz` from real installs. Not a blocker for C-M1.

## 12. Spec self-review

- [x] No TBDs / placeholders.
- [x] Each milestone has a clear deliverable and gate.
- [x] Test project layout matches qa-tester §5.1 and solution-patterns §1.
- [x] Folder mirror rule applied (qa-tester §5.2).
- [x] Tooling list is constrained — no Playwright on a non-web app, no WinAppDriver/Appium.
- [x] Database strategy is real-DB-not-mocked per qa-tester §1.9 — uses sub-project B's `x360ce_Tests`.
- [x] Perf piggyback is net462-correct (ETW, not EventPipe).
- [x] AutomationId convention matches qa-tester §6.4.
- [x] Sub-project D unlock points are explicit per milestone.
- [x] All references to renumbered sub-projects (A/B/C/D) are consistent throughout.

## 13. Next steps

1. User reviews this design.
2. Invoke `writing-plans` for `docs/plans/C-tests/plan.md` with the milestone breakdown and step-by-step implementation.
3. Start **C-M1** (Engine.Tests) — smallest, highest-priority, unlocks Engine-only cherry-picks. Can run in parallel with sub-project B implementation since C-M1 has no DB dependency.
