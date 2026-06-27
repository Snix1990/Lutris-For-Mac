import SwiftUI
import LutrisForMacCore

struct RunnerProfilePickerView: View {
    let runnerName: String
    let currentProfileID: UUID?
    let profiles: [PlatformMappingProfile]
    let onSelect: (UUID?) -> Void
    let onBack: () -> Void
    let parentFocusManager: ConsoleFocusManager

    @StateObject private var focusManager = ConsoleFocusManager()

    private var items: [(id: UUID?, name: String)] {
        var result: [(UUID?, String)] = [(nil, tr("Kein Profil (Passthrough)"))]
        for p in profiles {
            result.append((p.id, p.name))
        }
        return result
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        onBack()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                            Text(verbatim: runnerName)
                                .font(.system(size: 24, weight: .bold))
                        }
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)

                // Profile list
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ScrollController().frame(width: 0, height: 0)

                            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                                let isSelected = item.id == currentProfileID
                                let isFocused = focusManager.isFocused(section: .allGames, index: offset)

                                HStack(spacing: 16) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(isSelected ? .ps4Pink : .white.opacity(0.4))
                                        .frame(width: 28)

                                    Text(item.name)
                                        .font(.system(size: 18, weight: isSelected ? .medium : .regular))
                                        .foregroundColor(.white)

                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(item.id)
                                }
                                .id("profile_\(offset)")
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: focusManager.focusedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("profile_\(newIndex)", anchor: .center)
                        }
                    }
                }
            }
        }
        .modifier(ControllerNavigationModifier(
            consoleState: ConsoleState(),
            focusManager: focusManager,
            gridColumns: 1,
            onConfirm: { _, index in
                guard index < items.count else { return }
                onSelect(items[index].id)
            },
            onBack: { onBack() },
            onSearchToggle: { },
            onUpdateFocusState: { },
            onSearchActiveChanged: { _ in }
        ))
        .onAppear {
            ControllerNavigationSystem.shared.setFocusManager(focusManager)
            ControllerNavigationSystem.shared.overrideActionMap = [
                .dpadUp: .moveUp,
                .dpadDown: .moveDown,
                .dpadLeft: .moveLeft,
                .dpadRight: .moveRight,
                .buttonA: .confirm,
                .buttonB: .back,
                .buttonMenu: .menu,
                .leftThumbstickButton: .confirm,
                .rightThumbstickButton: .back,
                .leftThumbStickUp: .moveUp,
                .leftThumbStickDown: .moveDown,
                .leftThumbStickLeft: .moveLeft,
                .leftThumbStickRight: .moveRight,
                .leftShoulder: .moveLeft,
                .rightShoulder: .moveRight,
                .leftTrigger: .cycleContentSectionUp,
                .rightTrigger: .cycleContentSectionDown,
                .buttonX: .toggleSearch,
                .buttonY: .menu,
                .buttonOptions: .back,
            ]
            focusManager.isLinearMode = true
            focusManager.activeSection = .allGames
            focusManager.focusedIndex = 0
            focusManager.itemCountInSection = items.count
        }
        .onDisappear {
            ControllerNavigationSystem.shared.overrideActionMap = nil
            ControllerNavigationSystem.shared.setFocusManager(parentFocusManager)
        }
    }
}
