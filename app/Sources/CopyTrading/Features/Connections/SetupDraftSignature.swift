import DesktopCore

/// The setup a check covered: the configuration it would save, and a digest of the keys typed
/// with it. The digest never leaves memory and is only compared within one run of the app.
struct SetupDraftSignature: Equatable {
    let configuration: TradingConfiguration?
    let typedKeys: Int
}
