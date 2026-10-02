"""One conversation's bounded memory and one answer's ordered events; nothing is persisted."""

from collections import OrderedDict
from typing import Literal

from pydantic import BaseModel, ConfigDict

MAX_TURNS = 20
MAX_CONVERSATIONS = 4
MAX_LINKS = 3

type EventKind = Literal["text", "step", "link", "proposal", "error", "done"]


class AssistantLink(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    kind: Literal["post", "account", "guru"]
    id: str
    title: str


class AssistantEvent(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    seq: int
    kind: EventKind
    text: str | None = None
    link: AssistantLink | None = None
    proposal_id: str | None = None
    code: str | None = None


class Turn:
    """One answer in progress: an append-only event log the app reads by sequence."""

    def __init__(self, turn_id: str) -> None:
        self.turn_id = turn_id
        self._events: list[AssistantEvent] = []
        self._links: set[tuple[str, str]] = set()
        self._text_written = False
        self.done = False
        self.cancelled = False

    def _add(
        self,
        kind: EventKind,
        *,
        text: str | None = None,
        link: AssistantLink | None = None,
        proposal_id: str | None = None,
        code: str | None = None,
    ) -> None:
        if self.done:
            return
        self._events.append(
            AssistantEvent(
                seq=len(self._events) + 1,
                kind=kind,
                text=text,
                link=link,
                proposal_id=proposal_id,
                code=code,
            )
        )

    def add_text(self, chunk: str) -> None:
        """Text written after a tool call starts a new paragraph instead of running on."""
        if not chunk:
            return
        if self._text_written and self._events[-1].kind != "text":
            chunk = "\n\n" + chunk.lstrip("\n")
        self._text_written = True
        self._add(kind="text", text=chunk)

    def add_step(self, text: str) -> None:
        self._add(kind="step", text=text)

    def add_link(self, link: AssistantLink) -> None:
        key = (link.kind, link.id)
        if key in self._links or len(self._links) >= MAX_LINKS:
            return
        self._links.add(key)
        self._add(kind="link", link=link)

    def add_proposal(self, proposal_id: str) -> None:
        self._add(kind="proposal", proposal_id=proposal_id)

    def fail(self, code: str, text: str) -> None:
        self._add(kind="error", code=code, text=text)
        self.finish()

    def finish(self) -> None:
        self._add(kind="done")
        self.done = True

    def cancel(self) -> None:
        self.cancelled = True
        self.finish()

    def events(self, after: int) -> tuple[AssistantEvent, ...]:
        return tuple(event for event in self._events if event.seq > after)


class Conversation:
    def __init__(self, conversation_id: str) -> None:
        self.conversation_id = conversation_id
        self.turns: list[list[object]] = []
        self.running: Turn | None = None
        self.turn_ids: list[str] = []

    @property
    def history(self) -> list[object]:
        return [message for turn in self.turns for message in turn]

    def remember(self, messages: list[object]) -> None:
        self.turns.append(list(messages))
        del self.turns[:-MAX_TURNS]


class ConversationBook:
    def __init__(self) -> None:
        self._conversations: OrderedDict[str, Conversation] = OrderedDict()
        self._turns: dict[str, Turn] = {}

    def get_or_open(self, conversation_id: str) -> Conversation:
        conversation = self._conversations.pop(conversation_id, None) or Conversation(
            conversation_id
        )
        self._conversations[conversation_id] = conversation
        while len(self._conversations) > MAX_CONVERSATIONS:
            _, dropped = self._conversations.popitem(last=False)
            if dropped.running is not None:
                dropped.running.cancel()
            # Remove all turn ids from this conversation
            for turn_id in dropped.turn_ids:
                self._turns.pop(turn_id, None)
        return conversation

    def existing(self, conversation_id: str) -> Conversation:
        return self._conversations[conversation_id]

    def register(self, turn: Turn, conversation: Conversation) -> None:
        self._turns[turn.turn_id] = turn
        conversation.turn_ids.append(turn.turn_id)
        # Remove old turn ids from _turns if the conversation has too many
        while len(conversation.turn_ids) > MAX_TURNS:
            old_id = conversation.turn_ids.pop(0)
            self._turns.pop(old_id, None)

    def turn(self, turn_id: str) -> Turn:
        return self._turns[turn_id]

    def forget_all(self) -> None:
        for conversation in self._conversations.values():
            if conversation.running is not None:
                conversation.running.cancel()
        self._conversations.clear()
        self._turns.clear()
