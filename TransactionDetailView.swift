import SwiftUI
import UIKit

struct TransactionDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let tx: MoneyTransaction
    @State private var shareURL: URL?
    @State private var showTextShare = false
    @State private var selectedAttachment: TransactionAttachment?
    @State private var attachmentToDelete: TransactionAttachment?
    @State private var showDeleteAttachmentAlert = false

    private var currentTransaction: MoneyTransaction {
        store.transactions.first(where: { $0.id == tx.id }) ?? tx
    }

    var body: some View {
        List {
            Section("Операция") {
                LabeledContent("Номер", value: currentTransaction.number)
                LabeledContent("Имя", value: currentTransaction.personName)
                LabeledContent("Тип", value: currentTransaction.type.title)
                LabeledContent("Сумма", value: transactionAmountText(currentTransaction))
                if let rate = currentTransaction.usdToTJSRateSnapshot,
                   let totalUSD = currentTransaction.totalEquivalentUSD {
                    LabeledContent("Курс", value: "1$ = \(rate.moneyText) TJS")
                    LabeledContent("Итого в USD", value: "\(totalUSD.fixedMoneyText(2))$")
                }
                LabeledContent("Дата", value: currentTransaction.date.formatted(date: .abbreviated, time: .shortened))

                if !currentTransaction.comment.isEmpty {
                    LabeledContent("Комментарий", value: currentTransaction.comment)
                }
            }

            if !currentTransaction.attachments.isEmpty {
                Section("Фото и чеки") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(currentTransaction.attachments) { attachment in
                                attachmentThumbnail(attachment)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Text("\(currentTransaction.attachments.count) вложений")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    showTextShare = true
                } label: {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }

                Button {
                    shareURL = PDFService.singleReceipt(transaction: currentTransaction)
                } label: {
                    Label("Премиум PDF", systemImage: "doc.richtext.fill")
                }

                Button(role: .destructive) {
                    store.delete(currentTransaction)
                    dismiss()
                } label: {
                    Label("Удалить операцию", systemImage: "trash.fill")
                }
            }
        }
        .navigationTitle("Детали")
        .sheet(isPresented: $showTextShare) {
            ShareSheet(items: [shortShareText])
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .sheet(item: $selectedAttachment) { attachment in
            AttachmentPreview(attachment: attachment)
        }
        .alert("Удалить фото/чек?", isPresented: $showDeleteAttachmentAlert) {
            Button("Удалить", role: .destructive) {
                if let attachmentToDelete {
                    store.removeAttachment(transactionID: currentTransaction.id, attachmentID: attachmentToDelete.id)
                }
                attachmentToDelete = nil
            }
            Button("Отмена", role: .cancel) {
                attachmentToDelete = nil
            }
        } message: {
            Text("Вложение будет удалено из этой операции. Это действие нельзя отменить.")
        }
    }


    private var shortShareText: String {
        let name = currentTransaction.personName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = name.isEmpty ? "Без имени" : name
        let amountText = shareOperationAmountText(currentTransaction)

        switch currentTransaction.type {
        case .received:
            return "\(safeName)\n\(amountText) гирифтам"
        case .paid:
            return "\(safeName)\n\(amountText) супоридам"
        case .exchange:
            return "\(safeName)\n\(amountText) обмен"
        case .adjustment:
            return "\(safeName)\n\(amountText) корректировка"
        }
    }

    private func transactionAmountText(_ tx: MoneyTransaction) -> String {
        var parts = ["\(tx.amount.moneyText) \(tx.currency.rawValue)"]
        if let c = tx.secondaryCurrency, let a = tx.secondaryAmount, a > 0 {
            parts.append("\(a.moneyText) \(c.rawValue)")
        }
        return parts.joined(separator: " + ")
    }

    /// Text used by WhatsApp / Telegram / Messages sharing.
    /// Mixed USD + TJS operations are always displayed in a compact form such as:
    /// 1250$+150см=1266.16$
    private func shareOperationAmountText(_ tx: MoneyTransaction) -> String {
        guard let secondaryCurrency = tx.secondaryCurrency,
              let secondaryAmount = tx.secondaryAmount,
              secondaryAmount > 0 else {
            return "\(shareNumber(tx.amount))\(shareCurrencySymbol(tx.currency))"
        }

        // For mixed USD/TJS operations keep the readable order USD first, TJS second,
        // regardless of which currency was originally entered as the primary field.
        let usdAmount: Decimal?
        let tjsAmount: Decimal?

        if tx.currency == .USD && secondaryCurrency == .TJS {
            usdAmount = tx.amount
            tjsAmount = secondaryAmount
        } else if tx.currency == .TJS && secondaryCurrency == .USD {
            usdAmount = secondaryAmount
            tjsAmount = tx.amount
        } else {
            usdAmount = nil
            tjsAmount = nil
        }

        guard let usdAmount, let tjsAmount else {
            return "\(shareNumber(tx.amount))\(shareCurrencySymbol(tx.currency))+\(shareNumber(secondaryAmount))\(shareCurrencySymbol(secondaryCurrency))"
        }

        let totalUSD = tx.totalEquivalentUSD ?? mixedTotalUSD(usd: usdAmount, tjs: tjsAmount, tx: tx)
        let base = "\(shareNumber(usdAmount))$+\(shareNumber(tjsAmount))см"

        if let totalUSD {
            return "\(base)=\(shareNumber(totalUSD, forceTwoDecimals: true))$"
        }
        return base
    }

    private func mixedTotalUSD(usd: Decimal, tjs: Decimal, tx: MoneyTransaction) -> Decimal? {
        let rate = tx.usdToTJSRateSnapshot ?? store.preferences.usdToTJSRate
        guard rate > 0 else { return nil }
        return usd + (tjs / rate)
    }

    private func shareCurrencySymbol(_ currency: Currency) -> String {
        switch currency {
        case .USD: return "$"
        case .TJS: return "см"
        }
    }

    private func shareNumber(_ amount: Decimal, forceTwoDecimals: Bool = false) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = forceTwoDecimals ? 2 : 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: number) ?? number.stringValue
    }

    @ViewBuilder
    private func attachmentThumbnail(_ attachment: TransactionAttachment) -> some View {
        if let image = UIImage(data: attachment.data) {
            ZStack(alignment: .topTrailing) {
                Button {
                    selectedAttachment = attachment
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 118, height: 118)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    attachmentToDelete = attachment
                    showDeleteAttachmentAlert = true
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.88))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
    }
}

private struct AttachmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: TransactionAttachment

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = UIImage(data: attachment.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
