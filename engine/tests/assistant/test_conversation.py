"""A turn's events read in order; conversations stay bounded and forget on demand."""

import pytest

from copytrading_engine.assistant.conversation import (
    AssistantLink,
    ConversationBook,
    Turn,
)


def test_events_after_a_sequence_are_only_the_new_ones():
    turn = Turn("t-1")
    turn.add_step("Looked at your accounts")
    turn.add_text("You hold ")
    turn.add_text("4 NVDA.")
    turn.finish()
    assert [e.kind for e in turn.events(0)] == ["step", "text", "text", "done"]
    assert [e.text for e in turn.events(2)] == ["4 NVDA.", None]
    assert turn.done


def test_a_failed_turn_says_why_and_is_done():
    turn = Turn("t-1")
    turn.add_text("Partial")
    turn.fail("model_timeout", "Your model didn't answer in time.")
    kinds = [(e.kind, e.code) for e in turn.events(0)]
    assert kinds == [("text", None), ("error", "model_timeout"), ("done", None)]


def test_links_are_deduplicated_and_capped_at_three():
    turn = Turn("t-1")
    for index in range(5):
        turn.add_link(AssistantLink(kind="account", id=f"a{index % 4}", title=f"a{index}"))
    assert [e.link.id for e in turn.events(0) if e.link] == ["a0", "a1", "a2"]


def test_the_book_keeps_four_conversations_and_drops_the_oldest():
    book = ConversationBook()
    for index in range(5):
        book.get_or_open(f"c-{index}")
    with pytest.raises(KeyError):
        book.existing("c-0")
    assert book.existing("c-4").conversation_id == "c-4"


def test_forgetting_cancels_running_turns():
    book = ConversationBook()
    conversation = book.get_or_open("c-1")
    turn = Turn("t-1")
    conversation.running = turn
    book.register(turn, conversation)
    book.forget_all()
    assert turn.cancelled
    with pytest.raises(KeyError):
        book.turn("t-1")


def test_history_keeps_the_last_twenty_turns():
    book = ConversationBook()
    conversation = book.get_or_open("c-1")
    for index in range(25):
        conversation.remember([f"request-{index}", f"response-{index}"])
    assert len(conversation.turns) == 20
    assert conversation.history[0] == "request-5"


def test_evicting_a_conversation_removes_its_turn_ids():
    book = ConversationBook()
    conversation = book.get_or_open("c-1")
    turn = Turn("t-1")
    book.register(turn, conversation)
    # Evict c-1 by opening 4 more conversations
    for index in range(4):
        book.get_or_open(f"c-{index + 2}")
    with pytest.raises(KeyError):
        book.turn("t-1")


def test_registering_more_than_max_turns_drops_oldest_ids():
    book = ConversationBook()
    conversation = book.get_or_open("c-1")
    for index in range(23):
        turn = Turn(f"t-{index}")
        book.register(turn, conversation)
    # Only the last 20 turns should be accessible
    with pytest.raises(KeyError):
        book.turn("t-0")
    with pytest.raises(KeyError):
        book.turn("t-1")
    with pytest.raises(KeyError):
        book.turn("t-2")
    # These should be accessible
    assert book.turn("t-3").turn_id == "t-3"
    assert book.turn("t-22").turn_id == "t-22"


def test_cancel_finishes_the_turn():
    turn = Turn("t-1")
    turn.add_text("partial")
    turn.cancel()
    assert turn.done
    assert turn.cancelled
    assert [e.kind for e in turn.events(0)] == ["text", "done"]


def test_add_text_after_cancel_appends_nothing():
    turn = Turn("t-1")
    turn.add_text("first")
    turn.cancel()
    turn.add_text("should not appear")
    assert [e.text for e in turn.events(0)] == ["first", None]


def test_second_finish_after_done_appends_nothing():
    turn = Turn("t-1")
    turn.add_text("text")
    turn.finish()
    turn.finish()
    turn.fail("code", "message")
    events = turn.events(0)
    assert [e.kind for e in events] == ["text", "done"]


def test_text_after_a_tool_call_starts_a_new_paragraph():
    turn = Turn("t-1")
    turn.add_text("Let me look.")
    turn.add_step("Looked at your accounts")
    turn.add_text("You hold ")
    turn.add_text("4 NVDA.")
    assert "".join(e.text for e in turn.events(0) if e.kind == "text") == (
        "Let me look.\n\nYou hold 4 NVDA."
    )


def test_an_answer_that_starts_after_a_tool_call_needs_no_break():
    turn = Turn("t-1")
    turn.add_step("Looked at your accounts")
    turn.add_text("You hold 4 NVDA.")
    assert [e.text for e in turn.events(0) if e.kind == "text"] == ["You hold 4 NVDA."]
