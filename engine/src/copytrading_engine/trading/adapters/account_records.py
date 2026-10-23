"""Each account's record follows the Alpaca account its keys open, not the name in the setup.

A record lives in `accounts/<name>/execution.sqlite3`, and its `identity` row names the Alpaca
account it was made with. Before the accounts open, the records are put under the names the setup
gives those Alpaca accounts now: the same keys under a new name open the same record, with its
lots, and a record a name used to hold for another Alpaca account moves aside to
`<name>-earlier` rather than block it.

Nothing that holds a record is ever deleted here: only a folder with no record file gives way. A
record that can't be read is never moved, and the account it would affect doesn't open. Every
folder that moves is locked as an account owner locks it, and a move interrupted by a crash is
finished, or undone, before the next plan.
"""

import fcntl
import json
import logging
import os
import shutil
import sqlite3
from collections.abc import Generator, Iterator, Mapping
from contextlib import ExitStack, closing, contextmanager
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

log = logging.getLogger(__name__)

# An Alpaca account as a record names it: its environment and Alpaca's account ID.
type BrokerIdentity = tuple[str, str]

RECORD = "execution.sqlite3"
LOCK = "executor.lock"
STAGED = ".moving-"
# Where a move in progress is written down; a dot-file, so it is never taken for an account.
JOURNAL = ".record-moves.json"


class Unbound(Enum):
    """A folder with no Alpaca account to go by."""

    # No record file at all: the folder holds nothing and may give way.
    EMPTY = "empty"
    # A record file that names no Alpaca account yet; it is moved aside, never deleted.
    UNNAMED = "unnamed"
    # A record file that couldn't be read; it is never moved or deleted.
    UNREADABLE = "unreadable"


type Held = BrokerIdentity | Unbound


@dataclass(frozen=True, slots=True)
class RecordPlan:
    """Folder renames, folders that give way, and the accounts that cannot open."""

    moves: dict[str, str] = field(default_factory=dict)
    cleared: tuple[str, ...] = ()
    refusals: dict[str, str] = field(default_factory=dict)


def record_identity(account_dir: Path) -> Held:
    """The Alpaca account a folder's record was made with, or why there is none to go by."""
    database = account_dir / RECORD
    if not database.exists():
        return Unbound.EMPTY
    try:
        with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as db:
            found = db.execute(
                "SELECT environment, account_id FROM identity WHERE singleton=1"
            ).fetchone()
    except sqlite3.Error:
        return Unbound.UNREADABLE
    return (found[0], found[1]) if found is not None else Unbound.UNNAMED


def account_folders(root: Path) -> Iterator[Path]:
    """Every account's folder; a dot-folder, such as one staged mid-move, is not an account."""
    if root.is_dir():
        for child in sorted(root.iterdir()):
            if child.is_dir() and not child.is_symlink() and not child.name.startswith("."):
                yield child


def held_records(root: Path) -> dict[str, Held]:
    """Every account folder and the Alpaca account its record belongs to."""
    return {child.name: record_identity(child) for child in account_folders(root)}


def plan_records(
    wanted: Mapping[str, BrokerIdentity | None], held: Mapping[str, Held]
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
    # A setup name whose own folder can't be read can't be told apart from its record.
    refusals |= {
        name: "record_unreadable"
        for name in wanted
        if held.get(name) is Unbound.UNREADABLE and name not in refusals
    }
    owner = {
        identity: names[0]
        for identity, names in sharing.items()
        if len(names) == 1 and names[0] not in refusals
    }
    moves: dict[str, str] = {}
    for folder, identity in held.items():
        if isinstance(identity, Unbound):
            # A record with no Alpaca account steps aside from a name another record needs.
            if identity is Unbound.UNNAMED and folder in known and folder not in refusals:
                moves[folder] = ""
            continue
        target = owner.get(identity)
        if target is not None and folder != target:
            moves[folder] = target
        elif target is None and folder in known and folder not in refusals:
            # The name now belongs to another Alpaca account; its old record steps aside.
            moves[folder] = ""
    # An UNNAMED folder only steps aside when a record must take its place.
    arriving = {target for target in moves.values() if target}
    for folder in [name for name, target in moves.items() if not target]:
        if held[folder] is Unbound.UNNAMED and folder not in arriving:
            del moves[folder]
    taken = set(held) | set(wanted)
    for folder in sorted(name for name, target in moves.items() if not target):
        parked = f"{folder}-earlier"
        suffix = 2
        while parked in taken:
            parked = f"{folder}-earlier-{suffix}"
            suffix += 1
        taken.add(parked)
        moves[folder] = parked
    cleared = tuple(
        sorted(
            folder
            for folder, identity in held.items()
            if identity is Unbound.EMPTY and folder in arriving and folder not in moves
        )
    )
    return RecordPlan(moves=moves, cleared=cleared, refusals=refusals)


@contextmanager
def _locked(root: Path, folders: list[str]) -> Generator[str | None]:
    """Each folder locked as its account owner locks it, held through the move; yields the
    first folder another CopyTrading has open, with nothing locked, or None."""
    with ExitStack() as stack:
        for name in folders:
            lock = stack.enter_context((root / name / LOCK).open("a"))
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                stack.close()
                yield name
                return
        yield None


def _write_journal(path: Path, moves: Mapping[str, str]) -> None:
    staging = path.with_suffix(".tmp")
    with staging.open("w") as handle:
        json.dump(dict(moves), handle)
        handle.flush()
        os.fsync(handle.fileno())
    staging.replace(path)


def apply_record_plan(root: Path, plan: RecordPlan) -> str | None:
    """Make the moves, through temporary names so two records can trade places. Returns the
    folder another CopyTrading has open, and then changes nothing at all."""
    touched = sorted(set(plan.moves) | set(plan.cleared))
    if not touched:
        return None
    with _locked(root, touched) as busy:
        if busy is not None:
            log.warning("account_records_in_use folder=%s", busy)
            return busy
        journal = root / JOURNAL
        _write_journal(journal, plan.moves)
        for folder in plan.cleared:
            shutil.rmtree(root / folder)
        for folder in plan.moves:
            (root / folder).rename(root / f"{STAGED}{folder}")
        for folder, target in plan.moves.items():
            (root / f"{STAGED}{folder}").rename(root / target)
        journal.unlink()
    return None


def recover_interrupted_moves(root: Path) -> None:
    """Finish the moves a crash interrupted, from their journal; without one, put each staged
    folder back under its own name. A folder that can go nowhere stays staged, never deleted."""
    journal = root / JOURNAL
    moves: dict[str, str] = json.loads(journal.read_text()) if journal.is_file() else {}
    if root.is_dir():
        for staged in sorted(root.iterdir()):
            if not staged.name.startswith(STAGED) or not staged.is_dir():
                continue
            folder = staged.name.removeprefix(STAGED)
            for target in (moves.get(folder), folder):
                if target and not (root / target).exists():
                    staged.rename(root / target)
                    log.warning("account_record_move_recovered from=%s to=%s", folder, target)
                    break
            else:
                log.error("account_record_move_unrecoverable folder=%s", folder)
    journal.unlink(missing_ok=True)


def reconcile_records(root: Path, wanted: Mapping[str, BrokerIdentity | None]) -> RecordPlan:
    """Put each record under the name the setup gives its Alpaca account now."""
    recover_interrupted_moves(root)
    plan = plan_records(wanted, held_records(root))
    if apply_record_plan(root, plan) is None:
        return plan
    # Nothing moved, so each account a move was for would open the wrong record: none opens.
    involved = set(plan.moves) | set(plan.moves.values()) | set(plan.cleared)
    busy = {name: "account_in_use" for name in wanted if name in involved}
    return RecordPlan(refusals=busy | plan.refusals)


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
    with (folder / LOCK).open("a") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return "account_in_use"
        shutil.rmtree(folder)
    return None
