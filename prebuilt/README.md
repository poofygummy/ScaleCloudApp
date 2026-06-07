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

## CI independent build (artifact download into prebuilt)

Workflow: **Build ScaleCloudApp** (testbuildSCApp.yml)

Optional input `kit_run_id`:
- A prior "Build ScaleCloudKit" run that published `ScaleCloudKit-prebuilt`.
- The workflow downloads the artifact and unpacks it under `ScaleCloudKit/prebuilt/`.
- The pbxproj + search paths then see a working NextcloudKit.framework exactly as if it had been built in-tree.

Result artifacts (among others):
- `ScaleCloudApp-xcarchive`
- `ScaleCloudApp-prebuilt`

To stand up a full Wrap without rebuilding any of Go/Kit/App, a Wrap dispatch job can receive an `app_run_id` and materialize the App artifact under `ScaleCloudApp/prebuilt`.

**There is no supported local build for this layer using generators or `xcodebuild` on a workstation.**

The authoritative description of the App target is the adapted upstream project under `ScaleCloudApp/ScaleCloudApp.xcodeproj/` (a narrow-edit copy of the `Nextcloud.xcodeproj` tree from `nextcloud/ios`). The only place this project (and the full iOSClient + Brand source surface it references) is built is inside the official **Build ScaleCloudApp** GitHub Actions workflow (`testbuildSCApp.yml`).

Typical independent usage:
- Supply a `kit_run_id` (from a prior successful "Build ScaleCloudKit" run that published `ScaleCloudKit-prebuilt`).
- Dispatch the App workflow with that input.
- The job materializes `NextcloudKit.framework` (and its Go transitive dep) under `ScaleCloudKit/prebuilt/`.
- It then uses the adapted `.xcodeproj` (or the lightweight `project.yml` for quicker paths) + `xcodebuild archive`.
- Resulting artifacts (`ScaleCloudApp-xcarchive` and `ScaleCloudApp-prebuilt`) can be fed to Wrap via an `app_run_id`.

## Used by

- ScaleCloudWrap (the optional distribution wrapper layer)
