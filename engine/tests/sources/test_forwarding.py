"""Delivery ordering and recovery without Discord, Kafka, or PostgreSQL."""

import asyncio

import pytest

from copytrading_engine.sources.application import Delivery, ForwardBatch

ROWS = [
    Delivery("discord:demo:1", '{"text":"first"}', "historical"),
    Delivery("discord:demo:2", '{"text":"second"}', "live"),
]


class Outbox:
    def __init__(self):
        self.rows = list(ROWS)
        self.fail_confirmation = False

    async def claim_batch(self):
        return list(self.rows)

    async def confirm(self, key):
        if self.fail_confirmation:
            raise OSError("confirmation failed")
        self.rows = [row for row in self.rows if row.key != key]


class Publisher:
    def __init__(self):
        self.deliveries = []
        self.failure = None
        self.fail_after_accept = False

    async def publish(self, delivery):
        if not self.failure or self.fail_after_accept:
            self.deliveries.append(delivery)
        if self.failure:
            raise self.failure


async def test_acknowledged_batch_preserves_source_order_and_payload():
    box, publisher = Outbox(), Publisher()
    batch = ForwardBatch(box, publisher)
    assert await batch.flush() == 2
    assert publisher.deliveries == ROWS
    assert await batch.flush() == 0


@pytest.mark.parametrize("error", [OSError, TimeoutError, asyncio.CancelledError])
@pytest.mark.parametrize("after_accept", [False, True])
async def test_interrupted_publish_does_not_confirm_or_overtake(error, after_accept):
    box, publisher = Outbox(), Publisher()
    publisher.failure = error()
    publisher.fail_after_accept = after_accept
    with pytest.raises(error):
        await ForwardBatch(box, publisher).flush()
    assert box.rows == ROWS
    assert publisher.deliveries == (ROWS[:1] if after_accept else [])

    publisher.failure = None
    assert await ForwardBatch(box, publisher).flush() == 2
    assert publisher.deliveries == (ROWS[:1] if after_accept else []) + ROWS
    assert not box.rows


async def test_lost_confirmation_replays_same_identity_before_later_message():
    box, publisher = Outbox(), Publisher()
    box.fail_confirmation = True
    with pytest.raises(OSError, match="confirmation"):
        await ForwardBatch(box, publisher).flush()
    assert publisher.deliveries == ROWS[:1]
    assert box.rows == ROWS
    box.fail_confirmation = False
    assert await ForwardBatch(box, publisher).flush() == 2
    assert publisher.deliveries == ROWS[:1] + ROWS


class _Scope:
    def __init__(self) -> None:
        self.entered = 0

    def __call__(self):
        scope = self

        class Entered:
            def __enter__(self) -> None:
                scope.entered += 1

            def __exit__(self, *exc) -> None:
                return None

        return Entered()


async def test_only_a_batch_with_messages_is_observed():
    box, publisher, scope = Outbox(), Publisher(), _Scope()
    batch = ForwardBatch(box, publisher, observe=scope)
    assert await batch.flush() == 2
    assert scope.entered == 1
    assert await batch.flush() == 0
    assert await batch.flush() == 0
    assert scope.entered == 1
