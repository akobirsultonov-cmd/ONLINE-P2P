import SwiftUI

enum AppTheme {
    static let bg = Color(red: 0.018, green: 0.055, blue: 0.09)
    static let card = Color(red: 0.035, green: 0.10, blue: 0.15)
    static let card2 = Color(red: 0.05, green: 0.15, blue: 0.20)
    static let green = Color(red: 0.04, green: 0.80, blue: 0.50)
    static let blue = Color(red: 0.12, green: 0.48, blue: 0.98)
    static let gold = Color(red: 0.96, green: 0.63, blue: 0.14)
    static let red = Color(red: 0.96, green: 0.25, blue: 0.29)

    static func currencyColor(_ currency: Currency) -> Color {
        currency == .USD ? green : gold
    }

    static let titleFont = Font.system(size: 31, weight: .bold, design: .rounded)
    static let sectionFont = Font.system(size: 19, weight: .bold, design: .rounded)
    static let amountFont = Font.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
    static let tableHeaderFont = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let tableBodyFont = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let tableAmountFont = Font.system(size: 14, weight: .bold, design: .rounded).monospacedDigit()
}

struct ProCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding()
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}
