import CoreGraphics

struct DisplayAnchor: Codable, Equatable, Sendable {
    let id: DisplayID
    let origin: CGPoint

    init?(frame: CGRect, displays: [OtherDisplay]) {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let display = displays.first(where: { $0.bounds.contains(center) }) else { return nil }
        id = display.id
        origin = display.bounds.origin
    }

    func resolve(_ frame: CGRect, on bounds: CGRect) -> CGRect {
        frame.offsetBy(dx: bounds.minX - origin.x, dy: bounds.minY - origin.y)
    }
}
