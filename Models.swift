import Foundation

enum Currency: String, Codable, CaseIterable, Identifiable {
    case USD, TJS
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .USD: return "$"
        case .TJS: return "с"
        }
    }

    var fullName: String {
        switch self {
        case .USD: return "Доллар США"
        case .TJS: return "Таджикский сомони"
        }
    }
}

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case received
    case paid
    case adjustment
    case exchange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .received: return "Гирифтам"
        case .paid: return "Супоридам"
        case .adjustment: return "Корректировка"
        case .exchange: return "Обмен"
        }
    }
}


struct ReportBalanceCheckpoint: Identifiable, Codable, Hashable {
    var id = UUID()
    var reportType: TransactionType
    var amount: Decimal
    var currency: Currency
    var date: Date = Date()

    init(id: UUID = UUID(), reportType: TransactionType, amount: Decimal, currency: Currency, date: Date = Date()) {
        self.id = id
        self.reportType = reportType
        self.amount = amount
        self.currency = currency
        self.date = date
    }
}

struct TransactionAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var data: Data
    var createdAt = Date()
}

struct MoneyTransaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var number: String
    var personName: String
    var type: TransactionType
    var amount: Decimal
    var currency: Currency
    var comment: String = ""
    var date: Date = Date()

    var exchangeTargetCurrency: Currency?
    var exchangeTargetAmount: Decimal?
    var secondaryCurrency: Currency?
    var secondaryAmount: Decimal?
    // Snapshot for mixed USD/TJS operations. Keeps the original conversion result
    // even if the user changes the rate later.
    var usdToTJSRateSnapshot: Decimal?
    var totalEquivalentUSD: Decimal?
    var attachments: [TransactionAttachment] = []

    enum CodingKeys: String, CodingKey {
        case id, number, personName, type, amount, currency, comment, date
        case exchangeTargetCurrency, exchangeTargetAmount, secondaryCurrency, secondaryAmount
        case usdToTJSRateSnapshot, totalEquivalentUSD, attachments
    }

    init(
        id: UUID = UUID(),
        number: String,
        personName: String,
        type: TransactionType,
        amount: Decimal,
        currency: Currency,
        comment: String = "",
        date: Date = Date(),
        exchangeTargetCurrency: Currency? = nil,
        exchangeTargetAmount: Decimal? = nil,
        secondaryCurrency: Currency? = nil,
        secondaryAmount: Decimal? = nil,
        usdToTJSRateSnapshot: Decimal? = nil,
        totalEquivalentUSD: Decimal? = nil,
        attachments: [TransactionAttachment] = []
    ) {
        self.id = id
        self.number = number
        self.personName = personName
        self.type = type
        self.amount = amount
        self.currency = currency
        self.comment = comment
        self.date = date
        self.exchangeTargetCurrency = exchangeTargetCurrency
        self.exchangeTargetAmount = exchangeTargetAmount
        self.secondaryCurrency = secondaryCurrency
        self.secondaryAmount = secondaryAmount
        self.usdToTJSRateSnapshot = usdToTJSRateSnapshot
        self.totalEquivalentUSD = totalEquivalentUSD
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try container.decode(String.self, forKey: .number)
        personName = try container.decode(String.self, forKey: .personName)
        type = try container.decode(TransactionType.self, forKey: .type)
        amount = try container.decode(Decimal.self, forKey: .amount)
        currency = try container.decode(Currency.self, forKey: .currency)
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        exchangeTargetCurrency = try container.decodeIfPresent(Currency.self, forKey: .exchangeTargetCurrency)
        exchangeTargetAmount = try container.decodeIfPresent(Decimal.self, forKey: .exchangeTargetAmount)
        secondaryCurrency = try container.decodeIfPresent(Currency.self, forKey: .secondaryCurrency)
        secondaryAmount = try container.decodeIfPresent(Decimal.self, forKey: .secondaryAmount)
        usdToTJSRateSnapshot = try container.decodeIfPresent(Decimal.self, forKey: .usdToTJSRateSnapshot)
        totalEquivalentUSD = try container.decodeIfPresent(Decimal.self, forKey: .totalEquivalentUSD)
        attachments = try container.decodeIfPresent([TransactionAttachment].self, forKey: .attachments) ?? []
    }
}

struct AppPreferences: Codable {
    var openingBalances: [Currency: Decimal] = [.USD: 0, .TJS: 0]
    var hideAmounts = false
    var useDarkTheme = true
    var faceIDEnabled = false
    var pinEnabled = false
    var usdToTJSRate: Decimal = 9.28
    var automaticDailyBackupEnabled = true

    enum CodingKeys: String, CodingKey {
        case openingBalances, hideAmounts, useDarkTheme, faceIDEnabled, pinEnabled, usdToTJSRate, automaticDailyBackupEnabled
    }

    init(
        openingBalances: [Currency: Decimal] = [.USD: 0, .TJS: 0],
        hideAmounts: Bool = false,
        useDarkTheme: Bool = true,
        faceIDEnabled: Bool = false,
        pinEnabled: Bool = false,
        usdToTJSRate: Decimal = 9.28,
        automaticDailyBackupEnabled: Bool = true
    ) {
        self.openingBalances = openingBalances
        self.hideAmounts = hideAmounts
        self.useDarkTheme = useDarkTheme
        self.faceIDEnabled = faceIDEnabled
        self.pinEnabled = pinEnabled
        self.usdToTJSRate = usdToTJSRate
        self.automaticDailyBackupEnabled = automaticDailyBackupEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openingBalances = try c.decodeIfPresent([Currency: Decimal].self, forKey: .openingBalances) ?? [.USD: 0, .TJS: 0]
        hideAmounts = try c.decodeIfPresent(Bool.self, forKey: .hideAmounts) ?? false
        useDarkTheme = try c.decodeIfPresent(Bool.self, forKey: .useDarkTheme) ?? true
        faceIDEnabled = try c.decodeIfPresent(Bool.self, forKey: .faceIDEnabled) ?? false
        pinEnabled = try c.decodeIfPresent(Bool.self, forKey: .pinEnabled) ?? false
        usdToTJSRate = try c.decodeIfPresent(Decimal.self, forKey: .usdToTJSRate) ?? 9.28
        automaticDailyBackupEnabled = try c.decodeIfPresent(Bool.self, forKey: .automaticDailyBackupEnabled) ?? true
    }
}

struct BackupPayload: Codable {
    var transactions: [MoneyTransaction]
    var preferences: AppPreferences
    var reportBalanceCheckpoints: [ReportBalanceCheckpoint] = []
    var createdAt = Date()

    enum CodingKeys: String, CodingKey {
        case transactions, preferences, reportBalanceCheckpoints, createdAt
    }

    init(transactions: [MoneyTransaction], preferences: AppPreferences, reportBalanceCheckpoints: [ReportBalanceCheckpoint] = [], createdAt: Date = Date()) {
        self.transactions = transactions
        self.preferences = preferences
        self.reportBalanceCheckpoints = reportBalanceCheckpoints
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transactions = try c.decodeIfPresent([MoneyTransaction].self, forKey: .transactions) ?? []
        preferences = try c.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()
        reportBalanceCheckpoints = try c.decodeIfPresent([ReportBalanceCheckpoint].self, forKey: .reportBalanceCheckpoints) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct ClientBackupSummary: Codable, Hashable {
    var name: String
    var transactionCount: Int
    var attachmentCount: Int
    var balances: [Currency: Decimal]
}

struct FullBackupArchive: Codable {
    var schemaVersion: Int = 2
    var createdAt: Date = Date()
    var appVersion: String
    var buildNumber: String
    var transactions: [MoneyTransaction]
    var reportBalanceCheckpoints: [ReportBalanceCheckpoint] = []
    var preferences: AppPreferences
    var clients: [ClientBackupSummary]
    var cashBalances: [Currency: Decimal]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, createdAt, appVersion, buildNumber
        case transactions, reportBalanceCheckpoints, preferences, clients, cashBalances
    }

    init(
        schemaVersion: Int = 2,
        createdAt: Date = Date(),
        appVersion: String,
        buildNumber: String,
        transactions: [MoneyTransaction],
        reportBalanceCheckpoints: [ReportBalanceCheckpoint] = [],
        preferences: AppPreferences,
        clients: [ClientBackupSummary],
        cashBalances: [Currency: Decimal]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.transactions = transactions
        self.reportBalanceCheckpoints = reportBalanceCheckpoints
        self.preferences = preferences
        self.clients = clients
        self.cashBalances = cashBalances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "—"
        buildNumber = try container.decodeIfPresent(String.self, forKey: .buildNumber) ?? "—"
        transactions = try container.decode([MoneyTransaction].self, forKey: .transactions)
        reportBalanceCheckpoints = try container.decodeIfPresent([ReportBalanceCheckpoint].self, forKey: .reportBalanceCheckpoints) ?? []
        preferences = try container.decode(AppPreferences.self, forKey: .preferences)
        clients = try container.decodeIfPresent([ClientBackupSummary].self, forKey: .clients) ?? []
        cashBalances = try container.decodeIfPresent([Currency: Decimal].self, forKey: .cashBalances) ?? [:]
    }
}
