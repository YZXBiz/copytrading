/// Where the account sheet opens when it is asked for one setting rather than the whole account:
/// its limits from Edit Limits, or the price tolerance from Activity's suggestion.
enum AccountEditorFocus {
    case limits
    case entryTolerance
}
