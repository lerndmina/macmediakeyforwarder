import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "Keys are sent to one app at a time. Order matters when nothing matches “Now Playing.” Built-in players use native control; other apps use Space and ⌘← / ⌘→ (see README)."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    "Prefer Now Playing app when it is in the list",
                    isOn: $preferences.preferNowPlayingRouting
                )
                .help(
                    "Uses Apple private Media Remote. Console may show repeated Operation not permitted under the debugger; often harmless. If keys go to the wrong app, describe that and try turning this off to compare."
                )

                List {
                    ForEach(Array(preferences.targets.enumerated()), id: \.element.bundleIdentifier) { index, target in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                TextField(
                                    "Display name",
                                    text: displayNameBinding(for: target.bundleIdentifier)
                                )
                                .textFieldStyle(.roundedBorder)
                                Text(target.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            VStack(spacing: 4) {
                                Button {
                                    moveTarget(from: index, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                Button {
                                    moveTarget(from: index, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index >= preferences.targets.count - 1)
                                Button(role: .destructive) {
                                    removeTarget(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(minHeight: 200)
                .border(Color(nsColor: .separatorColor))

                HStack {
                    Button("Add application…") { addApplication() }
                    Spacer()
                    Text("Use arrows to reorder. Remove with the trash control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(minWidth: 480, minHeight: 360)
            .navigationTitle("Targets & Routing")
        }
    }

    private func moveTarget(from index: Int, by delta: Int) {
        let to = index + delta
        guard preferences.targets.indices.contains(index),
              preferences.targets.indices.contains(to) else { return }
        var next = preferences.targets
        next.swapAt(index, to)
        preferences.targets = next
    }

    private func removeTarget(at index: Int) {
        guard preferences.targets.indices.contains(index) else { return }
        var next = preferences.targets
        next.remove(at: index)
        if next.isEmpty {
            next = BuiltInMediaPlayerBundle.orderedDefaults.map { PlayerTarget(bundleIdentifier: $0, displayName: nil) }
        }
        preferences.targets = next
    }

    private func displayNameBinding(for bundleID: String) -> Binding<String> {
        Binding(
            get: {
                guard let i = preferences.targets.firstIndex(where: { $0.bundleIdentifier == bundleID }) else { return "" }
                let t = preferences.targets[i]
                return t.displayName ?? BuiltInMediaPlayerBundle.defaultDisplayName(for: bundleID)
            },
            set: { newValue in
                guard let i = preferences.targets.firstIndex(where: { $0.bundleIdentifier == bundleID }) else { return }
                var next = preferences.targets
                next[i].displayName = newValue.isEmpty ? nil : newValue
                preferences.targets = next
            }
        )
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var bundleID: String?
        if let b = Bundle(url: url)?.bundleIdentifier, !b.isEmpty {
            bundleID = b
        } else if let b = Bundle(path: url.path)?.bundleIdentifier, !b.isEmpty {
            bundleID = b
        }

        guard let bid = bundleID else { return }
        if preferences.targets.contains(where: { $0.bundleIdentifier == bid }) { return }

        let name = FileManager.default.displayName(atPath: url.path)
        preferences.targets.append(PlayerTarget(bundleIdentifier: bid, displayName: name))
    }
}
