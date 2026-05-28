import SwiftUI

/// Read-only reviewer dashboard — lists all flags from the session,
/// grouped by type, sorted by time.
struct DashboardView: View {

    let flags: [IntegrityFlag]

    // Group flags by type, keep each group sorted oldest-first.
    private var grouped: [(FlagType, [IntegrityFlag])] {
        var dict: [FlagType: [IntegrityFlag]] = [:]
        for flag in flags {
            dict[flag.type, default: []].append(flag)
        }
        return FlagType.allCases.compactMap { type in
            guard let group = dict[type], !group.isEmpty else { return nil }
            return (type, group.sorted { $0.timestamp < $1.timestamp })
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if flags.isEmpty {
                    emptyState
                } else {
                    flagList
                }
            }
            .navigationTitle("Session Review")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sub-views

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
            Section {
                summaryRow(label: "Total flags", value: "\(flags.count)")
                summaryRow(label: "Flag types",  value: "\(grouped.count)")
            } header: {
                Text("Summary")
            }

            ForEach(grouped, id: \.0) { type, events in
                Section {
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
                } header: {
                    Text("\(type.displayName)  (\(events.count))")
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

    // MARK: - Helpers

    private func iconName(for type: FlagType) -> String {
        switch type {
        case .noFace:         return "person.slash"
        case .multipleFaces:  return "person.2"
        case .headTurnedAway: return "arrow.turn.up.left"
        }
    }

    private func color(for type: FlagType) -> Color {
        switch type {
        case .noFace:         return .red
        case .multipleFaces:  return .orange
        case .headTurnedAway: return .yellow
        }
    }
}

#Preview {
    DashboardView(flags: [
        IntegrityFlag(sessionID: "demo", type: .noFace),
        IntegrityFlag(sessionID: "demo", type: .multipleFaces),
        IntegrityFlag(sessionID: "demo", type: .headTurnedAway),
    ])
}
