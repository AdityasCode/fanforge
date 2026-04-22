# FanForge

FanForge is a macOS 13+ menu bar app for reading and controlling AppleSMC fan behavior on Apple Silicon Macs.

## Build Setup

### Targets
You need two targets in Xcode:

1. **`FanForge`** (main app)
2. **`FanForgeHelper`** (privileged helper tool)

### Main app target (`FanForge`)
- Include:
  - `App/*`
  - `SMC/*`
  - `Resources/Info.plist`
  - `FanForge.entitlements`
  - `FanForgeHelper/FanForgeHelperProtocol.swift` (shared protocol)
- Link frameworks:
  - `ServiceManagement.framework`
  - `Security.framework`

### Helper target (`FanForgeHelper`)
- Type: command-line tool / launchd helper
- Include:
  - `FanForgeHelper/main.swift`
  - `FanForgeHelper/HelperSMCWriter.swift`
  - `FanForgeHelper/FanForgeHelperProtocol.swift`
  - `SMC/*` (for SMC access primitives)
  - `FanForgeHelper/Info.plist`
  - `FanForgeHelper/FanForgeHelper.entitlements`
- Link frameworks:
  - `ServiceManagement.framework`
  - `Security.framework`
  - `IOKit.framework`
- Embed helper at:
  - `FanForge.app/Contents/Library/LaunchServices/`

### Signing requirements
- Sign **both** targets with the same Team identity.
- For distribution outside the App Store, use Developer ID signing/notarization.
- `SMAuthorizedClients` in helper `Info.plist` must match your signed app identifier requirement.

### Example build commands

```zsh
xcodebuild -project FanForge.xcodeproj -scheme FanForge -configuration Debug build
xcodebuild -project FanForge.xcodeproj -scheme FanForge -configuration Release build
```

## How SMJobBless Works

`SMJobBless` is the supported way to install a privileged helper on modern macOS. The app asks for admin authorization once, then requests launchd to install a signed helper tool into a protected system location. launchd starts that helper as root, and the app communicates with it over a mach service via XPC.

The security model relies on code-signing requirements in both directions: the app must be allowed to bless the helper, and the helper must only accept approved clients. This is why bundle identifiers, signing identities, and `SMAuthorizedClients`/mach service names must remain aligned between app and helper targets.

## Running Modes

### Production mode (recommended)
- Build and sign both targets.
- Launch `FanForge` normally.
- In the menu bar UI, click **Enable fan control** to install the helper.
- After successful installation, fan write requests route through XPC to the root helper.

### Debug mode without helper
A compile flag is available:

- `DEBUG_NO_HELPER`

When enabled, `FanController` bypasses XPC and writes directly with `SMCWriter`. This requires launching the app as root in development.

```zsh
sudo ./FanForge
```

Use this mode only for local testing.

## Known Firmware Limitations (M3/M4/M5)

- Apple firmware may reject or ignore fan override requests even with root/helper access.
- If the system decides cooling demand is low, target writes can be silently reverted.
- FanForge verifies read-back after writes and surfaces rejection states in UI.
- This behavior is firmware policy, not an application-side crash or logic failure.

## Files Added for Privileged Write Support

- `FanForgeHelper/FanForgeHelperProtocol.swift`
- `FanForgeHelper/main.swift`
- `FanForgeHelper/HelperSMCWriter.swift`
- `FanForgeHelper/Info.plist`
- `FanForgeHelper/FanForgeHelper.entitlements`
- `App/HelperConnection.swift`
- Updated `App/FanController.swift` for helper routing
- Updated `FanForge.entitlements` for mach-lookup exception
