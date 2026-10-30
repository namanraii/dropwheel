import DropwheelCore
import SwiftUI

struct WheelView: View {
    @ObservedObject var model: WheelModel
    var backdrop: Color?
    var onCommit: (CatalogItem) -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if let backdrop {
                    backdrop
                }
                enclosure
                petals(in: size)
                labels(in: size)
                centerLabel
                if model.purpose != .drag {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(click)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                model.highlight(at: location, viewSize: size)
                            case .ended:
                                break
                            }
                        }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: WheelMetrics.windowSize, height: WheelMetrics.windowSize)
        .scaleEffect(model.appeared || reduceMotion ? 1 : 0.45, anchor: .center)
        .opacity(model.appeared || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : bloom, value: model.appeared)
        .onExitCommand { onDismiss() }
    }

    /// bloom .2s cubic-bezier(.18, .82, .24, 1), from scale .45
    private var bloom: Animation {
        .timingCurve(0.18, 0.82, 0.24, 1, duration: 0.2)
    }

    /// petal fill .12s ease
    private var highlightMove: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12)
    }

    /// Highlight used on Tangerine's wheel.
    private var accent: Color { Color(red: 1, green: 82 / 255, blue: 0) }

    private var ink: Color { Color(red: 40 / 255, green: 43 / 255, blue: 41 / 255) }

    private var glassFill: RadialGradient {
        RadialGradient(
            stops: [
                .init(color: Color.white.opacity(0.8), location: 0),
                .init(color: Color(red: 243 / 255, green: 246 / 255, blue: 247 / 255).opacity(0.58), location: 0.68),
                .init(color: Color(red: 244 / 255, green: 246 / 255, blue: 246 / 255).opacity(0.75), location: 1),
            ],
            center: .center,
            startRadius: 42,
            endRadius: WheelMetrics.outerRadius
        )
    }

    private var enclosure: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(Color.white.opacity(0.14)))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.22), lineWidth: 1.25))
            .frame(
                width: WheelMetrics.outerRadius * 2 + 22,
                height: WheelMetrics.outerRadius * 2 + 22
            )
            .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
    }

    private func petals(in size: CGSize) -> some View {
        let count = model.items.count
        return ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, _ in
                let active = model.highlighted == index
                PetalShape(index: index, count: count)
                    .fill(Color.white.opacity(0.92))
                    .overlay(PetalShape(index: index, count: count).fill(glassFill).opacity(active ? 0 : 1))
                    .overlay(PetalShape(index: index, count: count).fill(accent).opacity(active ? 1 : 0))
                    .overlay(
                        PetalShape(index: index, count: count)
                            .stroke(
                                active
                                    ? Color(red: 194 / 255, green: 101 / 255, blue: 52 / 255).opacity(112 / 255)
                                    : Color(red: 93 / 255, green: 102 / 255, blue: 102 / 255).opacity(56 / 255),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: Color(red: 38 / 255, green: 52 / 255, blue: 56 / 255).opacity(0.14), radius: 5, y: 3)
                    .animation(reduceMotion ? nil : highlightMove, value: model.highlighted)
                    .zIndex(active ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func labels(in size: CGSize) -> some View {
        let count = model.items.count
        return ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let angle = WheelMetrics.centerAngle(index: index, count: max(count, 1))
                let radius = WheelMetrics.labelRadius
                let x = size.width / 2 + CGFloat(cos(angle) * radius)
                let y = size.height / 2 - CGFloat(sin(angle) * radius)
                let active = model.highlighted == index
                let tool = !item.symbol.isEmpty
                ZStack {
                    if tool {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(active ? Color.white : Color.black)
                            .position(x: x, y: y - 12)
                    }
                    Text(item.title)
                    .font(.system(size: tool ? 9 : 13, weight: .semibold, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(active ? Color.white : Color.black)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .position(x: x, y: tool ? y + 8 : y)
                }
                .animation(reduceMotion ? nil : highlightMove, value: model.highlighted)
                .allowsHitTesting(false)
            }
        }
    }

    private var centerLabel: some View {
        Group {
            if model.items.isEmpty {
                Text(model.emptyMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160)
            } else if let selected = model.selectedItem {
                Text(selected.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .tracking(0.35)
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 70, minHeight: 32)
                    .background(Color.white.opacity(184 / 255), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(179 / 255), lineWidth: 1))
            }
        }
    }

    private var click: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                model.highlight(
                    at: value.location,
                    viewSize: CGSize(width: WheelMetrics.windowSize, height: WheelMetrics.windowSize)
                )
            }
            .onEnded { value in
                model.highlight(
                    at: value.location,
                    viewSize: CGSize(width: WheelMetrics.windowSize, height: WheelMetrics.windowSize)
                )
                if let item = model.selectedItem {
                    onCommit(item)
                } else {
                    onDismiss()
                }
            }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct PetalShape: Shape {
    var index: Int
    var count: Int

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(
                x: center.x + CGFloat(Darwin.cos(angle) * radius),
                y: center.y - CGFloat(Darwin.sin(angle) * radius)
            )
        }
        let outer = WheelMetrics.outerRadius
        let inner = WheelMetrics.innerRadius
        let gap = WheelMetrics.gap
        let corner = WheelMetrics.corner
        let mid = WheelMetrics.centerAngle(index: index, count: count)
        let sweep = 2 * Double.pi / Double(count)
        let leading = mid - sweep / 2
        let trailing = mid + sweep / 2
        func inset(_ radius: Double) -> Double {
            asin(min(0.95, gap / 2 / max(radius, gap / 2 + 0.01)))
        }
        let outerStart = leading + inset(outer)
        let outerEnd = trailing - inset(outer)
        let innerStart = leading + inset(inner)
        let innerEnd = trailing - inset(inner)
        let outerCorner = min(0.15, (outerEnd - outerStart) * 0.24)
        let innerCorner = min(0.18, (innerEnd - innerStart) * 0.18)
        let innerControl = inner / max(0.01, Darwin.cos(innerCorner))
        let innerLead = innerControl + inner * Darwin.tan(innerCorner)
        let outerLead = outer - corner

        var path = Path()
        path.move(to: point(innerLead, leading + inset(innerLead)))
        path.addLine(to: point(outerLead, leading + inset(outerLead)))
        path.addQuadCurve(to: point(outer, outerStart + outerCorner), control: point(outer, outerStart))
        appendArc(to: &path, from: outerStart + outerCorner, to: outerEnd - outerCorner, radius: outer, point: point)
        path.addQuadCurve(to: point(outerLead, trailing - inset(outerLead)), control: point(outer, outerEnd))
        path.addLine(to: point(innerLead, trailing - inset(innerLead)))
        path.addQuadCurve(to: point(inner, innerEnd - innerCorner), control: point(innerControl, trailing - inset(innerControl)))
        appendArc(to: &path, from: innerEnd - innerCorner, to: innerStart + innerCorner, radius: inner, point: point)
        path.addQuadCurve(to: point(innerLead, leading + inset(innerLead)), control: point(innerControl, leading + inset(innerControl)))
        path.closeSubpath()
        return path
    }

    private func appendArc(
        to path: inout Path,
        from start: Double,
        to end: Double,
        radius: Double,
        point: (Double, Double) -> CGPoint
    ) {
        var delta = end - start
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let steps = 18
        for step in 1...steps {
            path.addLine(to: point(radius, start + delta * Double(step) / Double(steps)))
        }
    }
}
