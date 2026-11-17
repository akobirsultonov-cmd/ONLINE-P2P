import Foundation
import SwiftUI
import Security

// Use one device per datastore for the first release. Version conflicts are never overwritten.
@MainActor
final class OnlineSyncManager: ObservableObject {
    @Published var status = "Не подключено"
    @Published var busy = false
    @Published var configuredURL = UserDefaults.standard.string(forKey: "P2P.Sync.URL") ?? ""
    @Published var enabled = UserDefaults.standard.bool(forKey: "P2P.Sync.Enabled")
    private weak var store: AppStore?
    private var version: Int { get { UserDefaults.standard.integer(forKey: "P2P.Sync.Version") } set { UserDefaults.standard.set(newValue, forKey: "P2P.Sync.Version") } }
    private var dirty: Bool { get { UserDefaults.standard.bool(forKey: "P2P.Sync.Dirty") } set { UserDefaults.standard.set(newValue, forKey: "P2P.Sync.Dirty") } }
    private var lastWrite: Int = 0
    private var applyingRemote = false

    init(store: AppStore) { self.store = store }
    func configure(url: String, token: String) throws {
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil else { throw SyncError.invalidURL }
        guard token.count >= 32 else { throw SyncError.invalidToken }
        guard let encoded = token.data(using: .utf8) else { throw SyncError.invalidToken }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "P2P.OnlineSync", kSecAttrAccount as String: "device", kSecValueData as String: encoded, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "P2P.OnlineSync", kSecAttrAccount as String: "device"] as CFDictionary)
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw SyncError.keychain }
        configuredURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(configuredURL, forKey: "P2P.Sync.URL")
        enabled = false
        UserDefaults.standard.set(false, forKey: "P2P.Sync.Enabled")
        version = 0
        dirty = false
        status = "Подключение настроено. Выберите направление первой синхронизации."
    }
    private var token: String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "P2P.OnlineSync", kSecAttrAccount as String: "device", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func request(_ method: String, body: Data? = nil) async throws -> (Int, Data) {
        guard let base = URL(string: configuredURL), base.scheme == "https", let token else { throw SyncError.invalidURL }
        let url = base.appendingPathComponent("api/snapshot")
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        req.timeoutInterval = 40
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.network }
        return (http.statusCode, data)
    }
    // Opt-in initial upload or download, never automatic destruction of local data.
    func firstSync(upload: Bool) async {
        guard !busy, let store else { return }
        busy = true
        defer { busy = false }
        do {
            let (statusCode, body) = try await request("GET")
            guard statusCode == 200 else { throw SyncError.server(statusCode) }
            let remote = try JSONDecoder().decode(SnapshotEnvelope.self, from: body)
            if upload {
                guard remote.version == 0 else { status = "Сервер уже содержит данные. Сначала скачайте их или сделайте резервную копию."; return }
                version = 0
                dirty = true
                enabled = true
                UserDefaults.standard.set(true, forKey: "P2P.Sync.Enabled")
                busy = false
                await sync()
            } else {
                guard let payload = remote.payload, remote.version > 0 else { status = "На сервере ещё нет данных"; return }
                let backup = try JSONEncoder().encode(payload)
                // Back up the existing local data before applying remote state.
                try savePreSyncBackup(store)
                applyingRemote = true
                defer { applyingRemote = false }
                try store.restore(from: backup)
                version = remote.version
                dirty = false
                enabled = true
                UserDefaults.standard.set(true, forKey: "P2P.Sync.Enabled")
                status = "Подключено · версия \(version)"
            }
        } catch { status = "Ошибка: \(error.localizedDescription)" }
    }
    private func savePreSyncBackup(_ store: AppStore) throws {
        guard let data = store.backupData() else { throw SyncError.network }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "pre-online-sync-\(Int(Date().timeIntervalSince1970)).json"
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
    func localSaved() {
        guard enabled, !applyingRemote else { return }
        dirty = true
        lastWrite += 1
        Task { await sync() }
    }
    func sync() async {
        guard enabled, !busy, let store else { return }
        busy = true
        defer { busy = false }
        do {
            if dirty {
                let generation = lastWrite
                guard let backup = store.backupData(), let payload = try JSONSerialization.jsonObject(with: backup) as? [String: Any] else { throw SyncError.network }
                let upload = try JSONSerialization.data(withJSONObject: ["baseVersion": version, "payload": payload])
                let (code, body) = try await request("PUT", body: upload)
                if code == 409 { status = "⚠ Конфликт! Локальные изменения сохранены на iPhone, сервер не перезаписан. Отключите синхронизацию и разберите конфликт."; enabled = false; UserDefaults.standard.set(false, forKey: "P2P.Sync.Enabled"); return }
                guard code == 200 else { throw SyncError.server(code) }
                let result = try JSONDecoder().decode(SyncWriteResponse.self, from: body)
                version = result.version
                dirty = (generation != lastWrite)
                status = "Отправлено · версия \(version)"
                if dirty { Task { await sync() } }
            } else {
                let (code, body) = try await request("GET")
                guard code == 200 else { throw SyncError.server(code) }
                let remote = try JSONDecoder().decode(SnapshotEnvelope.self, from: body)
                if remote.version > version, let payload = remote.payload {
                    // Do not overwrite locally saved data while awaiting network response.
                    guard !dirty else { status = "Есть локальные изменения; повторите синхронизацию"; return }
                    let backup = try JSONEncoder().encode(payload)
                    applyingRemote = true
                    defer { applyingRemote = false }
                    try store.restore(from: backup)
                    version = remote.version
                }
                status = "Актуально · версия \(version)"
            }
        } catch { status = "Нет связи: \(error.localizedDescription). Данные остались на iPhone." }
    }
    func pause() { enabled = false; UserDefaults.standard.set(false, forKey: "P2P.Sync.Enabled"); status = "Синхронизация приостановлена" }
}
private struct SnapshotEnvelope: Decodable { let version: Int; let payload: [String: JSONValue]? }
private struct SyncWriteResponse: Decodable { let version: Int }
// Values remain lossless for JSON archive fields including attachments encoded as base64.
private enum JSONValue: Codable {
    case string(String), number(Decimal), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Decimal.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
}
private enum SyncError: LocalizedError {
    case invalidURL, invalidToken, keychain, network, server(Int)
    var errorDescription: String? {
        switch self { case .invalidURL: return "Укажите HTTPS-адрес сервера"; case .invalidToken: return "Токен минимум 32 символа"; case .keychain: return "Не удалось сохранить токен"; case .network: return "Ошибка сети/формата"; case .server(let code): return "HTTP \(code)" }
    }
}
struct OnlineSyncSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var url = UserDefaults.standard.string(forKey: "P2P.Sync.URL") ?? ""
    @State private var token = ""
    @State private var note = ""
    var body: some View {
        Form {
            Section("Защищённое подключение") {
                TextField("https://your-domain.com", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Токен устройства", text: $token).textInputAutocapitalization(.never)
                Button("Сохранить подключение") {
                    do { try store.onlineSync.configure(url: url, token: token); token = ""; note = "Настройки сохранены" }
                    catch { note = error.localizedDescription }
                }
                if !note.isEmpty { Text(note).font(.caption) }
            }
            Section("Первое подключение") {
                Text("Внимание: сначала сохраните резервную копию. Выберите ОДНО действие. Загрузка с сервера заменит данные на iPhone; перед этим создаётся локальная копия.").font(.caption)
                Button("Отправить данные iPhone на ПУСТОЙ сервер") { Task { await store.onlineSync.firstSync(upload: true) } }
                Button("Загрузить данные сервера на iPhone") { Task { await store.onlineSync.firstSync(upload: false) } }
            }
            Section("Состояние") {
                Text(store.onlineSync.status)
                Button("Синхронизировать сейчас") { Task { await store.onlineSync.sync() } }.disabled(!store.onlineSync.enabled || store.onlineSync.busy)
                Button("Приостановить") { store.onlineSync.pause() }.disabled(!store.onlineSync.enabled)
            }
            Text("Синхронизация выполняется при изменениях и при открытии приложения. Для фоновой доставки при закрытом приложении нужны APNs и отдельная серверная настройка.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Онлайн-синхронизация")
    }
}
