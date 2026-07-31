import SwiftUI

struct ToolsSettingsView: View {
    @AppStorage(UserDefaults.fadeModeKey)
    private var fadeMode = true
    @AppStorage(UserDefaults.fadeDurationKey)
    private var fadeDuration: Double = defaultAnnotationFadeDuration
    @AppStorage(UserDefaults.defaultTextFontSizeKey)
    private var defaultTextSize: Double = Double(defaultTextAnnotationFontSize)
    @AppStorage(UserDefaults.defaultCounterFontSizeKey)
    private var defaultCounterSize: Double = Double(defaultCounterFontSize)

    var body: some View {
        let minTextSize = Double(textAnnotationFontSizeRange.lowerBound)
        let maxTextSize = Double(textAnnotationFontSizeRange.upperBound)
        let minCounterSize = Double(counterFontSizeRange.lowerBound)
        let maxCounterSize = Double(counterFontSizeRange.upperBound)
        let minFadeDuration = Double(annotationFadeDurationRange.lowerBound)
        let maxFadeDuration = Double(annotationFadeDurationRange.upperBound)
        Form {
            Section {
                PaneHeader(pane: .tools)
            }

            Section {
                Picker("Drawing Mode", selection: $fadeMode) {
                    Text("Fade").tag(true)
                    Text("Persist").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: fadeMode) { _, newValue in
                    AppDelegate.shared?.setFadeMode(newValue)
                }

                if fadeMode {
                    SettingsSliderRow(
                        title: "Fade Duration",
                        value: $fadeDuration,
                        range: minFadeDuration...maxFadeDuration,
                        step: 0.25,
                        valueText: { L10n.format("%.2f seconds", $0) },
                        boundsText: { L10n.format("%.0f seconds", $0) }
                    )
                    .onChange(of: fadeDuration) { _, newValue in
                        AppDelegate.shared?.updateFadeDuration(newValue)
                    }
                }
            } header: {
                SettingsHeader(
                    icon: "timer",
                    color: .blue,
                    title: "Drawing Behavior",
                    subtitle: "Choose whether annotations fade automatically or stay visible"
                )
            }

            Section {
                SettingsSliderRow(
                    title: "Default Text Size",
                    value: $defaultTextSize,
                    range: minTextSize...maxTextSize,
                    step: 1,
                    valueText: { "\(Int($0)) pt" },
                    boundsText: { "\(Int($0)) pt" }
                )
            } header: {
                SettingsHeader(
                    icon: "textformat.size",
                    color: .orange,
                    title: "Text Tool",
                    subtitle: "Adjust the default font size for text annotations"
                )
            }

            Section {
                SettingsSliderRow(
                    title: "Default Counter Size",
                    value: $defaultCounterSize,
                    range: minCounterSize...maxCounterSize,
                    step: 1,
                    valueText: { "\(Int($0)) pt" },
                    boundsText: { "\(Int($0)) pt" }
                )
            } header: {
                SettingsHeader(
                    icon: "number.circle",
                    color: .green,
                    title: "Counter Tool",
                    subtitle: "Adjust the default size for counter annotations"
                )
            }
        }
        .formStyle(.grouped)
        .settingsScrollEdgeEffect()
    }
}
