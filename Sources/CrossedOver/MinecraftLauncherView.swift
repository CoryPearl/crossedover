import SwiftUI
import CrossedOverCore

/// One launcher surface, shared by the sidebar menu and Settings. Installation
/// and gameplay stay in the same owned helper session after Microsoft sign-in.
struct MinecraftLauncherView: View {
    @Bindable var model: AppModel
    var renderingSnapshot = false
    @Environment(\.dismiss) private var dismiss
    @State private var uninstallConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Minecraft").font(.system(size: 28, weight: .semibold))
                    Text("Bedrock Edition · Windows").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel("Close Minecraft launcher")
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.bedrockActive && model.bedrockStatus?.phase != .playing {
                    if let progress = model.bedrockStatus?.progress { ProgressView(value: progress) }
                    else { ProgressView().controlSize(.small) }
                }
                if let error = model.bedrockError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            HStack(spacing: 12) {
                if model.bedrockActive {
                    Button(model.bedrockStopping ? "Stopping…" : model.bedrockStatus?.phase == .playing ? "Stop Minecraft" : "Cancel") {
                        model.stopMinecraft()
                    }.disabled(model.bedrockStopping)
                } else {
                    Button(model.bedrockInstalled ? "Play" : "Install & Play") { model.startMinecraft() }
                        .disabled(!model.bedrockAvailable || !model.bedrockChecked || model.busy)
                }
                Spacer()
                if model.bedrockInstalled {
                    Button("Game files & worlds") { model.openMinecraftFiles() }
                }
                if model.bedrockAvailable {
                    if renderingSnapshot { Image(systemName: "ellipsis").frame(width: 24) }
                    else {
                        Menu {
                            Button("Sign out of Microsoft…") { model.startMinecraft(signOut: true) }
                            if model.bedrockInstalled { Button("Uninstall Minecraft…", role: .destructive) { uninstallConfirmation = true } }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                            .disabled(model.bedrockActive || model.busy).accessibilityLabel("Minecraft options")
                    }
                }
            }.buttonStyle(.bordered)
            Divider()
            Text("Local Bedrock preview for Apple silicon and macOS 26+. Requires Rosetta and a Minecraft for Windows purchase. Your worlds use a separate environment; Steam and Epic can stay open. This does not run the Windows Xbox app or its full game catalog.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if renderingSnapshot {
                Text("Minecraft compatibility & setup").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Link("Minecraft compatibility & setup", destination: URL(string: "https://github.com/CoryPearl/crossedover/blob/xbox-bedrock-1.4/docs/XBOX_AND_BEDROCK.md")!)
                    .font(.system(size: 11))
            }
        }
        .padding(32).frame(width: 540).background(Color(white: 0.085)).tint(.white)
        .foregroundStyle(Color(white: 0.93)).preferredColorScheme(.dark)
        .task { await model.checkMinecraft() }
        .confirmationDialog("Uninstall Minecraft?", isPresented: $uninstallConfirmation, titleVisibility: .visible) {
            Button("Move game to Trash", role: .destructive) { model.uninstallMinecraft() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves Minecraft's game files to Trash. Your worlds and Windows environment stay in crossedover. Empty Trash to reclaim space; you can reinstall later.")
        }
    }

    private var title: String {
        if model.bedrockActive { return model.bedrockStopping ? "Stopping Minecraft…" : model.bedrockStatus?.title ?? "Checking Minecraft…" }
        if model.bedrockError != nil { return "Minecraft needs attention" }
        if !model.bedrockChecked { return "Checking the Bedrock runtime…" }
        if !model.bedrockAvailable { return "Bedrock preview runtime needed" }
        return model.bedrockInstalled ? "Ready to play" : "Bring your Windows edition to Mac"
    }
    private var detail: String {
        if model.bedrockActive { return model.bedrockStatus?.detail ?? "Verifying the separate runtime before starting." }
        if !model.bedrockAvailable { return "This build does not include the separate Bedrock runtime yet. Its setup button becomes available after that runtime is built and verified." }
        if model.bedrockInstalled { return "Open your installed Windows edition with your Microsoft account. Your worlds stay in Minecraft’s separate environment." }
        return "Sign in with your own Microsoft account. Minecraft is downloaded from Microsoft when a secure package is available."
    }
}
