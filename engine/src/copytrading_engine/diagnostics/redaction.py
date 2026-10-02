"""Recursive credential removal before diagnostic admission."""

import base64
import binascii
import html
import json
import re
from dataclasses import dataclass
from typing import Literal
from urllib.parse import quote, quote_plus, unquote_plus

from copytrading_engine.shared.payload_capture import JsonValue

_SENSITIVE_FRAGMENTS = (
    "authorization",
    "cookie",
    "credential",
    "password",
    "passwd",
    "secret",
    "token",
    "apikey",
    "privatekey",
)
_REDACTED = "[REDACTED]"
MAX_DIAGNOSTIC_PAYLOAD_BYTES = 48 * 1024
_CREDENTIAL_HEADER = re.compile(
    r"(?i)(?P<field>\b(?:authorization|proxy-authorization|x-api-key)\s*[:=]\s*)"
    r"(?:(?:bearer|basic)\s+)?(?P<value>[^\s,;\]}\"']+)"
)
_AUTH_SCHEME = re.compile(r"(?i)\b(?P<scheme>bearer|basic)\s+(?P<value>[A-Za-z0-9._~+/=-]{8,})")
_QUERY_PARAMETER = re.compile(r"(?P<prefix>[?&;]|^)(?P<key>[^?&;=\s]+)=(?P<value>[^&#;\s]*)")
_PERCENT_ESCAPE = re.compile(r"%[0-9A-Fa-f]{2}")


@dataclass(frozen=True, slots=True)
class RedactionResult:
    value: JsonValue
    redacted_fields: int


type DiagnosticPayloadStatus = Literal["complete", "oversize", "missing"]


@dataclass(frozen=True, slots=True)
class DiagnosticPayloadAdmission:
    payload: JsonValue | None
    status: DiagnosticPayloadStatus
    original_bytes: int
    redacted_fields: int


def redact_with_count(value: JsonValue, *, secrets: tuple[str, ...]) -> RedactionResult:
    """Redact recursively and report how many values or fields were removed."""
    replacements = _secret_forms(secrets)
    return _redact(value, replacements)


def admit_diagnostic_payload(
    value: JsonValue | None,
    *,
    secrets: tuple[str, ...],
    max_bytes: int = MAX_DIAGNOSTIC_PAYLOAD_BYTES,
    source_bytes: int | None = None,
) -> DiagnosticPayloadAdmission:
    """Redact first, then admit a complete payload only within the fixed byte cap."""
    if type(max_bytes) is not int or not 1 <= max_bytes <= MAX_DIAGNOSTIC_PAYLOAD_BYTES:
        raise ValueError("diagnostic payload limit is outside the supported bounds")
    if source_bytes is not None and (type(source_bytes) is not int or source_bytes < 0):
        raise ValueError("diagnostic payload byte count must be nonnegative")
    if value is None:
        return DiagnosticPayloadAdmission(None, "missing", source_bytes or 0, 0)

    safe = redact_with_count(value, secrets=secrets)
    serialized = json.dumps(safe.value, ensure_ascii=False, separators=(",", ":"))
    original_bytes = (
        source_bytes
        if source_bytes is not None
        else len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    )
    if original_bytes > max_bytes or len(serialized.encode("utf-8")) > max_bytes:
        return DiagnosticPayloadAdmission(None, "oversize", original_bytes, safe.redacted_fields)
    return DiagnosticPayloadAdmission(safe.value, "complete", original_bytes, safe.redacted_fields)


def _redact(value: JsonValue, secrets: tuple[str, ...]) -> RedactionResult:
    if isinstance(value, dict):
        result: dict[str, JsonValue] = {}
        count = 0
        for key, item in value.items():
            if _is_sensitive_key(key):
                result[key] = _REDACTED
                count += 1
            else:
                safe = _redact(item, secrets)
                result[key] = safe.value
                count += safe.redacted_fields
        return RedactionResult(result, count)
    if isinstance(value, list):
        result = []
        count = 0
        for item in value:
            safe = _redact(item, secrets)
            result.append(safe.value)
            count += safe.redacted_fields
        return RedactionResult(result, count)
    if isinstance(value, str):
        return _redact_text(value, secrets)
    return RedactionResult(value, 0)


def _redact_text(value: str, secrets: tuple[str, ...]) -> RedactionResult:
    structured = _parse_structured(value)
    if structured is not None:
        safe = _redact(structured, secrets)
        return RedactionResult(
            json.dumps(safe.value, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
            safe.redacted_fields,
        )

    result = value
    count = 0
    for secret in secrets:
        occurrences = result.count(secret)
        if occurrences:
            result = result.replace(secret, _REDACTED)
            count += occurrences

    def redact_header(match: re.Match[str]) -> str:
        nonlocal count
        count += 1
        return match.group("field") + _REDACTED

    result = _CREDENTIAL_HEADER.sub(redact_header, result)

    def redact_auth_scheme(match: re.Match[str]) -> str:
        nonlocal count
        count += 1
        return f"{match.group('scheme')} {_REDACTED}"

    result = _AUTH_SCHEME.sub(redact_auth_scheme, result)

    def redact_query(match: re.Match[str]) -> str:
        nonlocal count
        key = unquote_plus(match.group("key"))
        if not _is_sensitive_key(key) and _normalized_key(key) not in _SENSITIVE_QUERY_NAMES:
            return match.group(0)
        count += 1
        return f"{match.group('prefix')}{match.group('key')}={_REDACTED}"

    result = _QUERY_PARAMETER.sub(redact_query, result)
    return RedactionResult(result, count)


_SENSITIVE_QUERY_NAMES = frozenset(
    {"apikey", "auth", "authorization", "key", "password", "signature", "sig"}
)


def _parse_structured(value: str) -> dict[str, JsonValue] | list[JsonValue] | None:
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError, TypeError:
        parsed = None
    if isinstance(parsed, dict | list):
        return parsed

    # Some clients serialize JSON as a quoted or escaped string before logging it.
    if isinstance(parsed, str) and parsed != value:
        return _parse_structured(parsed)

    compact = value.strip()
    if len(compact) >= 32 and re.fullmatch(r"[A-Za-z0-9_-]+={0,2}", compact):
        try:
            decoded = base64.urlsafe_b64decode(compact + "=" * (-len(compact) % 4))
            parsed = json.loads(decoded)
        except binascii.Error, UnicodeDecodeError, json.JSONDecodeError, ValueError:
            return None
        if isinstance(parsed, dict | list):
            return parsed
    return None


def _secret_forms(secrets: tuple[str, ...]) -> tuple[str, ...]:
    forms: set[str] = set()
    for secret in secrets:
        if not secret:
            continue
        encoded = secret.encode("utf-8")
        forms.update(
            {
                secret,
                quote(secret, safe=""),
                quote_plus(secret),
                _lower_percent_escapes(quote(secret, safe="")),
                base64.b64encode(encoded).decode("ascii"),
                base64.urlsafe_b64encode(encoded).decode("ascii"),
                base64.b64encode(encoded).decode("ascii").rstrip("="),
                base64.urlsafe_b64encode(encoded).decode("ascii").rstrip("="),
                json.dumps(secret, ensure_ascii=True)[1:-1],
                html.escape(secret, quote=True),
                encoded.hex(),
            }
        )
    return tuple(sorted(forms, key=len, reverse=True))


def _lower_percent_escapes(value: str) -> str:
    return _PERCENT_ESCAPE.sub(lambda match: match.group(0).lower(), value)


def _normalized_key(key: str) -> str:
    return re.sub(r"[^a-z0-9]", "", key.casefold())


def _is_sensitive_key(key: str) -> bool:
    normalized = _normalized_key(key)
    return any(fragment in normalized for fragment in _SENSITIVE_FRAGMENTS)
