import SwiftUI

/// The dot-matrix strip: orange dots on black, the unlit ones faintly there
/// as on the real thing. Redrawn only when its picture changes.
struct PinballDotMatrixView: View, Equatable {
    let dots: PinballDotFrame
    /// Bumped with every new message or score, so the strip can flash it in.
    let key: Int

    static let amber = Color(red: 1.0, green: 0.56, blue: 0.12)

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            PinballDotMatrixView.paint(context, size: size, dots: dots)
        }
        .aspectRatio(CGFloat(PinballDotFrame.columns) / CGFloat(PinballDotFrame.rows), contentMode: .fit)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Self.amber.opacity(0.35), lineWidth: 1)
        )
    }

    private static func paint(_ context: GraphicsContext, size: CGSize, dots: PinballDotFrame) {
        let columns = PinballDotFrame.columns, rows = PinballDotFrame.rows
        let pitch = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
        let x0 = (size.width - pitch * CGFloat(columns)) / 2
        let y0 = (size.height - pitch * CGFloat(rows)) / 2
        let r = pitch * 0.36
        var off = Path()
        var on = Path()
        var halo = Path()
        for row in 0..<rows {
            for column in 0..<columns {
                let cx = x0 + (CGFloat(column) + 0.5) * pitch
                let cy = y0 + (CGFloat(row) + 0.5) * pitch
                if dots[row, column] {
                    on.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                    let h = pitch * 0.62
                    halo.addEllipse(in: CGRect(x: cx - h, y: cy - h, width: h * 2, height: h * 2))
                } else {
                    off.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                }
            }
        }
        context.fill(off, with: .color(amber.opacity(0.10)))
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(halo, with: .color(amber.opacity(0.22)))
        context.fill(on, with: .color(amber))
    }
}
