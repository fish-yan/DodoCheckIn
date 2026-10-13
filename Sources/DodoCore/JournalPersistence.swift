import Foundation
import SwiftData

@Model
final class StoredJournal {
    @Attribute(.unique) var id: String
    var payload: Data

    init(payload: Data) {
        id = "child-journal-v1"
        self.payload = payload
    }
}

// One versioned document lets a review and its rewards commit atomically.
// Only the UI store accesses its ModelContext, so persistence is main-actor isolated.
@MainActor
final class JournalPersistence {
    let container: ModelContainer
    private let context: ModelContext
    private let document: StoredJournal
    private(set) var journal: Journal

    init(now: Date, memoryOnly: Bool = false, url: URL? = nil) throws {
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(isStoredInMemoryOnly: memoryOnly, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: StoredJournal.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        if let saved = try context.fetch(FetchDescriptor<StoredJournal>()).first {
            document = saved
            journal = try JSONDecoder().decode(Journal.self, from: saved.payload)
            guard (1...3).contains(journal.schemaVersion) else { throw PersistenceError.unsupportedVersion }
        } else {
            journal = Journal(now: now)
            document = StoredJournal(payload: try JSONEncoder().encode(journal))
            context.insert(document)
            try context.save()
        }
        if journal.expandedRulesStartDay == nil || journal.listeningStartDay == nil {
            var upgraded = journal
            CheckInEngine.reconcile(&upgraded, now: now)
            try commit(upgraded)
        }
    }

    func commit(_ next: Journal) throws {
        let data = try JSONEncoder().encode(next)
        document.payload = data
        do {
            try context.save()
            journal = next
        } catch {
            context.rollback()
            throw error
        }
    }
}

enum PersistenceError: LocalizedError {
    case unsupportedVersion
    var errorDescription: String? { "此记录由更新版本创建，请更新 App 后打开。" }
}
