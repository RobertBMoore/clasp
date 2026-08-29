import AppKit
import SwiftUI

/// Shared, semantic presentation primitives for Clasp's native surfaces.
///
/// These values describe the application chrome only. Document typography
/// remains in `DocumentStyle`, and neither layer is ever serialized into a
/// note's Markdown source.
enum ClaspDesign {
    enum Metrics {
        static let editorToolbarControlHeight: CGFloat = 30
        static let editorToolbarIconWidth: CGFloat = 30
        static let editorToolbarCornerRadius: CGFloat = 7
        static let editorToolbarGroupSpacing: CGFloat = 6
        static let editorToolbarHorizontalPadding: CGFloat = 20
        static let editorToolbarVerticalPadding: CGFloat = 9
        static let editorToolbarHeight = editorToolbarControlHeight + (editorToolbarVerticalPadding * 2)

        static let editorCanvasInset: CGFloat = 16
        static let editorPageTopInset: CGFloat = 12
        static let editorPageContentTopPadding: CGFloat = 36
        static let editorPageCornerRadius: CGFloat = 10
        static let editorPageShadowRadius: CGFloat = 8

        static let paragraphStylePickerSize = CGSize(width: 286, height: 422)
        static let menuEdgeInset: CGFloat = 16
        static let menuCornerRadius: CGFloat = 12

        static let settingsPagePadding: CGFloat = 24
        static let settingsCardCornerRadius: CGFloat = 14
    }

    enum Motion {
        static let quick: Double = 0.1
        static let menu: Double = 0.12
    }

    enum Color {
        static let editorCanvas = NSColor(name: nil) { appearance in
            var resolved = NSColor.windowBackgroundColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor.windowBackgroundColor.blended(
                    withFraction: 0.32,
                    of: NSColor.underPageBackgroundColor
                ) ?? NSColor.windowBackgroundColor
            }
            return resolved
        }

        static var toolbarSurface: SwiftUI.Color {
            SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.72)
        }

        static var controlSurface: SwiftUI.Color {
            SwiftUI.Color(nsColor: .controlBackgroundColor).opacity(0.92)
        }

        static var controlBorder: SwiftUI.Color {
            SwiftUI.Color(nsColor: .separatorColor).opacity(0.58)
        }
    }
}

struct ClaspToolbarButtonStyle: ButtonStyle {
    var width: CGFloat = ClaspDesign.Metrics.editorToolbarIconWidth

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: width, height: ClaspDesign.Metrics.editorToolbarControlHeight)
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
            .background(
                configuration.isPressed
                    ? SwiftUI.Color.accentColor.opacity(0.16)
                    : ClaspDesign.Color.controlSurface,
                in: RoundedRectangle(
                    cornerRadius: ClaspDesign.Metrics.editorToolbarCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClaspDesign.Metrics.editorToolbarCornerRadius,
                    style: .continuous
                )
                .stroke(ClaspDesign.Color.controlBorder, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(
                .easeOut(duration: ClaspDesign.Motion.quick),
                value: configuration.isPressed
            )
    }
}

private struct ClaspToolbarControlSurface: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: ClaspDesign.Metrics.editorToolbarControlHeight)
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
            .background(
                ClaspDesign.Color.controlSurface,
                in: RoundedRectangle(
                    cornerRadius: ClaspDesign.Metrics.editorToolbarCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClaspDesign.Metrics.editorToolbarCornerRadius,
                    style: .continuous
                )
                .stroke(ClaspDesign.Color.controlBorder, lineWidth: 1)
            }
    }
}

extension View {
    func claspToolbarControlSurface(
        width: CGFloat = ClaspDesign.Metrics.editorToolbarIconWidth
    ) -> some View {
        modifier(ClaspToolbarControlSurface(width: width))
    }
}
