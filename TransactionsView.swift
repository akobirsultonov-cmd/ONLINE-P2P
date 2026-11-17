import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject var store: AppStore

    @State private var search = ""
    @State private var selectedCurrency: Currency?
    @State private var selectedType: TransactionType?
    @State private var showNew = false
    @State private var showDeleteDialog = false
    @State private var transactionToDelete: MoneyTransaction?
    @State private var transactionToEdit: MoneyTransaction?

    private var filteredTransactions: [MoneyTransaction] {
        store.transactions.filter { tx in
            let textMatch =
                search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                tx.personName.localizedCaseInsensitiveContains(search) ||
                tx.comment.localizedCaseInsensitiveContains(search) ||
                tx.number.localizedCaseInsensitiveContains(search) ||
                tx.amount.moneyText.contains(search) ||
                (tx.secondaryAmount?.moneyText.contains(search) ?? false)

            let currencyMatch =
                selectedCurrency == nil ||
                tx.currency == selectedCurrency || tx.secondaryCurrency == selectedCurrency ||
                tx.exchangeTargetCurrency == selectedCurrency

            let typeMatch =
                selectedType == nil ||
                tx.type == selectedType

            return textMatch && currencyMatch && typeMatch
        }
    }

    private struct TransactionDayGroup: Identifiable {
        let id: Date
        let date: Date
        let transactions: [MoneyTransaction]
    }

    private var groupedTransactions: [TransactionDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredTransactions) { tx in
            calendar.startOfDay(for: tx.date)
        }

        return grouped
            .map { key, value in
                TransactionDayGroup(
                    id: key,
                    date: key,
                    transactions: value.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        searchBar
                        filterRow
                        cardsSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNew) {
                NewTransactionView()
            }
            .sheet(item: $transactionToEdit) { tx in
                EditTransactionView(transaction: tx)
            }
            .alert("Удалить операцию?", isPresented: $showDeleteDialog) {
                Button("Удалить", role: .destructive) {
                    if let tx = transactionToDelete {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.delete(tx)
                        }
                    }
                    transactionToDelete = nil
                }

                Button("Отмена", role: .cancel) {
                    transactionToDelete = nil
                }
            } message: {
                Text("Вы действительно хотите удалить эту операцию? Это действие нельзя отменить.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Операции")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("История всех ваших операций")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            Spacer(minLength: 16)

            Button {
                showNew = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.green.opacity(0.18), AppTheme.green.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Circle()
                        .stroke(AppTheme.green.opacity(0.65), lineWidth: 1)
                        .frame(width: 56, height: 56)

                    Image(systemName: "plus")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(AppTheme.green)
                }
            }
            .buttonStyle(.plain)
            .shadow(color: AppTheme.green.opacity(0.22), radius: 10, x: 0, y: 0)
        }
        .padding(.top, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.72))

            TextField("Имя, номер, сумма, комментарий", text: $search)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            Menu {
                filterMenuContent
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(searchSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var filterMenuContent: some View {
        Group {
            Button("Сбросить все фильтры") {
                selectedCurrency = nil
                selectedType = nil
            }

            Menu("Валюта") {
                Button("Все валюты") { selectedCurrency = nil }
                ForEach(Currency.allCases) { currency in
                    Button(currency.rawValue) { selectedCurrency = currency }
                }
            }

            Menu("Тип") {
                Button("Все типы") { selectedType = nil }
                Button("Гирифтам") { selectedType = .received }
                Button("Супоридам") { selectedType = .paid }
                Button("Обмен") { selectedType = .exchange }
                Button("Корректировка") { selectedType = .adjustment }
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickTypeChip(title: "Все", isActive: selectedType == nil) {
                    selectedType = nil
                }
                quickTypeChip(title: "Гирифтам", color: AppTheme.green, isActive: selectedType == .received) {
                    selectedType = .received
                }
                quickTypeChip(title: "Супоридам", color: AppTheme.blue, isActive: selectedType == .paid) {
                    selectedType = .paid
                }
                quickTypeChip(title: "Обмен", color: AppTheme.gold, isActive: selectedType == .exchange) {
                    selectedType = .exchange
                }

                menuChip(title: selectedCurrency?.rawValue ?? "Валюта", color: AppTheme.green) {
                    Button("Все валюты") { selectedCurrency = nil }
                    ForEach(Currency.allCases) { currency in
                        Button(currency.rawValue) { selectedCurrency = currency }
                    }
                }

                menuChip(title: selectedType?.title ?? "Тип", color: AppTheme.green) {
                    Button("Все типы") { selectedType = nil }
                    Button("Гирифтам") { selectedType = .received }
                    Button("Супоридам") { selectedType = .paid }
                    Button("Обмен") { selectedType = .exchange }
                    Button("Корректировка") { selectedType = .adjustment }
                }
            }
            .padding(.vertical, 0)
        }
    }

    private var cardsSection: some View {
        VStack(spacing: 16) {
            if filteredTransactions.isEmpty {
                emptyState
            } else {
                ForEach(groupedTransactions) { group in
                    VStack(spacing: 8) {
                        dayHeader(for: group)

                        ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, tx in
                            OperationSwipeRow(
                                index: index + 1,
                                tx: tx,
                                onEdit: { transactionToEdit = tx },
                                onDelete: {
                                    transactionToDelete = tx
                                    showDeleteDialog = true
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private func dayHeader(for group: TransactionDayGroup) -> some View {
        HStack(spacing: 10) {
            Text(dayTitle(group.date))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Text("\(group.transactions.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.green.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.green.opacity(0.16), lineWidth: 1)
                )

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter.string(from: date)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(AppTheme.green)

            Text("Ничего не найдено")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Попробуйте изменить поиск или фильтры")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.50))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(searchSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var searchSurface: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.075),
                Color.white.opacity(0.045)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func quickTypeChip(title: String, color: Color = .white, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? .white : color.opacity(title == "Все" ? 0.92 : 0.95))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isActive ? color.opacity(title == "Все" ? 0.12 : 0.10) : Color.white.opacity(0.03))
                )
                .overlay(
                    Capsule()
                        .stroke(isActive ? color.opacity(0.85) : Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: isActive ? color.opacity(0.20) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }

    private func menuChip<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }
}


struct OperationSwipeRow: View {
    let index: Int
    let tx: MoneyTransaction
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let actionWidth: CGFloat = 86

    private var deleteActionOpacity: Double {
        let progress = min(1, max(0, -offset / actionWidth))
        return Double(progress)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        offset = 0
                        isOpen = false
                    }
                    onDelete()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Удалить")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(deleteActionOpacity)
                .allowsHitTesting(isOpen || offset < -10)
            }

            NavigationLink {
                TransactionDetailView(tx: tx)
            } label: {
                OperationPremiumCard(index: index, tx: tx)
            }
            .buttonStyle(.plain)
            .offset(x: offset)
            .highPriorityGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let x = value.translation.width
                        if x < 0 {
                            offset = max(-actionWidth, x)
                        } else if isOpen {
                            offset = min(0, -actionWidth + x)
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                offset = isOpen ? -actionWidth : 0
                            }
                            return
                        }

                        let shouldOpen = value.translation.width < -38 || value.predictedEndTranslation.width < -65
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            isOpen = shouldOpen
                            offset = shouldOpen ? -actionWidth : 0
                        }
                    }
            )
            .contextMenu {
                Button {
                    onEdit()
                } label: {
                    Label("Редактировать", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct OperationPremiumCard: View {
    let index: Int
    let tx: MoneyTransaction

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(tx.type.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(typeColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(typeColor)
                .shadow(color: typeColor.opacity(0.35), radius: 8)
                .frame(width: 22)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 5) {
                    Text(amountText)
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(typeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(currencyLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(typeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(typeColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(typeColor.opacity(0.18), lineWidth: 1)
                        )
                }

                Text(shortDate(tx.date))
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.50))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(typeColor.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: typeColor.opacity(0.09), radius: 6, x: 0, y: 1)
    }

    private var displayName: String {
        tx.personName.isEmpty ? tx.type.title : tx.personName
    }

    private var currencyLabel: String {
        if let c = tx.secondaryCurrency, tx.secondaryAmount != nil { return "\(tx.currency.rawValue)+\(c.rawValue)" }
        return tx.currency.rawValue
    }

    private var typeColor: Color {
        switch tx.type {
        case .received:
            return AppTheme.green
        case .paid:
            return AppTheme.blue
        case .adjustment, .exchange:
            return AppTheme.gold
        }
    }

    private var iconName: String {
        switch tx.type {
        case .received:
            return "arrow.down.to.line"
        case .paid:
            return "arrow.up.to.line"
        case .exchange:
            return "arrow.left.arrow.right"
        case .adjustment:
            return "slider.horizontal.3"
        }
    }

    private var amountText: String {
        let sign: String
        switch tx.type {
        case .received: sign = "+"
        case .paid, .exchange: sign = "−"
        case .adjustment: sign = tx.amount >= 0 ? "+" : ""
        }
        var parts = [tx.amount.moneyText]
        if let a = tx.secondaryAmount, a > 0 { parts.append(a.moneyText) }
        return sign + parts.joined(separator: " + ")
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.065),
                Color.white.opacity(0.032)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter.string(from: date)
    }
}

// Used on dashboard and detail views.
struct TransactionRow: View {
    let tx: MoneyTransaction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.personName.isEmpty ? tx.type.title : tx.personName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text(tx.number)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !tx.comment.isEmpty {
                    Text(tx.comment)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text(tx.secondaryCurrency.map { "\(tx.currency.rawValue) + \($0.rawValue)" } ?? tx.currency.rawValue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 5)
    }

    private var icon: String {
        switch tx.type {
        case .received: return "arrow.down.circle.fill"
        case .paid: return "arrow.up.circle.fill"
        case .adjustment: return "plusminus.circle.fill"
        case .exchange: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    private var color: Color {
        switch tx.type {
        case .received: return AppTheme.green
        case .paid: return AppTheme.blue
        case .adjustment, .exchange: return AppTheme.gold
        }
    }

    private var amountText: String {
        let sign: String
        switch tx.type {
        case .received: sign = "+"
        case .paid, .exchange: sign = "−"
        case .adjustment: sign = tx.amount >= 0 ? "+" : ""
        }
        var parts = [tx.amount.moneyText]
        if let a = tx.secondaryAmount, a > 0 { parts.append(a.moneyText) }
        return sign + parts.joined(separator: " + ")
    }
}
