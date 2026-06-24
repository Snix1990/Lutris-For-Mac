import Foundation

public enum WineRenderMode: String, Codable, CaseIterable {
    case auto = "auto"
    case dxvkMoltenVK = "dxvk"
    case d3dMetal = "d3dmetal"

    public var displayName: String {
        switch self {
        case .auto: return "Automatisch"
        case .dxvkMoltenVK: return "DXVK + MoltenVK"
        case .d3dMetal: return "D3DMetal (GPTK)"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "Automatisch wählen (D3DMetal bevorzugt)"
        case .dxvkMoltenVK: return "DirectX 9-11 → Vulkan → Metal (breitere Kompatibilität)"
        case .d3dMetal: return "DirectX 11/12 → Metal (Apple GPTK, neuer & schneller)"
        }
    }
}
