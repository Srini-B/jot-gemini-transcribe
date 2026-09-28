# 2026-09-27 — iPhone app redesign and session fixes

## Why

After testing build 0.4.3 (12) on a phone, the owner asked for a redesign of
every iOS screen and the keyboard, with the app icon used throughout, plus fixes
for eight problems:

1. A stray line on the first intro screen.
2. Mixed text and button CTAs, and an API-key page that did not say which
   provider it wanted.
3. Microphone and keyboard permissions on separate pages.
4. Onboarding restarting after a trip to Settings, and Full Access only
   detected after killing the app.
5. No way to dismiss the keyboard from the Try field.
6. Slow dictation through OpenRouter, on iOS and macOS.
7. A Live Activity visible in the Dynamic Island while the session is idle
   (Typeless shows nothing), and dismissing it ended the warm session.
8. With Live Activities turned off, the second in-place dictation failed with
   "microphone unavailable".

## Decisions

- Visual direction: Aqua Voice's light canvas with one brand-blue accent, pill
  CTAs and 12 pt cards, found through Refero; the keyboard-setup mockup follows
  Wispr Flow's Settings illustration. Brand images come from the app icon.
- Every CTA is a pill; secondary actions ("Add a key later", "Set up later") are
  secondary pills, not text links.
- The keys page lists Google, OpenRouter, Vercel and TinyFish on one page with
  their purpose, says one model provider is enough and TinyFish is optional,
  and shows the provider picker once two keys are saved, as on the Mac.
- Setup state is observed rather than read once: `SetupMonitor` reloads the App
  Group on activation, on a new keyboard Darwin ping, and on Live Activity
  enablement changes. The onboarding page is persisted.
- The Live Activity stays for the whole warm session because the owner's bug 8
  shows iOS needs it for a background mic start. Its warm state renders nothing
  in the Dynamic Island. Dismissing it no longer ends the session; the next tap
  bounces once and starts a new activity. A refused background start marks the
  session as needing the foreground instead of failing every tap.
- Latency: the trace showed OpenRouter dictation is two sequential calls
  (transcription, then cleanup) with no live path, and every stop waited the
  full 1.5 s trailing-capture cap in the simulator. The iOS cap is now 0.6 s,
  since the stop is a deliberate tap. OpenRouter chat calls ask for
  `provider.sort: latency`. Each model call now logs its duration and request
  size, so a slow dictation on a device can be split by stage.
  Thinking stays at `low`: `minimal` is rejected by the model.

## Verification

- iPhone 18 Pro simulator with the mock Gemini server: welcome, keys,
  permissions, Try it, Home, History, Meetings and Settings render in light and
  dark mode; Done dismisses the keyboard and the tabs work afterwards; a cold
  tap in Reminders bounced once and returned; a warm tap recorded in place; the
  warm Dynamic Island is empty; recording shows the waveform and timer.
- Trailing capture measured 634 ms after the change (1530 ms before).
- `./scripts/build.sh`, `./scripts/build-ios.sh` and `./scripts/test.sh`
  (193 tests, 9 skipped, 0 failures) pass.
- Not verified: dismissing the Live Activity or disabling Live Activities on a
  device (the simulator cannot), and real OpenRouter latency (no key on the
  build machine). Both need a TestFlight build on a phone.
