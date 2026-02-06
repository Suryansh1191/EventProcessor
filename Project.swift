import ProjectDescription

let project = Project(
    name: "EventProcessor",
    packages: [
        .remote(url: "https://github.com/stephencelis/SQLite.swift.git", requirement: .upToNextMajor(from: "0.15.5")),
        .remote(url: "https://github.com/firebase/firebase-ios-sdk", requirement: .upToNextMajor(from: "12.9.0"))
    ],
    targets: [
        .target(
            name: "EventProcessor",
            destinations: .macOS,
            product: .app,
            bundleId: "com.bambooLocal.EventProcessor",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["EventProcessor/**"],
            resources: [
                "EventProcessor/Resources/**"
            ],
            dependencies: [
                .package(product: "SQLite"),
                .package(product: "FirebaseCore"),
                .package(product: "FirebaseFirestore"),
                .xcframework(path: "llama.xcframework")
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "5Q3MB75L4L",
                    "ENABLE_APP_SANDBOX": "YES",
                    "ENABLE_HARDENED_RUNTIME": "YES",
                    "ENABLE_OUTGOING_NETWORK_CONNECTIONS": "YES",
                    "ENABLE_USER_SELECTED_FILES": "readonly"
                ]
            )
        ),
        .target(
            name: "EventProcessorTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.bambooLocal.EventProcessorTests",
            infoPlist: .default,
            sources: ["EventProcessor/Tests/**"],
            dependencies: [
                .target(name: "EventProcessor")
            ]
        )
    ]
)
