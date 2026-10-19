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
