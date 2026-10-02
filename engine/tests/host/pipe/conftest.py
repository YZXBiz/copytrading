"""Fixtures shared by the pipe tests."""

from collections.abc import AsyncIterator, Iterator

import pytest
from pydantic_ai.messages import ModelResponse, TextPart

from copytrading_engine.assistant.service import AssistantService
from copytrading_engine.host.installation import Installation
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.host.self_test.parser import SelfTestParser
from copytrading_engine.host.self_test.service import SelfTestService
from copytrading_engine.host.self_test.store import SQLiteSelfTestStore
from copytrading_engine.host.status import EngineQueries

from ...assistant.scripted import assistant, streamed
from ...control.fakes import service as control_service


@pytest.fixture
def store(tmp_path) -> Iterator[SQLiteSelfTestStore]:
    """A fresh installation's self-test store, closed after the test."""
    with (
        Installation(tmp_path / "application.db") as installation,
        SQLiteSelfTestStore(installation) as opened,
    ):
        yield opened


@pytest.fixture
async def pipe_with_assistant(
    store: SQLiteSelfTestStore,
) -> AsyncIterator[tuple[PipeServer, AssistantService]]:
    """A pipe server whose assistant answers every question with one scripted sentence."""
    svc, *_ = assistant(streamed(lambda messages, info: ModelResponse(parts=[TextPart("Hello")])))
    control, *_ = control_service()
    server = PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
        control=control,
        assistant=svc,
    )
    yield server, svc
    await svc.reset()


@pytest.fixture
def pipe_without_assistant(store: SQLiteSelfTestStore) -> PipeServer:
    """A pipe server with no control service, so no assistant."""
    return PipeServer(
        SelfTestService(store, SelfTestParser()),
        EngineQueries(store, store.installation.instance_id),
    )
