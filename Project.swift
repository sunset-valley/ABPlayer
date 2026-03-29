import ProjectDescription

let buildVersionString = "113"
let shortVersionString = "0.3.0"

let signingSettings: SettingsDictionary = [
  "CODE_SIGN_IDENTITY": "Apple Development",
  "CODE_SIGN_IDENTITY[sdk=macosx*]": "Developer ID Application",
  "CODE_SIGN_STYLE": "Manual",
  "DEVELOPMENT_TEAM": "",
  "DEVELOPMENT_TEAM[sdk=macosx*]": "Z7SKC87T6Q",
  "PROVISIONING_PROFILE_SPECIFIER": "",
  "PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]": "ABPlayer-ID",
]

let project = Project(
  name: "ABPlayer",
  settings: .settings(
    base: [
      "SWIFT_VERSION": "6.2",
      "ENABLE_HARDENED_RUNTIME": "YES",
      "CODE_SIGN_ENTITLEMENTS": "ABPlayer/Resources/ABPlayer.entitlements",
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
          "https://s3.kcoding.cn/d/ABPlayerRelease/appcast.xml",
        "SUEnableAutomaticChecks": true,
        "SUPublicEDKey": "Zw9DuoU9cuGJGt81eRRfWq5OwhCG+udkeOBwScjchU0=",
        "NSAppTransportSecurity": .dictionary([
          "NSExceptionDomains": .dictionary([
            "s3.kcoding.cn": .dictionary([
              "NSExceptionAllowsInsecureHTTPLoads": true,
              "NSIncludesSubdomains": true,
            ]),
          ]),
        ]),
      ]),
      buildableFolders: [
        "ABPlayer/Sources",
        "ABPlayer/Resources",
      ],
      copyFiles: [
        .executables(name: "ffmpeg", files: [.glob(pattern: "ABPlayer/Resources/Helpers/ffmpeg")]),
      ],
      dependencies: [
        .sdk(name: "AppIntents", type: .framework, status: .optional),
        .external(name: "Sentry"),
        .external(name: "WhisperKit"),
        .external(name: "KeyboardShortcuts"),
        .external(name: "Sparkle"),
        .external(name: "TelemetryDeck"),
      ],
      settings: .settings(base: signingSettings)
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
          "https://s3.kcoding.cn/d/ABPlayerRelease/appcast.xml",
        "SUEnableAutomaticChecks": true,
        "SUPublicEDKey": "Zw9DuoU9cuGJGt81eRRfWq5OwhCG+udkeOBwScjchU0=",
        "NSAppTransportSecurity": .dictionary([
          "NSExceptionDomains": .dictionary([
            "s3.kcoding.cn": .dictionary([
              "NSExceptionAllowsInsecureHTTPLoads": true,
              "NSIncludesSubdomains": true,
            ]),
          ]),
        ]),
      ]),
      buildableFolders: [
        "ABPlayer/Sources",
        "ABPlayer/Resources",
      ],
      copyFiles: [
        .executables(name: "ffmpeg", files: [.glob(pattern: "ABPlayer/Resources/Helpers/ffmpeg")]),
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
      dependencies: [.target(name: "ABPlayerDev")]
    ),
    .target(
      name: "ABPlayerUITests",
      destinations: .macOS,
      product: .uiTests,
      bundleId: "cc.ihugo.app.ABPlayerUITests",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .default,
      buildableFolders: [
        "ABPlayer/UITests",
      ],
      dependencies: [.target(name: "ABPlayerDev")]
    ),
  ],
  schemes: [
    .scheme(
      name: "ABPlayerDev",
      shared: true,
      buildAction: .buildAction(targets: ["ABPlayerDev"]),
      testAction: .targets(["ABPlayerTests", "ABPlayerUITests"]),
      runAction: .runAction(executable: "ABPlayerDev"),
      archiveAction: .archiveAction(configuration: .release)
    ),
  ]
)
