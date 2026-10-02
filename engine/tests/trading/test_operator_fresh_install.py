"""A fresh install has an application database before any source has been captured."""

import sqlite3
from contextlib import closing

from copytrading_engine.trading.adapters.operator_queries import SQLiteOperatorEvidence
from copytrading_engine.trading.application.account_access import AccountAccess
from copytrading_engine.trading.application.operator_service import OperatorQueryService


def _service(data_dir) -> OperatorQueryService:
    return OperatorQueryService(
        AccountAccess(
            data_dir,
            lambda: {},
            configuration=lambda: None,
            runtime_state=lambda: "paused",
            evidence=SQLiteOperatorEvidence(),
        )
    )


async def test_source_activity_is_empty_before_the_first_capture(tmp_path):
    # The self-test store creates application.db before the source store creates its tables.
    with closing(sqlite3.connect(tmp_path / "application.db")) as db:
        db.execute("CREATE TABLE self_test_placeholder (id INTEGER PRIMARY KEY)")
        db.commit()

    page = await _service(tmp_path).source_activity(None, 25)

    assert page.items == ()
    assert page.rejected_items == ()
    assert page.next_before_seq is None
