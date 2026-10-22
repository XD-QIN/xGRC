import Foundation
import Persistence
import Testing

/// One bad saved field or record must not cost every setting or camera.
@Suite("Persistence")
struct PersistenceTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("xgrc-persistence-\(UUID().uuidString)", isDirectory: true)

    private func write(_ json: String, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func backups() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".unreadable-") }
    }

    @Test("An unknown mode or a field of the wrong type keeps every other setting")
    func lenientSettings() async throws {
        try write("""
        {"afHold": true, "sessionMode": "timeTravel", "bulbSeconds": "ten", "releaseDelaySeconds": 7,
         "intervalometer": {"intervalSeconds": 3, "frames": null, "focusEachFrame": "yes"}}
        """, to: "settings.json")
        let settings = await Stores(directory: directory, secrets: InMemorySecretStore()).settings.load()
        #expect(settings.afHold)
        #expect(settings.sessionMode == .remoteAndGeotag)
        #expect(settings.bulbSeconds == 0)
        #expect(settings.releaseDelaySeconds == 7)
        #expect(settings.intervalometer.intervalSeconds == 3)
        #expect(settings.intervalometer.frames == nil, "null means run until stopped")
        #expect(settings.intervalometer.focusEachFrame == false)
        #expect(settings.autoDisconnectMinutes == 15)
    }

    @Test("A settings file from before Tap to shoot, Auto reconnect and Appearance takes their defaults")
    func newSettingsDefaults() async throws {
        try write("""
        {"afHold": true, "bulbSeconds": 30, "appearance": "sepia"}
        """, to: "settings.json")
        let settings = await Stores(directory: directory, secrets: InMemorySecretStore()).settings.load()
        #expect(settings.afHold)
        #expect(settings.bulbSeconds == 30)
        #expect(settings.tapToShoot == false)
        #expect(settings.autoReconnect)
        #expect(settings.appearance == .system)
    }

    @Test("One unreadable camera record is dropped, the rest are kept, and the file is backed up")
    func lenientCameras() async throws {
        let good = UUID()
        try write("""
        [{"id": "\(good)", "driverID": "sony", "name": "a7 IV", "peripheralID": "\(UUID())", "keepAwake": 3},
         {"id": "not-a-uuid", "driverID": "sony", "name": "broken", "peripheralID": "\(UUID())"}]
        """, to: "cameras.json")
        let stores = Stores(directory: directory, secrets: InMemorySecretStore())
        let cameras = await stores.cameras.load()
        #expect(cameras.map(\.id) == [good])
        #expect(cameras.first?.keepAwake == false)
        #expect(try backups().count == 1)
    }

    @Test("An unreadable file is backed up before the defaults overwrite it")
    func unreadableBackedUp() async throws {
        try write("{ this is not json", to: "settings.json")
        let stores = Stores(directory: directory, secrets: InMemorySecretStore())
        #expect(await stores.settings.load() == AppSettings())
        try await stores.settings.update { $0.afHold = true }
        let saved = try backups()
        #expect(saved.count == 1)
        let backup = try String(contentsOf: directory.appendingPathComponent(try #require(saved.first)), encoding: .utf8)
        #expect(backup == "{ this is not json")
    }
}
