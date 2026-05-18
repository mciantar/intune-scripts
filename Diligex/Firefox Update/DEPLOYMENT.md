# Firefox Maintenance Solution: Deployment & Technical Reference

## 1. Deployment Model
This solution utilizes **Intune Platform Scripts** to bootstrap a persistent **Scheduled Task** architecture, managing both System-wide and User-space Firefox installations independently.

### Deployment Steps
1.  **Execute Bootstrap**: Deploy `Bootstrap.ps1` as an **Intune Platform Script** (Run as SYSTEM). This creates the required folder structure (`C:\ProgramData\WorkstationManagement\Firefox`) and sets ACLs.
2.  **Build Installers**: Run `Build.ps1` locally. This encodes `FirefoxUpdateSystem.ps1` and `FirefoxUpdateUser.ps1` into Base64 and injects them into their respective installer scripts.
3.  **Deploy System Task**: Deploy `FirefoxUpdateSystemScheduledTaskInstaller.ps1` as an **Intune Platform Script** (Run as SYSTEM). It will wait for the Bootstrap to finish, dump the script, and register the SYSTEM scheduled task.
4.  **Deploy User Task**: Deploy `FirefoxUpdateUserScheduledTaskInstaller.ps1` as an **Intune Platform Script** (Run as USER). It will wait for the Bootstrap to finish, dump the script, and register the USER scheduled task.

---

## 2. Architecture & Scope

### System Scope (`FirefoxUpdateSystem.ps1`)
- **Target**: `C:\Program Files\Mozilla Firefox\firefox.exe`
- **Context**: Runs as SYSTEM via Scheduled Task (`HighestAvailable`).
- **Behavior**: Checks the Mozilla API for the latest version. If outdated, broadcasts a 5-minute warning to all active sessions using `msg.exe`, gracefully closes Firefox, and installs the update silently.

### User Scope (`FirefoxUpdateUser.ps1`)
- **Target**: `%LocalAppData%\Mozilla Firefox\firefox.exe`
- **Context**: Runs as the logged-on User via Scheduled Task (`LeastPrivilege`).
- **Behavior**: Checks the Mozilla API for the latest version. If outdated, prompts the user with a GUI form (5-minute warning), gracefully closes Firefox, and installs the update silently in the user's profile.

---

## 3. Security & Trust Model

### Atomic Locking (`Get-Lock`)
Scripts use `[System.IO.File]::Open` with `FileMode::CreateNew` and `FileShare::None`. 
- **Stale Lock Handling**: If `CreateNew` fails, the script attempts a standard `Open`. If the standard `Open` succeeds, it proves no active process holds a handle. The script then deletes the stale file and re-acquires.
- **Race Prevention**: `runtime.lock` ensures that only one disruption event (prompt/kill) occurs at a time across all sessions.

### Installer Validation
- **Digital Signature**: Both scripts dynamically download the latest installer, verify the `FirefoxSetup.exe` signature status, and ensure the Signer is **Mozilla Corporation** before execution.

### ACL Enforcement
- **Read-Only**: `scripts/` and `state/` are read-only for `Users`.
- **Modify**: `locks/` and `logs/` allow `Modify` for `Users` to support atomic lock creation and per-user logging.

---

## 4. Scheduled Task Semantics

### USER Task (Group Principal)
- **Principal**: `S-1-5-32-545` (Builtin\Users)
- **RunLevel**: `LeastPrivilege`
- **Trigger**: `TimeTrigger` + `Repetition PT4H`.
- **Behavior**: Spawns a unique process instance for **every** interactive logon session.

### SYSTEM Task (Service Principal)
- **Principal**: `S-1-5-18` (SYSTEM)
- **RunLevel**: `HighestAvailable`
- **Trigger**: `TimeTrigger` + `Repetition PT4H` + `StartWhenAvailable`.
