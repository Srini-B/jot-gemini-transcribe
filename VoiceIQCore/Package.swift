// swift-tools-version: 5.10
// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PackageDescription

let package = Package(
    name: "VoiceIQCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoiceIQCore", targets: ["VoiceIQCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.2.0"),
    ],
    targets: [
        // WebRTC's AEC3 echo canceller and a small C bridge, built by
        // Vendor/WebRTCAEC/build.sh. BSD-licensed; see Vendor/WebRTCAEC/Notices.
        .binaryTarget(
            name: "CVoiceIQAEC",
            path: "Vendor/WebRTCAEC/CVoiceIQAEC.xcframework"
        ),
        .target(
            name: "VoiceIQCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "Sauce",
                "CVoiceIQAEC",
            ],
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .testTarget(
            name: "VoiceIQCoreTests",
            dependencies: ["VoiceIQCore"],
            path: "Tests"
        ),
    ]
)
