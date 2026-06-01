import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @Binding var selectedGameID: UUID?
    @ObservedObject private var runnerManager = RunnerManager.shared
    @ObservedObject private var serviceManager = ServiceManager.shared
    @State private var showRunnerManager = false
    @State private var showServices = false
    @State private var showControllers = false
    @State private var showDesktopIntegration = false
    @State private var showStatistics = false
    @State private var showEmulatorSetup = false
    @State private var showSteamSync = false
    @State private var crossoverImportResult: Int?
    @State private var showCrossOverAlert = false

    var body: some View {
        List {
            Toggle(isOn: $viewModel.showFavoritesOnly) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 18)
                    LText("Favoriten").font(.system(size: 13))
                    Spacer()
                    if viewModel.favoriteCount > 0 {
                        Text("\(viewModel.favoriteCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.button)

            Section(header: Text(verbatim: tr("Filter")).font(.system(size: 16)).textCase(nil)) {
                Button {
                    viewModel.selectedRunner = nil
                    viewModel.selectedPlatform = nil
                    viewModel.selectedCategory = nil
                    viewModel.selectedGameCategory = nil
                    viewModel.showFavoritesOnly = false
                    selectedGameID = nil
                } label: {
                    HStack {
                        LText("Alle Spiele")
                            .foregroundColor(isAllSelected ? .accentColor : .primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if !viewModel.availablePlatforms.isEmpty {
                Section(header: Text(verbatim: tr("Plattform")).font(.system(size: 16)).textCase(nil)) {
                    ForEach(viewModel.availablePlatforms, id: \.self) { platform in
                        Button {
                            viewModel.selectedPlatform = viewModel.selectedPlatform == platform ? nil : platform
                            selectedGameID = nil
                        } label: {
                            HStack {
                                Text(platform)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !viewModel.availableGameCategories.isEmpty {
                Section(header: Text(verbatim: tr("Kategorien")).font(.system(size: 16)).textCase(nil)) {
                    ForEach(viewModel.availableGameCategories, id: \.self) { cat in
                        Button {
                            viewModel.selectedGameCategory = viewModel.selectedGameCategory == cat ? nil : cat
                            selectedGameID = nil
                        } label: {
                            HStack {
                                Text(cat)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if serviceManager.services.contains(where: { $0.installed }) {
                Section(header: Text(verbatim: tr("Drittanbieter")).font(.system(size: 16)).textCase(nil)) {
                    ForEach(serviceManager.services.filter(\.installed)) { service in
                        Button {
                            viewModel.selectedRunner = service.name
                            selectedGameID = nil
                        } label: {
                            HStack {
                                Text(service.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if service.gameCount > 0 {
                                    Text("\(service.gameCount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(header: Text(verbatim: tr("Scans")).font(.system(size: 16)).textCase(nil)) {
                Button {
                    showServices = true
                } label: {
                    LText("Alle scannen")
                }
                .buttonStyle(.plain)

                Button {
                    showSteamSync = true
                } label: {
                    LText("Steam-Bibliothek")
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        let count = viewModel.importFromCrossOverBottles()
                        crossoverImportResult = count
                        showCrossOverAlert = true
                    }
                } label: {
                    LText("CrossOver scannen")
                }
                .buttonStyle(.plain)
            }

             Section(header: Text(verbatim: tr("System")).font(.system(size: 16)).textCase(nil)) {
                Button {
                    showEmulatorSetup = true
                } label: {
                    HStack {
                        LText("Emulatoren")
                        Spacer()
                        let count = EmulatorManager.shared.emulators.filter(\.installed).count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showControllers = true
                } label: {
                    HStack {
                        LText("Controller")
                        Spacer()
                        let count = ControllerManager.shared.connectedControllers.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showDesktopIntegration = true
                } label: {
                    LText("Desktop")
                }
                .buttonStyle(.plain)

                Button {
                    showRunnerManager = true
                } label: {
                    LText("Runner verwalten")
                }
                .buttonStyle(.plain)

                Button {
                    showStatistics = true
                } label: {
                    LText("Statistiken")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .frame(maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 180)
        .sheet(isPresented: $showRunnerManager) {
            RunnerManagementView()
        }
        .sheet(isPresented: $showServices) {
            ServiceSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showControllers) {
            ControllerSettingsView()
        }
        .sheet(isPresented: $showDesktopIntegration) {
            DesktopIntegrationView()
        }
        .sheet(isPresented: $showEmulatorSetup) {
            EmulatorSetupView()
        }
        .sheet(isPresented: $showStatistics) {
            StatisticsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSteamSync) {
            SteamLibrarySyncView(viewModel: viewModel)
        }
        .alert(Text(verbatim: tr("CrossOver Scan")), isPresented: $showCrossOverAlert, presenting: crossoverImportResult) { _ in
            Button { } label: { LText("OK") }
        } message: { count in
            Text(verbatim: trf("%d Spiele aus CrossOver-Bottles importiert.", count))
        }
    }

    private var isAllSelected: Bool {
        viewModel.selectedRunner == nil
        && viewModel.selectedPlatform == nil
        && viewModel.selectedCategory == nil
        && viewModel.selectedGameCategory == nil
        && !viewModel.showFavoritesOnly
    }
}
