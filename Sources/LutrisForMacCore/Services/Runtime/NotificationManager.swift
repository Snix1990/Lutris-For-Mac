import Foundation
import SwiftUI

public enum NotificationType: Equatable, Sendable {
    case info, warning, error, success
}

public struct NotificationItem: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let type: NotificationType
    public let icon: String
    public let title: String
    public let message: String
    public let timestamp = Date()
    public let duration: TimeInterval

    public init(type: NotificationType, icon: String, title: String, message: String, duration: TimeInterval = 4) {
        self.type = type
        self.icon = icon
        self.title = title
        self.message = message
        self.duration = duration
    }
}

@MainActor
public final class NotificationManager: ObservableObject {
    public static let shared = NotificationManager()

    @Published public private(set) var activeNotifications: [NotificationItem] = []
    public var maxVisible = 5

    private init() {}

    public func post(_ item: NotificationItem) {
        activeNotifications.insert(item, at: 0)
        if activeNotifications.count > maxVisible {
            activeNotifications.removeLast(activeNotifications.count - maxVisible)
        }

        if item.duration > 0 {
            let id = item.id
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(item.duration * 1_000_000_000))
                self?.dismiss(id: id)
            }
        }
    }

    public func dismiss(id: UUID) {
        activeNotifications.removeAll { $0.id == id }
    }

    public func dismissAll() {
        activeNotifications.removeAll()
    }

    public nonisolated static func info(title: String, message: String, duration: TimeInterval = 4) {
        Task { @MainActor in
            shared.post(NotificationItem(type: .info, icon: "info.circle.fill",
                                         title: title, message: message, duration: duration))
        }
    }

    public nonisolated static func warning(title: String, message: String, duration: TimeInterval = 5) {
        Task { @MainActor in
            shared.post(NotificationItem(type: .warning, icon: "exclamationmark.triangle.fill",
                                         title: title, message: message, duration: duration))
        }
    }

    public nonisolated static func error(title: String, message: String, duration: TimeInterval = 6) {
        Task { @MainActor in
            shared.post(NotificationItem(type: .error, icon: "xmark.circle.fill",
                                         title: title, message: message, duration: duration))
        }
    }

    public nonisolated static func success(title: String, message: String, duration: TimeInterval = 3) {
        Task { @MainActor in
            shared.post(NotificationItem(type: .success, icon: "checkmark.circle.fill",
                                         title: title, message: message, duration: duration))
        }
    }
}

// MARK: - OSD Overlay View

public struct NotificationOverlayView: View {
    @StateObject private var manager = NotificationManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(manager.activeNotifications) { item in
                NotificationRow(item: item)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(item.id)
            }
        }
        .padding(10)
        .frame(maxWidth: 320, alignment: .trailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.activeNotifications.count)
        .allowsHitTesting(true)
    }
}

private struct NotificationRow: View {
    let item: NotificationItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .foregroundColor(tintColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(verbatim: item.message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                Button { NotificationManager.shared.dismiss(id: item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tintColor.opacity(0.08))
                }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tintColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
        .onHover { hovering = $0 }
        .onTapGesture { NotificationManager.shared.dismiss(id: item.id) }
        .padding(.horizontal, 4)
    }

    private var tintColor: Color {
        switch item.type {
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        case .success: return .green
        }
    }
}
