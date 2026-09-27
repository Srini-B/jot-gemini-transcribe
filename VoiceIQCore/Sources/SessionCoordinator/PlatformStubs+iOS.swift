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

#if os(iOS)
import Foundation

/// iOS cannot capture other apps' screens, so dictation carries no screenshots.
/// Same shape as the macOS collector so the coordinator needs no branches.
final class ScreenContextCollector {
    func start() {}
    func stop() -> [Data] { [] }
}

/// A keyboard extension is never offered secure text fields, so there is no
/// system-wide secure-input state to respect on iOS.
public enum SecureInput {
    struct Holder { let name: String; let pid: pid_t }
    public static var isActive: Bool { false }
    static func holder() -> Holder? { nil }
    static func advice(forHolder name: String) -> String { "" }
}
#endif
