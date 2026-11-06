/// Waits until `condition` holds, for code running on other tasks. Real time only bounds the wait;
/// it never drives the code under test.
func eventually(_ condition: () -> Bool) async -> Bool {
    let limit = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < limit {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

/// Gives other tasks a moment to run, before checking that something did not happen.
func settle() async {
    try? await Task.sleep(for: .milliseconds(20))
}
