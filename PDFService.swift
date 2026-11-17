import UIKit
import SwiftUI

enum PDFService {
    static func singleReceipt(transaction: MoneyTransaction) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(transaction.number).pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                drawPageBackground(page)
                drawGreenFrame(page)
                drawTitle(title: transaction.type.title, period: shortDate(transaction.date), page: page)

                let headerY: CGFloat = 190
                drawTableHeader(y: headerY, page: page)
                let rect = CGRect(x: 48, y: headerY + 32, width: page.width - 96, height: 48)
                drawRow(index: 1, transaction: transaction, rect: rect, zebra: false)

                drawTotalsBox(
                    operationCount: 1,
                    transactions: [transaction],
                    page: page,
                    y: 390
                )
            }
            return url
        } catch {
            print("PDF error:", error)
            return nil
        }
    }

    static func premiumList(
        transactions: [MoneyTransaction],
        type: TransactionType,
        from: Date,
        to: Date,
        checkpoints: [ReportBalanceCheckpoint] = []
    ) -> URL? {
        let filtered = transactions
            .filter { $0.type == type && $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }

        let reportCheckpoints = checkpoints
            .filter { $0.reportType == type && $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(type.title)-Report.pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        do {
            try renderer.writePDF(to: url) { context in
                var currentY: CGFloat = 0
                var firstPage = true
                var sectionRowIndex = 0

                func beginPage(showTitle: Bool) {
                    context.beginPage()
                    drawPageBackground(page)
                    drawGreenFrame(page)
                    if showTitle {
                        drawTitle(
                            title: type.title,
                            period: "Период: \(shortDate(from)) — \(shortDate(to))",
                            page: page
                        )
                        drawTableHeader(y: 190, page: page)
                        currentY = 224
                    } else {
                        drawTableHeader(y: 58, page: page)
                        currentY = 92
                    }
                    firstPage = false
                }

                func ensureSpace(_ needed: CGFloat) {
                    if currentY + needed > 790 {
                        beginPage(showTitle: false)
                    }
                }

                func drawTransactions(_ items: [MoneyTransaction]) {
                    sectionRowIndex = 0
                    for tx in items {
                        ensureSpace(48)
                        sectionRowIndex += 1
                        let rect = CGRect(x: 48, y: currentY, width: page.width - 96, height: 44)
                        drawRow(
                            index: sectionRowIndex,
                            transaction: tx,
                            rect: rect,
                            zebra: sectionRowIndex.isMultiple(of: 2)
                        )
                        currentY += 44
                    }
                }

                beginPage(showTitle: true)

                if filtered.isEmpty && reportCheckpoints.isEmpty {
                    "Нет операций за выбранный период".draw(
                        in: CGRect(x: 60, y: 250, width: page.width - 120, height: 30),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                            .foregroundColor: UIColor(white: 0.28, alpha: 1),
                            .paragraphStyle: centeredStyle()
                        ]
                    )
                    drawTotalsBox(operationCount: 0, transactions: [], page: page, y: 690)
                    return
                }

                var segmentStart = from

                for checkpoint in reportCheckpoints {
                    let segment = filtered.filter { $0.date >= segmentStart && $0.date <= checkpoint.date }
                    drawTransactions(segment)

                    ensureSpace(138)
                    drawSectionTotals(
                        operationCount: segment.count,
                        transactions: segment,
                        page: page,
                        y: currentY + 8
                    )
                    currentY += 70

                    drawBalanceCheckpoint(checkpoint, page: page, y: currentY + 8)
                    currentY += 62

                    // Start a fresh table after every manual balance marker,
                    // matching the user's handwritten report template.
                    if currentY + 78 > 790 {
                        beginPage(showTitle: false)
                    } else {
                        drawTableHeader(y: currentY + 8, page: page)
                        currentY += 50
                    }

                    segmentStart = checkpoint.date.addingTimeInterval(0.001)
                }

                let finalSegment = filtered.filter { $0.date >= segmentStart && $0.date <= to }
                drawTransactions(finalSegment)

                // The final summary appears only once after the last block.
                if currentY + 118 > 790 {
                    context.beginPage()
                    drawPageBackground(page)
                    drawGreenFrame(page)
                    currentY = 92
                }
                drawTotalsBox(
                    operationCount: finalSegment.count,
                    transactions: finalSegment,
                    page: page,
                    y: max(currentY + 14, 690)
                )
            }
            return url
        } catch {
            print("PDF error:", error)
            return nil
        }
    }

    private static func drawPageBackground(_ page: CGRect) {
        UIColor.white.setFill()
        UIRectFill(page)
    }

    private static func drawGreenFrame(_ page: CGRect) {
        let green = brandGreen()
        let frame = UIBezierPath(rect: page.insetBy(dx: 18, dy: 18))
        green.setStroke()
        frame.lineWidth = 1.2
        frame.stroke()

        // Decorative corners similar to the selected mockup.
        let corner: CGFloat = 14
        let inset: CGFloat = 24
        let points: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: inset, y: inset + corner), CGPoint(x: inset, y: inset), CGPoint(x: inset + corner, y: inset)),
            (CGPoint(x: page.width - inset - corner, y: inset), CGPoint(x: page.width - inset, y: inset), CGPoint(x: page.width - inset, y: inset + corner)),
            (CGPoint(x: inset, y: page.height - inset - corner), CGPoint(x: inset, y: page.height - inset), CGPoint(x: inset + corner, y: page.height - inset)),
            (CGPoint(x: page.width - inset - corner, y: page.height - inset), CGPoint(x: page.width - inset, y: page.height - inset), CGPoint(x: page.width - inset, y: page.height - inset - corner))
        ]
        for triple in points {
            let p = UIBezierPath()
            p.move(to: triple.0)
            p.addLine(to: triple.1)
            p.addLine(to: triple.2)
            p.lineWidth = 2
            green.setStroke()
            p.stroke()
        }
    }

    private static func drawTitle(title: String, period: String, page: CGRect) {
        let green = brandGreen()
        let center = centeredStyle()

        // Clean report header: no app logo, no P2P Offline branding.
        title.draw(
            in: CGRect(x: 44, y: 58, width: page.width - 88, height: 48),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 30, weight: .bold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: center
            ]
        )

        period.draw(
            in: CGRect(x: 44, y: 111, width: page.width - 88, height: 24),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(white: 0.34, alpha: 1),
                .paragraphStyle: center
            ]
        )

        // Minimal premium divider.
        let y: CGFloat = 154
        let line = UIBezierPath()
        line.move(to: CGPoint(x: 70, y: y))
        line.addLine(to: CGPoint(x: page.width - 70, y: y))
        line.lineWidth = 1.25
        green.withAlphaComponent(0.75).setStroke()
        line.stroke()

        let dot = UIBezierPath(ovalIn: CGRect(x: page.midX - 3, y: y - 3, width: 6, height: 6))
        green.setFill()
        dot.fill()
    }

    private static func drawTableHeader(y: CGFloat, page: CGRect) {
        let green = brandGreen()
        let header = CGRect(x: 48, y: y, width: page.width - 96, height: 34)
        let headerPath = UIBezierPath(roundedRect: header, cornerRadius: 10)
        green.setFill()
        headerPath.fill()

        let whiteStyle: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.white
        ]

        "№".draw(in: CGRect(x: 62, y: y + 9, width: 24, height: 16), withAttributes: whiteStyle)
        "ИМЯ".draw(in: CGRect(x: 103, y: y + 9, width: 160, height: 16), withAttributes: whiteStyle)
        "СУММА".draw(in: CGRect(x: 286, y: y + 9, width: 70, height: 16), withAttributes: whiteStyle)
        "ВАЛЮТА".draw(in: CGRect(x: 384, y: y + 9, width: 68, height: 16), withAttributes: whiteStyle)
        "ДАТА".draw(in: CGRect(x: 480, y: y + 9, width: 55, height: 16), withAttributes: whiteStyle)
    }

    private static func drawRow(index: Int, transaction: MoneyTransaction, rect: CGRect, zebra: Bool) {
        let green = brandGreen()
        if zebra {
            UIColor(white: 0.985, alpha: 1).setFill()
            UIBezierPath(rect: rect).fill()
        }

        UIColor(white: 0.88, alpha: 1).setStroke()
        let bottom = UIBezierPath()
        bottom.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        bottom.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        bottom.lineWidth = 0.7
        bottom.stroke()

        let numberStyle: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        let textStyle: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor(white: 0.08, alpha: 1)
        ]
        let amountStyle: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
            .foregroundColor: green
        ]
        let dateStyle: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor(white: 0.18, alpha: 1)
        ]

        "\(index))".draw(in: CGRect(x: 62, y: rect.minY + 13, width: 30, height: 18), withAttributes: numberStyle)
        (transaction.personName.isEmpty ? "Без имени" : transaction.personName).draw(
            in: CGRect(x: 103, y: rect.minY + 12, width: 165, height: 20),
            withAttributes: textStyle
        )
        // For mixed USD + TJS operations the PDF shows one normalized USD total.
        // Example: 1250 USD + 420 TJS at the saved rate -> 1290 USD.
        let pdfValue = pdfDisplayValue(for: transaction)
        let amountText = pdfValue.amount.moneyText
        let currencyText = pdfValue.currency.rawValue
        amountText.draw(
            in: CGRect(x: 276, y: rect.minY + 12, width: 100, height: 20),
            withAttributes: amountStyle
        )
        currencyText.draw(
            in: CGRect(x: 382, y: rect.minY + 12, width: 74, height: 20),
            withAttributes: textStyle
        )
        shortDate(transaction.date).draw(
            in: CGRect(x: 478, y: rect.minY + 12, width: 60, height: 20),
            withAttributes: dateStyle
        )
    }

    private static func drawSectionTotals(
        operationCount: Int,
        transactions: [MoneyTransaction],
        page: CGRect,
        y: CGFloat
    ) {
        let green = brandGreen()
        let rect = CGRect(x: 48, y: y, width: page.width - 96, height: 54)
        UIColor(red: 0.975, green: 0.995, blue: 0.98, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
        green.withAlphaComponent(0.40).setStroke()
        let outline = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        outline.lineWidth = 1
        outline.stroke()

        "Всего операций: \(operationCount)".draw(
            in: CGRect(x: rect.minX + 18, y: rect.minY + 18, width: 190, height: 20),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: UIColor(white: 0.18, alpha: 1)
            ]
        )

        let totals = totalsByCurrency(transactions)
        let totalText = totals.isEmpty
            ? "Итого сумма: 0"
            : "Итого сумма: " + totals.map { "\($0.value.moneyText) \($0.key.rawValue)" }.joined(separator: "   ")
        totalText.draw(
            in: CGRect(x: rect.midX - 20, y: rect.minY + 18, width: rect.width / 2 + 10, height: 20),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold),
                .foregroundColor: green
            ]
        )
    }

    private static func drawBalanceCheckpoint(_ checkpoint: ReportBalanceCheckpoint, page: CGRect, y: CGFloat) {
        let green = brandGreen()
        let rect = CGRect(x: 48, y: y, width: page.width - 96, height: 46)
        let box = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        UIColor(red: 0.94, green: 0.985, blue: 0.95, alpha: 1).setFill()
        box.fill()
        green.setStroke()
        box.lineWidth = 1.4
        box.stroke()

        "ОСТАТОК".draw(
            in: CGRect(x: rect.minX + 18, y: rect.minY + 13, width: 150, height: 22),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .black),
                .foregroundColor: UIColor.black
            ]
        )

        "\(checkpoint.amount.moneyText) \(checkpoint.currency.rawValue)".draw(
            in: CGRect(x: rect.midX - 55, y: rect.minY + 11, width: 170, height: 24),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold),
                .foregroundColor: green
            ]
        )

        shortDate(checkpoint.date).draw(
            in: CGRect(x: rect.maxX - 90, y: rect.minY + 14, width: 72, height: 18),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor(white: 0.20, alpha: 1)
            ]
        )
    }

    private static func drawTotalsBox(
        operationCount: Int,
        transactions: [MoneyTransaction],
        page: CGRect,
        y: CGFloat
    ) {
        let green = brandGreen()
        let rect = CGRect(x: 48, y: y, width: page.width - 96, height: 100)
        let box = UIBezierPath(roundedRect: rect, cornerRadius: 16)
        UIColor(red: 0.975, green: 0.995, blue: 0.98, alpha: 1).setFill()
        box.fill()
        green.withAlphaComponent(0.45).setStroke()
        box.lineWidth = 1
        box.stroke()

        // Chart circle
        let circleRect = CGRect(x: rect.minX + 24, y: rect.minY + 24, width: 52, height: 52)
        green.setFill()
        UIBezierPath(ovalIn: circleRect).fill()
        let chart = UIImage(systemName: "chart.bar.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        chart?.draw(in: CGRect(x: circleRect.minX + 15, y: circleRect.minY + 15, width: 22, height: 22))

        "Всего операций:".draw(
            in: CGRect(x: rect.minX + 96, y: rect.minY + 24, width: 150, height: 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(white: 0.25, alpha: 1)
            ]
        )
        "\(operationCount)".draw(
            in: CGRect(x: rect.minX + 96, y: rect.minY + 47, width: 90, height: 28),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 23, weight: .bold),
                .foregroundColor: green
            ]
        )

        let divider = UIBezierPath()
        divider.move(to: CGPoint(x: rect.midX, y: rect.minY + 20))
        divider.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 20))
        UIColor(white: 0.82, alpha: 1).setStroke()
        divider.lineWidth = 1
        divider.stroke()

        "Итого сумма:".draw(
            in: CGRect(x: rect.midX + 26, y: rect.minY + 22, width: 140, height: 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor(white: 0.25, alpha: 1)
            ]
        )

        // Keep the selected visual style, but present per-currency totals to avoid mixing currencies mathematically.
        let totals = totalsByCurrency(transactions)
        let totalText = totals.map { "\($0.key.rawValue): \($0.value.moneyText)" }.joined(separator: "   ")
        totalText.draw(
            in: CGRect(x: rect.midX + 26, y: rect.minY + 47, width: rect.width / 2 - 44, height: 36),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold),
                .foregroundColor: green
            ]
        )
    }

    private static func totalsByCurrency(_ transactions: [MoneyTransaction]) -> [(key: Currency, value: Decimal)] {
        Currency.allCases.compactMap { currency in
            let value = transactions.reduce(Decimal.zero) { partial, tx in
                let display = pdfDisplayValue(for: tx)
                return display.currency == currency ? partial + display.amount : partial
            }
            return value == 0 ? nil : (currency, value)
        }
    }

    /// Value shown in PDF reports. Mixed USD/TJS operations are represented
    /// by the USD equivalent captured when the operation was saved.
    private static func pdfDisplayValue(for transaction: MoneyTransaction) -> (amount: Decimal, currency: Currency) {
        guard let secondaryAmount = transaction.secondaryAmount,
              secondaryAmount > 0,
              let secondaryCurrency = transaction.secondaryCurrency else {
            return (transaction.amount, transaction.currency)
        }

        if let savedTotal = transaction.totalEquivalentUSD, savedTotal > 0 {
            return (savedTotal, .USD)
        }

        // Backward-compatible fallback for older mixed operations that do not
        // yet have totalEquivalentUSD saved. Use the rate snapshot from the
        // operation itself so later rate changes do not alter old PDF reports.
        if let rate = transaction.usdToTJSRateSnapshot, rate > 0 {
            var totalUSD: Decimal
            if transaction.currency == .USD && secondaryCurrency == .TJS {
                totalUSD = transaction.amount + (secondaryAmount / rate)
            } else if transaction.currency == .TJS && secondaryCurrency == .USD {
                totalUSD = (transaction.amount / rate) + secondaryAmount
            } else if transaction.currency == .USD {
                totalUSD = transaction.amount + secondaryAmount
            } else {
                totalUSD = (transaction.amount + secondaryAmount) / rate
            }

            var source = totalUSD
            var rounded = Decimal()
            NSDecimalRound(&rounded, &source, 2, .plain)
            return (rounded, .USD)
        }

        return (transaction.amount, transaction.currency)
    }

    private static func brandGreen() -> UIColor {
        UIColor(red: 0.02, green: 0.52, blue: 0.22, alpha: 1)
    }

    private static func centeredStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter.string(from: date)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
