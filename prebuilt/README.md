# ScaleCloudApp Prebuilt

This layer is the full Nextcloud-derived iOS application (iOSClient/ + Brand/ customisation tree) linked against the ScaleCloudKit prebuilt.

## Authoritative build vehicle

The primary description of this target (all source files, entitlements, plists, resources, dozens of third-party dependencies such as RealmSwift/LucidBanner/MobileVLCKit/...) is the adapted upstream project:

```
ScaleCloudApp/ScaleCloudApp.xcodeproj/
```

It was produced by taking a copy of the `Nextcloud.xcodeproj` tree from the `nextcloud/ios` upstream repository (at the time of the ScaleCloud fork) and performing only the following narrow edits while preserving the rest of the pbxproj byte-for-byte for future mergeability:
- Source root groups already pointed at `iOSClient` and `Brand` (they matched our transplant layout).
- All `.xcscheme` `ReferencedContainer` entries rewritten from `Nextcloud.xcodeproj` to `ScaleCloudApp.xcodeproj`.
- Replaced the upstream `XCRemoteSwiftPackageReference "NextcloudKit"` + productRef usages for the main "Nextcloud" app target with a classic `PBXFileReference` + `PBXBuildFile (fileRef)` pointing at `../ScaleCloudKit/prebuilt/NextcloudKit.framework`.
- Injected `FRAMEWORK_SEARCH_PATHS = "$(inherited) $(SRCROOT)/../ScaleCloudKit/prebuilt";` into the two main-app XCBuildConfiguration blocks (Debug/Release).
- Added a tiny header comment noting the provenance.

This keeps future diffs with upstream nextcloud/ios tractable.

A thin secondary xcodegen `project.yml` exists for quick paths / projectReference consumers but is not the source of truth for the full client.

## CI independent build (manual prebuilt placement)

Workflow: **Build ScaleCloudApp** (testbuildSCApp.yml)

Before dispatching:
- Download the `ScaleCloudKit-prebuilt` artifact from a prior successful "Build ScaleCloudKit" run (and the Go prebuilt if you don't have it committed).
- Manually unpack them so that `ScaleCloudKit/prebuilt/NextcloudKit.framework` (and `ScaleCloudGo/prebuilt/...`) exist in the tree.
- The adapted `ScaleCloudApp.xcodeproj` (with its explicit file reference and `FRAMEWORK_SEARCH_PATHS`) will then see the prebuilt exactly as if it had been built in the same job.

Result artifacts (among others):
- `ScaleCloudApp-xcarchive`
- `ScaleCloudApp-prebuilt`

To stand up a full Wrap without rebuilding any of Go/Kit/App, download the `ScaleCloudApp-prebuilt` artifact yourself and unpack its payload into `ScaleCloudApp/prebuilt/` before you dispatch Wrap.

**There is no supported local build for this layer using generators or `xcodebuild` on a workstation.**

The authoritative description of the App target is the adapted upstream project under `ScaleCloudApp/ScaleCloudApp.xcodeproj/` (a narrow-edit copy of the `Nextcloud.xcodeproj` tree from `nextcloud/ios`). The only place this project (and the full iOSClient + Brand source surface it references) is built is inside the official **Build ScaleCloudApp** GitHub Actions workflow (`testbuildSCApp.yml`).

Typical independent usage:
- Dispatch Kit (after you have manually placed a Go prebuilt).
- Download the `ScaleCloudKit-prebuilt` artifact from that run.
- Unpack it into `ScaleCloudKit/prebuilt/` (and ensure Go prebuilt is also present).
- Dispatch the App workflow (it takes no run-id style inputs). The job only checks (in the first step) that the Go and Kit prebuilts you placed by hand are already present under their respective prebuilt/ trees, then builds using the adapted `.xcodeproj`.
- Resulting artifacts can be fed to Wrap by you downloading the App prebuilt artifact and manually unpacking it under `ScaleCloudApp/prebuilt/` before the Wrap dispatch.

## Used by

- ScaleCloudWrap (the optional distribution wrapper layer)
