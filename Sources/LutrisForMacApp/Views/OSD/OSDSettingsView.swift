import SwiftUI

struct OSDSettingsView: View {
    @StateObject private var osd = OSDManager.shared

    var body: some View {
        Form {
            Section(header: Text(verbatim: "Position")) {
                Toggle("An Fenster anhängen", isOn: $osd.settings.attachToWindow)

                Picker("Ecke", selection: $osd.settings.position) {
                    ForEach(OSDPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }

                HStack {
                    Text(verbatim: "Y-Versatz")
                    Spacer()
                    TextField("", value: $osd.settings.verticalOffset, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text(verbatim: "px (-500–500)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                Slider(value: $osd.settings.verticalOffset, in: -500...500, step: 10)
            }

            Section(header: Text(verbatim: "Darstellung")) {
                HStack {
                    Text(verbatim: "Schriftgröße")
                    Spacer()
                    TextField("", value: $osd.settings.fontSize, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text(verbatim: "pt (9–24)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                HStack {
                    Text(verbatim: "Deckkraft")
                    Spacer()
                    TextField("", value: Binding(
                        get: { Int(osd.settings.opacity * 100) },
                        set: { osd.settings.opacity = Double($0) / 100 }
                    ), format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Text(verbatim: "% (10–100)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }

            Section(header: Text(verbatim: "Anzeige")) {
                Toggle("FPS", isOn: $osd.settings.showFPS)
                Toggle("RAM (%)", isOn: $osd.settings.showRAM)
                Toggle("CPU (%)", isOn: $osd.settings.showCPU)
                Toggle("GPU (%)", isOn: $osd.settings.showGPU)
                Toggle("FrameTimes", isOn: $osd.settings.showFrameTimes)
                Toggle("Media Player", isOn: $osd.settings.showMediaPlayer)
                Toggle("Logging Status", isOn: $osd.settings.showLogging)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { osd.isShowingSettings = true }
        .onDisappear { osd.isShowingSettings = false }
        .onChange(of: osd.settings.position) { _, _ in
            osd.updatePosition()
        }
        .onChange(of: osd.settings.attachToWindow) { _, _ in
            osd.updatePosition()
        }
        .onChange(of: osd.settings.verticalOffset) { _, _ in
            osd.updatePosition()
        }
    }
}
