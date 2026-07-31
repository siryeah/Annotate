import Combine
import SwiftUI

struct CursorSettingsView: View {
    @State private var clickEffectsEnabled: Bool = CursorHighlightManager.shared.clickEffectsEnabled
    @State private var cursorHighlightEnabled: Bool = CursorHighlightManager.shared.cursorHighlightEnabled
    @State private var effectColor: Color = Color(CursorHighlightManager.shared.effectColor)
    @State private var effectSize: Double = Double(CursorHighlightManager.shared.effectSize)
    @State private var spotlightSize: Double = Double(CursorHighlightManager.shared.spotlightSize)
    @State private var activeCursorStyle: ActiveCursorStyle = CursorHighlightManager.shared.activeCursorStyle
    @State private var activeCursorSize: Double = Double(CursorHighlightManager.shared.activeCursorSize)

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .cursor)
            }

            Section {
                LabeledContent {
                    ActiveCursorPreview(
                        style: activeCursorStyle,
                        color: CursorHighlightManager.shared.annotationColor,
                        size: CGFloat(activeCursorSize)
                    )
                } label: {
                    Text("Cursor Style")
                    Text("Choose how the cursor appears while annotating")
                }

                Picker("Cursor Style", selection: $activeCursorStyle) {
                    ForEach(ActiveCursorStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: activeCursorStyle) { _, newValue in
                    CursorHighlightManager.shared.activeCursorStyle = newValue
                }

                if activeCursorStyle == .brush
                    || activeCursorStyle == .circle
                    || activeCursorStyle == .crosshair
                {
                    SettingsSliderRow(
                        title: "Cursor Size",
                        value: $activeCursorSize,
                        range: 20...56,
                        boundsText: { "\(Int($0))" }
                    )
                    .onChange(of: activeCursorSize) { _, newValue in
                        Task { @MainActor in
                            CursorHighlightManager.shared.activeCursorSize = CGFloat(newValue)
                        }
                    }
                }
            } header: {
                SettingsHeader(
                    icon: "cursorarrow",
                    color: .purple,
                    title: "Active Cursor",
                    subtitle: "Cursor appearance when overlay is active"
                )
            }

            Section {
                Toggle(isOn: $cursorHighlightEnabled) {
                    Text("Enable Cursor Spotlight")
                    Text("Show spotlight following cursor")
                }
                .onChange(of: cursorHighlightEnabled) { _, _ in
                    CursorHighlightManager.shared.cursorHighlightEnabled = cursorHighlightEnabled
                }

                if cursorHighlightEnabled {
                    SettingsSliderRow(
                        title: "Spotlight Size",
                        value: $spotlightSize,
                        range: 30...100,
                        boundsText: { "\(Int($0))" }
                    )
                    .onChange(of: spotlightSize) { _, newValue in
                        Task { @MainActor in
                            CursorHighlightManager.shared.spotlightSize = CGFloat(newValue)
                        }
                    }
                }

                Toggle(isOn: $clickEffectsEnabled) {
                    Text("Enable Click Effect")
                    Text("Ripple on click + highlight while holding")
                }
                .onChange(of: clickEffectsEnabled) { _, _ in
                    CursorHighlightManager.shared.clickEffectsEnabled = clickEffectsEnabled
                }

                if clickEffectsEnabled {
                    SettingsSliderRow(
                        title: "Click Effect Size",
                        value: $effectSize,
                        range: 30...100,
                        boundsText: { "\(Int($0))" }
                    )
                    .onChange(of: effectSize) { _, newValue in
                        Task { @MainActor in
                            CursorHighlightManager.shared.effectSize = CGFloat(newValue)
                        }
                    }
                }

                if clickEffectsEnabled || cursorHighlightEnabled {
                    LabeledContent {
                        HStack(spacing: 6) {
                            ForEach(Array(colorPalette.enumerated()), id: \.offset) { _, color in
                                PresetColorButton(
                                    color: color,
                                    isSelected: NSColor(effectColor).isClose(to: color)
                                ) {
                                    effectColor = Color(color)
                                    CursorHighlightManager.shared.effectColor = color
                                }
                            }
                        }
                    } label: {
                        Text("Effect Color")
                    }
                }
            } header: {
                SettingsHeader(
                    icon: "cursorarrow.motionlines",
                    color: .pink,
                    title: "Cursor Highlight",
                    subtitle: "Spotlight and click effects for presentations"
                )
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .settingsScrollEdgeEffect()
        .onAppear {
            syncState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorHighlightStateChanged)) { _ in
            syncState()
        }
    }

    private func syncState() {
        clickEffectsEnabled = CursorHighlightManager.shared.clickEffectsEnabled
        cursorHighlightEnabled = CursorHighlightManager.shared.cursorHighlightEnabled
        effectColor = Color(CursorHighlightManager.shared.effectColor)
        effectSize = Double(CursorHighlightManager.shared.effectSize)
        spotlightSize = Double(CursorHighlightManager.shared.spotlightSize)
        activeCursorStyle = CursorHighlightManager.shared.activeCursorStyle
        activeCursorSize = Double(CursorHighlightManager.shared.activeCursorSize)
    }
}

private struct PresetColorButton: View {
    let color: NSColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SwiftUI.Circle()
                .fill(Color(color))
                .frame(width: 24, height: 24)
                .overlay(
                    SwiftUI.Circle()
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    SwiftUI.Circle()
                        .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ActiveCursorPreview: View {
    let style: ActiveCursorStyle
    let color: NSColor
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            switch style {
            case .none:
                drawPointerCursor(context: context, center: center, outerColor: .white)

            case .brush:
                drawBrushCursor(context: context, center: center, size: size)

            case .outline:
                drawPointerCursor(context: context, center: center, outerColor: Color(color))

            case .circle:
                let innerSize = size * 0.4
                let strokeWidth = max(2.0, size / 10)
                let outerRect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                let innerRect = CGRect(x: center.x - innerSize / 2, y: center.y - innerSize / 2, width: innerSize, height: innerSize)

                context.stroke(Path(ellipseIn: outerRect), with: .color(Color(color)), lineWidth: strokeWidth)
                context.fill(Path(ellipseIn: innerRect), with: .color(Color(color)))

            case .crosshair:
                var path = Path()
                path.move(to: CGPoint(x: center.x - size / 2, y: center.y))
                path.addLine(to: CGPoint(x: center.x + size / 2, y: center.y))
                path.move(to: CGPoint(x: center.x, y: center.y - size / 2))
                path.addLine(to: CGPoint(x: center.x, y: center.y + size / 2))

                context.stroke(path, with: .color(Color(color)), lineWidth: max(2.5, size / 5))
            }
        }
        .frame(width: 64, height: 64)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func drawPointerCursor(context: GraphicsContext, center: CGPoint, outerColor: Color) {
        let offsetX = center.x - 5.7
        let offsetY = center.y - 9.25

        var outerPath = Path()
        outerPath.move(to: CGPoint(x: offsetX, y: offsetY))
        outerPath.addLine(to: CGPoint(x: offsetX, y: offsetY + 16))
        outerPath.addLine(to: CGPoint(x: offsetX + 3.3, y: offsetY + 13.2))
        outerPath.addLine(to: CGPoint(x: offsetX + 6.1, y: offsetY + 18.5))
        outerPath.addLine(to: CGPoint(x: offsetX + 8, y: offsetY + 17.5))
        outerPath.addLine(to: CGPoint(x: offsetX + 9.6, y: offsetY + 16.6))
        outerPath.addLine(to: CGPoint(x: offsetX + 7, y: offsetY + 11.8))
        outerPath.addLine(to: CGPoint(x: offsetX + 11.4, y: offsetY + 11.8))
        outerPath.closeSubpath()

        var innerPath = Path()
        innerPath.move(to: CGPoint(x: offsetX + 1, y: offsetY + 2.8))
        innerPath.addLine(to: CGPoint(x: offsetX + 1, y: offsetY + 14))
        innerPath.addLine(to: CGPoint(x: offsetX + 3.5, y: offsetY + 11.6))
        innerPath.addLine(to: CGPoint(x: offsetX + 6.3, y: offsetY + 16.8))
        innerPath.addLine(to: CGPoint(x: offsetX + 8.2, y: offsetY + 15.9))
        innerPath.addLine(to: CGPoint(x: offsetX + 5.4, y: offsetY + 10.7))
        innerPath.addLine(to: CGPoint(x: offsetX + 9, y: offsetY + 10.7))
        innerPath.closeSubpath()

        context.fill(outerPath, with: .color(outerColor))
        context.fill(innerPath, with: .color(.black))
    }

    private func drawBrushCursor(
        context: GraphicsContext,
        center: CGPoint,
        size: CGFloat
    ) {
        let scale = size / 24
        let origin = CGPoint(
            x: center.x - 9.1 * scale,
            y: center.y + 9.2 * scale
        )

        var path = Path()
        path.move(to: origin)
        path.addCurve(
            to: CGPoint(x: origin.x + 6.2 * scale, y: origin.y - 3.2 * scale),
            control1: CGPoint(x: origin.x + 1.2 * scale, y: origin.y - 0.2 * scale),
            control2: CGPoint(x: origin.x + 4.2 * scale, y: origin.y - 0.8 * scale)
        )
        path.addLine(
            to: CGPoint(x: origin.x + 18.2 * scale, y: origin.y - 15.2 * scale)
        )
        path.addCurve(
            to: CGPoint(x: origin.x + 15.0 * scale, y: origin.y - 18.4 * scale),
            control1: CGPoint(x: origin.x + 19.0 * scale, y: origin.y - 16.1 * scale),
            control2: CGPoint(x: origin.x + 16.2 * scale, y: origin.y - 19.0 * scale)
        )
        path.addLine(
            to: CGPoint(x: origin.x + 3.2 * scale, y: origin.y - 6.2 * scale)
        )
        path.addCurve(
            to: origin,
            control1: CGPoint(x: origin.x + 1.3 * scale, y: origin.y - 4.4 * scale),
            control2: CGPoint(x: origin.x + 0.4 * scale, y: origin.y - 1.4 * scale)
        )
        path.closeSubpath()

        context.drawLayer { layerContext in
            layerContext.addFilter(
                .shadow(
                    color: .black.opacity(0.42),
                    radius: max(2.5, size * 0.11),
                    x: 1.2,
                    y: 1.4
                )
            )
            layerContext.fill(
                path,
                with: .color(Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255))
            )
            layerContext.stroke(path, with: .color(.white), lineWidth: max(2.5, size * 0.14))
        }

        var whiteDetails = Path()
        whiteDetails.move(
            to: CGPoint(x: origin.x + 0.7 * scale, y: origin.y - 0.7 * scale)
        )
        whiteDetails.addLine(
            to: CGPoint(x: origin.x + 5.8 * scale, y: origin.y - 2.8 * scale)
        )
        whiteDetails.addLine(
            to: CGPoint(x: origin.x + 2.8 * scale, y: origin.y - 5.8 * scale)
        )
        whiteDetails.closeSubpath()
        whiteDetails.move(
            to: CGPoint(x: origin.x + 10.7 * scale, y: origin.y - 11.0 * scale)
        )
        whiteDetails.addLine(
            to: CGPoint(x: origin.x + 12.8 * scale, y: origin.y - 9.0 * scale)
        )
        whiteDetails.addLine(
            to: CGPoint(x: origin.x + 15.7 * scale, y: origin.y - 11.9 * scale)
        )
        whiteDetails.addLine(
            to: CGPoint(x: origin.x + 13.6 * scale, y: origin.y - 14.0 * scale)
        )
        whiteDetails.closeSubpath()
        context.fill(whiteDetails, with: .color(.white))

        var blackTip = Path()
        blackTip.move(to: origin)
        blackTip.addLine(
            to: CGPoint(x: origin.x + 2.25 * scale, y: origin.y - 0.85 * scale)
        )
        blackTip.addLine(
            to: CGPoint(x: origin.x + 0.85 * scale, y: origin.y - 2.25 * scale)
        )
        blackTip.closeSubpath()
        context.fill(blackTip, with: .color(.black))
    }
}
