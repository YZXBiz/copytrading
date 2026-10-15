/// Where a drafted trade's price comes from: the price the guru posted, the market's live quote,
/// or a limit the owner types.
enum PriceChoice: Equatable {
    case guru
    case market
    case limit
}
