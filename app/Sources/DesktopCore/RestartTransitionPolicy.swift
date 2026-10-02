public enum RestartTransitionPolicy {
    public static func nextAttempt(
        attemptsUsed: Int,
        maximumRestarts: Int,
        explicitlyStopped: Bool
    ) -> Int? {
        guard !explicitlyStopped, attemptsUsed < maximumRestarts else { return nil }
        return attemptsUsed + 1
    }
}
