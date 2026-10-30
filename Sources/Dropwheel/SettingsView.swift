import AppKit
import DropwheelCore
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var imageQuality: Double
    @Published var bitrate: Int
    @Published var dpi: Int
    @Published var reveal: Bool
    @Published var launchAtLogin: Bool
    @Published var loginMessage = ""
    @Published var binaries = BinaryAvailability.current()

    init() {
        let settings = ConvertSettings.load()
        imageQuality = Double(settings.imageQuality)
        bitrate = settings.audioBitrateKbps
        dpi = settings.pdfDPI
        reveal = settings.revealInFinder
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func save() {
        ConvertSettings(
            imageQuality: Int(imageQuality),
            audioBitrateKbps: bitrate,
            pdfDPI: dpi,
            revealInFinder: reveal
        ).clamped().save()
    }

    func refresh() {
        binaries = BinaryAvailability.current()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginMessage = ""
        } catch {
            loginMessage = "\(error.localizedDescription) Move Dropwheel.app into Applications if this keeps failing."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Images") {
                HStack {
                    Text("Quality \(Int(model.imageQuality))")
                    Slider(value: Binding(
                        get: { model.imageQuality },
                        set: { model.imageQuality = $0; model.save() }
                    ), in: 50...98, step: 1)
                }
            }
            Section("Audio") {
                Picker("Bitrate", selection: Binding(
                    get: { model.bitrate },
                    set: { model.bitrate = $0; model.save() }
                )) {
                    ForEach([128, 160, 192, 256, 320], id: \.self) { value in
                        Text("\(value) kbps").tag(value)
                    }
                }
            }
            Section("PDF pages") {
                Picker("Resolution", selection: Binding(
                    get: { model.dpi },
                    set: { model.dpi = $0; model.save() }
                )) {
                    Text("150 DPI").tag(150)
                    Text("300 DPI").tag(300)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Show the new file in Finder", isOn: Binding(
                    get: { model.reveal },
                    set: { model.reveal = $0; model.save() }
                ))
                Toggle("Open Dropwheel at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLogin($0) }
                ))
                if !model.loginMessage.isEmpty {
                    Text(model.loginMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("On this Mac") {
                dependency("ImageMagick", path: model.binaries.magick, hint: "brew install imagemagick")
                dependency("ffmpeg", path: model.binaries.ffmpeg, hint: "brew install ffmpeg")
                dependency("Ghostscript", path: model.binaries.ghostscript, hint: "brew install ghostscript")
                dependency("LibreOffice", path: model.binaries.libreOffice, hint: "brew install --cask libreoffice")
                dependency("unar", path: model.binaries.unar, hint: "brew install unar")
            }
            Section {
                Button("Open the log") {
                    NSWorkspace.shared.open(Log.url)
                }
                Text("Files stay on this Mac. Dropwheel writes a new copy beside the original.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.top, 8)
        .onAppear { model.refresh() }
    }

    private func dependency(_ name: String, path: String?, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            Text(path ?? "Not installed. \(hint)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

@MainActor
final class SettingsController {
    static let shared = SettingsController()
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "Dropwheel Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 480, height: 560))
            window.isReleasedWhenClosed = false
            self.window = window
        }
        model.refresh()
        AppActivation.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
