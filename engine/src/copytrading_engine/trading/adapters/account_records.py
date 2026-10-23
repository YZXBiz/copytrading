"""Each account's record follows the Alpaca account its keys open, not the name in the setup.

A record lives in `accounts/<name>/execution.sqlite3`, and its `identity` row names the Alpaca
account it was made with. Before the accounts open, the records are put under the names the setup
gives those Alpaca accounts now: the same keys under a new name open the same record, with its
lots, and a record a name used to hold for another Alpaca account moves aside to
`<name>-earlier` rather than block it. Nothing is deleted except a folder that never held a
record.
"""

import fcntl
import shutil
import sqlite3
from collections.abc import Mapping
from contextlib import closing
from dataclasses import dataclass, field
from pathlib import Path

# An Alpaca account as a record names it: its environment and Alpaca's account ID.
type BrokerIdentity = tuple[str, str]

RECORD = "execution.sqlite3"


@dataclass(frozen=True, slots=True)
class RecordPlan:
    """Folder renames, in an order that never overwrites, and the accounts that cannot open."""

    moves: dict[str, str] = field(default_factory=dict)
    cleared: tuple[str, ...] = ()
    refusals: dict[str, str] = field(default_factory=dict)


def record_identity(account_dir: Path) -> BrokerIdentity | None:
    """The Alpaca account a folder's record was made with; None for a folder without one."""
    database = account_dir / RECORD
    if not database.is_file():
        return None
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
        try:
            row = db.execute("SELECT environment, account_id FROM identity WHERE singleton=1")
            found = row.fetchone()
        except sqlite3.OperationalError:
            return None
    return (found[0], found[1]) if found is not None else None


def held_records(root: Path) -> dict[str, BrokerIdentity | None]:
    """Every account folder and the Alpaca account its record belongs to."""
    if not root.is_dir():
        return {}
    return {
        child.name: record_identity(child)
        for child in sorted(root.iterdir())
        if child.is_dir() and not child.is_symlink()
    }


def plan_records(
    wanted: Mapping[str, BrokerIdentity | None], held: Mapping[str, BrokerIdentity | None]
) -> RecordPlan:
    """Where each record goes so every setup name holds its own Alpaca account's record.

    `wanted` maps each setup name to the Alpaca account its keys open, or None when that could
    not be checked; such a name keeps its folder unless another account's record is in it.
    """
    known = {name: identity for name, identity in wanted.items() if identity is not None}
    sharing: dict[BrokerIdentity, list[str]] = {}
    for name, identity in known.items():
        sharing.setdefault(identity, []).append(name)
    refusals = {
        name: "alpaca_account_shared"
        for names in sharing.values()
        if len(names) > 1
        for name in names
    }
    owner = {identity: names[0] for identity, names in sharing.items() if len(names) == 1}
    moves: dict[str, str] = {}
    for folder, identity in held.items():
        if identity is None:
            continue
        target = owner.get(identity)
        if target is not None and folder != target:
            moves[folder] = target
        elif target is None and folder in known and folder not in refusals:
            # The name now belongs to another Alpaca account; its old record steps aside.
            moves[folder] = ""
    taken = set(held) | set(wanted)
    for folder in sorted(name for name, target in moves.items() if not target):
        parked = f"{folder}-earlier"
        suffix = 2
        while parked in taken:
            parked = f"{folder}-earlier-{suffix}"
            suffix += 1
        taken.add(parked)
        moves[folder] = parked
    # A folder that never held a record may sit where a record must go; it holds nothing.
    arriving = set(moves.values())
    cleared = tuple(
        sorted(
            folder
            for folder, identity in held.items()
            if identity is None and folder in arriving and folder not in moves
        )
    )
    return RecordPlan(moves=moves, cleared=cleared, refusals=refusals)


def apply_record_plan(root: Path, plan: RecordPlan) -> None:
    """Rename through temporary names first, so two records can trade places."""
    for folder in plan.cleared:
        shutil.rmtree(root / folder)
    staged = {folder: root / f".moving-{folder}" for folder in plan.moves}
    for folder, temporary in staged.items():
        (root / folder).rename(temporary)
    for folder, temporary in staged.items():
        temporary.rename(root / plan.moves[folder])


def reconcile_records(root: Path, wanted: Mapping[str, BrokerIdentity | None]) -> RecordPlan:
    """Put each record under the name the setup gives its Alpaca account now."""
    plan = plan_records(wanted, held_records(root))
    apply_record_plan(root, plan)
    return plan


def delete_record(root: Path, name: str) -> str | None:
    """Delete the record of an account the setup no longer has, when its owner asks; the shares
    stay at Alpaca. Returns why it can't: another CopyTrading has it open, or there is none."""
    folder = root / name
    if (
        not name
        or name.startswith(".")
        or "/" in name
        or folder.is_symlink()
        or not folder.is_dir()
    ):
        return "not_found"
    with (folder / "executor.lock").open("w") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return "account_in_use"
        shutil.rmtree(folder)
    return None
