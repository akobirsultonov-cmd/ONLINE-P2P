import SwiftUI
import UniformTypeIdentifiers
import UIKit


struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    @State private var showAdjustment = false
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var exportingToICloud = false
    @State private var selectingAutoBackupFolder = false
    @State private var iCloudBackupDocument = BackupFileDocument(data: Data())
    @State private var tempBalances: [Currency: String] = [:]
    @State private var backupStatus: String?
    @State private var isRestoringBackup = false
    @State private var openingBalanceStatus: String?
    @State private var exchangeRateText = ""
    @State private var exchangeRateStatus: String?
    @State private var pinAction: PINActionMode?
    @FocusState private var focusedOpeningCurrency: Currency?
    @FocusState private var exchangeRateFocused: Bool

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Начальный остаток кассы") {
                    ForEach(Currency.allCases) { currency in
                        HStack {
                            Text(currency.rawValue)
                            Spacer()
                            TextField(
                                "0",
                                text: Binding(
                                    get: {
                                        tempBalances[currency] ??
                                        (store.preferences.openingBalances[currency] ?? 0).moneyText
                                    },
                                    set: { tempBalances[currency] = $0 }
                                )
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedOpeningCurrency, equals: currency)
                        }
                    }

                    Button {
                        saveOpeningBalances()
                    } label: {
                        Label("Сохранить начальные остатки", systemImage: "checkmark.circle.fill")
                    }

                    if let openingBalanceStatus {
                        Label(openingBalanceStatus, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.green)
                    }

                    Button("Корректировка кассы") {
                        focusedOpeningCurrency = nil
                        showAdjustment = true
                    }
                }

                Section("Курс валюты") {
                    HStack {
                        Text("1 USD =")
                        Spacer()
                        TextField("9.28", text: $exchangeRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($exchangeRateFocused)
                            .frame(maxWidth: 120)
                        Text("TJS")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        saveExchangeRate()
                    } label: {
                        Label("Сохранить курс USD → TJS", systemImage: "dollarsign.arrow.circlepath")
                    }

                    if let exchangeRateStatus {
                        Text(exchangeRateStatus)
                            .font(.caption)
                            .foregroundStyle(exchangeRateStatus.hasPrefix("Курс сохранён") ? AppTheme.green : .red)
                    }

                    Text("Курс используется для подсказки общей суммы в TJS. USD и TJS всё равно сохраняются на остатках отдельно.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Онлайн") {
                    NavigationLink("Веб-админка и синхронизация") { OnlineSyncSettingsView().environmentObject(store) }
                    Text(store.onlineSync.status).font(.caption).foregroundStyle(.secondary)
                }

                Section("Безопасность") {
                    Toggle(
                        "Face ID",
                        isOn: Binding(
                            get: { store.preferences.faceIDEnabled },
                            set: {
                                store.preferences.faceIDEnabled = $0
                                store.save()
                            }
                        )
                    )

                    Toggle(
                        "PIN-код",
                        isOn: Binding(
                            get: { store.preferences.pinEnabled },
                            set: { requested in
                                if requested {
                                    pinAction = PINManager.hasPIN ? .change : .create
                                } else {
                                    pinAction = .disable
                                }
                            }
                        )
                    )

                    if store.preferences.pinEnabled {
                        Button {
                            pinAction = .change
                        } label: {
                            Label("Изменить PIN-код", systemImage: "key.fill")
                        }
                    }

                    Toggle(
                        "Скрывать суммы",
                        isOn: Binding(
                            get: { store.preferences.hideAmounts },
                            set: {
                                store.preferences.hideAmounts = $0
                                store.save()
                            }
                        )
                    )
                }

                Section("Внешний вид") {
                    Toggle(
                        "Тёмная тема",
                        isOn: Binding(
                            get: { store.preferences.useDarkTheme },
                            set: {
                                store.preferences.useDarkTheme = $0
                                store.save()
                            }
                        )
                    )
                }

                Section("Данные") {
                    Toggle(
                        "Автокопия каждый день",
                        isOn: Binding(
                            get: { store.preferences.automaticDailyBackupEnabled },
                            set: { store.setAutomaticDailyBackupEnabled($0) }
                        )
                    )

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "icloud.fill")
                            .foregroundStyle(AppTheme.green)
                        Text(store.automaticBackupStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        selectingAutoBackupFolder = true
                    } label: {
                        Label(
                            store.automaticBackupFolderName == nil ? "Выбрать папку iCloud для автокопии" : "Папка iCloud: \(store.automaticBackupFolderName!)",
                            systemImage: "folder.badge.gearshape"
                        )
                    }

                    if store.automaticBackupFolderName != nil {
                        Button(role: .destructive) {
                            store.clearAutomaticBackupFolder()
                        } label: {
                            Label("Сменить/сбросить папку iCloud", systemImage: "folder.badge.minus")
                        }
                    }

                    Button {
                        store.createAutomaticBackupNow()
                    } label: {
                        Label("Создать копию сейчас", systemImage: "arrow.clockwise.icloud")
                    }

                    Text("Один раз выберите папку в iCloud Drive. После этого приложение будет автоматически сохранять туда полную копию при очередном ежедневном запуске и хранить последние 7 копий. Локальная запасная копия тоже остаётся на iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        guard let data = store.backupData() else { return }
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("P2P-Backup.json")
                        try? data.write(to: url)
                        backupURL = url
                    } label: {
                        Label("Полная резервная копия", systemImage: "externaldrive.badge.plus")
                    }

                    Button {
                        guard let data = store.backupData() else { return }
                        iCloudBackupDocument = BackupFileDocument(data: data)
                        exportingToICloud = true
                    } label: {
                        Label("Сохранить полную копию в iCloud Drive", systemImage: "icloud.and.arrow.up")
                    }

                    Button {
                        importing = true
                    } label: {
                        HStack {
                            Label("Восстановить полную копию из iCloud Drive", systemImage: "icloud.and.arrow.down")
                            if isRestoringBackup {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRestoringBackup)

                    if let backupStatus {
                        Text(backupStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: appVersion)
                    LabeledContent("Сборка", value: buildNumber)
                }
            }
            .navigationTitle("Настройки")
            .onAppear {
                loadOpeningBalanceFields()
                exchangeRateText = store.preferences.usdToTJSRate.moneyText
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") {
                        focusedOpeningCurrency = nil
                        exchangeRateFocused = false
                    }
                }
            }
            .sheet(item: $pinAction) { mode in
                PINSetupView(mode: mode) { enabled in
                    var updated = store.preferences
                    updated.pinEnabled = enabled
                    store.preferences = updated
                    store.save()
                }
            }
            .sheet(isPresented: $showAdjustment) {
                AdjustmentView()
            }
            .sheet(item: $backupURL) { url in
                ShareSheet(items: [url])
            }
            .fileExporter(
                isPresented: $exportingToICloud,
                document: iCloudBackupDocument,
                contentType: .json,
                defaultFilename: "P2P-Offline-Full-Backup-\(backupDateText).json"
            ) { result in
                switch result {
                case .success:
                    let stats = store.backupStatistics()
                    backupStatus = "Полная копия сохранена: \(stats.transactions) операций, \(stats.clients) клиентов, \(stats.attachments) фото/чеков."
                case .failure(let error):
                    backupStatus = "Ошибка сохранения: \(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $selectingAutoBackupFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try store.setAutomaticBackupFolder(url)
                        backupStatus = "Папка iCloud выбрана. Создаю проверочную копию…"
                    } catch {
                        backupStatus = "Не удалось сохранить доступ к папке: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        backupStatus = "Ошибка выбора папки: \(error.localizedDescription)"
                    }
                }
            }
            .sheet(isPresented: $importing) {
                BackupDocumentPicker { result in
                    importing = false
                    switch result {
                    case .success(let localURL):
                        restoreBackupFile(from: localURL)
                    case .failure(let error):
                        if (error as? CocoaError)?.code != .userCancelled {
                            backupStatus = "Ошибка выбора файла: \(error.localizedDescription)"
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
    }


    private func loadOpeningBalanceFields() {
        for currency in Currency.allCases {
            tempBalances[currency] = (store.preferences.openingBalances[currency] ?? 0).moneyText
        }
    }

    private func saveOpeningBalances() {
        focusedOpeningCurrency = nil

        var values: [Currency: Decimal] = [:]
        for currency in Currency.allCases {
            let raw = tempBalances[currency] ??
                (store.preferences.openingBalances[currency] ?? 0).moneyText

            guard let value = raw.decimalValue else {
                openingBalanceStatus = "Проверьте сумму для \(currency.rawValue)"
                return
            }
            values[currency] = value
        }

        store.setOpeningBalances(values)
        loadOpeningBalanceFields()
        openingBalanceStatus = "Начальные остатки сохранены"

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if openingBalanceStatus == "Начальные остатки сохранены" {
                openingBalanceStatus = nil
            }
        }
    }

    private func saveExchangeRate() {
        exchangeRateFocused = false
        guard let rate = exchangeRateText.decimalValue, rate > 0 else {
            exchangeRateStatus = "Введите корректный курс больше 0"
            return
        }
        store.setUSDToTJSRate(rate)
        exchangeRateText = rate.moneyText
        exchangeRateStatus = "Курс сохранён: 1$ = \(rate.moneyText) TJS"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if exchangeRateStatus?.hasPrefix("Курс сохранён") == true {
                exchangeRateStatus = nil
            }
        }
    }

    private func restoreBackupFile(from url: URL) {
        isRestoringBackup = true
        backupStatus = "Восстанавливаю полную копию…"

        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Data, Error> = Result {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                return data
            }

            DispatchQueue.main.async {
                isRestoringBackup = false
                switch result {
                case .success(let data):
                    do {
                        try store.restore(from: data)
                        backupStatus = store.restoreSummaryText()
                    } catch {
                        backupStatus = "Копия выбрана, но данные не удалось восстановить: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    backupStatus = "Файл выбран, но не читается: \(error.localizedDescription)"
                }
            }
        }
    }

    private var backupDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter.string(from: Date())
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}


struct BackupDocumentPicker: UIViewControllerRepresentable {
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .data, .item],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<URL, Error>) -> Void

        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let sourceURL = urls.first else {
                completion(.failure(CocoaError(.fileNoSuchFile)))
                return
            }

            do {
                // asCopy=true usually returns a readable local URL. We copy it once more
                // into our temp folder so the URL stays valid after the picker closes.
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Imported-P2P-Backup-\(UUID().uuidString).json")
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                completion(.success(destination))
            } catch {
                // If the provider already gave us a sandbox copy, use it directly.
                if FileManager.default.isReadableFile(atPath: sourceURL.path) {
                    completion(.success(sourceURL))
                } else {
                    completion(.failure(error))
                }
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.failure(CocoaError(.userCancelled)))
        }
    }
}
