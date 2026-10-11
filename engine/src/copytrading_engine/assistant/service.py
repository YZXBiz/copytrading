"""Answers run as background tasks the app polls; nothing outlives a reset."""

import asyncio
import datetime as dt
import uuid
from collections.abc import Awaitable, Callable, Iterable
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, SecretStr
from pydantic_ai.models import Model

from copytrading_engine.assistant import insights
from copytrading_engine.assistant.agent import BudgetExceeded, ModelRejected, run_turn
from copytrading_engine.assistant.conversation import (
    AssistantEvent,
    Conversation,
    ConversationBook,
    Turn,
)
from copytrading_engine.assistant.tools import AssistantTools
from copytrading_engine.control.service import ControlService
from copytrading_engine.parsing.providers.registry import open_chat_model
from copytrading_engine.trading.domain.config import ProviderConfiguration

MESSAGES = {
    "model_timeout": (
        "Your model didn't answer in time. Try again, or pick another model in Connections."
    ),
    "model_unavailable": (
        "Your model couldn't be reached. Check your connection, "
        "or pick another model in Connections."
    ),
    "model_rejected": (
        "Your model refused the request. Check its key and model name in Connections."
    ),
    "budget_exceeded": "That needed more steps than one answer allows. Try a narrower question.",
}


MAX_GURUS = 50


class AskGuru(BaseModel):
    """A guru as the owner knows them: the id the engine records, and the name the app shows."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,64}$")
    name: str = Field(min_length=1, max_length=100)


MAX_SETUP_ACCOUNTS = 20

type SetupState = Literal["connected", "filled", "missing", "failed"]


class AskSetupAccount(BaseModel):
    """An account in Connections: its name, paper or live, and how far it is set up. No keys."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    name: str = Field(min_length=1, max_length=64)
    environment: Literal["paper", "live"]
    state: SetupState


class AskSetup(BaseModel):
    """What Connections holds, which may not be saved yet, so the assistant can tell an account
    that is set up but not started from no account at all. It never carries a key or a token."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    saved: bool
    copying: bool
    unsaved_changes: bool
    discord: SetupState
    interpreter: SetupState
    accounts: tuple[AskSetupAccount, ...] = Field(default=(), max_length=MAX_SETUP_ACCOUNTS)


class AskContext(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    screen: Literal[
        "today",
        "activity",
        "people",
        "accounts",
        "connections",
        "gettingStarted",
        "diagnostics",
        "settings",
    ]
    selected_source_id: str | None = None
    selected_account_id: str | None = None
    selected_guru_id: str | None = None
    language: Literal["en", "zh-Hans"] = "en"
    gurus: tuple[AskGuru, ...] = Field(default=(), max_length=MAX_GURUS)
    setup: AskSetup | None = None

    def guru_names(self) -> dict[str, str]:
        return {guru.id: guru.name for guru in self.gurus}


class AssistantService:
    def __init__(
        self,
        control: ControlService,
        operator: insights.Operator,
        *,
        engine_state: Callable[[], str],
        register_secrets: Callable[[Iterable[str]], object],
        open_model: Callable[..., Awaitable[tuple[Model, Callable[[], Awaitable[None]]]]] = (
            open_chat_model
        ),
        now: Callable[[], dt.datetime] = lambda: dt.datetime.now(dt.UTC),
        time_budget: float = 60,
    ) -> None:
        self._control = control
        self._operator = operator
        self._engine_state = engine_state
        self._register_secrets = register_secrets
        self._open_model = open_model
        self._now = now
        self._time_budget = time_budget
        self._book = ConversationBook()
        self._tasks: dict[asyncio.Task[None], Turn] = {}

    async def ask(
        self,
        conversation_id: str,
        text: str,
        context: AskContext,
        provider: ProviderConfiguration,
        provider_api_key: SecretStr,
    ) -> str:
        conversation = self._book.get_or_open(conversation_id)
        self._stop_cancelled()
        if conversation.running is not None and not conversation.running.done:
            return conversation.running.turn_id
        turn = Turn(f"t-{uuid.uuid4().hex[:12]}")
        conversation.running = turn
        self._book.register(turn, conversation)
        self._register_secrets((provider_api_key.get_secret_value(),))
        task = asyncio.create_task(
            self._answer(conversation, turn, text, context, provider, provider_api_key),
            name=turn.turn_id,
        )
        self._tasks[task] = turn
        task.add_done_callback(lambda finished: self._tasks.pop(finished, None))
        return turn.turn_id

    async def _answer(
        self,
        conversation: Conversation,
        turn: Turn,
        text: str,
        context: AskContext,
        provider: ProviderConfiguration,
        key: SecretStr,
    ) -> None:
        close: Callable[[], Awaitable[None]] | None = None
        try:
            try:
                config = provider.reader(key, timeout=self._time_budget)
                model, close = await self._open_model(provider.name, config)
            except ValueError:
                turn.fail("model_rejected", MESSAGES["model_rejected"])
                return
            tools = AssistantTools(
                self._control,
                self._operator,
                turn,
                engine_state=self._engine_state,
                now=self._now,
                guru_names=context.guru_names(),
            )
            messages = await asyncio.wait_for(
                run_turn(model, tools, turn, text, context, conversation.history),
                timeout=self._time_budget,
            )
            conversation.remember(messages)
            turn.finish()
        except TimeoutError:
            turn.fail("model_timeout", MESSAGES["model_timeout"])
        except asyncio.CancelledError:
            turn.finish()
            raise
        except BudgetExceeded:
            turn.fail("budget_exceeded", MESSAGES["budget_exceeded"])
        except ModelRejected:
            turn.fail("model_rejected", MESSAGES["model_rejected"])
        except Exception:  # noqa: BLE001 - any provider failure ends the turn in plain words
            turn.fail("model_unavailable", MESSAGES["model_unavailable"])
        finally:
            if close is not None:
                await self._close(close)

    @staticmethod
    async def _close(close: Callable[[], Awaitable[None]]) -> None:
        """Close the client even when a second cancellation arrives while closing."""
        closing = asyncio.ensure_future(close())
        try:
            await asyncio.shield(closing)
        except asyncio.CancelledError:
            raise  # the shielded close keeps running to completion on its own
        except Exception:  # noqa: BLE001 - a failed close must not change how the turn ended
            pass

    def _stop_cancelled(self) -> None:
        """Stop the tasks of turns cancelled elsewhere, such as an evicted conversation's."""
        for task, turn in self._tasks.items():
            if turn.cancelled:
                task.cancel()

    def turn(self, turn_id: str, after: int) -> tuple[tuple[AssistantEvent, ...], bool]:
        turn = self._book.turn(turn_id)
        return turn.events(after), turn.done

    def cancel(self, turn_id: str) -> bool:
        try:
            turn = self._book.turn(turn_id)
        except KeyError:
            return False
        turn.cancel()
        for task in self._tasks:
            if task.get_name() == turn_id:
                task.cancel()
        return True

    async def reset(self) -> None:
        self._book.forget_all()
        for task in list(self._tasks):
            task.cancel()
        await asyncio.gather(*list(self._tasks), return_exceptions=True)
