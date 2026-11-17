import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var transactions: [MoneyTransaction] = []
    @Published var reportBalanceCheckpoints: [ReportBalanceCheckpoint] = []
    @Published var preferences = AppPreferences()
    @Published private(set) var automaticBackupStatus: String = ""
    @Published private(set) var lastAutomaticBackupDate: Date?
    @Published private(set) var automaticBackupFolderName: String?

    lazy var onlineSync = OnlineSyncManager(store: self)

    private let saveURL: URL
    private let autoBackupLastSuccessKey = "P2POffline.AutoBackup.LastSuccess"
    private var autoBackupInProgress = false

    init() {
        saveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("p2p_simple_data.json")
        load()
        seedIfNeeded()
        lastAutomaticBackupDate = UserDefaults.standard.object(forKey: autoBackupLastSuccessKey) as? Date
        automaticBackupFolderName = AutomaticBackupManager.selectedFolderName
        refreshAutomaticBackupStatus()
        runAutomaticBackupIfNeeded()
    }


    func setAutomaticDailyBackupEnabled(_ enabled: Bool) {
        var updated = preferences
        updated.automaticDailyBackupEnabled = enabled
        preferences = updated
        save(skipAutomaticBackup: true)
        refreshAutomaticBackupStatus()
        if enabled {
            runAutomaticBackupIfNeeded(force: true)
        }
    }

    func createAutomaticBackupNow() {
        runAutomaticBackupIfNeeded(force: true)
    }

    func setAutomaticBackupFolder(_ url: URL) throws {
        try AutomaticBackupManager.setSelectedFolder(url)
        automaticBackupFolderName = AutomaticBackupManager.selectedFolderName
        refreshAutomaticBackupStatus()
        runAutomaticBackupIfNeeded(force: true)
    }

    func clearAutomaticBackupFolder() {
        AutomaticBackupManager.clearSelectedFolder()
        automaticBackupFolderName = nil
        refreshAutomaticBackupStatus()
    }

    func runAutomaticBackupIfNeeded(force: Bool = false) {
        guard preferences.automaticDailyBackupEnabled || force else {
            refreshAutomaticBackupStatus()
            return
        }
        guard !autoBackupInProgress else { return }

        let now = Date()
        // Daily means once per calendar day, not once every rolling 24 hours.
        // Example: if the last copy was yesterday at 23:01 and the app is opened
        // today at 08:00, a new copy must be created immediately.
        if !force, let last = lastAutomaticBackupDate,
           Calendar.autoupdatingCurrent.isDate(last, inSameDayAs: now) {
            refreshAutomaticBackupStatus()
            return
        }

        guard let data = backupData() else {
            automaticBackupStatus = "Не удалось подготовить копию"
            return
        }

        autoBackupInProgress = true
        automaticBackupStatus = "Создаю полную автокопию…"

        DispatchQueue.global(qos: .utility).async {
            let result = Result { try AutomaticBackupManager.save(data: data) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.autoBackupInProgress = false
                switch result {
                case .success(let backup):
                    self.lastAutomaticBackupDate = backup.date
                    UserDefaults.standard.set(backup.date, forKey: self.autoBackupLastSuccessKey)
                    let stats = self.backupStatistics()
                    self.automaticBackupStatus = "Сохранено: \(stats.transactions) операций, \(stats.clients) клиентов, \(stats.attachments) фото/чеков • \(backup.locationDescription)"
                case .failure(let error):
                    self.automaticBackupStatus = "Ошибка автокопии: \(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshAutomaticBackupStatus() {
        guard preferences.automaticDailyBackupEnabled else {
            automaticBackupStatus = "Автокопия выключена"
            return
        }
        guard let lastAutomaticBackupDate else {
            automaticBackupStatus = automaticBackupFolderName == nil ? "Автокопия включена. Выберите папку iCloud." : "Автокопия включена. Первая копия будет создана автоматически."
            return
        }
        automaticBackupStatus = "Последняя автокопия: \(automaticBackupDateText(lastAutomaticBackupDate))"
    }

    private func automaticBackupDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: date)
    }

    func nextTransactionNumber() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let prefix = "OP-\(formatter.string(from: Date()))"
        let count = transactions.filter { $0.number.hasPrefix(prefix) }.count + 1
        return String(format: "%@-%04d", prefix, count)
    }

    func addTransaction(
        personName: String,
        type: TransactionType,
        amount: Decimal,
        currency: Currency,
        comment: String,
        date: Date = Date(),
        secondaryCurrency: Currency? = nil,
        secondaryAmount: Decimal? = nil,
        usdToTJSRateSnapshot: Decimal? = nil,
        totalEquivalentUSD: Decimal? = nil,
        attachments: [TransactionAttachment] = []
    ) {
        let tx = MoneyTransaction(
            number: nextTransactionNumber(),
            personName: personName,
            type: type,
            amount: amount,
            currency: currency,
            comment: comment,
            date: date,
            secondaryCurrency: secondaryCurrency,
            secondaryAmount: secondaryAmount,
            usdToTJSRateSnapshot: usdToTJSRateSnapshot,
            totalEquivalentUSD: totalEquivalentUSD,
            attachments: attachments
        )
        transactions.insert(tx, at: 0)
        save()
    }

    func addExchange(
        personName: String,
        from: Currency,
        fromAmount: Decimal,
        to: Currency,
        toAmount: Decimal,
        comment: String,
        rateSnapshot: Decimal? = nil
    ) {
        let tx = MoneyTransaction(
            number: nextTransactionNumber(),
            personName: personName,
            type: .exchange,
            amount: fromAmount,
            currency: from,
            comment: comment,
            exchangeTargetCurrency: to,
            exchangeTargetAmount: toAmount,
            usdToTJSRateSnapshot: rateSnapshot
        )
        transactions.insert(tx, at: 0)
        save()
    }

    func addReportBalanceCheckpoint(reportType: TransactionType, amount: Decimal, currency: Currency, date: Date) {
        guard reportType == .received || reportType == .paid, amount >= 0 else { return }
        let checkpoint = ReportBalanceCheckpoint(reportType: reportType, amount: amount, currency: currency, date: date)
        reportBalanceCheckpoints.append(checkpoint)
        reportBalanceCheckpoints.sort { $0.date > $1.date }
        save()
    }

    func deleteReportBalanceCheckpoint(_ checkpoint: ReportBalanceCheckpoint) {
        reportBalanceCheckpoints.removeAll { $0.id == checkpoint.id }
        save()
    }

    func setOpeningBalances(_ balances: [Currency: Decimal]) {
        var updated = preferences
        for currency in Currency.allCases {
            updated.openingBalances[currency] = balances[currency] ?? 0
        }
        preferences = updated
        save()
    }

    func setUSDToTJSRate(_ rate: Decimal) {
        guard rate > 0 else { return }
        var updated = preferences
        updated.usdToTJSRate = rate
        preferences = updated
        save()
    }

    func cashBalance(_ currency: Currency) -> Decimal {
        var value = preferences.openingBalances[currency] ?? 0

        for tx in transactions {
            if tx.type == .exchange {
                if tx.currency == currency { value -= tx.amount }
                if tx.exchangeTargetCurrency == currency {
                    value += tx.exchangeTargetAmount ?? 0
                }
                continue
            }

            let sign: Decimal
            switch tx.type {
            case .received, .adjustment: sign = 1
            case .paid: sign = -1
            case .exchange: sign = 0
            }

            if tx.currency == currency {
                value += sign * tx.amount
            }
            if tx.secondaryCurrency == currency, let second = tx.secondaryAmount {
                value += sign * second
            }
        }

        return value
    }

    private func totalAmount(_ tx: MoneyTransaction, in currency: Currency) -> Decimal {
        var result: Decimal = 0
        if tx.currency == currency { result += tx.amount }
        if tx.secondaryCurrency == currency { result += tx.secondaryAmount ?? 0 }
        return result
    }

    func received(_ currency: Currency, from start: Date, to end: Date) -> Decimal {
        transactions
            .filter { $0.type == .received && $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + totalAmount($1, in: currency) }
    }

    func paid(_ currency: Currency, from start: Date, to end: Date) -> Decimal {
        transactions
            .filter { $0.type == .paid && $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + totalAmount($1, in: currency) }
    }

    func delete(_ transaction: MoneyTransaction) {
        transactions.removeAll { $0.id == transaction.id }
        save()
    }


    func removeAttachment(transactionID: UUID, attachmentID: UUID) {
        guard let index = transactions.firstIndex(where: { $0.id == transactionID }) else { return }
        transactions[index].attachments.removeAll { $0.id == attachmentID }
        save()
    }

    func updateTransaction(_ updated: MoneyTransaction) {
        guard let index = transactions.firstIndex(where: { $0.id == updated.id }) else { return }
        transactions[index] = updated
        save()
    }

    func backupData() -> Data? {
        let archive = FullBackupArchive(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            transactions: transactions,
            reportBalanceCheckpoints: reportBalanceCheckpoints,
            preferences: preferences,
            clients: clientBackupSummaries(),
            cashBalances: Dictionary(uniqueKeysWithValues: Currency.allCases.map { ($0, cashBalance($0)) })
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(archive)
    }

    func restore(from data: Data) throws {
        let decoder = JSONDecoder()

        // New complete backup format (2.6.0+).
        if let archive = try? decoder.decode(FullBackupArchive.self, from: data) {
            transactions = archive.transactions
            reportBalanceCheckpoints = archive.reportBalanceCheckpoints
            preferences = archive.preferences
            if preferences.pinEnabled && !PINManager.hasPIN { preferences.pinEnabled = false }
            save()
            return
        }

        // Compatibility with backups created by older versions.
        let legacy = try decoder.decode(BackupPayload.self, from: data)
        transactions = legacy.transactions
        reportBalanceCheckpoints = legacy.reportBalanceCheckpoints
        preferences = legacy.preferences
        if preferences.pinEnabled && !PINManager.hasPIN { preferences.pinEnabled = false }
        save()
    }

    func backupStatistics() -> (clients: Int, transactions: Int, attachments: Int) {
        (
            clientBackupSummaries().count,
            transactions.count,
            transactions.reduce(0) { $0 + $1.attachments.count }
        )
    }

    func restoreSummaryText() -> String {
        let stats = backupStatistics()
        let usd = cashBalance(.USD).moneyText
        let tjs = cashBalance(.TJS).moneyText
        return "Восстановлено: \(stats.transactions) операций, \(stats.clients) клиентов, \(stats.attachments) фото/чеков. Остатки: USD \(usd), TJS \(tjs)."
    }

    private func clientBackupSummaries() -> [ClientBackupSummary] {
        var order: [String] = []
        var grouped: [String: [MoneyTransaction]] = [:]

        for tx in transactions {
            let name = tx.personName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if grouped[name] == nil { order.append(name) }
            grouped[name, default: []].append(tx)
        }

        return order.compactMap { name in
            guard let items = grouped[name] else { return nil }
            var balances: [Currency: Decimal] = [.USD: 0, .TJS: 0]

            for tx in items {
                switch tx.type {
                case .received:
                    balances[tx.currency, default: 0] += tx.amount
                    if let c = tx.secondaryCurrency, let a = tx.secondaryAmount { balances[c, default: 0] += a }
                case .paid:
                    balances[tx.currency, default: 0] -= tx.amount
                    if let c = tx.secondaryCurrency, let a = tx.secondaryAmount { balances[c, default: 0] -= a }
                case .adjustment:
                    balances[tx.currency, default: 0] += tx.amount
                    if let c = tx.secondaryCurrency, let a = tx.secondaryAmount { balances[c, default: 0] += a }
                case .exchange:
                    balances[tx.currency, default: 0] -= tx.amount
                    if let target = tx.exchangeTargetCurrency {
                        balances[target, default: 0] += tx.exchangeTargetAmount ?? 0
                    }
                }
            }

            return ClientBackupSummary(
                name: name,
                transactionCount: items.count,
                attachmentCount: items.reduce(0) { $0 + $1.attachments.count },
                balances: balances
            )
        }
    }

    func save(skipAutomaticBackup: Bool = false) {
        do {
            let data = try JSONEncoder().encode(
                BackupPayload(transactions: transactions, preferences: preferences, reportBalanceCheckpoints: reportBalanceCheckpoints)
            )
            try data.write(to: saveURL, options: .atomic)
            if onlineSync.enabled { onlineSync.localSaved() }
            if !skipAutomaticBackup {
                runAutomaticBackupIfNeeded()
            }
        } catch {
            print("Save error:", error)
        }
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: saveURL),
            let payload = try? JSONDecoder().decode(BackupPayload.self, from: data)
        else { return }

        transactions = payload.transactions
        reportBalanceCheckpoints = payload.reportBalanceCheckpoints
        preferences = payload.preferences
    }

    private func seedIfNeeded() {
        guard transactions.isEmpty else { return }
        preferences.openingBalances = [.USD: 25000, .TJS: 100000]
        transactions = [
            MoneyTransaction(
                number: "OP-20260825-0001",
                personName: "Равшан",
                type: .received,
                amount: 12000,
                currency: .USD,
                comment: "Получено наличными"
            ),
            MoneyTransaction(
                number: "OP-20260825-0002",
                personName: "Зафар",
                type: .paid,
                amount: 4000,
                currency: .USD,
                comment: "Выдано наличными"
            )
        ]
        save()
    }
}

extension Decimal {
    var moneyText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}

extension String {
    var decimalValue: Decimal? {
        Decimal(
            string: replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
        )
    }
}

extension Decimal {
    func truncated(scale: Int) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .down)
        return result
    }

    func fixedMoneyText(_ fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}
