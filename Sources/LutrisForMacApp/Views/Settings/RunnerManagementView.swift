import SwiftUI

struct RunnerManagementView: View {
    @StateObject private var runnerManager = RunnerManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddRunner = false

    var body: some View {
        VStack(spacing: 0) {
            LText("Runner verwalten")
                .font(.title2)
                .bold()
                .padding()

            List {
                Section(header: Text(verbatim: tr("Verfügbare Runner"))) {
                    ForEach(runnerManager.runners) { runner in
                        HStack {
                            Image(systemName: runner.category.systemImage)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(runner.displayName)
                                    .font(.headline)
                                Text(runner.installType)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if runner.installed {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .helpLText("Installiert")
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .helpLText("Nicht installiert")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()

            HStack {
                Button { showAddRunner = true } label: { LText("Runner hinzufügen") }
                Spacer()
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 400)
        .sheet(isPresented: $showAddRunner) {
            AddRunnerSheet(runnerManager: runnerManager)
        }
    }
}
