import SwiftUI

/// Read-only reviewer dashboard.
/// Shows in-memory flags immediately, then enriches from the backend in the background.
/// Flags are grouped by type, sorted oldest-first within each group.
struct DashboardView: View {

    // In-memory flags passed from the session — always available instantly.
    let localFlags: [IntegrityFlag]
    let sessionID: String
    var terminated: Bool = false
    var terminationReason: String? = nil

    @State private var remoteFlags: [IntegrityFlag] = []
    @State private var isFetching = false
    @State private var fetchError: String? = nil

    /// Merge local + remote, deduplicated by id, sorted by timestamp.
    private var allFlags: [IntegrityFlag] {
        var seen = Set<UUID>()
        return (localFlags + remoteFlags)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var grouped: [(FlagType, [IntegrityFlag])] {
        var dict: [FlagType: [IntegrityFlag]] = [:]
        for flag in allFlags { dict[flag.type, default: []].append(flag) }
        return FlagType.allCases.compactMap { type in
            guard let group = dict[type], !group.isEmpty else { return nil }
            return (type, group)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if allFlags.isEmpty && !isFetching {
                    emptyState
                } else {
                    flagList
                }
            }
            .safeAreaInset(edge: .top) {
                if terminated {
                    terminationBanner
                }
            }
            .navigationTitle("Session Review")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isFetching {
                        ProgressView()
                    } else {
                        Button("Refresh") { Task { await fetchRemote() } }
                    }
                }
            }
            .task { await fetchRemote() }
        }
    }

    // MARK: - Sub-views

    private var terminationBanner: some View {
        VStack(spacing: 6) {
            Label("EXAM TERMINATED", systemImage: "xmark.octagon.fill")
                .font(.headline.bold())
            if let reason = terminationReason {
                Text(reason)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.red)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("No integrity flags recorded.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var flagList: some View {
        List {
            // Summary section
            Section("Summary") {
                summaryRow(label: "Session ID", value: String(sessionID.prefix(8)) + "…")
                summaryRow(label: "Total flags", value: "\(allFlags.count)")
                summaryRow(label: "Flag types",  value: "\(grouped.count)")
                if let err = fetchError {
                    Label(err, systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Per-type sections
            ForEach(grouped, id: \.0) { type, events in
                Section("\(type.displayName)  (\(events.count))") {
                    ForEach(events) { flag in
                        HStack {
                            Text(Self.timeFormatter.string(from: flag.timestamp))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label(type.displayName, systemImage: iconName(for: type))
                                .font(.callout)
                                .foregroundStyle(color(for: type))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }

    // MARK: - Backend fetch

    private func fetchRemote() async {
        guard let url = URL(string: "\(FlagLogger.backendBaseURL)/sessions/\(sessionID)/flags") else { return }

        isFetching = true
        fetchError = nil
        defer { isFetching = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // IntegrityFlag defines its own CodingKeys mapping snake_case → camelCase,
            // so we don't use convertFromSnakeCase here.
            remoteFlags = try decoder.decode([IntegrityFlag].self, from: data)
        } catch {
            fetchError = "Backend unavailable — showing local data."
        }
    }

    // MARK: - Helpers

    private func iconName(for type: FlagType) -> String {
        switch type {
        case .noFace:          return "person.slash"
        case .multipleFaces:   return "person.2"
        case .headTurnedAway:  return "arrow.turn.up.left"
        case .appBackgrounded: return "rectangle.portrait.and.arrow.right"
        }
    }

    private func color(for type: FlagType) -> Color {
        switch type {
        case .noFace:          return .red
        case .multipleFaces:   return .orange
        case .headTurnedAway:  return .yellow
        case .appBackgrounded: return .purple
        }
    }
}

#Preview {
    DashboardView(
        localFlags: [
            IntegrityFlag(sessionID: "demo", type: .noFace),
            IntegrityFlag(sessionID: "demo", type: .multipleFaces),
            IntegrityFlag(sessionID: "demo", type: .headTurnedAway),
        ],
        sessionID: "demo"
    )
}
