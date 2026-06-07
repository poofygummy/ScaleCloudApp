# ScaleCloudApp Prebuilt Archive

This directory contains the precompiled ScaleCloudApp.xcarchive.

## Contents

```
ScaleCloudApp.xcarchive/
├── Info.plist
├── Products/
│   └── Applications/
│       └── ScaleCloudApp.app/
└── dSYMs/
```

## How to Build

**Prerequisites**: Both `ScaleCloudGo/prebuilt/` and `ScaleCloudKit/prebuilt/` must exist!

Run the GitHub Actions workflow:
- Workflow: `testbuild.yml`
- Layer: `app`

Or build locally:
```bash
tuist generate ScaleCloudApp
cd ScaleCloudApp
xcodebuild archive \
  -scheme ScaleCloudApp \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/prebuilt/ScaleCloudApp.xcarchive"
```

## Dependencies

- Requires: `ScaleCloudGo/prebuilt/ScaleCloudGo.xcframework`
- Requires: `ScaleCloudKit/prebuilt/ScaleCloudKit.xcarchive`

## Used By

- ScaleCloudWrap (depends on this app)

## When to Rebuild

Rebuild when you modify:
- Any Swift source files in `ScaleCloudApp/iOSClient/`
- `ScaleCloudApp/Project.swift`
- Or when ScaleCloudGo or ScaleCloudKit are rebuilt

After rebuilding, **you must also rebuild**:
- ScaleCloudWrap
