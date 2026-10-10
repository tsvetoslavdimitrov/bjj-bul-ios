import SwiftUI

enum LegalDocument: String, Identifiable, CaseIterable {
    case terms, privacy

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .terms: return "legal.terms"
        case .privacy: return "legal.privacy"
        }
    }

    /// Loads the bundled Markdown (Legal/terms_bg.md etc.), Bulgarian or English by device language.
    func load() -> String {
        let language = Locale.current.language.languageCode?.identifier == "bg" ? "bg" : "en"
        let name = "\(rawValue)_\(language)"
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Legal"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "Contact: \(AppConfig.contactEmail)"
        }
        return text
    }
}

/// Minimal Markdown renderer: headings (#, ##), bullet lists (- ) and inline formatting.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    lineView(line)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(document.titleKey)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lines: [String] {
        document.load()
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3)))).font(.headline).padding(.top, 6)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2)))).font(.title2).bold()
        } else if line.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 6) {
                Text(verbatim: "•")
                Text(inline(String(line.dropFirst(2))))
            }
        } else {
            Text(inline(line))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
