import SwiftData
import SwiftUI

struct TodayView: View {
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
                    Text("What did you\nship today?")
                        .font(.largeTitle.weight(.bold)).tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Small steps. A story worth keeping.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 12)
                WeekStrip(entries: entries.map(\.record), now: now)
                Divider()
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
                            symbol: "text.alignleft", title: "A fresh page.",
                            message: "A feature landed? A stubborn bug fixed? Give today’s progress a place to live.")
                        PrimaryAction(title: "Log a build", symbol: "plus") { sheet = .entry }
                            .accessibilityIdentifier("today.logBuild")
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
                            Label("Log another build", systemImage: "plus")
                        }
                        .font(.subheadline.weight(.medium)).padding(.top, 16)
                        .frame(minHeight: 44).accessibilityIdentifier("today.logBuild")
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Divider()
                    HStack {
                        Eyebrow(text: "Daily reflection")
                        Spacer()
                        Button(reflection == nil ? "Add" : "Edit") { sheet = .reflection }
                            .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                            .accessibilityIdentifier("today.reflection")
                    }
                    if let reflection {
                        Text(reflection.text).font(.body).fixedSize(horizontal: false, vertical: true)
                        Label("Written by you", systemImage: "pencil").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("What moved forward? What did you learn?")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 32)
        }
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
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .task {
            // Refresh day boundaries while the app remains open; cancellation follows view lifetime.
            while !Task.isCancelled {
                now = .now
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
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
