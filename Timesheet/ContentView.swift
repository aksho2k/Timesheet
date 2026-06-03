import SwiftUI

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
                .onAppear { titleFocused = true }

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
                    .foregroundStyle(.red)
                Text("Recording")
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

            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Start", selection: $viewModel.startTime, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $viewModel.endTime, displayedComponents: .hourAndMinute)
            }
            .datePickerStyle(.compact)

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
