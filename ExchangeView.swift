import SwiftUI

struct ExchangeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var personName = ""
    @State private var from: Currency = .USD
    @State private var to: Currency = .TJS
    @State private var fromAmount = ""
    @State private var manualToAmount = ""
    @State private var comment = ""
    @State private var rateText = ""
    @State private var useManualResult = false
    @State private var showConfirmation = false
    @State private var showError = false
    @State private var errorText = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, amount, result, rate, comment }

    private var rate: Decimal {
        rateText.decimalValue ?? store.preferences.usdToTJSRate
    }

    private var inputAmount: Decimal? {
        guard let value = fromAmount.decimalValue, value > 0 else { return nil }
        return value
    }

    private var calculatedToAmount: Decimal? {
        guard let amount = inputAmount, rate > 0 else { return nil }
        let result: Decimal = from == .USD ? amount * rate : amount / rate
        return result.truncated(scale: 2)
    }

    private var finalToAmount: Decimal? {
        if useManualResult {
            guard let value = manualToAmount.decimalValue, value > 0 else { return nil }
            return value
        }
        return calculatedToAmount
    }

    private var recentClients: [String] {
        var seen = Set<String>()
        return store.transactions.compactMap { tx in
            let name = tx.personName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { return nil }
            seen.insert(name)
            return name
        }.prefix(5).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        directionCard
                        rateCard
                        amountCard
                        balancePreviewCard
                        detailsCard
                        saveButton
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                rateText = store.preferences.usdToTJSRate.fixedMoneyText(2)
            }
            .alert("Проверьте обмен", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText)
            }
            .alert("Сохранить обмен?", isPresented: $showConfirmation) {
                Button("Сохранить") { saveExchange() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(confirmationText)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Обмен валют")
                    .font(AppTheme.titleFont)
                    .foregroundStyle(.white)
                Text("USD ↔ TJS • автоматический расчёт")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
    }

    private var directionCard: some View {
        ProCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Направление", systemImage: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("1$ = \(rate.fixedMoneyText(2)) TJS")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.green)
                }

                HStack(spacing: 10) {
                    currencyBox(title: "Отдаю", currency: from, amount: inputAmount)

                    Button(action: swapCurrencies) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(AppTheme.blue.opacity(0.22))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(AppTheme.blue.opacity(0.45), lineWidth: 1))
                    }

                    currencyBox(title: "Получаю", currency: to, amount: finalToAmount)
                }
            }
        }
    }

    private func currencyBox(title: String, currency: Currency, amount: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 6) {
                Text(currency.symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.currencyColor(currency))
                Text(currency.rawValue)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text(amount.map { $0.moneyText } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var rateCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Курс доллара", systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("USD → TJS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.gold)
                }

                HStack(spacing: 8) {
                    Text("1$ =")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))

                    TextField("9.30", text: $rateText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .rate)
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 46)
                        .background(Color.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text("TJS")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.gold)

                    Button("Сохранить") {
                        guard rate > 0 else { return }
                        store.setUSDToTJSRate(rate)
                        focusedField = nil
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.green)
                }

                Text("Ответ ниже пересчитывается автоматически при изменении суммы или курса.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var amountCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Сумма обмена")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Вся сумма") {
                        let balance = store.cashBalance(from)
                        if balance > 0 { fromAmount = balance.moneyText }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.blue)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Вы отдаёте")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    HStack {
                        TextField("0", text: $fromAmount)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .amount)
                            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .onChange(of: fromAmount) { _ in
                                if !useManualResult { manualToAmount = "" }
                            }
                        Text(from.rawValue)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.currencyColor(from))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Вы получите")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        if useManualResult {
                            HStack {
                                TextField("0", text: $manualToAmount)
                                    .keyboardType(.decimalPad)
                                    .focused($focusedField, equals: .result)
                                    .font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(AppTheme.green)
                                Text(to.rawValue)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(AppTheme.currencyColor(to))
                            }
                        } else {
                            Text(finalToAmount.map { "\($0.fixedMoneyText(2)) \(to.rawValue)" } ?? "0.00 \(to.rawValue)")
                                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(AppTheme.green)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .background(AppTheme.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.green.opacity(0.18), lineWidth: 1))

                Toggle(isOn: $useManualResult) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ручной результат")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Включай только если хочешь изменить рассчитанную сумму вручную")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
                .tint(AppTheme.green)
            }
        }
    }

    private var balancePreviewCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Проверка остатка", systemImage: "banknote.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                balanceRow(currency: from, before: store.cashBalance(from), after: store.cashBalance(from) - (inputAmount ?? 0))
                Divider().overlay(Color.white.opacity(0.08))
                balanceRow(currency: to, before: store.cashBalance(to), after: store.cashBalance(to) + (finalToAmount ?? 0))
            }
        }
    }

    private func balanceRow(currency: Currency, before: Decimal, after: Decimal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(currency.rawValue)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.currencyColor(currency))
                Text("Было: \(before.moneyText) \(currency.symbol)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("После обмена")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text("\(after.moneyText) \(currency.symbol)")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(after >= 0 ? .white : AppTheme.red)
            }
        }
    }

    private var detailsCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Детали")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)

                TextField("Имя клиента (необязательно)", text: $personName)
                    .focused($focusedField, equals: .name)
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if !recentClients.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentClients, id: \.self) { name in
                                Button(name) { personName = name }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(.horizontal, 12)
                                    .frame(height: 34)
                                    .background(Color.white.opacity(0.055))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                TextField("Комментарий (необязательно)", text: $comment)
                    .focused($focusedField, equals: .comment)
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var saveButton: some View {
        Button {
            validateAndConfirm()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                Text("Проверить и сохранить обмен")
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.86))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(AppTheme.green)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var confirmationText: String {
        guard let amount = inputAmount, let result = finalToAmount else { return "Проверьте сумму" }
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = name.isEmpty ? "Обмен" : name
        return "\(prefix)\n\(amount.moneyText) \(from.rawValue) → \(result.fixedMoneyText(2)) \(to.rawValue)\nКурс: 1$ = \(rate.fixedMoneyText(2)) TJS"
    }

    private func swapCurrencies() {
        let oldFrom = from
        from = to
        to = oldFrom
        if let currentResult = finalToAmount {
            fromAmount = currentResult.moneyText
        }
        manualToAmount = ""
        useManualResult = false
    }

    private func validateAndConfirm() {
        focusedField = nil
        guard rate > 0 else {
            errorText = "Введите правильный курс валюты."
            showError = true
            return
        }
        guard let amount = inputAmount, amount > 0 else {
            errorText = "Введите сумму, которую отдаёте."
            showError = true
            return
        }
        guard let result = finalToAmount, result > 0 else {
            errorText = "Не удалось рассчитать сумму получения."
            showError = true
            return
        }
        guard store.cashBalance(from) >= amount else {
            errorText = "Недостаточно \(from.rawValue). В наличии: \(store.cashBalance(from).moneyText) \(from.symbol)"
            showError = true
            return
        }
        store.setUSDToTJSRate(rate)
        showConfirmation = true
    }

    private func saveExchange() {
        guard let amount = inputAmount, let result = finalToAmount, amount > 0, result > 0 else { return }
        store.addExchange(
            personName: personName.trimmingCharacters(in: .whitespacesAndNewlines),
            from: from,
            fromAmount: amount,
            to: to,
            toAmount: result,
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            rateSnapshot: rate
        )
        dismiss()
    }
}

struct AdjustmentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var currency: Currency = .USD
    @State private var amountText = ""
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Валюта", selection: $currency) {
                    ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                }

                TextField("Например 50 или -50", text: $amountText)
                    .keyboardType(.numbersAndPunctuation)

                TextField("Причина", text: $reason)

                Button("Сохранить корректировку") {
                    if let value = amountText.decimalValue, value != 0, !reason.isEmpty {
                        store.addTransaction(
                            personName: "Корректировка",
                            type: .adjustment,
                            amount: value,
                            currency: currency,
                            comment: reason
                        )
                        dismiss()
                    }
                }
            }
            .navigationTitle("Корректировка")
        }
    }
}
