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

// Adapted from Dictus (github.com/getdictus/dictus-ios, MIT License,
// Copyright (c) 2026 PIVI Solutions). See THIRD_PARTY_NOTICES.md. The notes on
// each entry are Dictus's on-device findings and are kept because they explain
// the non-obvious choices (Messages uses ichat://, Safari has no entry).

/// The way back into the app the keyboard was typing in, keyed by its bundle ID.
///
/// A scheme only belongs here if opening it RESUMES the app where the user left
/// it. One that performs an action (compose, new tab, search) is worse than the
/// swipe-back screen, because it discards what the user was doing.
public enum KnownAppSchemes {
    public static let schemesByBundleId: [String: String] = [
        // Verified against the app's own Info.plist, official documentation, or the
        // shipping binary.
        // Verified on device: lands back in the note the user was editing.
        "com.apple.mobilenotes": "mobilenotes://",
        // `ichat://`, and this one is measured rather than inherited. Messages declares
        // several schemes and most of them *act* instead of resuming: `sms://`,
        // `messages://`, `imessage://` and `im://` all land the user on the **"New
        // message"** compose sheet, not in the conversation they were typing in.
        // `ichat://` is the only one that brings Messages back exactly where it was.
        // Verified twice on iOS 26.5, and the upstream catalogue has `sms://` here with
        // the compose bug intact. Do not "fix" this to the obvious scheme.
        "com.apple.MobileSMS": "ichat://",
        // Verified on device, twice. It was the top suspect on name shape — `message://`
        // reads like "open a specific message", which is `sms://`'s mistake — and the
        // suspicion was wrong. Kept as a note because the next reader will have the same
        // doubt.
        "com.apple.mobilemail": "message://",
        "com.apple.Pages": "pages://",
        "com.apple.Numbers": "numbers://",
        "com.apple.Keynote": "keynote://",
        // NOT `x-apple-reminder://`, which is unregistered.
        "com.apple.reminders": "x-apple-reminderkit://",
        // NOT `whatsapp://` — that one belongs to the SMB build below. Verified on device
        // to come back to the conversation the user was in, which makes it the reference
        // for what a good entry looks like: it names the app, not an action.
        "net.whatsapp.WhatsApp": "whatsapp-consumer://",
        "net.whatsapp.WhatsAppSMB": "whatsapp://",
        "com.telegram.telegram-ios": "tg://",
        "ph.telegra.Telegraph": "tg://",
        // NOT `tg://`, which is shared with official Telegram — iOS would pick between them.
        "app.swiftgram.ios": "sg://",
        // This bundle identifier is Slack. Verified on device: `://open` carries a verb,
        // which is the shape that turned out wrong for Messages, and here it resumes
        // correctly. Second time the name-shape heuristic raised a false alarm.
        "com.tinyspeck.chatlyio": "slack://open",
        // This bundle identifier is Simplenote.
        "com.codality.NotationalFlow": "simplenote://",
        "com.microsoft.Office.Word": "ms-word://",
        "com.microsoft.Office.Outlook": "ms-outlook://",
        "com.microsoft.skype.teams": "msteams://",
        "com.culturedcode.ThingsiPhone": "things://",
        "com.google.Gmail": "googlegmail://",
        "com.google.chrome.ios": "googlechrome://",
        "com.google.Translate": "googletranslate://",
        "com.google.OPA": "google://",
        "com.google.GoogleMobile": "googlemobileapp://",
        "com.google.gemini": "gemini-app://",
        "com.facebook.Facebook": "fb://",
        "com.facebook.Messenger": "fb-messenger://",
        "com.atebits.Tweetie2": "twitter://",
        "com.toyopagroup.picaboo": "snapchat://",
        "com.burbn.instagram": "instagram://",
        "com.burbn.barcelona": "barcelona://",
        "com.viber": "viber://",
        "com.spotify.client": "spotify://",
        "com.spotify.client.L32G8C83V9": "spotify://",
        "com.getdropbox.Dropbox": "dbapi-1://",
        "com.linkedin.LinkedIn": "linkedin://",
        // Verified on device.
        "com.openai.chat": "com.openai.chat://",
        "ai.perplexity.app": "perplexity-app://",
        // Verified on device.
        "com.anthropic.claude": "claude://",
        // Verified on device, T3 Code 1.2.0, 2026-09-22. The first entry added on purpose
        // rather than inherited, and it was in `knownNoSchemeHosts` until then. The scheme
        // always opened the app; up to 1.1.0 it also reset navigation to Home, measured on
        // device with `t3code://` and `t3code:///` alike. Upstream fixed that on our report
        // (pingdotgg/t3code#11950, #12002), so a result measured before 1.2.0 says nothing
        // about this entry. NOT the `.dev`, `.preview` or `.swiftui` bundles: nobody
        // outside T3's team runs them, and none was tested.
        "com.t3tools.t3code": "t3code://",
        "ai.x.GrokApp": "grok://",
        "md.obsidian": "obsidian://",
        "im.monica.app.monica": "monica://",
        "com.mem-labs.mem": "mem://",
        "com.cardify.tinder": "tinder://",
        "com.readdle.smartemail": "readdle-spark://",
        "com.hammerandchisel.discord": "discord://",
        "org.whispersystems.signal": "sgnl://",
        "co.fluder.mobile.FSNotes-iOS": "fsnotes://",
        "ch.threema.iapp": "threema://",
        "com.briansunter.logseq-dev": "logseq://",
        // Verified on device.
        "com.github.stormbreaker.prod": "github://",
        "com.appliedphasor.secure-shellfish": "shellfish://",
        "com.crystalnix.ServerAuditor": "termius://",
        "com.reddit.Reddit": "reddit://",
        "pro.writer": "ia-writer://",
        "ru.yandex.mobile.translate": "yandextranslate://",
        "com.openminis.app": "minis://",
        "com.tencent.xin": "weixin://",
        "com.letterboxd.LetterboxdApp": "letterboxd://",
        "eusoft.eudic.ip": "eudic://",
        "com.ex3ndr.happy": "happy://",
        "psyche.kelivo": "kelivo://",
        "com.agiletortoise.Drafts5": "drafts://",
        "com.ubercab.UberClient": "uber://",

        // Corroborated across independent sources but not read from a shipping app, so a
        // miss is possible. It degrades to the overlay.
        "notion.id": "notion://",
        "com.meituan.imeituan": "imeituan://",
        "com.newin.nplayer.basic": "nplayer-http://",
        "com.evernote.iPhone.Evernote": "evernote://",
        "jp.naver.line": "line://",
        "com.google.ios.youtube": "youtube://",
        "com.ebay.iphone": "ebay://",
        "com.google.Docs": "googledocs://",
        "com.taobao.taobao4iphone": "taobao://",
        "company.thebrowser.ArcMobile2": "arcmobile2://",

        // Single-source or inferred from a sibling platform. Weaker still, and kept only
        // because a miss costs nothing beyond the prompt the user would otherwise get.
        "com.alibaba.sourcing": "enalibaba://",
        "com.automattic.beeper": "beeper://",
        "com.xiaojukeji.didi": "diditaxi://",
        // VK Messenger. NOT the `vk.me` universal link — the main VK client claims that
        // domain with the same wildcard, so iOS picks between them.
        "com.vk.vkme": "vkme://",

        // No custom scheme; a universal link confirmed in the app's AASA file. See the
        // trade-off in this property's doc comment, and the audit note above: a root URL
        // is a navigation by construction, so none of these can resume the app where the
        // user left it. Untested, and suspect on the resume criterion.
        "com.google.ios.ytcreator": "https://studio.youtube.com/",
        "com.amazon.Amazon": "https://www.amazon.com/",
        "com.amazon.AmazonDE": "https://www.amazon.de/",
        "com.amazon.AmazonUK": "https://www.amazon.co.uk/",
        "ru.ivi": "https://www.ivi.ru/",
        "ru.oneme.app": "https://max.ru/",
        "ru.ozon.OzonStore": "https://www.ozon.ru/",
        "com.ClassDojo": "https://www.classdojo.com/ul/home",
        "com.kouzoh.ios.mercari": "https://jp.mercari.com/",
        "com.ubercab.UberEats": "https://www.ubereats.com/",

        // From the return table shipped in Typeless 2.7.0 (its LSApplicationQueriesSchemes
        // list), not verified on device here. A miss degrades to the swipe-back screen.
        "com.apple.Maps": "maps://",
        "com.larksuite.lark": "lark://",
        "com.microsoft.copilot": "copilotn://",
        "doordash.DoorDashConsumer": "doordash://",
        "com.google.Maps": "googlemaps://",
        "com.atlassian.jira.app": "jira://",
        "com.linear.ios": "linear://",
        "com.monday.monday": "monday://",
        "com.netflix.Netflix": "nflx://",
        "com.substack.Substack": "substack://",
        "com.zhiliaoapp.musically": "tiktok://",
        "com.fogcreek.trello": "trello://",
        "com.walmart.electronics": "walmart://",
        "com.google.Drive": "googledrive://"
    ]

    /// Hosts known to have no way back. They skip straight to the swipe-back
    /// screen and are not worth listing as gaps.
    public static let knownNoSchemeHosts: Set<String> = [
        // Ours. The keyboard can be its own host (a text field in VoiceiQ) and
        // returning the user to the app they are already in would be a no-op.
        "io.blue.voiceiq.ios",

        // Safari, deliberately. It is not that no scheme opens it — several do — but that
        // every one of them *acts*: `x-web-search://` opens an empty search and
        // `x-safari-https://` a blank tab, and both discard the page the user was reading.
        // Measured on iOS 26.5. Landing someone on a blank tab is worse than the
        // swipe-back overlay, which leaves their page where it was, so Safari is listed
        // as having no way back rather than a bad one.
        "com.apple.mobilesafari",

        // Apple view services and system apps that register no URL types.
        "com.apple.SafariViewService",
        "com.apple.springboard",
        // Confirmed on device: it is reached as a real host and correctly falls to
        // `no-scheme-known` rather than being reported as a gap.
        "com.apple.Spotlight",
        "com.apple.journal",
        "com.apple.mobilesms.compose",
        "com.apple.ShortcutsUI",
        "com.apple.AppleMediaServicesUI.ComposeReviewExtension",

        // Checked by hand upstream: no custom scheme, and no universal link that opens
        // the app at its root.
        "com.deepseek.chat",
        "com.hevyapp.hevy",
        "com.stably.orca.mobile",
        "org.edupage",
        "com.rivetrune.cognilog",
        "com.davetech.todo",
        "cc.calacatta.happiest",

        // Third-party apps upstream found to publish no way back.
        "com.dmitrii.medvedev.gptalk",
        "com.saner.ai",
        "dk.FirstForm.SnappyNotesiOS",
        "com.ai.venice",
        "com.replay.Echo",
        "com.avast.ios.security",
        "com.elaborapp.NoteBox",
        "com.lixkit.diary",
        "com.weichart.Zettel",
        "h3p.Neon-Vision-Editor",
        "ru.ozon.sellerApp",
        "kz.origon.empapp",
        "com.cloud-compiler",
        "com.corp.messenger.syncer",
        "com.yottaram.eMoods"
    ]

    /// The return URL for `bundleId`, preferring a user override.
    public static func returnURL(forHostId bundleId: String, overrides: [String: String] = [:]) -> URL? {
        (overrides[bundleId] ?? schemesByBundleId[bundleId]).flatMap(URL.init(string:))
    }

    /// True for a host with no entry that is not known to lack one: a gap in the table.
    public static func isWorthReporting(_ bundleId: String) -> Bool {
        schemesByBundleId[bundleId] == nil && !knownNoSchemeHosts.contains(bundleId)
    }
}
