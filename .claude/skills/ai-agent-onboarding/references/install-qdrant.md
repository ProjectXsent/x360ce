# Installing Qdrant Vector Database (Windows)

Qdrant is the vector database used by RooCode for persistent memory (via the qdrant-mcp-server). Install it once per machine; it runs as a user-level Windows Task that starts automatically at login.

## Prerequisites

- PowerShell 7+ (Step 3 of the onboarding process)
- The two setup scripts bundled in this skill:
  - `Setup_App_5a_Qdrant_Core_Windows.ps1`
  - `Setup_Helper_CoreFunctions.ps1`

## Installation Steps

### 1. Copy Setup Scripts to ProgramData

Ask the user for permission, then copy the scripts to `C:\ProgramData\Qdrant\`:

```powershell
$qdrantDir = "C:\ProgramData\Qdrant"
New-Item -ItemType Directory -Force -Path $qdrantDir | Out-Null

$scriptBase = ".\.ai\skills\ai-agent-onboarding\scripts"
Copy-Item "$scriptBase\Setup_App_5a_Qdrant_Core_Windows.ps1" $qdrantDir -Force
Copy-Item "$scriptBase\Setup_Helper_CoreFunctions.ps1" $qdrantDir -Force

Write-Host "Scripts copied to: $qdrantDir" -ForegroundColor Green
```

### 2. Run the Setup Script

Tell the user to open `C:\ProgramData\Qdrant\` in Explorer and run:

```
Setup_App_5a_Qdrant_Core_Windows.ps1
```

When prompted, select these menu options **in order**:

| Option | Action |
|--------|--------|
| **1** | Install App |
| **4** | Install User Task (post-login) |
| **5** | Start Task |

This installs Qdrant and registers it as a Windows Task Scheduler job that starts automatically after each login.

### 3. Verify the Installation

After the task starts, open a browser and navigate to:

```
http://localhost:6333/dashboard#/collections
```

Add this URL to browser favorites for quick access.

If the dashboard loads, Qdrant is running correctly.

## Notes

- Qdrant runs on port `6333` by default.
- The user-level task means no Administrator rights are required at runtime.
- Data is stored under `C:\ProgramData\Qdrant\` by default.
- To stop Qdrant manually: open Task Scheduler, find the Qdrant task, and stop it.
