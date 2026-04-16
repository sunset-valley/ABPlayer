import ProjectDescription

let buildVersionString = "137"
let shortVersionString = "0.4.8"

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
      dependencies: [
        .sdk(name: "AppIntents", type: .framework, status: .optional),
        .external(name: "Sentry"),
        .external(name: "WhisperKit"),
        .external(name: "KeyboardShortcuts"),
        .external(name: "Sparkle"),
        .external(name: "TelemetryDeck"),
      ],
      settings: .settings(base: [
        "CODE_SIGN_ENTITLEMENTS": "ABPlayer/Resources/ABPlayer.entitlements",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
      ])
    ),
    .target(
      name: "ABPlayerMAS",
      destinations: .macOS,
      product: .app,
      bundleId: "cc.ihugo.app.ABPlayerMAS",
      deploymentTargets: .macOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleVersion": .string(buildVersionString),
        "CFBundleShortVersionString": .string(shortVersionString),
        "CFBundleDisplayName": "ABPlayer",
        "NSMainStoryboardFile": "",
        "LSApplicationCategoryType": "public.app-category.education",
        "ITSAppUsesNonExemptEncryption": false,
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
        .external(name: "TelemetryDeck"),
      ],
      settings: .settings(base: [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) APPSTORE",
        "CODE_SIGN_ENTITLEMENTS": "ABPlayer/Resources/ABPlayer-MAS.entitlements",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIconMAS",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "Z7SKC87T6Q",
        "CODE_SIGN_IDENTITY": "Apple Development",
      ])
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
      dependencies: [
        .sdk(name: "AppIntents", type: .framework, status: .optional),
        .external(name: "Sentry"),
        .external(name: "WhisperKit"),
        .external(name: "KeyboardShortcuts"),
        .external(name: "Sparkle"),
        .external(name: "TelemetryDeck"),
      ],
      settings: .settings(base: [
        "CODE_SIGN_ENTITLEMENTS": "ABPlayer/Resources/ABPlayer.entitlements",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIconDev",
      ])
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
    .scheme(
      name: "ABPlayerMAS",
      shared: true,
      buildAction: .buildAction(targets: ["ABPlayerMAS"]),
      runAction: .runAction(executable: "ABPlayerMAS"),
      archiveAction: .archiveAction(configuration: .release)
    ),
  ]
)
