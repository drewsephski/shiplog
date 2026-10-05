import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \BuildEntry.occurredAt, order: .reverse) private var entries: [BuildEntry]
    @Query(sort: \JournalSummary.startDate, order: .reverse) private var summaries: [JournalSummary]
    @State private var search = ""

    private var filteredEntries: [BuildEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedStandardContains(search) || $0.detail.localizedStandardContains(search)
                || ($0.project?.name.localizedStandardContains(search) ?? false)
        }
    }
    private var dates: [Date] {
        var dates = Set(filteredEntries.map { Calendar.current.startOfDay(for: $0.occurredAt) })
        let reflections = summaries.filter {
            $0.periodRawValue == SummaryPeriod.daily.rawValue
                && (search.isEmpty || $0.text.localizedStandardContains(search))
        }
        dates.formUnion(reflections.compactMap { JournalLogic.reflectionDate(for: $0.key) })
        return dates.sorted(by: >)
    }

    var body: some View {
        List {
            if dates.isEmpty {
                JournalEmptyState(
                    symbol: search.isEmpty ? "clock" : "magnifyingglass",
                    title: search.isEmpty ? "Your story starts here." : "No matching work.",
                    message: search.isEmpty
                        ? "Build entries and reflections will collect here, day by day."
                        : "Try a project name or a different word."
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(dates, id: \.self) { date in
                    Section {
                        NavigationLink {
                            JournalDayView(date: date)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(date, format: .dateTime.weekday(.wide)).font(.headline)
                                let count = filteredEntries.filter {
                                    Calendar.current.isDate($0.occurredAt, inSameDayAs: date)
                                }.count
                                Text(
                                    count == 0
                                        ? "Daily reflection"
                                        : "\(count) \(count == 1 ? "build entry" : "build entries")"
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                        ForEach(filteredEntries.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: date) }) {
                            entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                EntryRow(entry: entry)
                            }
                        }
                    } header: {
                        Text(date, format: .dateTime.month(.wide).day().year())
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .searchable(text: $search, prompt: "Search your journal")
    }
}

struct JournalDayView: View {
    let date: Date
    @Query private var entries: [BuildEntry]
    @Query private var summaries: [JournalSummary]
    @State private var sheet: Sheet?
    private enum Sheet: String, Identifiable {
        case entry, reflection
        var id: String { rawValue }
    }

    init(date: Date) {
        self.date = date
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(
            filter: #Predicate<BuildEntry> { $0.occurredAt >= start && $0.occurredAt < end },
            sort: \BuildEntry.occurredAt, order: .reverse)
        let key = JournalLogic.reflectionKey(for: date)
        _summaries = Query(filter: #Predicate<JournalSummary> { $0.key == key })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: date.formatted(.dateTime.month(.wide).day().year()))
                Text(date, format: .dateTime.weekday(.wide)).font(.largeTitle.weight(.bold))
                if entries.isEmpty {
                    JournalEmptyState(
                        symbol: "text.alignleft", title: "A quiet page.",
                        message: "No builds logged for this day. Progress doesn’t always need a record.")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            NavigationLink {
                                EntryDetailView(entry: entry)
                            } label: {
                                EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                Button("Log a build for this day", systemImage: "plus") { sheet = .entry }
                    .frame(minHeight: 44)
                Divider()
                HStack {
                    Eyebrow(
                        text: summaries.first?.originRawValue == SummaryOrigin.generatedDraft.rawValue
                            ? "Daily story" : "Daily reflection")
                    Spacer()
                    Button(summaries.isEmpty ? "Add" : "Edit") { sheet = .reflection }.frame(minHeight: 44)
                }
                if let reflection = summaries.first {
                    Text(reflection.text).textSelection(.enabled)
                    if reflection.originRawValue == SummaryOrigin.generatedDraft.rawValue {
                        Label("AI draft · Based on your source activity", systemImage: "pencil").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Leave a thought for your future self.").foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .entry: EntryEditorView(date: min(date, .now))
            case .reflection: ReflectionEditorView(date: date, text: summaries.first?.text ?? "")
            }
        }
    }
}
