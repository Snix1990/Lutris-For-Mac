import SwiftUI

struct RunnerManagementView: View {
    @StateObject private var runnerManager = RunnerManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddRunner = false
    @State private var hoveredRunner: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                LText("Runner verwalten")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            .padding()

            Divider()

            GroupBox {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(runnerManager.runners) { runner in
                            let isHovered = hoveredRunner == runner.id
                            HStack {
                                Image(systemName: runner.category.systemImage)
                                    .font(.title3)
                                    .frame(width: 24)
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
                            .padding(10)
                            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                            .cornerRadius(8)
                            .onHover { hovering in
                                hoveredRunner = hovering ? runner.id : nil
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

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
