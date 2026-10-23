"""A record is found by the Alpaca account its keys open, whatever the setup names the account."""

import fcntl
import json
import sqlite3
from contextlib import closing

from copytrading_engine.execution.adapters.sqlite_ledger import Store
from copytrading_engine.trading.adapters.account_records import (
    JOURNAL,
    RecordPlan,
    Unbound,
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


def test_only_a_folder_with_no_record_file_gives_way(tmp_path):
    """A start whose keys were refused can leave a folder with no record; it holds nothing."""
    (tmp_path / "main").mkdir()
    (tmp_path / "main" / "executor.lock").touch()
    record(tmp_path, "zhap-account-2", ZHAP, marker="lots")

    plan = reconcile_records(tmp_path, {"main": ZHAP})

    assert plan.cleared == ("main",)
    assert (tmp_path / "main" / "marker").read_text() == "lots"


def test_a_record_that_names_no_alpaca_account_moves_aside_and_is_kept(tmp_path):
    record(tmp_path, "main", None, marker="unnamed")
    record(tmp_path, "zhap-account-2", ZHAP, marker="lots")

    plan = reconcile_records(tmp_path, {"main": ZHAP})

    assert plan.cleared == ()
    assert (tmp_path / "main" / "marker").read_text() == "lots"
    assert (tmp_path / "main-earlier" / "marker").read_text() == "unnamed"


def unreadable(root, name):
    folder = root / name
    folder.mkdir()
    (folder / "execution.sqlite3").write_bytes(b"not a database, and not ours to throw away")
    return folder


def test_a_record_that_cant_be_read_is_never_moved_and_its_account_does_not_open(tmp_path):
    damaged = unreadable(tmp_path, "main")
    record(tmp_path, "zhap-account-2", ZHAP, marker="lots")

    plan = reconcile_records(tmp_path, {"main": ZHAP})

    assert record_identity(damaged) is Unbound.UNREADABLE
    assert plan.refusals == {"main": "record_unreadable"}
    assert plan.moves == {}
    assert plan.cleared == ()
    assert (damaged / "execution.sqlite3").read_bytes().startswith(b"not a database")
    assert (tmp_path / "zhap-account-2" / "marker").read_text() == "lots"


def test_an_unreadable_record_of_another_account_is_left_alone(tmp_path):
    unreadable(tmp_path, "old")
    record(tmp_path, "zhap-account-2", ZHAP, marker="lots")

    plan = reconcile_records(tmp_path, {"main": ZHAP})

    assert plan.refusals == {}
    assert (tmp_path / "main" / "marker").read_text() == "lots"
    assert (tmp_path / "old" / "execution.sqlite3").read_bytes().startswith(b"not a database")


def test_a_folder_another_copytrading_has_open_stops_every_move(tmp_path):
    held = record(tmp_path, "zhap-account-2", ZHAP, marker="lots")
    record(tmp_path, "main", PRIMARY, marker="primary")
    with (held / "executor.lock").open("a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        plan = reconcile_records(tmp_path, {"main": ZHAP})

    assert plan.refusals == {"main": "account_in_use"}
    assert plan.moves == {}
    assert held_records(tmp_path) == {"main": PRIMARY, "zhap-account-2": ZHAP}
    assert (tmp_path / "main" / "marker").read_text() == "primary"


def test_a_move_a_crash_interrupted_is_finished_from_its_journal(tmp_path):
    root = tmp_path / "accounts"
    root.mkdir()
    record(root, ".moving-zhap-account-2", ZHAP, marker="lots")
    (root / JOURNAL).write_text(json.dumps({"zhap-account-2": "main"}))

    assert held_records(root) == {}  # a staged folder is never an account
    reconcile_records(root, {"main": ZHAP})

    assert (root / "main" / "marker").read_text() == "lots"
    assert not (root / JOURNAL).exists()
    assert [child.name for child in root.iterdir()] == ["main"]


def test_a_staged_folder_without_a_journal_goes_back_under_its_name(tmp_path):
    root = tmp_path / "accounts"
    root.mkdir()
    record(root, ".moving-testing", ("paper", "alpaca-testing"), marker="kept")

    reconcile_records(root, {})

    assert (root / "testing" / "marker").read_text() == "kept"


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
