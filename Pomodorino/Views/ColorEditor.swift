import AppKit
import SwiftUI

enum EditableColor: CaseIterable, Equatable {
    case accent
    case work
    case `break`
    case paused

    var title: String {
        switch self {
        case .accent: return "Accent"
        case .work: return "Work"
        case .break: return "Break"
        case .paused: return "Paused"
        }
    }

    var detail: String {
        switch self {
        case .accent: return "Controls and selected tab"
        case .work: return "Focus timer and menu bar"
        case .break: return "Break timer and menu bar"
        case .paused: return "Paused timer and menu bar"
        }
    }
}

struct ColorSettingRow: View {
    let role: EditableColor
    let isSelected: Bool
    @Binding var color: StoredColor
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color.color)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.32), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(role.title)
                    Text(role.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(role.title.lowercased()) color")
    }
}

struct InlineColorEditor: View {
    let title: String
    @Binding var color: StoredColor
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Edit \(title) color")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Reset", action: onReset)
                    .controlSize(.small)
            }

            HStack(spacing: 14) {
                ColorWheel(
                    hue: hsb.hue,
                    saturation: hsb.saturation
                ) { hue, saturation in
                    updateColor(hue: hue, saturation: saturation)
                }
                .frame(width: 136, height: 136)

                VStack(alignment: .leading, spacing: 8) {
                    Circle()
                        .fill(color.color)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.32), lineWidth: 1)
                        }

                    Text("Color wheel")
                        .font(.caption.weight(.medium))
                    Text("Drag to choose hue and saturation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            ColorSlider(
                title: "Opacity",
                value: opacityBinding,
                tint: Color(hue: hsb.hue, saturation: max(hsb.saturation, 0.5), brightness: 0.9)
            )
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var hsb: HSBComponents {
        let nsColor = color.nsColor.usingColorSpace(.sRGB) ?? color.nsColor
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 1
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return HSBComponents(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(brightness),
            alpha: Double(alpha)
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { color.alpha },
            set: { updateColor(opacity: $0) }
        )
    }

    private func updateColor(
        hue: Double? = nil,
        saturation: Double? = nil,
        opacity: Double? = nil
    ) {
        let current = hsb
        let hue = (hue ?? current.hue).truncatingRemainder(dividingBy: 1)
        let saturation = saturation ?? current.saturation
        let brightness = (hue == current.hue && saturation == current.saturation)
            ? current.brightness
            : 1
        let chroma = brightness * saturation
        let sector = hue * 6
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma

        let rgb: (Double, Double, Double)
        switch sector {
        case 0..<1: rgb = (chroma, secondary, 0)
        case 1..<2: rgb = (secondary, chroma, 0)
        case 2..<3: rgb = (0, chroma, secondary)
        case 3..<4: rgb = (0, secondary, chroma)
        case 4..<5: rgb = (secondary, 0, chroma)
        default: rgb = (chroma, 0, secondary)
        }

        color = StoredColor(
            red: rgb.0 + match,
            green: rgb.1 + match,
            blue: rgb.2 + match,
            alpha: opacity ?? current.alpha
        )
    }
}

private struct ColorWheel: View {
    let hue: Double
    let saturation: Double
    let onChange: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: diameter / 2, y: diameter / 2)

            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        )
                    )
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter / 2
                        )
                    )
                Circle()
                    .stroke(.white.opacity(0.32), lineWidth: 1)
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .frame(width: 14, height: 14)
                    .position(selectionPoint(center: center, radius: diameter / 2))
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        select(at: value.location, center: center, radius: diameter / 2)
                    }
            )
        }
        .accessibilityLabel("Color wheel")
    }

    private func selectionPoint(center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = hue * (.pi * 2) - (.pi / 2)
        let distance = saturation * Double(radius)
        return CGPoint(
            x: center.x + CGFloat(cos(angle) * distance),
            y: center.y + CGFloat(sin(angle) * distance)
        )
    }

    private func select(at point: CGPoint, center: CGPoint, radius: CGFloat) {
        let x = point.x - center.x
        let y = point.y - center.y
        let distance = min(sqrt(x * x + y * y), radius)
        let normalizedAngle = (atan2(y, x) + (.pi / 2)) / (.pi * 2)
        let normalizedHue = normalizedAngle < 0 ? normalizedAngle + 1 : normalizedAngle
        onChange(Double(normalizedHue), Double(distance / radius))
    }
}

private struct ColorSlider: View {
    let title: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .frame(width: 62, alignment: .leading)
            Slider(value: $value, in: 0...1)
                .tint(tint)
        }
    }
}

private struct HSBComponents {
    let hue: Double
    let saturation: Double
    let brightness: Double
    let alpha: Double
}
