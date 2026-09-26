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

import Foundation

public struct LearnedCorrection: Equatable, Sendable {
    public let original: String
    public let replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }
}

public enum EditDiff {
    public struct Match: Equatable, Sendable {
        public let window: String
        public let range: Range<String.Index>

        public static func == (lhs: Match, rhs: Match) -> Bool {
            lhs.window == rhs.window
        }
    }

    private struct Word {
        let text: String
        let key: String
        let range: Range<String.Index>
    }

    private struct Candidate {
        let match: Match
        let start: Int
        let end: Int
        let edits: Int
    }

    /// Locates several inserted passages together so repeated wording is assigned
    /// in insertion order instead of every passage claiming the best exact match.
    public static func locateWindows(insertions: [String], in current: String) -> [Match?] {
        let fieldWords = words(in: current)
        guard !fieldWords.isEmpty else { return Array(repeating: nil, count: insertions.count) }
        let lists = insertions.map { candidates(for: $0, in: current, fieldWords: fieldWords) }
        var memo: [State: Result] = [:]

        func solve(_ index: Int, _ minimumStart: Int) -> Result {
            guard index < lists.count else { return Result(score: 0, choices: []) }
            let state = State(index: index, minimumStart: minimumStart)
            if let cached = memo[state] { return cached }
            var best = solve(index + 1, minimumStart).prepending(nil, score: -100)
            for candidate in lists[index] where candidate.start >= minimumStart {
                let quality = 1_000 - candidate.edits * 100 - abs(candidate.end - candidate.start)
                let result = solve(index + 1, candidate.end).prepending(candidate.match, score: quality)
                if result.score > best.score { best = result }
            }
            memo[state] = best
            return best
        }

        return solve(0, 0).choices
    }

    public static func corrections(original: String, replacement: String) -> [LearnedCorrection] {
        let before = words(in: original)
        let after = words(in: replacement)
        guard !before.isEmpty, !after.isEmpty else { return [] }
        let matches = lcsPairs(before.map(\.text), after.map(\.text), caseSensitive: true)
        var output: [LearnedCorrection] = []
        var previousBefore = -1
        var previousAfter = -1

        for pair in matches + [(before.count, after.count)] {
            let removed = before[(previousBefore + 1)..<pair.0]
            let added = after[(previousAfter + 1)..<pair.1]
            if (1...3).contains(removed.count), (1...3).contains(added.count) {
                let originalText = clean(removed.map(\.text).joined(separator: " "))
                let replacementText = clean(added.map(\.text).joined(separator: " "))
                if valid(originalText), valid(replacementText), originalText != replacementText {
                    output.append(LearnedCorrection(original: originalText, replacement: replacementText))
                }
            }
            previousBefore = pair.0
            previousAfter = pair.1
        }
        return output
    }

    private struct State: Hashable {
        let index: Int
        let minimumStart: Int
    }

    private struct Result {
        let score: Int
        let choices: [Match?]

        func prepending(_ match: Match?, score addition: Int) -> Result {
            Result(score: score + addition, choices: [match] + choices)
        }
    }

    private static func candidates(for insertion: String, in current: String, fieldWords: [Word]) -> [Candidate] {
        let source = words(in: insertion)
        guard !source.isEmpty else { return [] }
        let allowedEdits = max(1, Int(ceil(Double(source.count) * 0.3)))
        let minimumCount = max(1, source.count - allowedEdits)
        let maximumCount = source.count + allowedEdits
        var found: [Candidate] = []

        for start in fieldWords.indices {
            for count in minimumCount...maximumCount where start + count <= fieldWords.count {
                let end = start + count
                let candidateWords = Array(fieldWords[start..<end])
                let edits = editDistance(source.map(\.key), candidateWords.map(\.key))
                guard edits <= allowedEdits else { continue }
                let range = fieldWords[start].range.lowerBound..<fieldWords[end - 1].range.upperBound
                found.append(Candidate(
                    match: Match(window: String(current[range]), range: range),
                    start: start,
                    end: end,
                    edits: edits
                ))
            }
        }
        return found.sorted {
            if $0.edits != $1.edits { return $0.edits < $1.edits }
            return $0.start < $1.start
        }.prefix(24).map { $0 }
    }

    private static func words(in text: String) -> [Word] {
        var result: [Word] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) {
            _, range, _, _ in
            let value = String(text[range])
            result.append(Word(text: value, key: clean(value).lowercased(), range: range))
        }
        return result
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'-")))
    }

    private static func valid(_ text: String) -> Bool {
        guard (1...60).contains(text.count), text.contains(where: { $0.isLetter || $0.isNumber }) else { return false }
        return !text.allSatisfy { $0.isNumber || $0.isWhitespace }
    }

    private static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        var row = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: rhs.count)
            for (j, right) in rhs.enumerated() {
                next[j + 1] = left == right ? row[j] : min(row[j], row[j + 1], next[j]) + 1
            }
            row = next
        }
        return row[rhs.count]
    }

    private static func lcsPairs(_ lhs: [String], _ rhs: [String], caseSensitive: Bool) -> [(Int, Int)] {
        let left = caseSensitive ? lhs : lhs.map { $0.lowercased() }
        let right = caseSensitive ? rhs : rhs.map { $0.lowercased() }
        var table = [[Int]](repeating: [Int](repeating: 0, count: right.count + 1), count: left.count + 1)
        if !left.isEmpty, !right.isEmpty {
            for i in stride(from: left.count - 1, through: 0, by: -1) {
                for j in stride(from: right.count - 1, through: 0, by: -1) {
                    table[i][j] = left[i] == right[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0
        var j = 0
        while i < left.count, j < right.count {
            if left[i] == right[j] {
                pairs.append((i, j)); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
