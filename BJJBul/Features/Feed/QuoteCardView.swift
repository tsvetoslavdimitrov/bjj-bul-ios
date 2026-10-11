import SwiftUI

struct QuoteCardView: View {
    let quote: Quote
    var isQuoteOfTheDay: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if isQuoteOfTheDay {
                    Text("quote.ofTheDay")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                Spacer()
                ShareLink(item: quote.shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Color.white)
                }
                .accessibilityLabel(Text("quote.share"))
            }
            Text(verbatim: "“\(quote.localizedText)”")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            if let author = quote.author {
                Text(verbatim: "— \(author)")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            BeltAccent(verified: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color.black, Color(red: 0.18, green: 0.18, blue: 0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}
