import DesktopCore
import Foundation

func runRuntimeGenerationTests() throws {
    let runtime = RuntimeGeneration()
    var engine = RuntimeGeneration()
    let runtimeStart = runtime.current
    let preSleepStatusRead = engine.current

    _ = engine.advance()  // Injected wake notification invalidates pre-sleep status work.
    try verify(runtime.accepts(runtimeStart), "wake must preserve the runtime's start/stop intent")
    try verify(!engine.accepts(preSleepStatusRead), "wake must reject a status callback started before sleep")
    let postWakeStatusRead = engine.current

    _ = engine.advance()  // Injected owned engine exit/restart.
    try verify(!engine.accepts(postWakeStatusRead), "engine restart must reject status from the prior child generation")
    try verify(runtime.accepts(runtimeStart), "engine restart must retain the enclosing runtime generation")
}
