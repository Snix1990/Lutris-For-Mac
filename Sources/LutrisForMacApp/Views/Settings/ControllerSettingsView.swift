import SwiftUI

struct ControllerSettingsView: View {
    @StateObject private var controllerManager = ControllerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controllerList

            if !controllerManager.lastActivity.isEmpty {
                Text(verbatim: trf("Letzte Aktivität: %@", controllerManager.lastActivity))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            HStack {
                Button { controllerManager.refresh() } label: { LText("Aktualisieren") }
                Spacer()
                Button { dismiss() } label: { LText("Schliessen") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 300)
    }

    private var header: some View {
        HStack {
            Image(systemName: "gamecontroller")
                .font(.title2)
            LText("Controller")
                .font(.title2)
                .bold()
            Spacer()
            Text(verbatim: trf("%d verbunden", controllerManager.connectedControllers.count))
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var controllerList: some View {
        List {
            if controllerManager.connectedControllers.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        LText("Kein Controller verbunden")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        LText("Verbinde einen Controller via Bluetooth oder USB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                Section(header: Text(verbatim: tr("Verbunden"))) {
                    ForEach(controllerManager.connectedControllers) { controller in
                        HStack(spacing: 12) {
                            Image(systemName: controllerIcon(controller.category))
                                .font(.title3)
                                .foregroundColor(.accentColor)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(controller.vendorName)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(controller.category.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(controller.productCategory)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if let battery = controller.batteryLevel {
                                batteryIcon(battery, state: controller.batteryState)
                            }

                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
    }

    private func controllerIcon(_ category: ControllerManager.ControllerInfo.ControllerCategory) -> String {
        switch category {
        case .extended: return "gamecontroller.fill"
        case .micro: return "rectangle.3.group.fill"
        case .standard: return "gamecontroller"
        case .unknown: return "questionmark"
        }
    }

    private func batteryIcon(_ level: Float, state: ControllerManager.ControllerInfo.BatteryState) -> some View {
        let icon: String
        let color: Color
        switch level {
        case 0.75...1.0:
            icon = "battery.100"
            color = .green
        case 0.5..<0.75:
            icon = "battery.75"
            color = .green
        case 0.25..<0.5:
            icon = "battery.50"
            color = .orange
        case 0.1..<0.25:
            icon = "battery.25"
            color = .red
        default:
            icon = "battery.0"
            color = .red
        }
        return HStack(spacing: 4) {
            if state == .charging {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                    .font(.caption2)
            }
            Image(systemName: icon)
                .foregroundColor(color)
            Text(verbatim: "\(Int(level * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
