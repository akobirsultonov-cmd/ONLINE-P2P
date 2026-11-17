import SwiftUI

struct ReportsView: View {
    @EnvironmentObject var store: AppStore

    @State private var range = 0
    @State private var customFrom = Calendar.current.startOfDay(for: Date())
    @State private var customTo = Date()
    @State private var shareURL: URL?
    @State private var showBalanceCheckpointManager = false
    @State private var showAddBalanceCheckpoint = false
    @State private var checkpointListFilter = 0
    @State private var checkpointType: TransactionType = .received
    @State private var checkpointAmountText = ""
    @State private var checkpointCurrency: Currency = .USD
    @State private var checkpointDate = Date()

    private var dates: (Date, Date) {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case 0:
            return (calendar.startOfDay(for: now), now)

        case 1:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            return (start, now)

        case 2:
            let components = calendar.dateComponents([.year, .month], from: now)
            let startOfMonth = calendar.date(from: components) ?? calendar.startOfDay(for: now)
            return (startOfMonth, now)

        default:
            let first = min(customFrom, customTo)
            let last = max(customFrom, customTo)
            let start = calendar.startOfDay(for: first)
            let lastStart = calendar.startOfDay(for: last)
            let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastStart) ?? last
            return (start, end)
        }
    }

    private var periodTransactions: [MoneyTransaction] {
        store.transactions
            .filter { $0.date >= dates.0 && $0.date <= dates.1 }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    periodSelector

                    if range == 3 {
                        customPeriodCard
                    }

                    periodSummary

                    ForEach(Currency.allCases) { currency in
                        ProCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(currency.rawValue)
                                        .font(.system(size: 23, weight: .bold, design: .rounded))

                                    Spacer()

                                    Text(store.cashBalance(currency).moneyText)
                                        .font(AppTheme.amountFont)
                                        .foregroundStyle(AppTheme.currencyColor(currency))
                                }

                                Text("Остаток на руках")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Divider().opacity(0.25)

                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Гирифтам")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)

                                        Text("+\(store.received(currency, from: dates.0, to: dates.1).moneyText)")
                                            .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                                            .foregroundStyle(AppTheme.green)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("Супоридам")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)

                                        Text("−\(store.paid(currency, from: dates.0, to: dates.1).moneyText)")
                                            .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                                            .foregroundStyle(AppTheme.blue)
                                    }
                                }
                            }
                        }
                    }

                    balanceCheckpointCard

                    operationTableCard

                    Button {
                        shareURL = PDFService.premiumList(
                            transactions: store.transactions,
                            type: .received,
                            from: dates.0,
                            to: dates.1,
                            checkpoints: store.reportBalanceCheckpoints
                        )
                    } label: {
                        Label("PDF • Гирифтам", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.green)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button {
                        shareURL = PDFService.premiumList(
                            transactions: store.transactions,
                            type: .paid,
                            from: dates.0,
                            to: dates.1,
                            checkpoints: store.reportBalanceCheckpoints
                        )
                    } label: {
                        Label("PDF • Супоридам", systemImage: "arrow.up.doc.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button {
                        shareURL = ExportService.csv(
                            transactions: store.transactions,
                            from: dates.0,
                            to: dates.1
                        )
                    } label: {
                        Label("Excel / CSV", systemImage: "tablecells.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.gold)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Отчёты")
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .fullScreenCover(isPresented: $showBalanceCheckpointManager) {
                balanceCheckpointManager
            }
        }
    }

    private var balanceCheckpointCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Остаток для PDF", systemImage: "banknote.fill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.gold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text("Нажми, чтобы открыть полный список всех остатков")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                let visible = store.reportBalanceCheckpoints
                    .sorted { $0.date > $1.date }

                if visible.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("Остатков пока нет — нажми, чтобы добавить")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                } else {
                    ForEach(visible.prefix(3)) { checkpoint in
                        HStack(spacing: 10) {
                            Image(systemName: checkpoint.reportType == .received ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(checkpoint.reportType == .received ? AppTheme.green : AppTheme.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(checkpoint.reportType.title) • \(checkpoint.amount.moneyText) \(checkpoint.currency.rawValue)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text(checkpoint.date.formatted(date: .numeric, time: .shortened))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    if visible.count > 3 {
                        Text("Ещё \(visible.count - 3) • открыть весь список")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.gold)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showBalanceCheckpointManager = true
        }
    }

    private var balanceCheckpointManager: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Фильтр", selection: $checkpointListFilter) {
                    Text("Все").tag(0)
                    Text("Гирифтам").tag(1)
                    Text("Супоридам").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 8)

                let all = store.reportBalanceCheckpoints.sorted { $0.date > $1.date }
                let filtered = all.filter { checkpoint in
                    checkpointListFilter == 0 ||
                    (checkpointListFilter == 1 && checkpoint.reportType == .received) ||
                    (checkpointListFilter == 2 && checkpoint.reportType == .paid)
                }

                if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "banknote")
                            .font(.system(size: 38))
                            .foregroundStyle(AppTheme.gold)
                        Text("Остатков пока нет")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("Нажми «Добавить», чтобы создать первый остаток для PDF")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { checkpoint in
                                ProCard {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill((checkpoint.reportType == .received ? AppTheme.green : AppTheme.gold).opacity(0.14))
                                                .frame(width: 42, height: 42)
                                            Image(systemName: checkpoint.reportType == .received ? "arrow.down" : "arrow.up")
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundStyle(checkpoint.reportType == .received ? AppTheme.green : AppTheme.gold)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(checkpoint.reportType.title)
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                            Text("\(checkpoint.amount.moneyText) \(checkpoint.currency.rawValue)")
                                                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                                            Text(checkpoint.date.formatted(date: .numeric, time: .shortened))
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button(role: .destructive) {
                                            store.deleteReportBalanceCheckpoint(checkpoint)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 17, weight: .semibold))
                                                .padding(10)
                                                .background(Color.red.opacity(0.10))
                                                .clipShape(Circle())
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Остатки для PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { showBalanceCheckpointManager = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        checkpointDate = Date()
                        checkpointAmountText = ""
                        showAddBalanceCheckpoint = true
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                    .fontWeight(.bold)
                }
            }
            .fullScreenCover(isPresented: $showAddBalanceCheckpoint) {
                balanceCheckpointSheet
            }
        }
    }

    private var balanceCheckpointSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.gold.opacity(0.14))
                                .frame(width: 72, height: 72)
                            Circle()
                                .stroke(AppTheme.gold.opacity(0.28), lineWidth: 1)
                                .frame(width: 72, height: 72)
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(AppTheme.gold)
                        }

                        Text("Новый остаток")
                            .font(.system(size: 25, weight: .bold, design: .rounded))

                        Text("Добавь контрольную отметку, которая появится в PDF")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    ProCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Label("Для какого отчёта", systemImage: "doc.text.fill")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                checkpointTypeButton(.received, title: "Гирифтам", icon: "arrow.down")
                                checkpointTypeButton(.paid, title: "Супоридам", icon: "arrow.up")
                            }
                        }
                    }

                    ProCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Сумма остатка", systemImage: "banknote")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            HStack(alignment: .center, spacing: 10) {
                                TextField("0", text: $checkpointAmountText)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.primary)

                                Text(checkpointCurrency.rawValue)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(checkpointCurrency == .USD ? AppTheme.green : AppTheme.gold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background((checkpointCurrency == .USD ? AppTheme.green : AppTheme.gold).opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            Divider().opacity(0.20)

                            HStack(spacing: 10) {
                                ForEach(Currency.allCases) { currency in
                                    Button {
                                        checkpointCurrency = currency
                                    } label: {
                                        Text(currency.rawValue)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(checkpointCurrency == currency ? AppTheme.gold.opacity(0.18) : Color.white.opacity(0.045))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(checkpointCurrency == currency ? AppTheme.gold.opacity(0.75) : Color.white.opacity(0.08), lineWidth: 1)
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(checkpointCurrency == currency ? AppTheme.gold : .primary)
                                }
                            }
                        }
                    }

                    ProCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Дата и время", systemImage: "calendar.badge.clock")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            DatePicker("", selection: $checkpointDate)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let value = checkpointAmountText.decimalValue, value >= 0 {
                        ProCard {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill((checkpointType == .received ? AppTheme.green : AppTheme.blue).opacity(0.14))
                                        .frame(width: 46, height: 46)
                                    Image(systemName: checkpointType == .received ? "arrow.down" : "arrow.up")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(checkpointType == .received ? AppTheme.green : AppTheme.blue)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Так появится в PDF")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                    Text("ОСТАТОК  \(value.moneyText) \(checkpointCurrency.rawValue)")
                                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                                    Text(checkpointDate.formatted(date: .numeric, time: .shortened))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }

                    Button {
                        guard let value = checkpointAmountText.decimalValue, value >= 0 else { return }
                        store.addReportBalanceCheckpoint(
                            reportType: checkpointType,
                            amount: value,
                            currency: checkpointCurrency,
                            date: checkpointDate
                        )
                        showAddBalanceCheckpoint = false
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Сохранить остаток")
                        }
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.gold, AppTheme.gold.opacity(0.78)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled((checkpointAmountText.decimalValue ?? -1) < 0)
                    .opacity((checkpointAmountText.decimalValue ?? -1) < 0 ? 0.42 : 1)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.secondary)
                        Text("Остаток используется только как контрольная отметка в PDF и не изменяет деньги в кассе.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 34)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Добавить остаток")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { showAddBalanceCheckpoint = false }
                        .foregroundStyle(AppTheme.green)
                }
            }
        }
    }

    @ViewBuilder
    private func checkpointTypeButton(_ type: TransactionType, title: String, icon: String) -> some View {
        let selected = checkpointType == type
        let tint = type == .received ? AppTheme.green : AppTheme.blue

        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                checkpointType = type
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? tint.opacity(0.16) : Color.white.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(selected ? tint.opacity(0.78) : Color.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(selected ? tint : .primary)
        }
        .buttonStyle(.plain)
    }

    private var periodSelector: some View {
        Picker("Период", selection: $range) {
            Text("Сегодня").tag(0)
            Text("7 дней").tag(1)
            Text("Месяц").tag(2)
            Text("Период").tag(3)
        }
        .pickerStyle(.segmented)
    }

    private var customPeriodCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Период отчёта", systemImage: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.green)

                    Spacer()

                    Text(periodText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.20)

                HStack(spacing: 12) {
                    dateField(title: "С", selection: $customFrom)
                    dateField(title: "По", selection: $customTo)
                }

                HStack(spacing: 8) {
                    quickPeriodButton("Этот месяц") {
                        setCurrentMonth()
                    }

                    quickPeriodButton("Прошлый месяц") {
                        setPreviousMonth()
                    }
                }
            }
        }
    }

    private var periodSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(AppTheme.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(range == 3 ? "Выбранный период" : "Период отчёта")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(periodText)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }

            Spacer()

            Text("\(periodTransactions.count) оп.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.green.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func dateField(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            DatePicker(
                title,
                selection: selection,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(AppTheme.green)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func quickPeriodButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var operationTableCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Таблица операций")
                    .font(AppTheme.sectionFont)

                HStack(spacing: 0) {
                    Text("№").frame(width: 30, alignment: .leading)
                    Text("ИМЯ").frame(maxWidth: .infinity, alignment: .leading)
                    Text("СУММА").frame(width: 105, alignment: .trailing)
                    Text("ДАТА").frame(width: 70, alignment: .trailing)
                }
                .font(AppTheme.tableHeaderFont)
                .foregroundStyle(.secondary)

                Divider().opacity(0.30)

                ForEach(Array(periodTransactions.prefix(10).enumerated()), id: \.element.id) { index, tx in
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .frame(width: 30, alignment: .leading)
                            .foregroundStyle(.secondary)

                        Text(tx.personName.isEmpty ? tx.type.title : tx.personName)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(displayAmount(tx))
                            .font(AppTheme.tableAmountFont)
                            .foregroundStyle(tx.type == .received ? AppTheme.green : (tx.type == .paid ? AppTheme.blue : AppTheme.gold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                            .frame(width: 105, alignment: .trailing)

                        Text(shortDate(tx.date))
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.vertical, 5)

                    if index < min(periodTransactions.count, 10) - 1 {
                        Divider().opacity(0.18)
                    }
                }

                if periodTransactions.isEmpty {
                    Text("Нет операций за выбранный период")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var periodText: String {
        "\(shortDate(dates.0)) — \(shortDate(dates.1))"
    }

    private func setCurrentMonth() {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        customFrom = calendar.date(from: components) ?? now
        customTo = now
    }

    private func setPreviousMonth() {
        let calendar = Calendar.current
        let now = Date()
        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        guard let currentStart = calendar.date(from: currentComponents),
              let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart),
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) else {
            return
        }

        customFrom = previousStart
        customTo = previousEnd
    }

    private func displayAmount(_ tx: MoneyTransaction) -> String {
        let sign = tx.type == .received ? "+" : (tx.type == .paid ? "−" : "")
        var parts = ["\(tx.amount.moneyText)\(tx.currency.symbol)"]
        if let c = tx.secondaryCurrency, let a = tx.secondaryAmount, a > 0 {
            parts.append("\(a.moneyText)\(c.symbol)")
        }
        return sign + parts.joined(separator: " + ")
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter.string(from: date)
    }
}
