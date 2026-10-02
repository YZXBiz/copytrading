"""Extraction keeps only instructions grounded in the source text."""

from decimal import Decimal

import pytest
from pydantic import ValidationError
from pydantic_ai.models.test import TestModel
from pydantic_ai.profiles import ModelProfile

from copytrading_engine.parsing.application import transform
from copytrading_engine.parsing.extraction import DecodedMessage, DecodeError, validate_grounding
from copytrading_engine.parsing.providers.anthropic import build_decoder as build_anthropic_decoder
from copytrading_engine.parsing.routes import Route
from copytrading_engine.shared.model_providers import ProviderConfig

from .builders import TEXT, decoded, raw
from .fakes import FakeDecoder


async def test_typed_extraction_passes_grounded_signal():
    result = await transform(
        raw(),
        Route(),
        FakeDecoder(
            decoded(fraction="0.1666666666666666666666666667", fraction_evidence="6分之一")
        ),
        "test",
    )
    assert result.decision == "trade"
    assert result.instructions[0].price == Decimal("25")
    assert result.instructions[0].fraction == Decimal("0.1666666666666666666666666667")
    assert result.evidence[0].price_evidence == "25"


async def test_omitted_buy_fraction_remains_missing():
    result = await transform(
        raw("25加了常规仓abc"), Route(), FakeDecoder(decoded(fraction=None)), "test"
    )
    assert result.instructions[0].fraction is None
    assert result.model_validate_json(result.model_dump_json()).instructions[0].fraction is None


@pytest.mark.parametrize(
    ("source", "changes"),
    [
        ("25加了6分之一常规仓abc", {}),
        ("25加了1/6常规仓abc", {}),
        ("25加了25%常规仓abc", {}),
        ("25加了half仓abc", {}),
        ("25加了full仓abc", {}),
        (
            "Bought ABC at 25, half position",
            {"action_evidence": "Bought", "symbol_evidence": "ABC"},
        ),
        (
            "Bought ABC at 25, full position",
            {"action_evidence": "Bought", "symbol_evidence": "ABC"},
        ),
    ],
)
async def test_model_cannot_omit_an_explicit_source_fraction(source, changes):
    with pytest.raises(DecodeError, match="evidence_validation_failed"):
        await transform(
            raw(source), Route(), FakeDecoder(decoded(fraction=None, **changes)), "test"
        )


@pytest.mark.parametrize(
    ("evidence", "value"),
    [("1/6", "0.1666666666666666666666666667"), ("1/3", "0.3333333333333333333333333333")],
)
async def test_ascii_ratio_is_grounded_and_preserved(evidence, value):
    result = await transform(
        raw(f"25加了{evidence}常规仓abc"),
        Route(),
        FakeDecoder(decoded(fraction=value, fraction_evidence=evidence)),
        "test",
    )
    assert result.instructions[0].fraction == Decimal(value)


@pytest.mark.parametrize(("evidence", "value"), [("half", "0.5"), ("full", "1")])
async def test_english_allocation_next_to_chinese_is_grounded(evidence, value):
    result = await transform(
        raw(f"25加了{evidence}仓abc"),
        Route(),
        FakeDecoder(decoded(fraction=value, fraction_evidence=evidence)),
        "test",
    )
    assert result.instructions[0].fraction == Decimal(value)


@pytest.mark.parametrize(
    ("word", "evidence", "value"), [("halfway", "half", "0.5"), ("fullest", "full", "1")]
)
async def test_allocation_words_must_not_match_ascii_substrings(word, evidence, value):
    source = raw(f"25加了{word}仓abc")
    without_allocation = await transform(
        source, Route(), FakeDecoder(decoded(fraction=None)), "test"
    )
    assert without_allocation.instructions[0].fraction is None
    with pytest.raises(DecodeError, match="evidence_validation_failed"):
        await transform(
            source,
            Route(),
            FakeDecoder(decoded(fraction=value, fraction_evidence=evidence)),
            "test",
        )


@pytest.mark.parametrize(
    ("source", "evidence", "value"),
    [
        ("25加了11/6仓abc", "1/6", "0.1666666666666666666666666667"),
        ("25加了125%仓abc", "25%", "0.25"),
        ("25加了11分之一仓abc", "1分之一", "1"),
    ],
)
async def test_numeric_fraction_evidence_requires_complete_token(source, evidence, value):
    with pytest.raises(DecodeError, match="evidence_validation_failed"):
        await transform(
            raw(source),
            Route(),
            FakeDecoder(decoded(fraction=value, fraction_evidence=evidence)),
            "test",
        )


async def test_ungrounded_buy_fraction_is_reviewed():
    with pytest.raises(DecodeError, match="evidence_validation_failed"):
        await transform(
            raw(),
            Route(),
            FakeDecoder(decoded(fraction="0.5", fraction_evidence="6分之一")),
            "test",
        )


@pytest.mark.parametrize(
    "changes",
    [
        {"price": "250"},
        {"symbol": "DEF"},
        {"action_evidence": "buy"},
        {"price_evidence": "5", "price": "5"},
    ],
)
async def test_ungrounded_output_is_reviewed(changes):
    with pytest.raises(DecodeError) as failure:
        await transform(raw(), Route(), FakeDecoder(decoded(**changes)), "test")
    assert failure.value.reason == "evidence_validation_failed"
    assert failure.value.issues[0].path.startswith("instructions.0.")


@pytest.mark.parametrize("text", ["如果" + TEXT, "昨天" + TEXT, "计划" + TEXT])
def test_conditional_and_recap_veto(text):
    with pytest.raises(ValueError, match="Conditional or historical language requires review"):
        validate_grounding(decoded(), text, Route())


async def test_prefix_failure_never_calls_model():
    decoder = FakeDecoder(decoded())
    result = await transform(raw(), Route(prefix="Different:"), decoder, "test")
    assert result.decision == "ignore"
    assert decoder.calls == 0


def test_missing_exit_reference_and_invalid_decision_rejected():
    with pytest.raises(ValidationError):
        decoded(action="close")
    with pytest.raises(ValidationError):
        DecodedMessage(decision="trade", reason="bad", instructions=[])


def test_trim_and_remaining_exit_are_distinct():
    trim = decoded(
        action="reduce",
        price="27",
        entry_price="25",
        fraction="0.5",
        action_evidence="出一半",
        price_evidence="27",
        entry_evidence="25",
        fraction_evidence="一半",
    )
    validate_grounding(trim, "27出一半25的abc", Route())
    close = decoded(
        action="close",
        price="28",
        entry_price="25",
        fraction="1",
        action_evidence="出掉",
        price_evidence="28",
        entry_evidence="25",
    )
    validate_grounding(close, "28出掉25剩下一半abc", Route())


def test_company_name_resolves_only_when_the_playbook_states_its_ticker():
    result = decoded(symbol="AAPL", symbol_evidence="苹果")
    with pytest.raises(ValueError, match="playbook"):
        validate_grounding(result, "25加了苹果", Route())
    with pytest.raises(ValueError, match="playbook"):
        validate_grounding(result, "25加了苹果", Route(playbook="苹果 is a fruit\nAAPL is Apple"))
    with pytest.raises(ValueError, match="playbook"):
        validate_grounding(result, "25加了苹果", Route(playbook="苹果 means AAPLX"))
    validate_grounding(result, "25加了苹果", Route(playbook="加 means buy\n苹果 means AAPL"))


def test_literal_ticker_needs_no_playbook_and_must_be_a_whole_token():
    validate_grounding(decoded(symbol="ABC", symbol_evidence="abc"), "25加了abc", Route())
    with pytest.raises(ValueError, match="Symbol evidence must be a complete ticker"):
        validate_grounding(decoded(symbol="AB", symbol_evidence="ab"), "25加了abc", Route())


async def test_real_pydantic_ai_adapter_with_test_model():
    from anthropic import AsyncAnthropic

    decoder = build_anthropic_decoder(
        ProviderConfig(api_key="test-only", model="claude-haiku-4-5-20251001", timeout=20),
        AsyncAnthropic(api_key="test-only", max_retries=0),
    )
    try:
        with decoder.agent.override(
            model=TestModel(
                custom_output_text=decoded().model_dump_json(),
                profile=ModelProfile(supports_json_schema_output=True),
            )
        ):
            result = await decoder.decode(TEXT, Route())
        assert result.instructions[0].symbol == "ABC"
    finally:
        await decoder.close()


async def test_prefix_and_message_use_the_same_unicode_normalization():
    result = await transform(
        raw("Example：" + TEXT),  # noqa: RUF001 - the fullwidth colon is the input under test
        Route(prefix="Example："),  # noqa: RUF001 - the fullwidth colon is the input under test
        FakeDecoder(
            decoded(fraction="0.1666666666666666666666666667", fraction_evidence="6分之一")
        ),
        "test",
    )
    assert result.decision == "trade"


async def test_one_price_cannot_fill_both_exit_roles():
    proposed = decoded(
        action="reduce",
        price="25",
        entry_price="25",
        fraction="0.5",
        action_evidence="出一半",
        price_evidence="25",
        entry_evidence="25",
        fraction_evidence="一半",
    )
    with pytest.raises(DecodeError) as failure:
        await transform(raw("出一半25的abc"), Route(), FakeDecoder(proposed), "test")
    assert failure.value.issues[0].code == "price_occurrence_reused"
    accepted = await transform(raw("25出一半25的abc"), Route(), FakeDecoder(proposed), "test")
    assert accepted.decision == "trade"


async def test_buyback_uses_current_price_and_does_not_emit_prior_sale():
    result = await transform(
        raw("25加回29卖出的abc"),
        Route(),
        FakeDecoder(decoded(action_evidence="加回")),
        "test",
    )
    assert result.decision == "trade"
    assert len(result.instructions) == 1
    instruction = result.instructions[0]
    assert instruction.action == "buy"
    assert instruction.price == Decimal("25")
    assert instruction.entry_price is None


def test_a_model_rounded_sixth_is_the_stated_sixth():
    result = decoded(fraction="0.16666666666666666", fraction_evidence="6分之一")
    validate_grounding(result, TEXT, Route())
    with pytest.raises(ValueError, match="Buy fraction is not explicitly supported"):
        validate_grounding(decoded(fraction="0.1667", fraction_evidence="6分之一"), TEXT, Route())


def test_selling_the_remaining_half_is_a_close():
    text = "245出剩下一半236的abc"
    result = decoded(
        action="close",
        price="245",
        price_evidence="245",
        entry_price="236",
        entry_evidence="236",
        fraction="1",
        fraction_evidence="一半",
        action_evidence="出剩下一半",
    )
    validate_grounding(result, text, Route())


def test_fraction_evidence_may_include_the_words_around_the_fraction():
    result = decoded(fraction="0.16666666666666666", fraction_evidence="6分之一常规仓")
    validate_grounding(result, TEXT, Route())
    with pytest.raises(ValueError, match="Buy fraction is not explicitly supported"):
        validate_grounding(
            decoded(fraction="0.5", fraction_evidence="6分之一常规仓"), TEXT, Route()
        )
