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

import XCTest
@testable import VoiceIQCore

final class HotkeyProcessorTests: XCTestCase {
    private var processor = HotkeyProcessor()

    override func setUp() {
        super.setUp()
        processor = HotkeyProcessor()
    }

    @discardableResult
    private func send(_ event: HotkeyProcessor.Event, at t: TimeInterval) -> HotkeyProcessor.Effects {
        processor.handle(event, at: t)
    }

    func testPressStartsHandsFreeAndNextPressStops() {
        XCTAssertEqual(send(.hotkeyDown, at: 0).intents, [.begin, .lockIn])
        XCTAssertEqual(send(.hotkeyUp, at: 0.1).intents, [], "release does nothing")
        XCTAssertTrue(processor.isSessionActive)
        XCTAssertEqual(send(.hotkeyDown, at: 8).intents, [.finalize])
        XCTAssertEqual(send(.hotkeyUp, at: 8.1).intents, [])
        XCTAssertFalse(processor.isSessionActive)
    }

    func testLongHoldDoesNotStop() {
        send(.hotkeyDown, at: 0)
        XCTAssertEqual(send(.hotkeyUp, at: 5).intents, [], "holding the key is harmless")
        XCTAssertTrue(processor.isSessionActive)
    }

    func testEscCancels() {
        send(.hotkeyDown, at: 0)
        send(.hotkeyUp, at: 0.1)
        XCTAssertEqual(send(.escDown, at: 3).intents, [.cancel])
        XCTAssertFalse(processor.isSessionActive)
    }

    func testChordWithinWindowAborts() {
        send(.hotkeyDown, at: 0)
        XCTAssertEqual(send(.otherKeyDown, at: 0.4).intents, [.abortAccidental])
        XCTAssertFalse(processor.isSessionActive)
        XCTAssertEqual(send(.hotkeyUp, at: 0.5).intents, [], "the chord's release is not a stop")
    }

    func testTypingAfterWindowPasses() {
        send(.hotkeyDown, at: 0)
        send(.hotkeyUp, at: 0.1)
        XCTAssertEqual(send(.otherKeyDown, at: 1.0).intents, [], "at the boundary the session keeps going")
        XCTAssertEqual(send(.otherKeyDown, at: 4).intents, [])
        XCTAssertTrue(processor.isSessionActive)
    }

    func testResetClearsPhantomSession() {
        send(.hotkeyDown, at: 0)
        processor.reset()
        XCTAssertFalse(processor.isSessionActive)
        XCTAssertEqual(send(.hotkeyDown, at: 1).intents, [.begin, .lockIn], "next press starts, not stops")
    }

    func testIdleIgnoresOtherEvents() {
        XCTAssertEqual(send(.hotkeyUp, at: 0).intents, [])
        XCTAssertEqual(send(.escDown, at: 0).intents, [])
        XCTAssertEqual(send(.otherKeyDown, at: 0).intents, [])
        XCTAssertFalse(processor.isSessionActive)
    }
}
