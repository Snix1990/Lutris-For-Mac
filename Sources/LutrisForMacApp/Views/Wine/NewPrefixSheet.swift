import SwiftUI

struct NewPrefixSheet: View {
    @ObservedObject var wineManager: WineManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var architecture: WinePrefix.WineArch = .win64
    @State private var selectedWineVersion: WineVersion?
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            LText("Neuen Wineprefix erstellen")
                .font(.title2)
                .bold()

            Form {
                TextField(tr("Name"), text: $name)

                Picker(selection: $architecture) {
                    ForEach(WinePrefix.WineArch.allCases, id: \.self) { arch in
                        Text(arch.displayName).tag(arch)
                    }
                } label: {
                    LText("Architektur")
                }

                if !wineManager.installedVersions.isEmpty {
                    Picker(selection: $selectedWineVersion) {
                        LText("Standard").tag(nil as WineVersion?)
                        ForEach(wineManager.installedVersions) { v in
                            Text(v.displayName).tag(v as WineVersion?)
                        }
                    } label: {
                        LText("Wine-Version")
                    }
                }
            }
            .formStyle(.grouped)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button { dismiss() } label: { LText("Abbrechen") }
                    .keyboardShortcut(.cancelAction)

                Button { create() } label: { LText("Erstellen") }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func create() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                try await wineManager.createPrefix(
                    name: name.trimmingCharacters(in: .whitespaces),
                    architecture: architecture,
                    wineVersion: selectedWineVersion
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
