"""Profile revision and evaluation behavior stays independent of execution."""

import asyncio
import datetime as dt
import hashlib
import importlib
import importlib.util
from decimal import Decimal
from pathlib import Path

import pytest
from pydantic import SecretStr, ValidationError

from copytrading_engine.execution.domain.sizing import RouteConnection
from copytrading_engine.shared.raw_message import RawMessage

from ..readings import buy, sell, trade

SIXTH = str(Decimal(1) / Decimal(6))
THIRD = str(Decimal(1) / Decimal(3))


def _profiles_module():
    spec = importlib.util.find_spec("copytrading_engine.trading.domain.profiles")
    assert spec is not None, "immutable profile/evaluation service is missing"
    return importlib.import_module("copytrading_engine.trading.domain.profiles")


def _draft(module, *, guru_id: str, symbol: str):
    return module.ProfileDraft(
        guru_id=guru_id,
        display_name=guru_id.title(),
        playbook=f"Apple means {symbol}",
        examples=(
            module.ProfileExample(
                message="Bought Apple at 200 1/6",
                expected_action="buy",
                expected_symbol=symbol,
                expected_fraction=Decimal("1") / Decimal("6"),
            ),
        ),
    )


def _mapped(route, name: str) -> str:
    """The ticker the route's playbook states for a company name, as a real model would read it."""
    line = next(line for line in route.playbook.splitlines() if line.startswith(f"{name} means "))
    return line.removeprefix(f"{name} means ")


def _message(message_id: str) -> RawMessage:
    import datetime as dt

    return RawMessage(
        schema_version=1,
        event_type="raw_message",
        source="discord",
        channel_id="123",
        id=message_id,
        timestamp=dt.datetime(2026, 9, 26, tzinfo=dt.UTC),
        text="Bought Apple at 200 1/6",
    )


def test_profile_revisions_are_immutable_and_content_addressed():
    module = _profiles_module()
    builder = module.ProfileBuilder()
    original = builder.build(
        _draft(
            module,
            guru_id="zhao",
            symbol="AAPL",
        )
    )
    edited = builder.build(
        _draft(
            module,
            guru_id="zhao",
            symbol="MSFT",
        )
    )

    assert original.guru_id == edited.guru_id == "zhao"
    assert original.profile_revision != edited.profile_revision
    assert original.playbook == "Apple means AAPL"
    with pytest.raises((ValidationError, AttributeError, TypeError)):
        original.display_name = "Changed in place"
    with pytest.raises((ValidationError, AttributeError, TypeError)):
        original.examples[0].expected_symbol = "TSLA"


def test_profile_examples_compare_expected_and_actual_without_execution():
    module = _profiles_module()
    profile = module.ProfileBuilder().build(
        _draft(
            module,
            guru_id="example-guru",
            symbol="AAPL",
        )
    )

    class Decoder:
        calls = 0

        async def decode(self, text, route, recent=()):
            self.calls += 1
            return trade(
                buy(
                    _mapped(route, "Apple"),
                    "200",
                    said="Bought",
                    ticker_said="Apple",
                    fraction=SIXTH,
                    fraction_said="1/6",
                )
            )

    decoder = Decoder()
    service = module.ProfileExampleReviewService(decoder, provider="deepseek", model="test-model")
    result = asyncio.run(
        service.evaluate(
            profile,
            destinations=(
                RouteConnection(account_id="paper-500", full_position_usd="500"),
                RouteConnection(account_id="paper-3000", full_position_usd="3000"),
            ),
        )
    )

    assert result.simulated is True
    assert result.no_order is True
    assert result.guru_id == profile.guru_id
    assert result.profile_revision == profile.profile_revision
    assert result.provider == "deepseek"
    assert result.model == "test-model"
    assert "charges may apply" in result.cost_notice
    assert len(result.examples) == 1
    assert result.examples[0].matches is True
    assert result.examples[0].actual.instructions[0].symbol == "AAPL"
    assert {
        destination.account_id: destination.budget_usd
        for destination in result.examples[0].actual.destinations
    } == {"paper-500": Decimal("83.33"), "paper-3000": Decimal("500.00")}
    assert decoder.calls == 1
    assert not hasattr(result, "orders")


def test_profile_example_mismatch_requires_settings_correction_and_rerun():
    module = _profiles_module()
    draft = _draft(
        module,
        guru_id="mismatch-guru",
        symbol="AAPL",
    )
    profile = module.ProfileBuilder().build(
        draft.model_copy(
            update={
                "examples": (
                    module.ProfileExample(
                        message="Bought Apple at 200 1/3",
                        expected_action="buy",
                        expected_symbol="AAPL",
                        expected_fraction=Decimal("1") / Decimal("6"),
                    ),
                )
            }
        )
    )

    class Decoder:
        async def decode(self, text, route, recent=()):
            return trade(
                buy(
                    _mapped(route, "Apple"),
                    "200",
                    said="Bought",
                    ticker_said="Apple",
                    fraction=THIRD,
                    fraction_said="1/3",
                )
            )

    review = asyncio.run(
        module.ProfileExampleReviewService(
            Decoder(), provider="deepseek", model="test-model"
        ).evaluate(profile, destinations=())
    )
    assert review.examples[0].matches is False
    assert review.examples[0].review_reasons == ("example_fraction_mismatch",)
    assert review.automatic_activation_allowed is False


def test_ungrounded_example_interpretation_returns_review_and_never_activates():
    module = _profiles_module()
    profile = module.ProfileBuilder().build(
        _draft(
            module,
            guru_id="ungrounded-example-guru",
            symbol="AAPL",
        )
    )

    class Decoder:
        async def decode(self, text, route, recent=()):
            return trade(
                buy(
                    "MSFT",
                    "200",
                    said="Bought",
                    ticker_said="Apple",
                    fraction=SIXTH,
                    fraction_said="1/6",
                )
            )

    review = asyncio.run(
        module.ProfileExampleReviewService(
            Decoder(), provider="deepseek", model="test-model"
        ).evaluate(
            profile,
            destinations=(RouteConnection(account_id="paper", full_position_usd="500"),),
        )
    )
    assert review.simulated is True
    assert review.no_order is True
    assert review.automatic_activation_allowed is False
    comparison = review.examples[0]
    assert comparison.matches is False
    assert comparison.actual.decision == "review"
    assert comparison.actual.review_reasons == ("symbol_not_in_playbook",)
    assert comparison.actual.destinations[0].reason == "example_interpretation_failed"


def test_matching_exit_example_preserves_position_sizing_review_without_blocking_profile():
    module = _profiles_module()
    profile = module.ProfileBuilder().build(
        module.ProfileDraft(
            guru_id="exit-example-guru",
            display_name="Exit Example Guru",
            playbook="Apple means AAPL",
            examples=(
                module.ProfileExample(
                    message="TRADE: Sold Apple half at 200 from 150",
                    expected_action="reduce",
                    expected_symbol="AAPL",
                    expected_fraction=Decimal("0.5"),
                    expected_buy_price=Decimal("150"),
                ),
            ),
        )
    )

    class Decoder:
        async def decode(self, text, route, recent=()):
            return trade(
                sell(
                    "AAPL",
                    "200",
                    bought_at="150",
                    said="Sold",
                    ticker_said="Apple",
                    fraction="0.5",
                    fraction_said="half",
                )
            )

    review = asyncio.run(
        module.ProfileExampleReviewService(
            Decoder(), provider="deepseek", model="test-model"
        ).evaluate(
            profile,
            destinations=(RouteConnection(account_id="paper", full_position_usd="500"),),
        )
    )
    comparison = review.examples[0]
    assert comparison.matches is True
    assert comparison.actual.destinations[0].reason == "position_required_for_exit_sizing"
    assert "position_required_for_exit_sizing" in review.review_reasons
    assert review.automatic_activation_allowed is True


@pytest.mark.parametrize(
    ("guru_id", "symbol", "connections", "expected_budgets"),
    [
        (
            "zhao",
            "AAPL",
            (
                RouteConnection(account_id="paper-500", full_position_usd="500"),
                RouteConnection(account_id="paper-3000", full_position_usd="3000"),
            ),
            # A 1/6 call is a sixth of each account's full position, rounded down to the cent.
            {"paper-500": Decimal("83.33"), "paper-3000": Decimal("500.00")},
        ),
        (
            "other-guru",
            "MSFT",
            (
                RouteConnection(account_id="paper-small", full_position_usd="125"),
                RouteConnection(account_id="paper-large", full_position_usd="1200"),
            ),
            {"paper-small": Decimal("20.83"), "paper-large": Decimal("200.00")},
        ),
    ],
)
def test_historical_evaluation_keeps_guru_revision_and_destination_sizing_independent(
    guru_id, symbol, connections, expected_budgets
):
    module = _profiles_module()
    profile = module.ProfileBuilder().build(
        _draft(
            module,
            guru_id=guru_id,
            symbol=symbol,
        )
    )

    class Decoder:
        async def decode(self, text, route, recent=()):
            mapped_symbol = _mapped(route, "Apple")
            return trade(
                buy(
                    mapped_symbol,
                    "200",
                    said="Bought",
                    ticker_said="Apple",
                    fraction=SIXTH,
                    fraction_said="1/6",
                )
            )

    service = module.ProfileEvaluationService(Decoder(), provider="deepseek", model="test-model")
    result = asyncio.run(
        service.evaluate(_message(f"m-{guru_id}"), profile, destinations=connections)
    )

    assert result.simulated is True
    assert result.no_order is True
    assert "provider charges may apply" in result.cost_notice
    assert result.guru_id == guru_id
    assert result.profile_revision == profile.profile_revision
    assert result.provider == "deepseek"
    assert result.model == "test-model"
    assert result.decision == "trade"
    assert result.instructions[0].symbol == symbol
    assert result.instructions[0].exit_basis is None
    assert {item.account_id: item.budget_usd for item in result.destinations} == expected_budgets
    assert not hasattr(result, "orders")


def test_historical_source_lookup_returns_only_the_immutable_historical_capture(tmp_path: Path):
    from copytrading_engine.sources.sqlite import SQLiteSourceStore
    from copytrading_engine.trading.adapters.operator_queries import historical_source_message

    async def capture():
        store = await SQLiteSourceStore.open(tmp_path / "application.db")
        await store.recovery_start(123, 1)
        source_time = dt.datetime.now(dt.UTC) - dt.timedelta(minutes=10)
        historic = RawMessage(
            schema_version=1,
            event_type="raw_message",
            source="discord",
            channel_id="123",
            author_id="456",
            id="1001",
            timestamp=source_time,
            text="Bought Apple at 200 1/6",
        )
        await store.capture_recovery_page(123, [historic], [], 1001)
        live = RawMessage(
            schema_version=1,
            event_type="raw_message",
            source="discord",
            channel_id="123",
            author_id="456",
            id="1002",
            timestamp=dt.datetime.now(dt.UTC),
            text="Bought Apple at 200 1/6",
        )
        await store.add(live)
        await store.close()
        return historic, live

    historic, live = asyncio.run(capture())
    database = tmp_path / "application.db"
    before = hashlib.sha256(database.read_bytes()).hexdigest()

    assert historical_source_message(database, historic.identity) == historic
    with pytest.raises(ValueError, match="historical_source_unavailable"):
        historical_source_message(database, live.identity)

    after = hashlib.sha256(database.read_bytes()).hexdigest()
    assert after == before


def test_runtime_historical_profile_action_does_not_open_execution_owners(tmp_path: Path):
    from copytrading_engine.sources.sqlite import SQLiteSourceStore
    from copytrading_engine.trading.domain.config import ProviderConfiguration
    from copytrading_engine.trading.entrypoints.factories import TradingFactories
    from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

    module = _profiles_module()
    profile = module.ProfileBuilder().build(
        _draft(
            module,
            guru_id="historic-guru",
            symbol="AAPL",
        )
    )
    source = _message("1001").model_copy(
        update={"timestamp": dt.datetime.now(dt.UTC) - dt.timedelta(minutes=10)}
    )
    calls = []

    class Decoder:
        async def decode(self, text, route, recent=()):
            return trade(
                buy(
                    _mapped(route, "Apple"),
                    "200",
                    said="Bought",
                    ticker_said="Apple",
                    fraction=SIXTH,
                    fraction_said="1/6",
                )
            )

        async def close(self):
            calls.append("decoder_closed")

    async def open_decoder(name, configuration):
        calls.append(("decoder", name, configuration.model))
        return Decoder()

    async def unexpected_owner(*args, **kwargs):
        raise AssertionError("Historical evaluation must not open a broker owner")

    async def evaluate():
        source_store = await SQLiteSourceStore.open(tmp_path / "application.db")
        await source_store.recovery_start(123, 1)
        await source_store.capture_recovery_page(123, [source], [], 1001)
        await source_store.close()
        before = hashlib.sha256((tmp_path / "application.db").read_bytes()).hexdigest()
        runtime = TradingRuntime(
            tmp_path,
            factories=TradingFactories(owner=unexpected_owner, decoder=open_decoder),
        )
        result = await runtime.profiles.evaluate_historical_profile(
            source.identity,
            profile,
            ProviderConfiguration(name="deepseek", model="test-model"),
            SecretStr("provider-secret"),
            [RouteConnection(account_id="paper", full_position_usd="300")],
        )
        after = hashlib.sha256((tmp_path / "application.db").read_bytes()).hexdigest()
        return result, before, after, runtime

    result, before, after, runtime = asyncio.run(evaluate())

    assert result.simulated is True
    assert result.no_order is True
    assert result.message_identity == source.identity
    assert result.profile_revision == profile.profile_revision
    assert result.destinations[0].budget_usd == Decimal("50.00")  # a sixth of $300
    assert before == after
    assert calls == [("decoder", "deepseek", "test-model"), "decoder_closed"]
    assert not (tmp_path / "accounts").exists()
    assert runtime.status().state == "paused"
    assert not hasattr(result, "orders")


def test_profile_schema_rejects_arbitrary_executable_convention_fields():
    module = _profiles_module()
    with pytest.raises(ValidationError):
        module.ProfileDraft.model_validate(
            {
                "guru_id": "custom",
                "display_name": "Custom",
                "playbook": "",
                "examples": [],
                "python_code": "import os; os.system('anything')",
            }
        )
