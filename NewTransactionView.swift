import SwiftUI
import PhotosUI
import UIKit

struct NewTransactionView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private let initialType: TransactionType

    @State private var personName = ""
    @State private var type: TransactionType
    @State private var amountText = ""
    @State private var secondaryAmountText = ""
    @State private var currency: Currency = .USD
    @State private var comment = ""
    @State private var operationDate = Date()

    @State private var showConfirmation = false
    @State private var showError = false
    @State private var showClientPicker = false
    @State private var showDatePicker = false
    @State private var showCommentEditor = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [TransactionAttachment] = []

    init(initialType: TransactionType = .received) {
        self.initialType = initialType
        _type = State(initialValue: initialType)
    }

    private var accentColor: Color {
        type == .received ? AppTheme.green : AppTheme.blue
    }

    private var amount: Decimal? {
        amountText.decimalValue
    }

    private var secondaryCurrency: Currency {
        currency == .USD ? .TJS : .USD
    }

    private var secondaryAmount: Decimal? {
        guard let value = secondaryAmountText.decimalValue, value > 0 else { return nil }
        return value
    }

    private var mixedAmountText: String {
        var parts: [String] = []
        if let amount, amount > 0 { parts.append("\(amount.moneyText)\(currency.symbol)") }
        if let secondaryAmount { parts.append("\(secondaryAmount.moneyText)\(secondaryCurrency.symbol)") }
        return parts.isEmpty ? "0" : parts.joined(separator: " + ")
    }

    private var equivalentTJS: Decimal? {
        guard let amount, amount > 0 else { return nil }
        let rate = store.preferences.usdToTJSRate
        if currency == .USD {
            return amount * rate + (secondaryAmount ?? 0)
        } else {
            return amount + (secondaryAmount ?? 0) * rate
        }
    }

    // Total mixed operation expressed in USD using the rate saved in Settings.
    // We truncate to 2 decimals to match the requested cash-calculation style:
    // 1250 USD + 90 TJS at 9.30 => 1259.67 USD.
    private var equivalentUSD: Decimal? {
        guard let amount, amount > 0 else { return nil }
        let rate = store.preferences.usdToTJSRate
        guard rate > 0 else { return nil }

        let raw: Decimal
        if currency == .USD {
            raw = amount + ((secondaryAmount ?? 0) / rate)
        } else {
            raw = (amount / rate) + (secondaryAmount ?? 0)
        }
        return raw.truncated(scale: 2)
    }

    private var equivalentUSDText: String {
        guard let value = equivalentUSD else { return "0.00$" }
        return "\(value.fixedMoneyText(2))$"
    }

    private var recentClients: [String] {
        var seen = Set<String>()
        var names: [String] = []

        for tx in store.transactions {
            let name = tx.personName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            names.append(name)
        }

        return Array(names.prefix(5))
    }

    private var allClients: [String] {
        var seen = Set<String>()
        return store.transactions.compactMap { tx in
            let name = tx.personName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { return nil }
            seen.insert(name)
            return name
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        topHeader
                        nameCard
                        typeCard
                        amountCard
                        detailsCard
                        toolsRow
                        previewCard
                        actionsCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showClientPicker) {
                ClientPickerSheet(
                    clients: allClients,
                    selectedName: $personName
                )
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showCommentEditor) {
                commentSheet
            }
            .alert("Проверьте данные", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Подтвердить операцию?", isPresented: $showConfirmation) {
                Button("Сохранить") {
                    save()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                if secondaryAmount != nil, let equivalentUSD {
                    Text("\(personName.trimmingCharacters(in: .whitespacesAndNewlines))\n\(mixedAmountText) = \(equivalentUSD.fixedMoneyText(2))$")
                } else {
                    Text("\(personName.trimmingCharacters(in: .whitespacesAndNewlines)) • \(mixedAmountText) • \(type.title)")
                }
            }
            .onChange(of: selectedPhotoItems) { items in
                loadSelectedPhotos(items)
            }

        }
    }

    private var topHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.white.opacity(0.13), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    )
            }

            Text(type.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Новая операция")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.52))
        }
    }

    private var nameCard: some View {
        premiumCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Имя")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AppTheme.green)
                        .frame(width: 46, height: 46)
                        .background(Color.black.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.09), lineWidth: 1)
                        )

                    TextField("Например: Равшан", text: $personName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(Color.black.opacity(0.17))
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }

                HStack {
                    Text("Недавние клиенты")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))

                    Spacer()

                    Button {
                        showClientPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Text("Все")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.62))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(recentClients, id: \.self) { name in
                            recentClientButton(name)
                        }

                        Button {
                            showClientPicker = true
                        } label: {
                            VStack(spacing: 7) {
                                Circle()
                                    .fill(Color.white.opacity(0.035))
                                    .frame(width: 58, height: 58)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .overlay(
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 19, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.82))
                                    )

                                Text("Ещё")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func recentClientButton(_ name: String) -> some View {
        Button {
            personName = name
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.green.opacity(0.12), Color.white.opacity(0.025)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle()
                            .stroke(personName == name ? AppTheme.green : Color.white.opacity(0.15), lineWidth: personName == name ? 1.6 : 1)
                    )
                    .overlay(
                        Image(systemName: "person")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(AppTheme.green)
                    )

                Text(name)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
    }

    private var typeCard: some View {
        premiumCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Тип операции")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 0) {
                    transactionTypeButton(.received, icon: "arrow.up")
                    transactionTypeButton(.paid, icon: "arrow.down")
                }
                .padding(3)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private func transactionTypeButton(_ item: TransactionType, icon: String) -> some View {
        let selected = type == item
        let color = item == .received ? AppTheme.green : AppTheme.blue

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                type = item
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(selected ? color : Color.white.opacity(0.92))
                    .frame(width: 25, height: 25)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(selected ? AppTheme.bg : Color.black.opacity(0.72))
                    )

                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(selected ? color.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? color : Color.clear, lineWidth: 1.2)
            )
            .shadow(color: selected ? color.opacity(0.22) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
    }

    private var amountCard: some View {
        premiumCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Сумма")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("1$ = \(store.preferences.usdToTJSRate.moneyText) TJS")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.green.opacity(0.85))
                }

                HStack(spacing: 10) {
                    Image(systemName: "banknote")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(accentColor)
                        .frame(width: 52, height: 66)
                        .background(Color.black.opacity(0.17))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        TextField(currency == .USD ? "1 200" : "340", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 32, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)

                        Text(amountText.isEmpty ? "Основная сумма" : amountInWordsHint)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.48))
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 0) {
                        currencyButton(.USD)
                        currencyButton(.TJS)
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }

                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.gold)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Дополнительно \(secondaryCurrency.rawValue)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.62))
                        TextField(secondaryCurrency == .TJS ? "340" : "50", text: $secondaryAmountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Text(secondaryCurrency.symbol)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.gold)
                        .frame(width: 48, height: 42)
                        .background(AppTheme.gold.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if let equivalentTJS, (secondaryAmount != nil || currency == .USD) {
                    HStack {
                        Image(systemName: "equal.circle.fill")
                            .foregroundStyle(AppTheme.green)
                        Text("Итого по курсу")
                            .foregroundStyle(Color.white.opacity(0.58))
                        Spacer()
                        Text("≈ \(equivalentTJS.moneyText) TJS")
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(AppTheme.green)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }
        }
    }

    private func currencyButton(_ item: Currency) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if currency != item { secondaryAmountText = "" }
                currency = item
            }
        } label: {
            Text(item.rawValue)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 66, height: 48)
                .background(currency == item ? accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(currency == item ? accentColor : Color.clear, lineWidth: 1.2)
                )
                .shadow(color: currency == item ? accentColor.opacity(0.22) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow(
                icon: "calendar",
                title: "Дата и время",
                value: operationDate.formatted(date: .abbreviated, time: .shortened),
                color: AppTheme.green
            ) {
                showDatePicker = true
            }

            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)

            detailRow(
                icon: "number",
                title: "Номер операции",
                value: "Авто",
                color: AppTheme.green
            ) {}

            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52)

            detailRow(
                icon: "message",
                title: "Комментарий",
                value: comment.isEmpty ? "Необязательно" : comment,
                color: AppTheme.green
            ) {
                showCommentEditor = true
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func detailRow(icon: String, title: String, value: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if title == "Номер операции" {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.green.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Text(value)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .lineLimit(1)
                }

                if title != "Номер операции" {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
        }
        .buttonStyle(.plain)
    }

    private var toolsRow: some View {
        HStack {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                toolButtonContent(
                    icon: pendingAttachments.isEmpty ? "camera" : "checkmark.circle.fill",
                    title: "Фото/чек",
                    subtitle: pendingAttachments.isEmpty ? "Добавить" : "Добавлено: \(pendingAttachments.count)"
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private func toolButtonContent(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppTheme.green)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 210, height: 66)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 34, height: 34)
                    .background(accentColor.opacity(0.10))
                    .clipShape(Circle())

                Text("Предпросмотр")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            previewLine("Тип:", type.title)
            previewLine("Сумма:", mixedAmountText)
            if secondaryAmount != nil, let equivalentUSD {
                previewLine("Курс:", "1$ = \(store.preferences.usdToTJSRate.moneyText) TJS")
                previewLine("Итого в USD:", "\(equivalentUSD.fixedMoneyText(2))$")
            }
            previewLine("Дата:", operationDate.formatted(date: .abbreviated, time: .omitted))
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [accentColor.opacity(0.18), AppTheme.card.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accentColor.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(0.12), radius: 12)
    }

    private func previewLine(_ label: String, _ value: String) -> some View {
        HStack {
            HStack(spacing: 10) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 5, height: 5)
                Text(label)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var actionsCard: some View {
        Button {
            validate()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                Text("Проверить и сохранить")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [accentColor, accentColor.opacity(0.76)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: accentColor.opacity(0.28), radius: 14)
        }
        .buttonStyle(.plain)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Дата и время",
                    selection: $operationDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(accentColor)
                .padding()

                Spacer()
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Дата и время")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { showDatePicker = false }
                        .foregroundStyle(accentColor)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var commentSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $comment)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(minHeight: 160)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                Text("\(comment.count)/200")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Spacer()
            }
            .padding()
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Комментарий")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        if comment.count > 200 {
                            comment = String(comment.prefix(200))
                        }
                        showCommentEditor = false
                    }
                    .foregroundStyle(accentColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [Color.white.opacity(0.060), Color.white.opacity(0.030)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func premiumCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var displayAmount: String {
        amount?.moneyText ?? (amountText.isEmpty ? "0" : amountText)
    }

    private var amountInWordsHint: String {
        guard let amount else { return "Введите сумму" }
        if amount == 1000 { return "Одна тысяча" }
        if amount == 5000 { return "Пять тысяч" }
        if amount == 10000 { return "Десять тысяч" }
        if amount == 12000 { return "Двенадцать тысяч" }
        return "Сумма операции"
    }

    private var errorMessage: String {
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Введите имя." }
        guard let amount, amount > 0 else { return "Введите основную сумму больше нуля." }
        if type == .paid && store.cashBalance(currency) < amount {
            return "Недостаточно остатка \(currency.rawValue) для выдачи."
        }
        if type == .paid, let second = secondaryAmount,
           store.cashBalance(secondaryCurrency) < second {
            return "Недостаточно остатка \(secondaryCurrency.rawValue) для выдачи."
        }
        return "Проверьте введённые данные."
    }

    private func validate() {
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, let amount, amount > 0 else {
            showError = true
            return
        }

        if type == .paid && store.cashBalance(currency) < amount {
            showError = true
            return
        }
        if type == .paid, let second = secondaryAmount,
           store.cashBalance(secondaryCurrency) < second {
            showError = true
            return
        }

        showConfirmation = true
    }

    private func save() {
        guard let amount else { return }

        store.addTransaction(
            personName: personName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type,
            amount: amount,
            currency: currency,
            comment: comment,
            date: operationDate,
            secondaryCurrency: secondaryAmount == nil ? nil : secondaryCurrency,
            secondaryAmount: secondaryAmount,
            usdToTJSRateSnapshot: secondaryAmount == nil ? nil : store.preferences.usdToTJSRate,
            totalEquivalentUSD: secondaryAmount == nil ? nil : equivalentUSD,
            attachments: pendingAttachments
        )

        dismiss()
    }


    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) {
        Task {
            var loaded: [TransactionAttachment] = []

            for item in items.prefix(6) {
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: raw),
                      let data = resizedJPEGData(from: image) else { continue }
                loaded.append(TransactionAttachment(data: data))
            }

            await MainActor.run {
                pendingAttachments = loaded
            }
        }
    }

    private func resizedJPEGData(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }

}

private struct ClientPickerSheet: View {
    let clients: [String]
    @Binding var selectedName: String

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [String] {
        guard !search.isEmpty else { return clients }
        return clients.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.white.opacity(0.55))
                        TextField("Поиск клиента", text: $search)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered, id: \.self) { name in
                                Button {
                                    selectedName = name
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(AppTheme.green.opacity(0.12))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Image(systemName: "person")
                                                    .foregroundStyle(AppTheme.green)
                                            )

                                        Text(name)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.32))
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 60)
                                    .background(AppTheme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Клиенты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(AppTheme.green)
                }
            }
        }
    }
}
