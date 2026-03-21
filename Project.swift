import ProjectDescription

let buildVersionString = "93"
let shortVersionString = "0.2.14"
let project = Project(
  name: "ABPlayer",
  settings: .settings(
    base: [
      "SWIFT_VERSION": "6.2",
    ],
    configurations: [
      .debug(name: "Debug"),
      .release(name: "Release"),
    ]
  ),
  targets: [
    .target(
      name: "ABPlayer",
      destinations: .macOS,
      product: .app,
      bundleId: "cc.ihugo.app.ABPlayer",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleVersion": .string(buildVersionString),
        "CFBundleShortVersionString": .string(shortVersionString),
        "NSMainStoryboardFile": "",
        "SUFeedURL":
          "http://s3.kcoding.cn/d/ABPlayerRelease/appcast.xml",
        "SUEnableAutomaticChecks": true,
        "SUPublicEDKey": "Zw9DuoU9cuGJGt81eRRfWq5OwhCG+udkeOBwScjchU0=",
        "NSAppTransportSecurity": .dictionary([
          "NSExceptionDomains": .dictionary([
            "s3.kcoding.cn": .dictionary([
              "NSExceptionAllowsInsecureHTTPLoads": true,
              "NSIncludesSubdomains": true,
            ])
          ])
        ]),
      ]),
      buildableFolders: [
        "ABPlayer/Sources",
        "ABPlayer/Resources",
      ],
      dependencies: [
        .sdk(name: "AppIntents", type: .framework, status: .optional),
        .external(name: "Sentry"),
        .external(name: "WhisperKit"),
        .external(name: "KeyboardShortcuts"),
        .external(name: "Sparkle"),
        .external(name: "TelemetryDeck"),
      ]
    ),
    .target(
      name: "ABPlayerDev",
      destinations: .macOS,
      product: .app,
      bundleId: "cc.ihugo.app.ABPlayerDev",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleVersion": .string(buildVersionString),
        "CFBundleShortVersionString": .string(shortVersionString),
        "NSMainStoryboardFile": "",
        "SUFeedURL":
          "http://s3.kcoding.cn/d/ABPlayerRelease/appcast.xml",
        "SUEnableAutomaticChecks": true,
        "SUPublicEDKey": "Zw9DuoU9cuGJGt81eRRfWq5OwhCG+udkeOBwScjchU0=",
        "NSAppTransportSecurity": .dictionary([
          "NSExceptionDomains": .dictionary([
            "s3.kcoding.cn": .dictionary([
              "NSExceptionAllowsInsecureHTTPLoads": true,
              "NSIncludesSubdomains": true,
            ])
          ])
        ]),
      ]),
      buildableFolders: [
        "ABPlayer/Sources",
        "ABPlayer/Resources",
      ],
      dependencies: [
        .sdk(name: "AppIntents", type: .framework, status: .optional),
        .external(name: "Sentry"),
        .external(name: "WhisperKit"),
        .external(name: "KeyboardShortcuts"),
        .external(name: "Sparkle"),
        .external(name: "TelemetryDeck"),
      ]
    ),
    .target(
      name: "ABPlayerTests",
      destinations: .macOS,
      product: .unitTests,
      bundleId: "cc.ihugo.app.ABPlayerTests",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "ABPlayer/Tests",
      ],
      dependencies: [.target(name: "ABPlayer")]
    ),
  ]
)
