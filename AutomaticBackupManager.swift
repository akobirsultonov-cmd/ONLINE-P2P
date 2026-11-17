import Foundation

struct AutomaticBackupResult {
    let date: Date
    let locationDescription: String
}

enum AutomaticBackupError: LocalizedError {
    case cannotAccessSelectedFolder
    case verificationFailed
    case iCloudWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotAccessSelectedFolder:
            return "Нет доступа к выбранной папке iCloud. Выберите папку ещё раз."
        case .verificationFailed:
            return "Не удалось проверить запись в выбранную папку iCloud."
        case .iCloudWriteFailed(let message):
            return "Копия сохранена на iPhone, но не в iCloud: \(message)"
        }
    }
}

enum AutomaticBackupManager {
    private static let folderName = "P2POffline-AutoBackups"
    private static let latestFileName = "P2P-Offline-Auto-Latest.json"
    private static let maxDatedBackups = 7
    private static let selectedFolderBookmarkKey = "P2POffline.AutoBackup.SelectedFolderBookmark"
    private static let selectedFolderNameKey = "P2POffline.AutoBackup.SelectedFolderName"

    static var selectedFolderName: String? {
        UserDefaults.standard.string(forKey: selectedFolderNameKey)
    }

    static var hasSelectedFolder: Bool {
        UserDefaults.standard.data(forKey: selectedFolderBookmarkKey) != nil
    }

    /// Saves a persistent bookmark only after proving that the selected Files/iCloud
    /// directory is genuinely writable. This prevents a false "folder selected" state.
    static func setSelectedFolder(_ url: URL) throws {
        let selectedURL = url.standardizedFileURL
        let accessed = selectedURL.startAccessingSecurityScopedResource()
        guard accessed else {
            throw AutomaticBackupError.cannotAccessSelectedFolder
        }
        defer { selectedURL.stopAccessingSecurityScopedResource() }

        // Verify the chosen File Provider / iCloud Drive folder before remembering it.
        let testName = ".p2p-write-test-\(UUID().uuidString).tmp"
        let testURL = selectedURL.appendingPathComponent(testName)
        let testData = Data("P2P Offline iCloud write test".utf8)
        do {
            try coordinatedWrite(testData, to: testURL)
            guard FileManager.default.fileExists(atPath: testURL.path) else {
                throw AutomaticBackupError.verificationFailed
            }
            try coordinatedRemove(testURL)
        } catch {
            try? coordinatedRemove(testURL)
            throw AutomaticBackupError.iCloudWriteFailed(error.localizedDescription)
        }

        // Apple recommends a minimal bookmark for a directory obtained from a document picker.
        let bookmark = try selectedURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: [.nameKey, .isDirectoryKey],
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: selectedFolderBookmarkKey)
        UserDefaults.standard.set(selectedURL.lastPathComponent, forKey: selectedFolderNameKey)
        UserDefaults.standard.synchronize()
    }

    static func clearSelectedFolder() {
        UserDefaults.standard.removeObject(forKey: selectedFolderBookmarkKey)
        UserDefaults.standard.removeObject(forKey: selectedFolderNameKey)
    }

    static func save(data: Data) throws -> AutomaticBackupResult {
        let fileManager = FileManager.default
        let now = Date()
        let fileName = "P2P-Offline-Auto-\(fileDateText(now)).json"

        // Always keep a local safety copy first.
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localFolder = documents.appendingPathComponent(folderName, isDirectory: true)
        try createFolderIfNeeded(localFolder, fileManager: fileManager)
        try writeLocal(data, fileName: fileName, folder: localFolder)
        try writeLocalLatest(data, folder: localFolder)
        pruneOldBackups(in: localFolder, fileManager: fileManager)

        // If the user selected an iCloud/Files folder, iCloud success is required.
        // Never silently report the local fallback as a successful cloud backup.
        if hasSelectedFolder {
            guard let selectedFolder = try resolveSelectedFolder() else {
                throw AutomaticBackupError.cannotAccessSelectedFolder
            }

            let accessed = selectedFolder.startAccessingSecurityScopedResource()
            guard accessed else {
                throw AutomaticBackupError.cannotAccessSelectedFolder
            }
            defer { selectedFolder.stopAccessingSecurityScopedResource() }

            do {
                try coordinatedWrite(data, to: selectedFolder.appendingPathComponent(fileName))
                try coordinatedWrite(data, to: selectedFolder.appendingPathComponent(latestFileName))
                pruneOldBackupsCoordinated(in: selectedFolder)

                // Verify that the provider exposes the just-written files.
                let latestURL = selectedFolder.appendingPathComponent(latestFileName)
                guard FileManager.default.fileExists(atPath: latestURL.path) else {
                    throw AutomaticBackupError.verificationFailed
                }

                let name = selectedFolderName ?? selectedFolder.lastPathComponent
                return AutomaticBackupResult(date: now, locationDescription: "iCloud: \(name) + iPhone")
            } catch let error as AutomaticBackupError {
                throw error
            } catch {
                throw AutomaticBackupError.iCloudWriteFailed(error.localizedDescription)
            }
        }

        // For builds that genuinely have an iCloud ubiquity container, keep this as a secondary route.
        if let container = fileManager.url(forUbiquityContainerIdentifier: nil) {
            let cloudFolder = container
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            do {
                try createFolderIfNeeded(cloudFolder, fileManager: fileManager)
                try coordinatedWrite(data, to: cloudFolder.appendingPathComponent(fileName))
                try coordinatedWrite(data, to: cloudFolder.appendingPathComponent(latestFileName))
                pruneOldBackupsCoordinated(in: cloudFolder)
                return AutomaticBackupResult(date: now, locationDescription: "iCloud Drive + iPhone")
            } catch {
                // No user-selected folder exists, so local safety copy is still a valid fallback.
                return AutomaticBackupResult(date: now, locationDescription: "iPhone • выберите папку iCloud")
            }
        }

        return AutomaticBackupResult(date: now, locationDescription: "iPhone • выберите папку iCloud")
    }

    private static func resolveSelectedFolder() throws -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: selectedFolderBookmarkKey) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ).standardizedFileURL

        if stale {
            let accessed = url.startAccessingSecurityScopedResource()
            guard accessed else { throw AutomaticBackupError.cannotAccessSelectedFolder }
            defer { url.stopAccessingSecurityScopedResource() }

            let refreshed = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: [.nameKey, .isDirectoryKey],
                relativeTo: nil
            )
            UserDefaults.standard.set(refreshed, forKey: selectedFolderBookmarkKey)
        }
        return url
    }

    private static func coordinatedWrite(_ data: Data, to destinationURL: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                // A non-atomic write avoids provider-host rename failures inside security-scoped folders.
                try data.write(to: coordinatedURL, options: [])
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private static func coordinatedRemove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var coordinationError: NSError?
        var removeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                removeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let removeError { throw removeError }
    }

    private static func createFolderIfNeeded(_ url: URL, fileManager: FileManager) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func writeLocal(_ data: Data, fileName: String, folder: URL) throws {
        let url = folder.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
    }

    private static func writeLocalLatest(_ data: Data, folder: URL) throws {
        let url = folder.appendingPathComponent(latestFileName)
        try data.write(to: url, options: [.atomic])
    }

    private static func pruneOldBackups(in folder: URL, fileManager: FileManager) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let dated = datedBackupURLs(urls)
        for url in sortedNewestFirst(dated).dropFirst(maxDatedBackups) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func pruneOldBackupsCoordinated(in folder: URL) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let dated = datedBackupURLs(urls)
        for url in sortedNewestFirst(dated).dropFirst(maxDatedBackups) {
            try? coordinatedRemove(url)
        }
    }

    private static func datedBackupURLs(_ urls: [URL]) -> [URL] {
        urls.filter {
            $0.lastPathComponent.hasPrefix("P2P-Offline-Auto-") &&
            $0.lastPathComponent != latestFileName &&
            $0.pathExtension.lowercased() == "json"
        }
    }

    private static func sortedNewestFirst(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
    }

    private static func fileDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}
