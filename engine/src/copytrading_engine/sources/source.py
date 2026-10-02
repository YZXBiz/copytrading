"""Translate Discord objects without involving persistence or publication."""

import discord
from pydantic import JsonValue, ValidationError

from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.sources.application import AttachmentReference
from copytrading_engine.sources.evidence import MAX_ATTACHMENTS_PER_MESSAGE


class InvalidSourceMessage(ValueError):
    def __init__(self, event: dict[str, JsonValue], reason: str) -> None:
        super().__init__(reason)
        self.event = event
        self.reason = reason


def envelope(message: discord.Message) -> RawMessage:
    parts = [message.content or ""]
    for embed in message.embeds:
        parts.extend([embed.title or "", embed.description or ""])
        for field in embed.fields:
            parts.extend([field.name or "", field.value or ""])
    event: dict[str, JsonValue] = {
        "schema_version": 1,
        "event_type": "raw_message",
        "source": "discord",
        "channel_id": str(message.channel.id),
        "author_id": str(message.author.id),
        "id": str(message.id),
        "timestamp": message.created_at.isoformat(),
        "text": "\n".join(part for part in parts if part),
        "image_count": len(message.attachments),
    }
    try:
        return RawMessage.model_validate(event)
    except ValidationError:
        reason = "text_too_long" if len(str(event["text"])) > 10_000 else "invalid_raw_message"
        raise InvalidSourceMessage(event, reason) from None


def attachment_references(message: discord.Message) -> tuple[AttachmentReference, ...]:
    """Return bounded source-adapter attachment references; callers never persist URLs."""
    result = []
    for attachment in message.attachments:
        size = getattr(attachment, "size", 0)
        result.append(
            AttachmentReference(
                attachment_id=str(getattr(attachment, "id", "")),
                filename=str(getattr(attachment, "filename", "")),
                content_type=(
                    str(attachment.content_type)
                    if getattr(attachment, "content_type", None) is not None
                    else None
                ),
                declared_size=size if type(size) is int else -1,
                url=str(getattr(attachment, "url", "")),
            )
        )
    return tuple(result)


def adapter_event(message: discord.Message) -> dict[str, JsonValue]:
    """Capture the received Discord text/embed/attachment metadata before normalization."""
    references = attachment_references(message)
    embeds: list[JsonValue] = []
    for embed in message.embeds:
        fields: list[JsonValue] = [
            {
                "name": str(field.name or ""),
                "value": str(field.value or ""),
                "inline": bool(getattr(field, "inline", False)),
            }
            for field in embed.fields
        ]
        embeds.append(
            {
                "title": str(embed.title) if embed.title is not None else None,
                "description": str(embed.description) if embed.description is not None else None,
                "fields": fields,
            }
        )
    attachments: list[JsonValue] = [
        {
            "attachment_id": reference.attachment_id,
            "filename": reference.filename,
            "content_type": reference.content_type,
            "declared_size": reference.declared_size,
        }
        for reference in references[:MAX_ATTACHMENTS_PER_MESSAGE]
    ]
    return {
        "event_type": "discord_message",
        "message_id": str(message.id),
        "channel_id": str(message.channel.id),
        "author_id": str(message.author.id),
        "timestamp": message.created_at.isoformat(),
        "content": str(message.content or ""),
        "embeds": embeds,
        "attachments": attachments,
        "attachments_omitted": max(0, len(references) - MAX_ATTACHMENTS_PER_MESSAGE),
    }


def require_history_channel(channel: object) -> discord.abc.Messageable:
    if not isinstance(channel, discord.abc.Messageable):
        raise ValueError("Configured source channel does not support message history")
    return channel
