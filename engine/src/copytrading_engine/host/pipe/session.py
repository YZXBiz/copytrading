"""The pipe session's lifecycle, shared by the server and the handlers that end it."""

from dataclasses import dataclass

from copytrading_engine.host.status import EngineState


@dataclass(slots=True)
class PipeSession:
    state: EngineState = "running"
    process_after_reply: bool = False
    stop_after_reply: bool = False

    def stop(self) -> None:
        """Reply first, then stop reading requests."""
        self.state = "stopping"
        self.stop_after_reply = True
