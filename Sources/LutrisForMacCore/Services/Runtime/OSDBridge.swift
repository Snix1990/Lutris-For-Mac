import Foundation

@MainActor
public enum OSDBridge {
    public static var show: (() -> Void)?
    public static var hide: (() -> Void)?
}
