import SwiftUI

/// Konfigurierbare Style-Parameter für die Nav-Bar
public struct NavBarButtonStyle {
    public var activeColor: Color = Color.ps4Pink
    public var inactiveColor: Color = Color.white.opacity(0.4)
    public var highlightColor: Color = Color.white
    public var backgroundActive: Color = Color.ps4Pink.opacity(0.12)
    public var backgroundHighlighted: Color = Color.ps4Pink.opacity(0.3)
    public var backgroundDefault: Color = Color.white.opacity(0.1)
    public var borderWidth: CGFloat = 2
    public var shadowRadius: CGFloat = 12
    public var fontSize: CGFloat = 28
    
    public static let ps4Style = NavBarButtonStyle()
}


