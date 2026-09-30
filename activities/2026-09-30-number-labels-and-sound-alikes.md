# 2026-09-30: Writing rules for counts next to numbers, clarifications, money, and sound-alike words

## Report

- MacBook, WhatsApp, 14:17. ElevenLabs heard "Those two, four and five seems
  to be disabled even now". The speaker meant two items, numbers 4 and 5. The
  cleanup (`gpt-6-luna`) wrote "Those two, four, and five seem to be
  disabled", which reads as three numbers. The rule "small numbers that read
  naturally as words stay words" kept 4 and 5 as words, and the added serial
  comma made them look like one list.

## Change

`PromptV1.rules`:

- A new numbers rule replaces "small numbers stay words". A count stays a
  word. A number that labels something (option 4, rows 4 and 5, version 2) is
  a digit. When a count is followed by the labels it counts, the labels go in
  parentheses, or after a colon at the end of the sentence, never joined to
  the count by a comma. When two numbers sit side by side, one is a word and
  one is digits ("two 10-minute calls").
- A new sound-alike rule says RAW's spelling of a homophone is not evidence.
  It lists the common pairs (to/too/two, for/four, there/their/they're,
  your/you're, its/it's, then/than, weather/whether, …) and says to pick the
  spelling the sentence means. A number word is a number only when the
  sentence counts or labels something with it. RAW's word is kept when the
  sentence reads correctly either way.

- A clarification rule extends the parentheses beyond numbers. When the
  speaker refers to something loosely ("both of them", "that bug") and within
  a few words says which one, both stay and the specifics go in parentheses.
  A correction that replaces the earlier words is not a clarification, and a
  name after a role ("my sister Anjali") stays plain prose.
- A money rule. An exact amount with its currency is symbol and digits, and
  the currency name and country are dropped ("six hundred Indian rupees" →
  "₹600", "three thousand Japanese yen" → "¥3,000", "four crore rupees" →
  "₹4 crore"). Shared symbols keep their prefix (C$, A$, S$, NZ$, HK$, CN¥), and
  a currency without a well-known symbol takes its ISO code ("AED 200").
  Money stays in words with no exact amount, when the currency is the subject,
  in idioms, for "a dollar" said as a unit, and when the speaker asks for
  words. That request is a formatting command and is not written. Slang keeps
  its word with digits ("20 bucks"). The generic numbers line no longer
  carries money examples.

`PromptV1.examples` has two new pairs: "the other three six seven and nine"
and "there sending it to for people by the end of the weak".

An earlier draft also turned an estimate ("four five days") into a range
("4–5 days"). That was dropped: "four or five days" is already what the model
writes, and it reads fine.

## Verification

### Clarifications and money (second round)

- 45 fixtures: the 20 below plus 25 new ones (5 clarifications, 5 controls:
  a role and name, 3 corrections, a plain sentence; 8 exact amounts; 7 words
  cases). The old prompt is `HEAD`, before both rounds.
- `gpt-6-luna`, 5 runs each. All 5 clarifications came out in parentheses in
  every run ("both reports (the sales one and the hiring one)", "all three of
  them (Arjun, Meera, and Tom)"), except "the thing I mentioned yesterday (the
  login timeout)", which was 4 of 5 (old: 0 of 5). Every correction still
  replaced its target, and "My manager Priya" stayed plain 5 of 5.
- Money on `gpt-6-luna`: ₹500, ¥2,000, €120, £45, $3 million, ₹2 crore, C$50 and
  AED 300 5 of 5 (old: "300 dirhams", mixed CA$/C$/"$50 CAD"). Words kept for
  "weak against the dollar", "euros or only pounds", "a single rupee", "a few
  dollars" and "just a dollar". "20 bucks" 5 of 5 (old: "$20"). "Write it in
  words, not symbols" was obeyed and dropped 5 of 5 (old: printed 2 of 5).
- `gemini-3.8-flash`, text cleanup as the app sends it (temperature 0,
  `thinkingLevel: low`), 3 runs each: every new-prompt answer was the intended
  one, including all clarifications, all amounts and all words cases.
- `gemini-3.8-flash` one-call path with audio, 16 fixtures spoken by macOS
  `say`, 3 runs each. The reported dictation came out "Those two (4 and 5)"
  3 of 3; the old prompt wrote "Rows 2, 4, and 5" or "Those 2, 4, and 5".
  Clarifications 11 of 12 runs, and every amount matched the rule. Other
  differences came from mishearing the synthetic voice ("eighty-five" for
  "twenty five", "Visa fees").
- Validation gate: `gpt-6-luna` 220/225 and Gemini text 132/135 on both
  prompts; every rejection was the all-filler take. In the one-call runs,
  "Visa fees: AED 300" failed the gate against the typed fixture (content
  divergence). The app gates only the two-call path, where RAW comes from the
  recording.

### Counts next to numbers and sound-alikes (first round)

- 20 fixtures, run 5 times each on `gpt-6-luna` with `reasoning_effort: none`,
  sent as one user message, as the app sends it without screenshots. The
  prompts were built by compiling the real `PromptV1.swift` and
  `DictationRulesSeed.swift`, old and new, through the owner's CLIProxyAPI.
- The reported dictation: old 0 of 5 ("Those two, four, and five"), new 5 of
  5 ("Those two (4 and 5) seem to be disabled even now.").
- Other count-plus-label cases: "The first three (1, 2, and 5) passed" 5 of 5
  (old: "three, one, two, and five"). "Those two options (4 and 5)" 5 of 5
  (old: "options, four and five"). "Both of them (3 and 8)" 5 of 5 (old: 3 of
  5 as digits, all joined by commas).
- Sound-alikes: "to the meeting to" → "too" 5 of 5 (old: dropped the word, 5
  of 5). They're/then/four/week, whose/whether and you're/than were right on
  both prompts.
- Unchanged, new prompt: "two kids", "for the next two weeks", "in five
  minutes", "two or three more people", "three 10-minute calls", "two ₹500
  notes", "Rows 4 and 5", self-correction, the spoken list, the question, and
  spoken punctuation. One of the five list runs wrote "A few things." instead
  of "A few things:".
- The validation gate accepted 95 of 100 answers on each prompt. The 5
  rejections on each were the all-filler take ("um uh yeah okay"), which comes
  back empty on both prompts (`empty_output`), as recorded on 2026-09-29.
- `scripts/test.sh`: 192 tests, 9 skipped, 0 failures. `scripts/build.sh`
  passes.
- Not verified: a live dictation in the app.
