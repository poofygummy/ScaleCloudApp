import ProjectDescription

// Use a variable to define shared build settings to avoid repetition
let baseSettings: SettingsDictionary = [
    "IPHONEOS_DEPLOYMENT_TARGET": "14.0",
    "MARKETING_VERSION": "1.0",
    "CURRENT_PROJECT_VERSION": "1"
]

let project = Project(
    name: "ScaleCloud",
    targets: [
        .target(
            name: "ScaleCloudApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.scalecloud.ScaleCloudApp",
            infoPlist: "Brand/iOSClient.plist",
            // AUTOMATED DISCOVERY:
            // This pulls every .swift file within iOSClient OR Brand,
            // excluding subfolders like "Tests" or "Widget".
            sources: ["iOSClient/**/*.swift", "Brand/**/*.swift"],
            resources: ["iOSClient/**/*.xcassets", "iOSClient/**/*.storyboard", "Brand/**/*.xcassets"],
            dependencies: [
                .project(target: "ScaleCloudKit", path: "../ScaleCloudKit")
            ],
            settings: .settings(base: baseSettings)
        )
    ]
)
