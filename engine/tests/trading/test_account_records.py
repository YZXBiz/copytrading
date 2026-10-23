"""A record is found by the Alpaca account its keys open, whatever the setup names the account."""

import fcntl
import sqlite3
from contextlib import closing

from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.trading.adapters.account_records import (
    RecordPlan,
    delete_record,
    held_records,
    plan_records,
    reconcile_records,
    record_identity,
)

ZHAP = ("paper", "alpaca-zhap")
PRIMARY = ("paper", "alpaca-primary")


def record(root, name, identity, marker=""):
    """A record folder as an earlier run leaves it: the database with its identity row."""
    folder = root / name
    store = Store(folder / "execution.sqlite3")
    store.close()
    if identity is not None:
        with closing(sqlite3.connect(folder / "execution.sqlite3")) as db:
            db.execute(
                "INSERT INTO identity(singleton, environment, account_id) VALUES (1, ?, ?)",
                identity,
            )
            db.commit()
    if marker:
        (folder / "marker").write_text(marker)
    return folder


def test_the_same_keys_under_a_new_name_open_the_same_record(tmp_path):
    record(tmp_path, "zhap-account-2", ZHAP, marker="today's lots")

    plan = reconcile_records(tmp_path, {"main": ZHAP})

    assert plan.moves == {"zhap-account-2": "main"}
    assert (tmp_path / "main" / "marker").read_text() == "today's lots"
    assert record_identity(tmp_path / "main") == ZHAP
    assert not (tmp_path / "zhap-account-2").exists()


def test_a_name_another_alpaca_account_used_moves_its_record_aside(tmp_path):
    """The owner's case: zhap's keys named "primary", where primary's own record lives."""
    record(tmp_path, "primary", PRIMARY, marker="GFS, WMT, NVDA")
    record(tmp_path, "zhap-account-2", ZHAP, marker="SOXL, SOXS")

    reconcile_records(tmp_path, {"primary": ZHAP})

    assert (tmp_path / "primary" / "marker").read_text() == "SOXL, SOXS"
    assert (tmp_path / "primary-earlier" / "marker").read_text() == "GFS, WMT, NVDA"
    assert held_records(tmp_path) == {"primary": ZHAP, "primary-earlier": PRIMARY}


def test_two_records_can_trade_names(tmp_path):
    record(tmp_path, "a", ZHAP, marker="zhap")
    record(tmp_path, "b", PRIMARY, marker="primary")

    reconcile_records(tmp_path, {"a": PRIMARY, "b": ZHAP})

    assert (tmp_path / "a" / "marker").read_text() == "primary"
    assert (tmp_path / "b" / "marker").read_text() == "zhap"


def test_two_names_for_one_alpaca_account_are_refused_and_nothing_moves(tmp_path):
    record(tmp_path, "zhap-account-2", ZHAP)

    plan = reconcile_records(tmp_path, {"main": ZHAP, "spare": ZHAP})

    assert plan.refusals == {"main": "alpaca_account_shared", "spare": "alpaca_account_shared"}
    assert plan.moves == {}
    assert held_records(tmp_path) == {"zhap-account-2": ZHAP}


def test_keys_that_could_not_be_checked_leave_their_folder_alone(tmp_path):
    record(tmp_path, "main", PRIMARY, marker="kept")

    plan = reconcile_records(tmp_path, {"main": None})

    assert plan == RecordPlan()
    assert (tmp_path / "main" / "marker").read_text() == "kept"


def test_a_folder_that_never_held_a_record_gives_way(tmp_path):
    """A start whose keys were refused leaves an empty folder under the name; it holds nothing."""
    record(tmp_path, "main", None)
    record(tmp_path, "zhap-account-2", ZHAP, marker="lots")

    plan = reconcile_records(tmp_path, {"main": ZHAP})

    assert plan.cleared == ("main",)
    assert (tmp_path / "main" / "marker").read_text() == "lots"


def test_records_of_accounts_no_longer_in_the_setup_stay_where_they_are(tmp_path):
    record(tmp_path, "testing", ("paper", "alpaca-testing"))
    record(tmp_path, "zhap-account-2", ZHAP)

    plan = reconcile_records(tmp_path, {"zhap-account-2": ZHAP})

    assert plan == RecordPlan()
    assert set(held_records(tmp_path)) == {"testing", "zhap-account-2"}


def test_a_parked_name_never_takes_one_already_used():
    plan = plan_records(
        {"primary": ZHAP},
        {
            "primary": PRIMARY,
            "primary-earlier": ("paper", "alpaca-older"),
            "zhap-account-2": ZHAP,
        },
    )

    assert plan.moves == {"primary": "primary-earlier-2", "zhap-account-2": "primary"}


def test_the_owner_deletes_a_record_the_setup_no_longer_has(tmp_path):
    record(tmp_path, "testing", ("paper", "alpaca-testing"))

    assert delete_record(tmp_path, "testing") is None
    assert not (tmp_path / "testing").exists()
    assert delete_record(tmp_path, "testing") == "not_found"
    assert delete_record(tmp_path, "../elsewhere") == "not_found"


def test_a_record_another_copytrading_has_open_is_never_deleted(tmp_path):
    folder = record(tmp_path, "testing", ("paper", "alpaca-testing"))
    with (folder / "executor.lock").open("w") as held:
        fcntl.flock(held.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        assert delete_record(tmp_path, "testing") == "account_in_use"

    assert record_identity(folder) == ("paper", "alpaca-testing")


def test_a_paper_and_a_live_account_with_one_id_are_different_accounts():
    plan = plan_records(
        {"paper": ("paper", "same"), "live": ("live", "same")},
        {"paper": ("paper", "same"), "live": ("live", "same")},
    )

    assert plan == RecordPlan()
