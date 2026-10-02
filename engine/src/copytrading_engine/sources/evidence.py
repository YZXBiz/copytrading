"""Pure bounds and normalization for source-owned ingress evidence."""

import json
import re
from collections.abc import Sequence

from pydantic import JsonValue

from copytrading_engine.shared.payload_capture import CaptureStatus
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.application import AttachmentReference

MAX_SOURCE_EVENT_BYTES = 64 * 1024
MAX_ATTACHMENTS_PER_MESSAGE = 10
OMITTED_ATTACHMENT_ID = "__additional_attachments_omitted__"
_ATTACHMENT_ID = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
_EVIDENCE_ID = re.compile(r"^[0-9a-f]{32}$")


def normalized_source_event(event: RawMessage) -> dict[str, JsonValue]:
    return {
        "event_type": "raw_message",
        "content": event.text,
        "embeds": [],
        "attachments": [],
        "attachments_omitted": 0,
    }


def bounded_source_event(payload: JsonValue) -> tuple[str | None, CaptureStatus, int]:
    serialized = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    size = len(serialized.encode("utf-8"))
    if size <= MAX_SOURCE_EVENT_BYTES:
        return serialized, "complete", size
    return None, "oversize", size


def is_evidence_id(value: str) -> bool:
    return bool(_EVIDENCE_ID.fullmatch(value))


def bounded_attachments(
    attachments: Sequence[AttachmentReference],
) -> tuple[tuple[AttachmentReference, ...], int]:
    selected = []
    used_ids: set[str] = set()
    for index, item in enumerate(attachments[:MAX_ATTACHMENTS_PER_MESSAGE]):
        candidate = item.attachment_id
        if not _ATTACHMENT_ID.fullmatch(candidate) or candidate == OMITTED_ATTACHMENT_ID:
            candidate = f"attachment-{index + 1}"
        base = candidate[:128]
        identifier = base
        suffix = 1
        while identifier in used_ids:
            ending = f"-{suffix}"
            identifier = base[: 128 - len(ending)] + ending
            suffix += 1
        used_ids.add(identifier)
        filename = "".join(character for character in item.filename if ord(character) >= 32)[:255]
        content_type = item.content_type[:255] if item.content_type is not None else None
        selected.append(
            AttachmentReference(
                attachment_id=identifier,
                filename=filename,
                content_type=content_type,
                declared_size=item.declared_size,
                url=item.url,
            )
        )
    return tuple(selected), max(0, len(attachments) - len(selected))
