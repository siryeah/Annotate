import Sparkle
import SwiftUI

struct AboutView: View {
    static let customRepositoryURL =
        URL(string: "https://github.com/siryeah/annotate-cn-custom")!
    static let customIssuesURL =
        URL(string: "https://github.com/siryeah/annotate-cn-custom/issues")!
    static let originalRepositoryURL =
        URL(string: "https://github.com/epilande/Annotate")!

    private let updaterController: SPUStandardUpdaterController

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Annotate"
    }


    var body: some View {
        VStack(spacing: 20) {
            // App Icon and Name
            VStack(spacing: 12) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text("A")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                }
                
                VStack(spacing: 4) {
                    Text(appName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(
                        L10n.format(
                            "Version %@ (%@)",
                            appVersion,
                            buildNumber
                        )
                    )
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
                .padding(.horizontal)
            
            // Update Section
            VStack(spacing: 12) {
                Text("Automatic updates are disabled for this custom build")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal)
            
            // Links and Attribution
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    Link("Custom Edition", destination: Self.customRepositoryURL)
                        .font(.caption)

                    Link("Original Project", destination: Self.originalRepositoryURL)
                        .font(.caption)
                }

                Link("Report Issue", destination: Self.customIssuesURL)
                    .font(.caption)

                VStack(spacing: 3) {
                    Text("Original project by epilande")
                    Text("Customized by AI Product Manager April (@siryeah)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

#Preview {
    AboutView(updaterController: SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    ))
}
