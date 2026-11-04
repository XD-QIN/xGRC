import BLEKit
import Foundation

/// GATT layout of RICOH THETA X and RICOH360 THETA A1 (protocol reference
/// § Bluetooth protocol reference › Ricoh THETA), from Ricoh's published
/// THETA Bluetooth API (ricohapi/theta-api-specs) and its MIT-licensed
/// client, ricohapi/theta-ble-client (`BleService.kt`,
/// `BleCharacteristic.kt`, `CameraControlCommandV2.kt`). Written from those
/// facts; no client code is copied.
public enum Theta {
    private static func chr(_ service: UUID, _ uuid: String) -> GATTCharacteristicID {
        GATTCharacteristicID(service: service, characteristic: UUID(uuidString: uuid)!)
    }

    /// Camera Control Command v2: JSON in and out, no authentication on X and A1.
    public static let controlService = UUID(uuidString: "B6AC7A7E-8C01-4A52-B188-68D53DF53EA2")!
    /// Notifies the camera state as JSON (`_captureStatus`, `_capturedPictures`, …).
    public static let notifyState = chr(controlService, "D32CE140-B0C2-4C07-AF15-2301B5057B8C")
    /// Takes options as JSON, e.g. `{"captureMode":"image"}`.
    public static let setOptions = chr(controlService, "F0BCD2F9-5862-4653-B50D-80DC51E8CB82")
    /// Takes a Web API command name as JSON. THETA X and A1 only; Ricoh's
    /// client says the Z1 does not support it.
    public static let requestShutter = chr(controlService, "6E2DEEBE-88B0-42A5-829D-1B2C6ABCE750")

    /// Shared with the Ricoh GR: Camera Information › Model Number String.
    public static let infoService = Ricoh.infoService
    public static let modelNumber = Ricoh.modelNumber

    public static let takePicture = Data(#"{"name":"camera.takePicture"}"#.utf8)
    /// A press in video mode would start a recording, so a remote session
    /// puts the camera in still mode first.
    public static let stillMode = Data(#"{"captureMode":"image"}"#.utf8)

    /// The client's name filter: the numeric part of the serial (X, Z1), or
    /// two letters and eight digits (A1). THETA advertises no public service.
    public static func nameMatches(_ name: String) -> Bool {
        name.range(of: #"^([A-Z]{2})?[0-9]{8}$"#, options: .regularExpression) != nil
    }

    /// Bodies whose Bluetooth API needs the Wi-Fi registration xGRC does not do.
    public static func needsWiFiRegistration(model: String) -> Bool {
        let upper = model.uppercased()
        return upper.contains("Z1") || upper.hasSuffix("THETA V") || upper.contains("THETA SC")
    }
}

/// RICOH THETA X and RICOH360 THETA A1, remote only. A shot is one JSON
/// command (`camera.takePicture`); state notifications are logged undecoded,
/// so shots are reported as *assumed*. THETA does not bond. V and Z1 need
/// their Bluetooth device registered over the camera's Wi-Fi first, which
/// xGRC does not do; they are refused with `unsupported`. THETA X has its
/// own GPS, and Ricoh's client has no Bluetooth location write for it.
/// Untested on a camera.
public actor ThetaDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "theta",
        brand: .ricoh,
        displayName: "RICOH THETA",
        capabilities: [.backgroundShooting],
        ackSource: "none decoded (state notify logged)"
    )

    public static var serviceUUIDs: [UUID] { [Theta.controlService] }

    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        let byService = advertisement.serviceUUIDs.contains(Theta.controlService)
        guard byService || advertisement.localName.map(Theta.nameMatches) == true else { return nil }
        let name = advertisement.localName.map { "THETA \($0)" } ?? "RICOH THETA"
        return CameraMatch(driverID: descriptor.id, displayName: name, modelCode: nil, isPairable: true)
    }

    private let link: DriverLink
    private var usesRemote = true

    public init(transport: any GATTTransport) {
        link = DriverLink(transport: transport, adaptiveWrites: true)
    }

    public func setFeatures(remote: Bool, geotag: Bool) {
        usesRemote = remote
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        let shoot = ShotStep.write(ShotWrite(Theta.takePicture, to: Theta.requestShutter, firesShutter: true))
        return ShotScript(focusSupported: false, focusPress: [], focusRelease: [], shootFromFocus: [],
                          shootWithoutFocus: [shoot], latch: [], unlatch: [], releaseAll: [],
                          minimumWriteGap: .zero, acknowledgesFocus: false)
    }()

    // MARK: Pairing and reconnect

    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        progress(.connecting)
        try await connect(window: DriverLink.bondingWindow)
        progress(.done)
        return .bondOnly
    }

    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        try await connect(window: DriverLink.writeTimeout)
    }

    public func disconnect() async {
        await link.disconnect()
    }

    private func connect(window: Duration) async throws {
        try await link.discover([Theta.infoService, Theta.controlService], required: [Theta.requestShutter])
        if await link.has(Theta.modelNumber),
           let model = String(data: try await link.read(Theta.modelNumber, timeout: window), encoding: .utf8),
           Theta.needsWiFiRegistration(model: model) {
            throw CameraError.unsupported
        }
        if await link.has(Theta.notifyState) {
            try? await link.subscribe(Theta.notifyState, decode: {
                .unknown(characteristic: Theta.notifyState, value: $0)
            })
        }
        if usesRemote, await link.has(Theta.setOptions) {
            try await link.write(Theta.stillMode, to: Theta.setOptions, timeout: window)
        }
    }

    // MARK: Buttons

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        guard button == .shutter else { return .unsupported }
        try await send(ShotWrite(Theta.takePicture, to: Theta.requestShutter, firesShutter: true))
        return .sent
    }

    public func release(_ button: CameraButton) async throws {}

    public func send(_ write: ShotWrite) async throws {
        try await link.send(write)
    }
}
