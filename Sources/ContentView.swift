import AppKit
import SwiftUI

private enum Palette {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.067)
    static let surface = Color(red: 0.094, green: 0.094, blue: 0.110)
    static let border = Color(red: 0.180, green: 0.180, blue: 0.208)
    static let text = Color(red: 0.898, green: 0.898, blue: 0.910)
    static let dim = Color(red: 0.451, green: 0.451, blue: 0.490)
    static let accent = Color(red: 0.412, green: 0.827, blue: 0.588)
    static let danger = Color(red: 0.910, green: 0.451, blue: 0.412)
}

enum PanelLayout {
    /// Panel height with no result showing (header + input + footer).
    static let baseHeight: CGFloat = 190
    /// Growth ceiling for the result block; past this it scrolls.
    static let maxResultHeight: CGFloat = 420
}

private let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
private let monoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)

/// CLI aliases, not versioned IDs: `sonnet` always resolves to the latest Sonnet,
/// so the app needs no update when a new model ships.
enum Model: String, CaseIterable, Identifiable {
    case haiku, sonnet, opus, fable

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .haiku: return "lightest"
        case .sonnet: return "balanced"
        case .opus: return "more capable"
        case .fable: return "most capable"
        }
    }

    /// Fallback ordering until this machine has measured anything, from runs on
    /// the developer's machine. Latency here is dominated by the service rather
    /// than model size — opus measured faster than haiku — so these are only a
    /// starting point, superseded by real samples.
    static let untestedDefault = Model.opus
}

@MainActor
final class ViewModel: ObservableObject {
    @Published var stats: [String: ModelStats] = Stats.load()

    /// Whether the user picked a model by hand. Until they do, the app follows
    /// whatever its own measurements say is fastest.
    @Published private(set) var isModelPinned = UserDefaults.standard.bool(forKey: "modelPinned")

    @Published var selectedModel: Model = {
        let pinned = UserDefaults.standard.bool(forKey: "modelPinned")
        let saved = UserDefaults.standard.string(forKey: "model") ?? ""
        if pinned, let model = Model(rawValue: saved) { return model }
        return Stats.fastest(in: Stats.load()) ?? Model.untestedDefault
    }()

    @Published var input = ""
    @Published var output = ""
    @Published var error = ""
    @Published var isRunning = false
    @Published var copied = false
    /// Which model the benchmark is currently timing, if any.
    @Published var benchmarking: Model?

    private var copiedResetTask: Task<Void, Never>?

    init() {
        let counts = stats.mapValues(\.samples.count).sorted { $0.key < $1.key }
        Log.write("model \(selectedModel.rawValue) (\(isModelPinned ? "pinned" : "auto")), samples \(counts)")
    }

    var canRun: Bool {
        !isRunning && benchmarking == nil
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isBusy: Bool { isRunning || benchmarking != nil }

    /// The fastest model by this machine's own samples, or nil while there isn't
    /// enough data to make the claim.
    var fastest: Model? { Stats.fastest(in: stats) }

    /// A hand pick wins over the measurements from here on.
    func pick(_ model: Model) {
        selectedModel = model
        isModelPinned = true
        UserDefaults.standard.set(model.rawValue, forKey: "model")
        UserDefaults.standard.set(true, forKey: "modelPinned")
    }

    func summary(for model: Model) -> String {
        guard let entry = stats[model.rawValue], let average = entry.average else {
            return "\(model.blurb) — not measured yet"
        }
        let count = entry.samples.count
        let fastestMark = (model == fastest) ? " ⚡ fastest" : ""
        return String(format: "%@ — %.1fs avg of %d%@", model.blurb, average, count, fastestMark)
    }

    func run() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }

        isRunning = true
        error = ""
        output = ""
        copied = false

        let model = selectedModel
        Task {
            let (result, seconds) = await Self.timedImprove(text, model: model)

            switch result {
            case .success(let improved):
                // Only successful calls are recorded — a timeout or a CLI error
                // would poison the average with a time that isn't the model's.
                stats = Stats.record(model: model, seconds: seconds)
                output = improved
                copy(improved)
                adoptFastestIfUnpinned()
            case .failure(let failure):
                error = failure.localizedDescription
            }
            isRunning = false
        }
    }

    /// Times every model once on a fixed sentence. Opt-in, because it costs four
    /// calls: running it on every launch would spend ~20s and quota each time.
    func runBenchmark() {
        guard !isBusy else { return }
        error = ""

        Task {
            for model in Model.allCases {
                benchmarking = model
                let (result, seconds) = await Self.timedImprove(Self.benchmarkSentence, model: model)
                if case .success = result {
                    stats = Stats.record(model: model, seconds: seconds)
                }
            }
            benchmarking = nil
            adoptFastestIfUnpinned()
        }
    }

    func resetStats() {
        Stats.reset()
        stats = [:]
    }

    private func adoptFastestIfUnpinned() {
        guard !isModelPinned, let fastest else { return }
        selectedModel = fastest
    }

    private static let benchmarkSentence =
        "me and him was going to the store yesterday but we dont have no money"

    private static func timedImprove(
        _ text: String,
        model: Model
    ) async -> (Result<String, Error>, TimeInterval) {
        await Task.detached(priority: .userInitiated) { () -> (Result<String, Error>, TimeInterval) in
            let start = Date()
            do {
                let output = try ClaudeRunner.improve(text, model: model.rawValue)
                return (.success(output), Date().timeIntervalSince(start))
            } catch {
                return (.failure(error), Date().timeIntervalSince(start))
            }
        }.value
    }

    func clear() {
        input = ""
        output = ""
        error = ""
        copied = false
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = true

        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

/// Ideal height of the result block, so the window can grow with the response.
private struct ResultHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    /// Height the result needs (0 = no result). The window consumes this.
    var onResultHeightChange: (CGFloat) -> Void = { _ in }

    @StateObject private var model = ViewModel()
    @FocusState private var inputFocused: Bool

    private var hasResult: Bool { !model.output.isEmpty || !model.error.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.border)
            inputArea
            if hasResult {
                Divider().overlay(Palette.border)
                resultArea
            }
            Divider().overlay(Palette.border)
            footer
        }
        .background(Palette.background)
        .onAppear { inputFocused = true }
        .onPreferenceChange(ResultHeightKey.self) { height in
            Task { @MainActor in onResultHeightChange(height) }
        }
        .onChange(of: hasResult) { _, has in
            if !has { onResultHeightChange(0) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isBusy ? Palette.accent : Palette.dim)
                .frame(width: 7, height: 7)
            Text("syntax")
                .font(monoSmall)
                .foregroundStyle(Palette.dim)

            modelPicker

            Spacer()
            if let timing = model.benchmarking {
                Text("timing \(timing.rawValue)…")
                    .font(monoSmall)
                    .foregroundStyle(Palette.accent)
            } else if model.copied {
                Text("copied ✓")
                    .font(monoSmall)
                    .foregroundStyle(Palette.accent)
                    .transition(.opacity)
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.dim)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Quit (⌘Q)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Palette.surface)
        // Lets the window be dragged from the header.
        .background(WindowDragArea())
    }

    private var modelPicker: some View {
        Menu {
            ForEach(Model.allCases) { option in
                Button {
                    model.pick(option)
                } label: {
                    // macOS draws the checkmark itself on the selected item.
                    Text("\(option.rawValue) — \(model.summary(for: option))")
                }
                .disabled(option == model.selectedModel)
            }

            Divider()

            Button("Benchmark all models (~20s)") { model.runBenchmark() }
                .disabled(model.isBusy)
            Button("Forget measurements") { model.resetStats() }
                .disabled(model.stats.isEmpty)
        } label: {
            HStack(spacing: 3) {
                Text(model.selectedModel.rawValue)
                // "auto" means the app is following its own measurements; it
                // disappears the moment you pick a model by hand.
                if !model.isModelPinned {
                    Text("auto")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.accent.opacity(0.8))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(monoSmall)
            .foregroundStyle(Palette.dim)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Palette.background.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.isRunning)
        .help(model.isModelPinned
              ? "Claude model to use"
              : "Following the fastest measured model — pick one to pin it")
    }

    // MARK: - Input

    private var inputArea: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("❯")
                .font(mono)
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)

            ZStack(alignment: .topLeading) {
                if model.input.isEmpty {
                    Text("type the sentence to fix…")
                        .font(mono)
                        .foregroundStyle(Palette.dim)
                        .padding(.leading, 5)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.input)
                    .font(mono)
                    .foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 62, maxHeight: 110)
    }

    // MARK: - Result

    private var resultArea: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 6) {
                Text(model.error.isEmpty ? "✓" : "!")
                    .font(mono)
                    .foregroundStyle(model.error.isEmpty ? Palette.accent : Palette.danger)
                Text(model.error.isEmpty ? model.output : model.error)
                    .font(mono)
                    .foregroundStyle(model.error.isEmpty ? Palette.text : Palette.danger)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // Inside a ScrollView the content gets its ideal height, so this
            // measures what the response needs, not what the window grants it.
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ResultHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(maxHeight: PanelLayout.maxResultHeight)
        .background(Palette.surface.opacity(0.5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard model.error.isEmpty, !model.output.isEmpty else { return }
            model.copy(model.output)
        }
        .help(model.error.isEmpty ? "Click to copy again" : "")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: model.run) {
                HStack(spacing: 5) {
                    if model.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .frame(width: 10, height: 10)
                    }
                    Text(model.isRunning ? "validating…" : "Validate")
                        .font(monoSmall)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(model.canRun ? Palette.accent.opacity(0.16) : Palette.surface)
                .foregroundStyle(model.canRun ? Palette.accent : Palette.dim)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(model.canRun ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!model.canRun)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Validate (⌘↵)")

            Button(action: model.clear) {
                Text("Clear")
                    .font(monoSmall)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Palette.surface)
                    .foregroundStyle(Palette.dim)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Palette.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .help("Clear (⌘K)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.background)
    }
}

/// Transparent AppKit view that lets the window be dragged from anywhere in its area.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
