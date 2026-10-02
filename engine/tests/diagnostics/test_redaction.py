"""Redaction removes credentials in every form while keeping payloads useful and bounded."""

import base64
import json
from urllib.parse import quote, quote_plus

import pytest

from copytrading_engine.diagnostics.redaction import JsonValue, redact_with_count


def test_payload_remains_useful_without_credentials():
    secret = "probe-key-0123456789"
    payload: JsonValue = {
        "message": "Bought AAPL 1/6",
        "response": "buy",
        "headers": {"Authorization": "Bearer " + secret},
        "error": "request failed using " + secret,
    }

    safe = redact_with_count(payload, secrets=(secret,)).value
    encoded = json.dumps(safe)

    assert "Bought AAPL 1/6" in encoded
    assert "buy" in encoded
    assert secret not in encoded
    assert "Bearer " + secret not in encoded


def test_redact_recurses_through_lists_and_sensitive_field_names():
    payload: JsonValue = {
        "steps": [
            {"api_key": "top-secret", "result": {"Cookie": "session=abc"}},
            {"nested": [{"clientSecret": "hidden"}]},
        ]
    }

    assert redact_with_count(payload, secrets=()).value == {
        "steps": [
            {"api_key": "[REDACTED]", "result": {"Cookie": "[REDACTED]"}},
            {"nested": [{"clientSecret": "[REDACTED]"}]},
        ]
    }


def test_redact_removes_encoded_credentials_and_header_or_query_values():
    secret = "mý-secret-credential-0123456789/a+"
    encoded_values = (
        secret,
        quote(secret, safe=""),
        quote_plus(secret),
        base64.b64encode(secret.encode()).decode(),
        base64.urlsafe_b64encode(secret.encode()).decode(),
        json.dumps(secret, ensure_ascii=True)[1:-1],
    )
    payload: JsonValue = {
        "nested": [{"AuthORIZATION": "Bearer unconfigured-header-value-987654321"}],
        "serialized": json.dumps({"items": [{"apiKey": secret}]}),
        "text": " ".join(encoded_values),
        "url": "https://provider.invalid/run?safe=visible&access_token=unconfigured-query-value-123456789",
        "header": "Proxy-Authorization: Basic unconfigured-basic-value-123456789",
    }

    safe = redact_with_count(payload, secrets=(secret,)).value
    encoded = json.dumps(safe, ensure_ascii=True)
    expected_secrets = (
        *encoded_values,
        "unconfigured-header-value-987654321",
        "unconfigured-query-value-123456789",
        "unconfigured-basic-value-123456789",
    )
    leaked_markers = [
        f"credential-{index}" for index, value in enumerate(expected_secrets) if value in encoded
    ]
    assert not leaked_markers, "redaction left credential markers in the diagnostic value"
    assert "safe=visible" in encoded


def test_redactor_reports_omissions_without_retaining_the_removed_value():
    from copytrading_engine.diagnostics import redaction

    result = redaction.redact_with_count(
        {"nested": [{"refresh_token": "controlled-private-marker"}]}, secrets=()
    )

    assert result.redacted_fields == 1
    assert result.value == {"nested": [{"refresh_token": "[REDACTED]"}]}
    assert "controlled-private-marker" not in json.dumps(result.value)


def test_diagnostic_payload_admission_is_bounded_and_never_calls_an_oversize_value_complete():
    from copytrading_engine.diagnostics import redaction

    admit = getattr(redaction, "admit_diagnostic_payload", None)
    assert callable(admit), "redaction must expose bounded payload admission"
    value: JsonValue = {"message": "x" * 128}
    admitted = admit(value, secrets=(), max_bytes=64)
    assert admitted.status == "oversize"
    assert admitted.payload is None
    assert admitted.original_bytes > 64

    complete = admit({"message": "safe"}, secrets=(), max_bytes=64)
    assert complete.status == "complete"
    assert complete.payload == {"message": "safe"}

    with pytest.raises(ValueError, match="diagnostic payload limit"):
        admit({"message": "safe"}, secrets=(), max_bytes=0)
