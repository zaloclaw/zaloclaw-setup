import Foundation
import SwiftUI
import AppKit

private let eventPrefix = "__ZALOC_EVENT__|"

enum ProviderType: String, CaseIterable, Identifiable {
    case openai = "openai"
    case google = "google"
    case anthropic = "anthropic"
    case openrouter = "openrouter"

    var id: String { rawValue }
}

enum CloneMode: String, CaseIterable, Identifiable {
    case reuse = "reuse"
    case replace = "replace"
    case fail = "fail"

    var id: String { rawValue }
}

private struct InstallerSettings: Codable {
    var workspaceRoot: String
    var configDir: String
    var provider: String
    var cloneMode: String
    var installMissingPrerequisites: Bool
    var launchUIAfterSetup: Bool?
}

struct CompletionNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class InstallerViewModel: ObservableObject {
    @Published var logs: String = ""
    @Published var isRunning: Bool = false
    @Published var setupStatus: String = "idle"
    @Published var currentStep: String = "pending"
    @Published var gatewayToken: String = ""
    @Published var gatewayContainer: String = ""
    @Published var logFilePath: String = ""
    @Published var stateFilePath: String = ""
    @Published var errorMessage: String = ""
    @Published var completionNotice: CompletionNotice?
    @Published var workspaceRoot: String = NSHomeDirectory() + "/zaloclaw-local"
    @Published var configDir: String = NSHomeDirectory() + "/.openclaw_z"
    @Published var provider: ProviderType = .openai
    @Published var providerApiKey: String = ""
    @Published var litellmMasterKey: String = ""
    @Published var cloneMode: CloneMode = .reuse
    @Published var installMissingPrerequisites: Bool = true
    @Published var launchUIAfterSetup: Bool = true

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    init() {
        loadSettings()
    }

    func startSetup() {
        guard !isRunning else { return }
        guard validateInputs() else { return }

        let scriptPath = resolveRunnerScriptPath()

        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            errorMessage = "Missing script: \(scriptPath.path)"
            setupStatus = "failed"
            return
        }

        errorMessage = ""
        logs = ""
        gatewayToken = ""
        gatewayContainer = ""
        logFilePath = ""
        stateFilePath = ""
        completionNotice = nil
        setupStatus = "running"
        currentStep = "starting"
        isRunning = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = buildRunnerArguments(scriptPath: scriptPath)
        proc.currentDirectoryURL = scriptPath.deletingLastPathComponent()

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        self.process = proc
        self.stdoutPipe = out
        self.stderrPipe = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consumeOutput(line)
            }
        }

        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consumeOutput(line)
            }
        }

        proc.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                self.process = nil
                self.isRunning = false
                if process.terminationStatus == 0 {
                    self.setupStatus = "completed"
                    if self.currentStep == "running" || self.currentStep == "starting" {
                        self.currentStep = "done"
                    }
                    self.presentCompletionNotice(
                        title: "Setup completed",
                        message: self.successSummaryMessage(),
                    )
                } else {
                    self.setupStatus = "failed"
                    self.currentStep = "failed"
                    if self.errorMessage.isEmpty {
                        self.errorMessage = "Installer exited with code \(process.terminationStatus)."
                    }
                    self.presentCompletionNotice(
                        title: "Setup failed",
                        message: self.errorMessage.isEmpty ? "Installer exited before completing." : self.errorMessage,
                    )
                }
            }
        }

        do {
            try proc.run()
        } catch {
            isRunning = false
            setupStatus = "failed"
            currentStep = "failed"
            errorMessage = "Failed to launch installer process: \(error.localizedDescription)"
        }
    }

    func stopSetup() {
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    func saveSettings() {
        let settings = InstallerSettings(
            workspaceRoot: workspaceRoot,
            configDir: configDir,
            provider: provider.rawValue,
            cloneMode: cloneMode.rawValue,
            installMissingPrerequisites: installMissingPrerequisites,
            launchUIAfterSetup: launchUIAfterSetup
        )
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsFileURL(), options: [.atomic])
        } catch {
            // Keep setup usable even if persistence fails.
        }
    }

    private func consumeOutput(_ chunk: String) {
        for rawLine in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(eventPrefix) {
                handleEventLine(line)
            } else {
                logs += line + "\n"
                parseLegacySignals(from: line)
            }
        }
    }

    private func parseLegacySignals(from line: String) {
        if line.contains("==>") || line.contains("Running") {
            currentStep = "running"
        }

        if let value = parseValue(line: line, key: "OpenClaw Gateway Token:") {
            gatewayToken = value
        }

        if let value = parseValue(line: line, key: "OPENCLAW_GATEWAY_CONTAINER=") {
            gatewayContainer = value
        }

        if isLikelyErrorLine(line), errorMessage.isEmpty {
            errorMessage = line
        }
    }

    private func isLikelyErrorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Ignore Docker BuildKit command echo lines that may include literal "ERROR:" snippets.
        if trimmed.range(of: "^#\\d+\\s+\\[[^\\]]+\\]\\s+RUN\\s", options: .regularExpression) != nil {
            return false
        }

        if trimmed.range(of: "^(ERROR:|Error:|error:)", options: .regularExpression) != nil {
            return true
        }

        if trimmed.range(of: "^(failed:|Failed:|failed\\s+to\\s|Failed\\s+to\\s)", options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private func handleEventLine(_ line: String) {
        let payload = String(line.dropFirst(eventPrefix.count))
        let parts = payload.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return }

        let type = parts[0]
        let key = parts[1]
        let value = parts[2]

        switch type {
        case "lifecycle":
            if key == "status" {
                setupStatus = value
                if value == "running" {
                    currentStep = "running"
                }
            }
            if key == "error", errorMessage.isEmpty, isLikelyErrorLine(value) {
                errorMessage = value
            }
            if key == "exit_code", value != "0", errorMessage.isEmpty {
                errorMessage = "Installer exited with code \(value)."
            }
        case "step":
            if key == "name" {
                currentStep = value
            }
        case "artifact":
            if key == "gateway_token" {
                gatewayToken = value
            }
            if key == "gateway_container" {
                gatewayContainer = value
            }
            if key == "log_file" {
                logFilePath = value
            }
            if key == "state_file" {
                stateFilePath = value
            }
        default:
            break
        }
    }

    func copyToClipboard(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    func pasteFromClipboard(into setter: (String) -> Void) {
        let pasteboard = NSPasteboard.general
        guard let value = pasteboard.string(forType: .string), !value.isEmpty else { return }
        setter(value)
    }

    func openPath(_ path: String) {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: value))
    }

    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func pickWorkspaceFolder() {
        if let selected = pickDirectory(startingAt: workspaceRoot) {
            workspaceRoot = selected
        }
    }

    func pickConfigFolder() {
        if let selected = pickDirectory(startingAt: configDir) {
            configDir = selected
        }
    }

    private func pickDirectory(startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        let response = panel.runModal()
        return response == .OK ? panel.url?.path : nil
    }

    private func isDockerDesktopInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "command -v docker >/dev/null 2>&1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func dockerDesktopGuidanceMessage() -> String {
        return """
Docker Desktop is required for ZaloClaw setup.

Please install Docker Desktop manually:
  1. Download from: https://www.docker.com/products/docker-desktop/
  2. Install the application
  3. Launch Docker Desktop from Applications folder
  4. Complete the first-run setup
  5. Wait until Docker is fully running
  6. Restart this installer

After installation, the docker command should be available in your shell.
"""
    }

    func isDockerError() -> Bool {
        return errorMessage.contains("Docker Desktop")
    }

    private func validateInputs() -> Bool {
        if !isDockerDesktopInstalled() {
            errorMessage = dockerDesktopGuidanceMessage()
            return false
        }
        if workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Workspace root is required."
            return false
        }
        if configDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "OpenClaw config directory is required."
            return false
        }
        if providerApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Provider API key is required."
            return false
        }
        if litellmMasterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "LiteLLM master key is required."
            return false
        }
        errorMessage = ""
        saveSettings()
        return true
    }

    private func buildRunnerArguments(scriptPath: URL) -> [String] {
        var args = [scriptPath.path]
        args += ["--workspace-root", workspaceRoot]
        args += ["--provider", provider.rawValue]
        args += ["--provider-api-key", providerApiKey]
        args += ["--litellm-master-key", litellmMasterKey]
        args += ["--config-dir", configDir]
        args += ["--clone-mode", cloneMode.rawValue]
        args += [launchUIAfterSetup ? "--launch-ui" : "--no-launch-ui"]
        args += [installMissingPrerequisites ? "--install-missing-prerequisites" : "--no-install-missing-prerequisites"]
        return args
    }

    private func parseValue(line: String, key: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        return line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func successSummaryMessage() -> String {
        var parts: [String] = ["ZClaw setup finished successfully."]

        if !workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Workspace: \(workspaceRoot)")
        }

        if !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Gateway token is available in Completion Artifacts.")
        }

        if !logFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Log file: \(logFilePath)")
        }

        return parts.joined(separator: "\n")
    }

    private func presentCompletionNotice(title: String, message: String) {
        completionNotice = CompletionNotice(title: title, message: message)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resolveRunnerScriptPath() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundledRunner = resourceURL
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("macos-swift-runner.sh")
                .standardizedFileURL
            if FileManager.default.fileExists(atPath: bundledRunner.path) {
                return bundledRunner
            }
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return root
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("macos-swift-runner.sh")
            .standardizedFileURL
    }

    private func settingsFileURL() -> URL {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ZClawInstaller", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("settings.json")
    }

    private func loadSettings() {
        let path = settingsFileURL()
        guard let data = try? Data(contentsOf: path),
              let settings = try? JSONDecoder().decode(InstallerSettings.self, from: data) else {
            return
        }

        workspaceRoot = settings.workspaceRoot
        configDir = settings.configDir
        provider = ProviderType(rawValue: settings.provider) ?? .openai
        cloneMode = CloneMode(rawValue: settings.cloneMode) ?? .replace
        installMissingPrerequisites = settings.installMissingPrerequisites
        launchUIAfterSetup = settings.launchUIAfterSetup ?? true
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: InstallerViewModel
    @State private var revealSecrets: Bool = false
    @MainActor
    init(model: InstallerViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundGradient,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if let url = Bundle.module.url(forResource: "zaloclaw-design", withExtension: "png"),
                       let nsImg = NSImage(contentsOf: url) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 32)
                    }
                    Text("ZClaw Installer")
                        .font(.title2.bold())
                        .foregroundStyle(primaryTextColor)
                    Spacer()
                    statusBadge(title: model.setupStatus.capitalized, icon: model.isRunning ? "bolt.horizontal.fill" : "checkmark.seal", tint: model.setupStatus == "failed" ? .red : (model.isRunning ? .orange : .green))
                    statusBadge(title: model.currentStep, icon: "list.bullet.rectangle", tint: .blue)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Label("Workspace Root", systemImage: "folder")
                                .frame(width: 150, alignment: .leading)
                            TextField("/path/to/workspace", text: $model.workspaceRoot)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                model.pickWorkspaceFolder()
                            } label: {
                                Label("Browse", systemImage: "folder.badge.plus")
                            }
                        }

                        HStack(spacing: 8) {
                            Label("Config Directory", systemImage: "externaldrive")
                                .frame(width: 150, alignment: .leading)
                            TextField("/path/to/.openclaw_z", text: $model.configDir)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                model.pickConfigFolder()
                            } label: {
                                Label("Browse", systemImage: "externaldrive.badge.plus")
                            }
                        }

                        HStack(spacing: 8) {
                            Label("Provider", systemImage: "brain")
                                .frame(width: 150, alignment: .leading)
                            Picker("Provider", selection: $model.provider) {
                                ForEach(ProviderType.allCases) { provider in
                                    Text(provider.rawValue).tag(provider)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Label("Provider API Key", systemImage: "key")
                                .frame(width: 150, alignment: .leading)
                            if revealSecrets {
                                TextField("Enter selected provider API key", text: $model.providerApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .textSelection(.enabled)
                            } else {
                                SecureField("Enter selected provider API key", text: $model.providerApiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                model.pasteFromClipboard { model.providerApiKey = $0 }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                model.copyToClipboard(model.providerApiKey)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.providerApiKey.isEmpty)
                        }

                        HStack(spacing: 8) {
                            Label("LiteLLM Key", systemImage: "lock.shield")
                                .frame(width: 150, alignment: .leading)
                            if revealSecrets {
                                TextField("Enter LITELLM master key", text: $model.litellmMasterKey)
                                    .textFieldStyle(.roundedBorder)
                                    .textSelection(.enabled)
                            } else {
                                SecureField("Enter LITELLM master key", text: $model.litellmMasterKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                model.pasteFromClipboard { model.litellmMasterKey = $0 }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                model.copyToClipboard(model.litellmMasterKey)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.litellmMasterKey.isEmpty)
                        }

                        HStack(spacing: 16) {
                            Toggle(isOn: $revealSecrets) {
                                Label("Show keys", systemImage: revealSecrets ? "eye.fill" : "eye.slash")
                            }
                            Toggle(isOn: $model.installMissingPrerequisites) {
                                Label("Install missing prerequisites", systemImage: "wrench.and.screwdriver")
                            }
                            Toggle(isOn: $model.launchUIAfterSetup) {
                                Label("Launch UI after setup", systemImage: "app.badge")
                            }
                        }

                        HStack(spacing: 8) {
                            Label("Clone Mode", systemImage: "arrow.triangle.2.circlepath")
                                .frame(width: 150, alignment: .leading)
                            Picker("Clone Mode", selection: $model.cloneMode) {
                                ForEach(CloneMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Configuration", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }
                .groupBoxStyle(.automatic)
                .padding(10)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button {
                        model.startSetup()
                    } label: {
                        Label("Start Setup", systemImage: "play.fill")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(model.isRunning)

                    Button {
                        model.stopSetup()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!model.isRunning)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        artifactRow(text: "Gateway Token", value: model.gatewayToken, icon: "key.horizontal") {
                            model.copyToClipboard(model.gatewayToken)
                        }
                        .disabled(model.gatewayToken.isEmpty)

                        artifactRow(text: "Gateway Container", value: model.gatewayContainer, icon: "shippingbox") {
                            model.copyToClipboard(model.gatewayContainer)
                        }
                        .disabled(model.gatewayContainer.isEmpty)

                        fileRow(text: "Log File", value: model.logFilePath, icon: "doc.text") {
                            model.openPath(model.logFilePath)
                        }
                        .disabled(model.logFilePath.isEmpty)

                        fileRow(text: "State File", value: model.stateFilePath, icon: "doc.richtext") {
                            model.openPath(model.stateFilePath)
                        }
                        .disabled(model.stateFilePath.isEmpty)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    Label("Completion Artifacts", systemImage: "checkmark.seal")
                        .font(.headline)
                }
                .padding(10)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )

                if !model.errorMessage.isEmpty {
                    if model.isDockerError() {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.title3)
                                Text("Docker Desktop Required")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                            }
                            
                            ScrollView([.vertical], showsIndicators: false) {
                                Text(model.errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(height: 140)
                            
                            HStack(spacing: 10) {
                                Button(action: {
                                    model.copyToClipboard(model.errorMessage)
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                
                                Button(action: {
                                    model.openURL("https://www.docker.com/products/docker-desktop/")
                                }) {
                                    Label("Open Download", systemImage: "link")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                                
                                Spacer()
                            }
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .border(Color.red.opacity(0.3), width: 1)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                                Text(model.errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                GroupBox {
                    ScrollView {
                        Text(model.logs.isEmpty ? "No output yet." : model.logs)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .foregroundStyle(primaryTextColor)
                    }
                    .background(consoleBackground, in: RoundedRectangle(cornerRadius: 10))
                    .frame(minHeight: 280)
                } label: {
                    Label("Embedded Output", systemImage: "terminal")
                        .font(.headline)
                }
                .padding(10)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
            }
            .padding(18)
            .tint(accentColor)
        }
        .frame(minWidth: 900, minHeight: 680)
        .overlay(alignment: .bottomTrailing) {
            donateQROverlay
                .padding(16)
        }
        .alert(item: $model.completionNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var backgroundGradient: [Color] {
        if colorScheme == .dark {
            return [Color(red: 0.10, green: 0.12, blue: 0.17), Color(red: 0.06, green: 0.07, blue: 0.10)]
        }
        return [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.16, blue: 0.22).opacity(0.95)
            : Color.white.opacity(0.92)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.88)
    }

    private var consoleBackground: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.black.opacity(0.05)
    }

    private var accentColor: Color {
        colorScheme == .dark ? Color.orange : Color.blue
    }

    @ViewBuilder
    private var donateQROverlay: some View {
        if let url = Bundle.module.url(forResource: "donate", withExtension: "png"),
           let nsImg = NSImage(contentsOf: url) {
            VStack(spacing: 6) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .cornerRadius(10)
                Text("Support us ☕")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
            .help("Scan to donate — thank you! ☕")
        }
    }

    private func statusBadge(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }

    private func artifactRow(text: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Label("\(text): \(value.isEmpty ? "(not detected)" : value)", systemImage: icon)
            Button(action: action) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    private func fileRow(text: String, value: String, icon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Label("\(text): \(value.isEmpty ? "(not detected)" : value)", systemImage: icon)
            Button(action: action) {
                Label("Open", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let viewModel = InstallerViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        fputs("[ZClawInstaller] Launching macOS window...\n", stderr)

        let contentView = ContentView(model: viewModel)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ZClaw Installer"
        window.center()
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        fputs("[ZClawInstaller] Window ready.\n", stderr)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct ZClawInstallerMain {
    @MainActor
    static func main() {
        fputs("[ZClawInstaller] Starting app runtime...\n", stderr)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
