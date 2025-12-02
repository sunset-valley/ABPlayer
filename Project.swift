import ProjectDescription

let project = Project(
    name: "ABPlayer",
    targets: [
        .target(
            name: "ABPlayer",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.ABPlayer",
            infoPlist: .default,
            buildableFolders: [
                "ABPlayer/Sources",
                "ABPlayer/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "ABPlayerTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.ABPlayerTests",
            infoPlist: .default,
            buildableFolders: [
                "ABPlayer/Tests"
            ],
            dependencies: [.target(name: "ABPlayer")]
        ),
    ]
)
