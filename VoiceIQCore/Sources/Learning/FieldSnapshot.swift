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

import ApplicationServices
import Foundation

public struct FieldSnapshot: @unchecked Sendable {
    public let element: AXUIElement
    public let pid: pid_t
    public let bundleID: String?

    public init(element: AXUIElement, pid: pid_t, bundleID: String?) {
        self.element = element
        self.pid = pid
        self.bundleID = bundleID
    }

    public func currentValue() -> String? {
        AXInserter.stringValue(of: element)
    }
}

struct FieldKey: Hashable {
    let pid: pid_t
    private let element: AXUIElement

    init(_ snapshot: FieldSnapshot) {
        pid = snapshot.pid
        element = snapshot.element
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(CFHash(element))
    }
}
