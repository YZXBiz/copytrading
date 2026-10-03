import DesktopCore
import Foundation
import Testing

func runRuntimeGenerationTests() throws {
    let runtime = RuntimeGeneration()
    var engine = RuntimeGeneration()
    let runtimeStart = runtime.current
    let preSleepStatusRead = engine.current

    _ = engine.advance()  // Injected wake notification invalidates pre-sleep status work.
    try #require(runtime.accepts(runtimeStart), "wake must preserve the runtime's start/stop intent")
    try #require(!engine.accepts(preSleepStatusRead), "wake must reject a status callback started before sleep")
    let postWakeStatusRead = engine.current

    _ = engine.advance()  // Injected owned engine exit/restart.
    try #require(!engine.accepts(postWakeStatusRead), "engine restart must reject status from the prior child generation")
    try #require(runtime.accepts(runtimeStart), "engine restart must retain the enclosing runtime generation")
}
