import AppKit
import SwiftUI
import VoiceIQCore

/// Saved agent runs: one row per session, the full transcript on the right.
struct AgentRunsPane: View {
    let store: AgentRunStore
    @State private var runs: [AgentSession] = []
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            List(runs, selection: $selection) { run in
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.title).font(VoiceIQUI.TypeScale.body()).lineLimit(1)
                    Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary)
                    Text(subtitle(run)).font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary)
                }.tag(run.id)
            }
            .overlay { if runs.isEmpty { Text("No agent runs yet").foregroundStyle(.secondary) } }
            .frame(width: 230)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)
            VStack(spacing: 0) {
                toolbar
                if let run = selected {
                    detail(run)
                } else {
                    ContentUnavailableView("No Run Selected", systemImage: "sparkles").frame(maxHeight: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reload)
        // A run that ended while this window sat behind the panel shows up
        // when the window comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification).receive(on: RunLoop.main)) { _ in
            reload()
        }
    }

    private var selected: AgentSession? { runs.first { $0.id == selection } }

    private var toolbar: some View {
        HStack {
            Spacer()
            Button("Copy", systemImage: "doc.on.doc") { copy() }.disabled(selection == nil)
            Button("Delete", systemImage: "trash", role: .destructive) { remove() }.disabled(selection == nil)
            Button("Delete All", systemImage: "trash.slash", role: .destructive) { removeAll() }.disabled(runs.isEmpty)
        }
        .padding(.horizontal, VoiceIQUI.Spacing.l)
        .padding(.top, VoiceIQUI.Spacing.l)
        .padding(.bottom, VoiceIQUI.Spacing.s)
    }

    private func detail(_ run: AgentSession) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(run.entries) { entry in
                    AgentEntryRow(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VoiceIQUI.Spacing.l)
        }
    }

    private func subtitle(_ run: AgentSession) -> String {
        let commands = run.commandCount == 1 ? "1 command" : "\(run.commandCount) commands"
        return run.modelID.isEmpty ? commands : "\(commands) · \(run.modelID)"
    }

    private func reload() {
        runs = store.list()
        if selection == nil || !runs.contains(where: { $0.id == selection }) {
            selection = runs.first?.id
        }
    }

    private func copy() {
        guard let run = selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(run.transcriptText, forType: .string)
    }

    private func remove() {
        guard let id = selection else { return }
        try? store.delete(id: id)
        selection = nil
        reload()
    }

    private func removeAll() {
        try? store.deleteAll()
        selection = nil
        reload()
    }
}
