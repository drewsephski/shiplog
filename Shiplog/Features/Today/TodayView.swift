import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(GitHubConnection.self) private var connection
    @Query(sort: \BuildEntry.occurredAt, order: .reverse) private var entries: [BuildEntry]
    @Query private var summaries: [JournalSummary]
    @State private var sheet: Sheet?
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now

    private enum Sheet: String, Identifiable {
        case entry, reflection, settings
        var id: String { rawValue }
    }
    private var todayEntries: [BuildEntry] {
        entries.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: now) }
    }
    private var reflection: JournalSummary? {
        summaries.first { $0.key == JournalLogic.reflectionKey(for: now) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    Text("Your work.\nWith its story.")
                        .font(.largeTitle.weight(.bold)).tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(connection.isConnected ? "From your selected GitHub repositories." : "Connect GitHub. Keep the story of what you build.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 12)
                WeekStrip(entries: entries.map(\.record), now: now)
                Divider()
                ConnectionStatusView()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Eyebrow(text: "Build journal")
                        Spacer()
                        if !todayEntries.isEmpty {
                            Text("\(todayEntries.count) \(todayEntries.count == 1 ? "entry" : "entries")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if todayEntries.isEmpty {
                        JournalEmptyState(
                            symbol: "text.alignleft", title: connection.isConnected ? "Your story is taking shape." : "Your work is already the starting point.",
                            message: connection.isConnected ? "Shiplog looks for work attributable to you. A quiet day stays a quiet page." : "Choose repositories and let Shiplog write today from your commits, pull requests, and issues.")
                        PrimaryAction(title: connection.isConnected ? "Analyze today" : "Connect GitHub", symbol: "arrow.right") {
                            Task {
                                if connection.isConnected { await connection.refresh(context: context, generate: true) }
                                else { await connection.connect(context: context) }
                            }
                        }.disabled(connection.isBusy).accessibilityIdentifier("today.github")
                        Button("Log a build manually", systemImage: "plus") { sheet = .entry }
                            .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("today.logBuild")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(todayEntries) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry)
                                } label: {
                                    EntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 48)
                            }
                        }
                        Button {
                            sheet = .entry
                        } label: {
                            Label("Log a build manually", systemImage: "plus")
                        }
                        .font(.subheadline.weight(.medium)).padding(.top, 16)
                        .frame(minHeight: 44).accessibilityIdentifier("today.logBuild")
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                    HStack {
                        Eyebrow(text: reflection?.originRawValue == SummaryOrigin.manual.rawValue || !connection.isConnected ? "Daily reflection" : "Daily story")
                        Spacer()
                        Button(reflection == nil ? "Add" : "Edit") { sheet = .reflection }
                            .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                            .accessibilityIdentifier("today.reflection")
                    }
                    if let reflection {
                        Text(reflection.text).font(.body).fixedSize(horizontal: false, vertical: true)
                        Label(reflection.originRawValue == SummaryOrigin.generatedDraft.rawValue ? "AI draft · Based on your source activity" : "Written by you", systemImage: "pencil")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("What moved forward? What did you learn?")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 32)
        }
        .refreshable { await connection.refresh(context: context, generate: true) }
        .navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ShiplogMark(size: 28) }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheet = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .entry: EntryEditorView()
            case .reflection: ReflectionEditorView(date: now, text: reflection?.text ?? "")
            case .settings: SettingsView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = .now
                Task { await connection.refresh(context: context) }
            }
        }
        .task {
            await connection.refresh(context: context)
            // Refresh day boundaries while the app remains open; cancellation follows view lifetime.
            while !Task.isCancelled {
                now = .now
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if scenePhase == .active { await connection.refresh(context: context) }
            }
        }
    }
}

struct WeekStrip: View {
    let entries: [EntryRecord]
    let now: Date
    private var dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                let isToday = Calendar.current.isDate(date, inSameDayAs: now)
                let hasWork = entries.contains { Calendar.current.isDate($0.occurredAt, inSameDayAs: date) }
                NavigationLink {
                    JournalDayView(date: date)
                } label: {
                    VStack(spacing: 9) {
                        Text(date, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.secondary)
                        Text(date, format: .dateTime.day()).font(.subheadline.weight(isToday ? .bold : .regular))
                            .frame(minWidth: 32, minHeight: 34)
                            .foregroundStyle(isToday ? JournalDesign.background : .primary)
                            .background(isToday ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        Circle().fill(hasWork ? Color.primary : Color.primary.opacity(0.13)).frame(width: 4, height: 4)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }.buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(date.formatted(date: .complete, time: .omitted)), \(hasWork ? "work logged" : "no builds logged")"
                    )
            }
        }
    }
}
