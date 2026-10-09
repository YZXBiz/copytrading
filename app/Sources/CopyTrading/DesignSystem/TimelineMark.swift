/// How a timeline row's dot is drawn: butter in an ink ring when the row traded, an amber ring
/// when it waits on the owner, and a plain ink ring for everything else.
enum TimelineMark {
    case traded
    case waiting
    case quiet
}
