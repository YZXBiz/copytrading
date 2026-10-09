/// How a timeline row's dot is drawn: sage in an ink ring when the row traded, sky while an order
/// is out with the broker, an amber ring when it waits on the owner, and a plain ink ring for
/// everything else.
enum TimelineMark {
    case traded
    case working
    case waiting
    case quiet
}
