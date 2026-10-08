"""The account feed: one readable row per outcome, the owner's own sales included."""

import datetime as dt

from copytrading_engine.execution.presentation.account_feed import account_feed

from .builders import NOW
from .test_lot_sales import confirmation, owned_lot, preview_request


def test_the_feed_shows_the_copied_buy_and_the_owners_sale_of_it(tmp_path):
    engine, _, app, lot_id, lot = owned_lot(tmp_path, sqlite=True)
    app.preview(preview_request(lot_id, lot.remaining_qty), NOW)
    sale = app.confirm(confirmation(), NOW + dt.timedelta(seconds=2))

    store = engine.ledger._repository
    page = account_feed("paper-demo", engine.ledger.snapshot(), store.feed_events(None, 50), 50)
    store.close()

    sold, bought = page.items
    assert (sold.kind, sold.source, sold.symbol, sold.order_id) == (
        "sold",
        "you",
        lot.symbol,
        sale.client_id,
    )
    assert sold.shares == lot.remaining_qty
    assert sold.price is not None
    assert sold.amount == lot.remaining_qty * sold.price
    assert sold.guru_id is None
    assert (bought.kind, bought.source, bought.order_id) == ("bought", "guru", lot_id)
    assert bought.message_id == sold.message_id, "the sale is filed under the post that bought"
    assert page.next_before_seq is None


def test_a_full_page_names_where_the_next_one_starts(tmp_path):
    engine, *_ = owned_lot(tmp_path, sqlite=True)
    store = engine.ledger._repository
    first = store.feed_events(None, 1)

    page = account_feed("paper-demo", engine.ledger.snapshot(), first, 1)

    assert [item.kind for item in page.items] == ["bought"]
    assert page.next_before_seq == first[0][0]
    assert store.feed_events(page.next_before_seq, 1) == ()
    store.close()
