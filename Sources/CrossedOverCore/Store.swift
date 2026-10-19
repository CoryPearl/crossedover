import Foundation
import GRDB

public final class Store: Sendable {
    private let database: DatabaseQueue
    public init(url: URL) throws {
        database = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "records") { table in
                table.column("kind", .text).notNull()
                table.column("id", .text).notNull()
                table.column("payload", .blob).notNull()
                table.primaryKey(["kind", "id"])
            }
        }
        try migrator.migrate(database)
    }
    public func close() throws { try database.close() }
    public func put<T: Encodable & Sendable>(_ value: T, kind: String, id: String) throws {
        let data = try JSONEncoder().encode(value)
        try database.write { db in
            try db.execute(sql: "INSERT INTO records(kind,id,payload) VALUES(?,?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload", arguments: [kind, id, data])
        }
    }
    public func all<T: Decodable & Sendable>(_ type: T.Type, kind: String) throws -> [T] {
        try database.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind=? ORDER BY id", arguments: [kind]).map { try JSONDecoder().decode(type, from: $0) }
        }
    }
    public func remove(kind: String, id: String) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM records WHERE kind=? AND id=?", arguments: [kind, id]) }
    }
    /// Game sessions share an ID with their launch operation. Commit both
    /// together so a delivered request is never mistaken for a started game.
    @discardableResult public func putSession(_ session: LaunchSession) throws -> Bool {
        try database.write { db in
            let id = session.id.uuidString
            if let old = try Data.fetchOne(db, sql: "SELECT payload FROM records WHERE kind='session' AND id=?", arguments: [id]),
               try JSONDecoder().decode(LaunchSession.self, from: old).endedAt != nil, session.endedAt == nil { return false }
            try db.execute(sql: "INSERT INTO records(kind,id,payload) VALUES('session',?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload", arguments: [id, try JSONEncoder().encode(session)])
            if let data = try Data.fetchOne(db, sql: "SELECT payload FROM records WHERE kind='operation' AND id=?", arguments: [id]) {
                var operation = try JSONDecoder().decode(OperationRecord.self, from: data)
                if operation.kind.hasPrefix("Launch ") {
                    operation.state = session.state == "running" ? "started" : session.state
                    operation.detail = session.detail ?? (session.state == "requested" ? "Launch request sent. Waiting for the game process." : "Game state: \(session.state).")
                    operation.updatedAt = Date()
                    try db.execute(sql: "UPDATE records SET payload=? WHERE kind='operation' AND id=?", arguments: [try JSONEncoder().encode(operation), id])
                }
            }
            return true
        }
    }
    public func finishOperation(_ operation: OperationRecord) throws {
        try database.write { db in
            if operation.state == "requested",
               let data = try Data.fetchOne(db, sql: "SELECT payload FROM records WHERE kind='operation' AND id=?", arguments: [operation.id.uuidString]),
               try JSONDecoder().decode(OperationRecord.self, from: data).state != "running" { return }
            try db.execute(sql: "INSERT INTO records(kind,id,payload) VALUES('operation',?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload", arguments: [operation.id.uuidString, try JSONEncoder().encode(operation)])
        }
    }
    /// Worker replies can arrive after Stop. Check and write in one transaction
    /// so a delayed reply cannot resurrect a terminal run.
    @discardableResult func updateActiveWindowsRun(_ run: WindowsAppRun) throws -> Bool {
        try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM records WHERE kind='windowsRun' AND id=?", arguments: [run.id.uuidString]) else { return false }
            let saved = try JSONDecoder().decode(WindowsAppRun.self, from: data)
            guard saved.isActive, saved.appID == run.appID, saved.environmentID == run.environmentID else { return false }
            try db.execute(sql: "UPDATE records SET payload=? WHERE kind='windowsRun' AND id=?", arguments: [try JSONEncoder().encode(run), run.id.uuidString])
            return true
        }
    }
    public func replaceGames(_ games: [GameInstallation], environmentID: UUID) throws {
        let encoder = JSONEncoder()
        let entries = try games.map { ($0.id, try encoder.encode($0)) }
        try database.write { db in
            let prefix = environmentID.uuidString + ":%"
            try db.execute(sql: "DELETE FROM records WHERE kind='game' AND id LIKE ?", arguments: [prefix])
            for (id, data) in entries {
                try db.execute(sql: "INSERT INTO records(kind,id,payload) VALUES('game',?,?)", arguments: [id, data])
            }
        }
    }
    /// Commit restored environment metadata and its executable cards together.
    public func restoreEnvironment(_ environment: ManagedEnvironment, apps: [WindowsApp]) throws {
        guard apps.allSatisfy({ $0.environmentID == environment.id }), Set(apps.map(\.id)).count == apps.count else {
            throw CrossedOverError.message("The backup contains invalid Windows app cards.")
        }
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let environmentData = try encoder.encode(environment)
        let entries = try apps.map { ($0.id.uuidString, try encoder.encode($0)) }
        try database.write { db in
            let existing = try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind='windowsApp'")
                .map { try decoder.decode(WindowsApp.self, from: $0) }
            guard !existing.contains(where: { existingApp in existingApp.environmentID != environment.id && apps.contains(where: { $0.id == existingApp.id }) }) else {
                throw CrossedOverError.message("A restored card conflicts with another Windows environment.")
            }
            for app in existing where app.environmentID == environment.id {
                try db.execute(sql: "DELETE FROM records WHERE kind='windowsApp' AND id=?", arguments: [app.id.uuidString])
            }
            for (id, data) in entries { try db.execute(sql: "INSERT INTO records(kind,id,payload) VALUES('windowsApp',?,?)", arguments: [id, data]) }
            try db.execute(sql: "INSERT INTO records(kind,id,payload) VALUES('environment',?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload", arguments: [environment.id.uuidString, environmentData])
        }
    }

}
