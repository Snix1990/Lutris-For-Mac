import SwiftUI

struct KeybindSettingsView: View {
    @State private var recordingAction: KeybindAction?
    @State private var eventMonitor: Any?
    @State private var refreshID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LText("Tastenkombinationen")
                .font(.title2).bold()

            LText("Klicke auf eine Tastenkombination, um sie zu ändern.")
                .font(.subheadline).foregroundColor(.secondary)

            List {
                ForEach(KeybindAction.allCases, id: \.rawValue) { action in
                    HStack {
                        Text(verbatim: action.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if recordingAction == action {
                            Text(tr("Taste drücken…"))
                                .foregroundColor(.accentColor)
                                .font(.body.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(4)
                        } else {
                            Button {
                                startRecording(action)
                            } label: {
                                Text(verbatim: Keybinds.shortcut(for: action).displayString)
                                    .font(.body.monospaced())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            Keybinds.reset(for: action)
                            refreshID += 1
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .helpLText("Auf Standard zurücksetzen")
                        .disabled(Keybinds.shortcut(for: action) == KeybindShortcut(key: action.defaultKey, modifiers: action.defaultModifiers))
                    }
                    .padding(.vertical, 4)
                }
            }
            .id(refreshID)
            .overlay(alignment: .bottom) {
                Button(tr("Alle zurücksetzen")) {
                    Keybinds.resetAll()
                    refreshID += 1
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(.bottom, 4)
            }
        }
        .padding()
        .onDisappear {
            removeMonitor()
        }
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        recordingAction = nil
    }

    private func startRecording(_ action: KeybindAction) {
        removeMonitor()
        recordingAction = action

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            guard recordingAction != nil else {
                removeMonitor()
                return event
            }

            guard let characters = event.charactersIgnoringModifiers else {
                removeMonitor()
                return event
            }

            let modifiers = event.modifierFlags
            let cmd = modifiers.contains(.command)
            let shift = modifiers.contains(.shift)
            let opt = modifiers.contains(.option)
            let ctrl = modifiers.contains(.control)

            guard cmd || shift || opt || ctrl else { return event }

            guard let ch = characters.first else {
                removeMonitor()
                return event
            }

            var mods: EventModifiers = []
            if cmd { mods.insert(.command) }
            if shift { mods.insert(.shift) }
            if opt { mods.insert(.option) }
            if ctrl { mods.insert(.control) }

            let shortcut = KeybindShortcut(key: KeyEquivalent(ch), modifiers: mods)
            Keybinds.setShortcut(shortcut, for: recordingAction ?? action)
            DispatchQueue.main.async {
                removeMonitor()
            }
            return nil
        }
        eventMonitor = monitor
    }
}
