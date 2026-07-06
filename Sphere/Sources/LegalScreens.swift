import SwiftUI

/// Bundled legal text. Concise and honest for a local-first, MIT-licensed
/// personal app — a starting template to review with counsel before release.
private struct LegalTextView: View {
    let title: LocalizedStringKey
    let sections: [(heading: LocalizedStringKey, body: LocalizedStringKey)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.heading).font(.headline)
                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("This is a plain-language starting point, not legal advice.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsScreen: View {
    var body: some View {
        LegalTextView(title: "Terms of Service", sections: [
            ("The short version",
             "Sphere is a personal tool you run on your own device. Use it to organise your life; you're responsible for what you put in and act on."),
            ("Provided \u{201C}as is\u{201D}",
             "Sphere is open-source software provided under the MIT License, without warranty of any kind. We aren't liable for any loss arising from its use."),
            ("Not professional advice",
             "Anything Sphere or its AI agents suggest — about health, finances, or anything else — is informational only, not medical, financial, or legal advice."),
            ("Your keys, your accounts",
             "If you add an API key for a cloud AI provider, you're bound by that provider's terms, and any usage costs are yours."),
            ("Your data is yours",
             "You own everything you create in Sphere and can export or delete it at any time."),
        ])
    }
}

struct PrivacyPolicyScreen: View {
    var body: some View {
        LegalTextView(title: "Privacy Policy", sections: [
            ("Local-first by design",
             "Sphere stores all of your data in a database on your device. There is no account and no server we operate — we never receive your data."),
            ("No tracking",
             "Sphere contains no analytics, ads, or third-party tracking SDKs."),
            ("On-device AI",
             "When you use the built-in on-device model, your prompts never leave your phone."),
            ("Cloud AI (optional)",
             "If you choose to connect OpenRouter with your own key, only the messages for that conversation are sent to that provider, processed under their privacy policy."),
            ("Device permissions",
             "Health, location, photos, microphone, and speech are used only for the features you enable, and the data stays on your device."),
            ("Your control",
             "Export all your data to a file, or delete it, at any time from Settings."),
        ])
    }
}
