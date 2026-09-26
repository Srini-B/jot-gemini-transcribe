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

public struct DiarizedWord: Equatable, Sendable {
    public var text: String
    public var speaker: String?
    public init(text: String, speaker: String?) { self.text = text; self.speaker = speaker }
}

public extension GeminiClient {
    func transcribeDiarized(audio: Data, mimeType: String = "audio/flac", model: String,
                            endpoint: URL, deadline: TimeInterval) async throws -> [DiarizedWord] {
        // `timestamp_granularities` is required in practice: with `diarization_mode`
        // alone the API returned no word_info annotations and a single text block
        // whose speaker turns were concatenated without spaces (verified 2026-09-26).
        let body: [String: Any] = [
            "model": model,
            "input": [["type": "audio", "mime_type": mimeType, "data": audio.base64EncodedString()]],
            "generation_config": ["transcription_config": [
                "mode": ["type": "verbatim", "diarization_mode": "speaker", "timestamp_granularities": ["word"]]
            ]],
        ]
        let data = try await post(path: "v1beta/interactions",
                                  body: try JSONSerialization.data(withJSONObject: body), endpoint: endpoint,
                                  deadline: deadline, modelLabel: model, modelIsInPath: false,
                                  stage: .meetingTranscribe)
        return try Self.parseDiarizedWords(data)
    }

    func summarizeMeeting(transcript: String, model: String, endpoint: URL,
                          deadline: TimeInterval) async throws -> MeetingNotes {
        let prompt = """
        Return ONLY JSON matching this shape exactly:
        {"title":"","summary":"","decisions":[],"actions":[{"text":"","owner":null,"deadline":null}],"notes":[]}

        Create faithful meeting notes from the transcript. Speaker labels such as "spk:0" and "Speaker 1" identify turns, not names. Never invent participants, facts, decisions, owners, deadlines, or context. Keep the language used in the transcript and do not translate. Ignore greetings, small talk, and verbal filler unless they affect the meeting.

        - title: A short, specific title of at most 8 words based on the main subject. Do not use a generic title when a specific topic is available.
        - summary: A few short prose paragraphs describing what was discussed in the order it was discussed. Preserve important nuance and disagreement. Combine repeated statements so each point appears once; do not turn repetition into extra significance.
        - decisions: Include only outcomes explicitly agreed or clearly finalized in the transcript. Use short standalone sentences. Proposals, preferences, unresolved suggestions, and assumptions are not decisions.
        - actions: Include only concrete follow-up tasks. Phrase each "text" as an imperative task that stands alone without the transcript, including the relevant object or context. Set "owner" only when the transcript names a person or clearly attributes the task to a named person; a bare speaker label is not a person, so otherwise use null. Set "deadline" only when a date, time, or deadline is spoken; otherwise use null. Do not infer either from roles or context.
        - notes: Capture open questions, risks, blockers, important numbers, dates, links, constraints, and follow-ups that do not fit elsewhere. Do not duplicate decisions or actions.

        Refer to a speaker label exactly as given only when attribution matters and no name is revealed. If the transcript is empty or too short to summarize meaningfully, return empty arrays, a short title or empty title as appropriate, and a one-sentence summary stating that there was not enough meeting content. Preserve every key exactly and return valid JSON with no markdown or extra text.

        Transcript:
        \(transcript)
        """
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "thinkingConfig": ["thinkingLevel": "low"],
            ],
        ]
        let text = try await generateContent(body: body, model: model, endpoint: endpoint, deadline: deadline,
                                             stage: .meetingSummary)
        return try Self.parseMeetingNotes(text)
    }

    static func parseDiarizedWords(_ data: Data) throws -> [DiarizedWord] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.network("unparseable_response")
        }
        let status = json["status"] as? String ?? "missing"
        guard status == "completed" else { throw mapInteractionStatus(status, json: json) }
        let content = (json["steps"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "model_output" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "text" }
        let words = content.flatMap { item -> [DiarizedWord] in
            (item["annotations"] as? [[String: Any]] ?? []).compactMap { annotation in
                guard annotation["type"] as? String == "word_info", let text = annotation["text"] as? String else { return nil }
                return DiarizedWord(text: text, speaker: annotation["speaker"] as? String)
            }
        }
        if !words.isEmpty { return words }
        let fallback = content.compactMap { $0["text"] as? String }.joined()
        return fallback.isEmpty ? [] : [DiarizedWord(text: fallback, speaker: nil)]
    }

    static func parseMeetingNotes(_ text: String) throws -> MeetingNotes {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: #"^```(?:json)?\s*|\s*```$"#,
                                                    with: "", options: .regularExpression)
        }
        return try JSONDecoder().decode(MeetingNotes.self, from: Data(cleaned.utf8))
    }
}
