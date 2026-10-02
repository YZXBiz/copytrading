"""Notification values are frozen copies, so a presenter cannot change what was queued."""

import datetime as dt

import pytest

from copytrading_engine.shared.notification_models import (
    NotificationIntent,
    NotificationPayload,
    QueuedNotification,
)

START = dt.datetime(2026, 1, 5, 15, tzinfo=dt.UTC)


def payload(**overrides) -> NotificationPayload:
    values = {"labels": {"kind": "fill"}, "annotations": {"summary": "x"}, "starts_at": START}
    return NotificationPayload(**(values | overrides))


def test_a_payload_keeps_its_own_read_only_copy():
    source = {"summary": "x"}
    made = payload(annotations=source)
    source["summary"] = "changed"

    assert made.annotations["summary"] == "x"
    with pytest.raises(TypeError):
        made.annotations["summary"] = "again"  # ty: ignore[invalid-assignment]


@pytest.mark.parametrize(
    ("overrides", "error"),
    [
        ({"labels": ["kind"]}, TypeError),
        ({"annotations": {"summary": 1}}, TypeError),
        ({"labels": {1: "x"}}, TypeError),
        ({"starts_at": "today"}, TypeError),
        ({"starts_at": dt.datetime(2026, 1, 5)}, ValueError),
    ],
)
def test_a_malformed_payload_is_refused(overrides, error):
    with pytest.raises(error):
        payload(**overrides)


def test_queued_notifications_and_intents_need_a_key_and_a_real_payload():
    assert QueuedNotification("k", payload()).key == "k"
    assert NotificationIntent("k", "stream", payload()).stream_id == "stream"
    for build in (
        lambda: QueuedNotification("", payload()),
        lambda: NotificationIntent("", "stream", payload()),
        lambda: NotificationIntent("k", "", payload()),
    ):
        with pytest.raises(ValueError, match="empty"):
            build()
    with pytest.raises(TypeError):
        QueuedNotification("k", {"summary": "x"})  # ty: ignore[invalid-argument-type]
    with pytest.raises(TypeError):
        NotificationIntent("k", "s", None)  # ty: ignore[invalid-argument-type]
