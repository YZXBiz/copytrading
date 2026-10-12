import DesktopCore

extension OrderActivity {
    /// A lot the owner sold by hand from its account page. It is tied to the post that bought
    /// the lot, but nobody copied it, so it never reads as a copied order.
    var isOwnerSale: Bool { clientID.hasPrefix("lotsale-") }
}
