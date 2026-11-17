import SwiftUI

struct EditTransactionView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let transaction: MoneyTransaction

    @State private var personName: String
    @State private var amountText: String
    @State private var secondaryAmountText: String
    @State private var currency: Currency
    @State private var type: TransactionType
    @State private var comment: String
    @State private var showError = false

    init(transaction: MoneyTransaction) {
        self.transaction = transaction
        _personName = State(initialValue: transaction.personName)
        _amountText = State(initialValue: transaction.amount.moneyText)
        _secondaryAmountText = State(initialValue: transaction.secondaryAmount?.moneyText ?? "")
        _currency = State(initialValue: transaction.currency)
        _type = State(initialValue: transaction.type)
        _comment = State(initialValue: transaction.comment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") {
                    TextField("Например: Равшан", text: $personName)
                        .textInputAutocapitalization(.words)
                }

                Section("Тип операции") {
                    Picker("Тип", selection: $type) {
                        Text("Гирифтам").tag(TransactionType.received)
                        Text("Супоридам").tag(TransactionType.paid)
                        Text("Обмен").tag(TransactionType.exchange)
                        Text("Корректировка").tag(TransactionType.adjustment)
                    }
                }

                Section("Сумма") {
                    TextField("Основная сумма", text: $amountText)
                        .keyboardType(.decimalPad)

                    Picker("Основная валюта", selection: $currency) {
                        ForEach(Currency.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Дополнительно \(currency == .USD ? "TJS" : "USD") (необязательно)", text: $secondaryAmountText)
                        .keyboardType(.decimalPad)
                }

                Section("Комментарий") {
                    TextField("Необязательно", text: $comment)
                }
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") { saveChanges() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Проверьте данные", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Введите имя и корректную сумму больше нуля.")
            }
        }
    }

    private func saveChanges() {
        let cleanName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let amount = amountText.decimalValue,
              amount > 0 else {
            showError = true
            return
        }

        var updated = transaction
        updated.personName = cleanName
        updated.amount = amount
        updated.currency = currency
        if let second = secondaryAmountText.decimalValue, second > 0 {
            let secondCurrency: Currency = currency == .USD ? .TJS : .USD
            updated.secondaryCurrency = secondCurrency
            updated.secondaryAmount = second

            let rate = store.preferences.usdToTJSRate
            if rate > 0 {
                let rawUSD: Decimal
                if currency == .USD {
                    rawUSD = amount + (second / rate)
                } else {
                    rawUSD = (amount / rate) + second
                }
                updated.usdToTJSRateSnapshot = rate
                updated.totalEquivalentUSD = rawUSD.truncated(scale: 2)
            }
        } else {
            updated.secondaryCurrency = nil
            updated.secondaryAmount = nil
            updated.usdToTJSRateSnapshot = nil
            updated.totalEquivalentUSD = nil
        }
        updated.type = type
        updated.comment = comment

        store.updateTransaction(updated)
        dismiss()
    }
}
