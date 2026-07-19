# ScaleCloud — Reset, Wipe & Install Detection

This document describes every path that wipes app state, what each path clears,
and how the app detects a fresh install. It is the canonical reference for
understanding why certain data survives or doesn't survive a reinstall.

---

## 1. What Survives a Normal iOS App Reinstall

iOS preserves the following across an over-the-top reinstall (same Team ID):

| Storage | Survives reinstall? |
|---|---|
| Keychain (`com.scalecloud`) — Apple ID, signing cert, anisette | **Yes** |
| Keychain (`com.nextcloud.keychain`) — Nextcloud passwords, E2EE, push | **Yes** |
| UserDefaults standard domain | **No** — wiped by iOS |
| App Group UserDefaults | **No** — wiped by iOS |
| Realm database (app group container) | **Yes** |
| App sandbox files (Documents, Library) | **Yes** |
| tsnet state directory (Library/Application Support/tailscale/) | **Yes** |

This means after a reinstall: Realm still has the old Nextcloud account records,
the Nextcloud password is still in Keychain, and the ScaleCloud signing
credentials are still in Keychain. The app would appear "already set up" even
though iloader just ran a fresh sideload that needs the full injection flow.
The install detection mechanism below exists to catch this case.

---

## 2. Install Detection — `detectFreshInstall()`

**File**: `ScaleCloudApp/iOSClient/SceneDelegate.swift`  
**Called from**: top of `presentSetupFlowIfNeeded()`, on every launch.

### How it works

Every install operation physically re-extracts the app bundle to disk, giving
the main executable a new file modification time — even if the binary is
byte-identical to the previous install. Normal subsequent launches never touch
that file, so the timestamp is stable across ordinary runs.

On every launch:
1. Read the current mod time of `Bundle.main.executablePath`.
2. Compare against `UserDefaults.standard.lastKnownExecutableModTime`
   (key: `com.scalecloud.lastKnownExecutableModTime`).
3. If they differ → fresh install detected → run full wipe (see §4).
4. Immediately after the wipe, write the new mod time back to UserDefaults so
   subsequent launches (which happen before setup completes) do not re-trigger
   the wipe.

### When `lastKnownExecutableModTime` is written

Written **only on confirmed setup completion** — never on detection alone:
- `SetupCoordinator.setupCompleted()` — UI path.
- Inline in `SetupCoordinator.performDebugChannelHandoff()` — debug-channel
  path (Phase 2), where the process is killed immediately after
  `SCALECLOUD_CREDENTIALS_OK` so `setupCompleted()` never runs.

### Edge case: very first install

`lastKnownExecutableModTime` is nil on first install. `nil != currentModTime`
so the wipe runs — but since there is nothing to wipe on a genuinely fresh
install, this is a no-op in practice.

---

## 3. The Three Wipe Paths

### Path A — `--scalecloud-reset` (iloader-triggered)

**Trigger**: iloader passes `--scalecloud-reset` as a launch argument when it
wants to force a clean credential injection (e.g. Apple ID change, or explicit
reinstall via the iloader UI).

**Location**: `presentSetupFlowIfNeeded()` in `SceneDelegate.swift`, after
`detectFreshInstall()`.

**What is wiped**:

| What | How |
|---|---|
| All ScaleCloud Keychain items (Apple ID, signing cert, anisette, provisioning profiles, cert expiry) | `Keychain.shared.reset()` |
| All Nextcloud Keychain items (passwords, E2EE keys, push notification keys, passcode) | `NCPreferences().removeAll()` |
| Standard UserDefaults domain | `removePersistentDomain(forName: bundleID)` |
| App Group UserDefaults domain | `removePersistentDomain(forName: capabilitiesGroup)` |
| Realm account records | `NCAccount().deleteAllAccounts()` (async Task) |
| tsnet state directory | `FileManager.removeItem(at: tsnetDir)` |

**What is NOT wiped**: `lastKnownExecutableModTime` is not written here.
It was already set by the previous successful setup completion, and it will be
updated again when the new setup flow completes.

---

### Path B — `detectFreshInstall()` (executable mod time mismatch)

**Trigger**: Automatically, on every launch, when the executable mod time does
not match `lastKnownExecutableModTime`.

**Location**: Top of `presentSetupFlowIfNeeded()`.

**What is wiped**: Identical to Path A.

**Additional step**: `lastKnownExecutableModTime` is immediately repopulated
with the current mod time after the wipe, so the next launch (which occurs
before setup completes) does not re-trigger.

---

### Path C — No-account DVT warmup wipe

**Trigger**: Automatically, in `startNextcloud()`, when Realm has no account
records (`activeTblAccount == nil`). This is the inherited Nextcloud upstream
wipe that resets stale data from a previous install during DVT certtrust probe
launches.

**Location**: `startNextcloud()` in `SceneDelegate.swift`, before
`presentSetupFlowIfNeeded()` is called.

**What is wiped**:
- `NCPreferences().removeAll()` — Nextcloud Keychain.
- `UserDefaults.standard.removePersistentDomain(forName: bundleID)` —
  standard UserDefaults domain.

**What is NOT wiped**: App Group UserDefaults, Realm, tsnet, ScaleCloud
Keychain. This is intentional — this wipe is narrow by design, clearing only
stale Nextcloud state.

**ScaleCloud keys are preserved**: All five ScaleCloud UserDefaults keys are
saved before the wipe and restored after it:
- `signCredentialsInjected` (`com.scalecloud.credentialsInjected`)
- `menuAnisetteServersList`
- `menuAnisetteURL`
- `ipaSourceURL` (`com.scalecloud.ipaSourceURL`)
- `lastSetupDate` (`com.scalecloud.lastSetupDate`)
- `lastKnownExecutableModTime` (`com.scalecloud.lastKnownExecutableModTime`)

---

## 4. Full Wipe — What "Everything" Means

Paths A and B both perform a full wipe. The complete list:

```
Keychain.shared.reset()
  ├── appleIDEmailAddress       (com.scalecloud Keychain)
  ├── appleIDPassword
  ├── appleIDAdsid
  ├── appleIDXcodeToken
  ├── signingCertificatePrivateKey
  ├── signingCertificateSerialNumber
  ├── signingCertificate
  ├── signingCertificatePassword
  ├── identifier                (anisette)
  ├── adiPb                     (anisette)
  ├── all provisioningProfile.* keys
  └── com.scalecloud.cert.expiry (UserDefaults key, removed here)

NCPreferences().removeAll()
  └── entire com.nextcloud.keychain Keychain service
      (passwords, E2EE keys, push keys, passcode, all per-account keys)

UserDefaults.standard.removePersistentDomain(forName: bundleID)
  └── all standard UserDefaults keys including all com.scalecloud.* keys

UserDefaults(suiteName: capabilitiesGroup).removePersistentDomain(...)
  └── all app-group UserDefaults keys

NCAccount().deleteAllAccounts()   [async]
  └── all Realm tableAccount records

FileManager.removeItem(at: tsnetDir)
  └── Library/Application Support/tailscale/
      (Tailscale node identity, network map, state)
```

After the wipe the app is in the same state as a genuine first install, except
that the Realm database file itself and the app's sandboxed files remain (iOS
does not provide an API to delete those at runtime).

---

## 5. Ordering Within `presentSetupFlowIfNeeded()`

```
presentSetupFlowIfNeeded(controller:)
  │
  ├─ 1. guard setupCoordinator == nil          (bail if already running)
  │
  ├─ 2. detectFreshInstall()                   (Path B — mod time check)
  │       if mismatch → full wipe + set lastKnownExecutableModTime
  │
  ├─ 3. if --scalecloud-reset arg present      (Path A — iloader-triggered)
  │       → full wipe
  │       → deleteAllAccounts() [async]
  │       → remove tsnet dir
  │
  ├─ 4. if !Keychain.shared.hasValidSignCredentials()
  │       → signCredentialsInjected = false    (guard reset for missing creds)
  │
  ├─ 5. guard !signCredentialsInjected          (skip if already set up)
  │
  └─ 6. asyncAfter(0.5s): create SetupCoordinator, start setup flow
```

Steps 2 and 3 are both full wipes and are independent. If iloader passes
`--scalecloud-reset` on a launch that also happens to be a fresh install,
both wipes run — the second is a no-op since the first already cleared
everything.

---

## 6. UserDefaults Key Reference

| Key | Property | Wiped by Path A/B? | Preserved by Path C? |
|---|---|---|---|
| `com.scalecloud.credentialsInjected` | `signCredentialsInjected` | Yes | Yes |
| `com.scalecloud.lastSetupDate` | `lastSetupDate` | Yes | Yes |
| `com.scalecloud.lastKnownExecutableModTime` | `lastKnownExecutableModTime` | Yes (then immediately re-set) | Yes |
| `com.scalecloud.ipaSourceURL` | `ipaSourceURL` | Yes | Yes |
| `menuAnisetteServersList` | `menuAnisetteServersList` | Yes | Yes |
| `menuAnisetteURL` | `menuAnisetteURL` | Yes | Yes |
| `com.scalecloud.cert.expiry` | (raw key, set in Keychain.reset) | Yes | No |
