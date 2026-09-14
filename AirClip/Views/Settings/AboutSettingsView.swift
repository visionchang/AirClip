import SwiftUI

struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("app_info")
                }

                Section {
                    Text("Copyright © 2025 Vision Studio. Licensed under the MIT License.")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                }
            }
            .formStyle(.grouped)
            
            HStack(spacing: 12) {
                Link(LocalizedStringKey("privacy_policy"), destination: LegalLinks.privacyPolicy)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .navigationTitle("about")
    }
}

