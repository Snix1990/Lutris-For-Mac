import SwiftUI

struct AddRunnerSheet: View {
    @ObservedObject var runnerManager: RunnerManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var binaryPath = ""
    @State private var category: Runner.RunnerCategory = .other

    var body: some View {
        VStack(spacing: 16) {
            LText("Benutzerdefinierten Runner hinzufügen")
                .font(.title2)
                .bold()

            Form {
                TextField(tr("Name"), text: $name)

                Picker(selection: $category) {
                    ForEach(Runner.RunnerCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                } label: {
                    LText("Kategorie")
                }

                HStack {
                    TextField(tr("Pfad zur Binary"), text: $binaryPath)
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            binaryPath = url.path
                        }
                    } label: { LText("Wählen") }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button { dismiss() } label: { LText("Abbrechen") }
                    .keyboardShortcut(.cancelAction)
                Button {
                    runnerManager.addCustomRunner(name: name, binaryPath: binaryPath, category: category)
                    dismiss()
                } label: { LText("Hinzufügen") }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || binaryPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
