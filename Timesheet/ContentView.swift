import SwiftUI

// MARK: - Entry type colours (match Google Calendar colorIds)
// Task  -> green  #0B8043  (colorId 10)
// Meeting -> yellow #F6BF26 (colorId 5)
extension EntryType {
    var dotColor: Color {
        switch self {
        case .task:    return Color(red: 0.043, green: 0.502, blue: 0.263)  // #0B8043
        case .meeting: return Color(red: 0.965, green: 0.749, blue: 0.149)  // #F6BF26
        }
    }
}

struct PopoverView: View {
    @EnvironmentObject var viewModel: TimesheetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewModel.state {
            case .newEntry:
                NewEntryView()
            case .recording:
                RecordingView()
            case .summary:
                SummaryView()
            case .saved:
                SavedView()
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - New Entry

struct NewEntryView: View {
    @EnvironmentObject var viewModel: TimesheetViewModel
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("New Entry", systemImage: "timer")
                .font(.headline)

            TextField("Entry title", text: $viewModel.entryTitle)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit { startIfReady() }
                .onAppear {
                    titleFocused = true
                    if viewModel.suggestions.isEmpty {
                        Task { await viewModel.fetchSuggestions() }
                    }
                }

            // Suggestions row
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await viewModel.fetchSuggestions() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .rotationEffect(
                                viewModel.isFetchingSuggestions
                                    ? .degrees(360) : .degrees(0)
                            )
                            .animation(
                                viewModel.isFetchingSuggestions
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .default,
                                value: viewModel.isFetchingSuggestions
                            )
                    }
                    .buttonStyle(.plain)
                }

                if !viewModel.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.suggestions, id: \.title) { suggestion in
                                Button {
                                    viewModel.entryTitle = suggestion.title
                                    viewModel.entryType  = suggestion.entryType
                                } label: {
                                    Text(suggestion.title)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .frame(maxWidth: 102)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.quaternary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Picker("", selection: $viewModel.entryType) {
                ForEach(EntryType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button(action: startIfReady) {
                Label("Start Timer", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.entryTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func startIfReady() {
        guard !viewModel.entryTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        viewModel.startRecording()
    }
}

// MARK: - Recording

struct RecordingView: View {
    @EnvironmentObject var viewModel: TimesheetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(viewModel.entryType.dotColor)
                Text("Recording \(viewModel.entryType.rawValue)")
                    .font(.headline)
                Spacer()
            }

            Text(viewModel.entryTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(viewModel.elapsedString)
                .font(.system(size: 44, weight: .light, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)

            Button {
                viewModel.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

// MARK: - Summary

struct SummaryView: View {
    @EnvironmentObject var viewModel: TimesheetViewModel
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Summary")
                    .font(.headline)
                Spacer()
                TypeBadge(type: viewModel.entryType)
            }

            Text(viewModel.entryTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                TimeFieldRow(label: "Start", time: $viewModel.startTime)
                TimeFieldRow(label: "End",   time: $viewModel.endTime)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Duration: \(viewModel.duration)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let message = viewModel.saveMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                Button("Discard") {
                    viewModel.reset()
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Save to Calendar", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .animation(.default, value: viewModel.saveMessage)
    }

    private func save() async {
        isSaving = true
        await viewModel.saveToCalendar()
        isSaving = false
    }
}

// MARK: - Time field row (DatePicker + rounding pills)

private struct TimeFieldRow: View {
    let label: String
    @Binding var time: Date

    /// Returns the floor and ceiling multiples of 5 minutes, or nil when time
    /// is already an exact multiple of 5.
    private var roundingSuggestions: (floor: Date, ceil: Date)? {
        let cal = Calendar.current
        let minute = cal.component(.minute, from: time)
        let second = cal.component(.second, from: time)
        // Already on a 5-minute boundary?
        guard minute % 5 != 0 || second != 0 else { return nil }

        let floorMinute = (minute / 5) * 5
        let base = cal.date(bySettingHour: cal.component(.hour, from: time),
                            minute: floorMinute,
                            second: 0,
                            of: time) ?? time
        let ceilDate = base.addingTimeInterval(5 * 60)
        return (floor: base, ceil: ceilDate)
    }

    var body: some View {
        HStack(spacing: 0) {
            DatePicker(label, selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)

            Spacer(minLength: 8)

            if let suggestions = roundingSuggestions {
                HStack(spacing: 8) {
                    RoundingPill(date: suggestions.floor, action: { time = suggestions.floor })
                    RoundingPill(date: suggestions.ceil,  action: { time = suggestions.ceil  })
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: roundingSuggestions?.floor)
    }
}

// MARK: - Rounding pill button

private struct RoundingPill: View {
    let date: Date
    let action: () -> Void

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    var body: some View {
        Button(action: action) {
            Text(Self.fmt.string(from: date))
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Saved Confirmation

struct SavedView: View {
    @EnvironmentObject var viewModel: TimesheetViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Saved successfully")
                .font(.headline)
            Spacer()
            Button {
                viewModel.reset()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minHeight: 190)
    }
}

// MARK: - Type Badge

struct TypeBadge: View {
    let type: EntryType

    var body: some View {
        Text(type.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(type == .task ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
            .foregroundStyle(type == .task ? Color.blue : Color.purple)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
