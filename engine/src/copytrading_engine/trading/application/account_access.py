"""Reach a trading account through its live owner, or its retained ledger, in bounded time."""

import asyncio
import heapq
import logging
from collections.abc import Awaitable, Callable, Hashable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from copytrading_engine.execution.domain.ledger_state import LedgerSnapshot
from copytrading_engine.execution.domain.lifecycle import AccountOwnerClosed
from copytrading_engine.execution.presentation.account_feed import AccountFeedPage
from copytrading_engine.execution.presentation.operator_views import (
    AccountEventPage,
    AccountOverview,
    UnavailableReason,
)
from copytrading_engine.trading.application.accounts import AccountSupervisor
from copytrading_engine.trading.application.ports import OperatorEvidence
from copytrading_engine.trading.domain.config import TradingConfiguration

log = logging.getLogger(__name__)


_OWNER_READ_TIMEOUT_SECONDS = 2
# Each page of posts asks for its own set; only the newest few answers are kept.
_REMEMBERED_READS = 64


@dataclass(frozen=True, slots=True)
class OwnerUnavailable:
    """A live owner read that timed out or failed; callers fall back or report it."""

    reason: UnavailableReason


async def bounded_owner_read[T](operation: Awaitable[T]) -> T | OwnerUnavailable:
    """A stalled broker worker cannot stall all native account/source reads."""
    task = asyncio.ensure_future(operation)
    done, _ = await asyncio.wait({task}, timeout=_OWNER_READ_TIMEOUT_SECONDS)
    if not done:
        task.add_done_callback(
            lambda completed: completed.exception() if not completed.cancelled() else None
        )
        return OwnerUnavailable("timeout")
    try:
        return task.result()
    except AccountOwnerClosed:
        # Copying is pausing or stopped: the retained ledger answers; nothing went wrong.
        return OwnerUnavailable("read_failed")
    except Exception as exc:  # noqa: BLE001 - one owner's failure is reported, not raised
        log.warning("operator_account_read_failed type=%s error=%s", type(exc).__name__, exc)
        return OwnerUnavailable("read_failed")


class OwnerReads:
    """Reads of a running account's worker, the same thread that places its orders. A busy worker
    is not a stopped one: while an earlier read still waits on it, that read's last answer stands
    in at once, and no second read queues behind the first to make the worker busier."""

    def __init__(self) -> None:
        self._owners: dict[str, object] = {}
        self._waiting: dict[str, asyncio.Future[object]] = {}
        self._last: dict[tuple[str, Hashable], object] = {}

    async def read[T](
        self, account_id: str, owner: object, key: Hashable, operation: Callable[[], Awaitable[T]]
    ) -> T | OwnerUnavailable:
        """`operation` reads `owner`, the account's worker now; `key` names what it reads, so an
        answer stands in only for the same read of the same worker."""
        if self._owners.get(account_id) is not owner:
            self._forget(account_id)
            self._owners[account_id] = owner
        remembered = (account_id, key)
        waiting = self._waiting.get(account_id)
        if waiting is not None and not waiting.done():
            return cast(T, self._last.get(remembered, OwnerUnavailable("timeout")))
        task = asyncio.ensure_future(operation())
        self._waiting[account_id] = cast(asyncio.Future[object], task)

        def keep(done: asyncio.Future[T]) -> None:
            # A read that outlived its wait still brings the newest answer once it lands.
            if self._owners.get(account_id) is owner and not done.cancelled():
                if done.exception() is None:
                    self._last.pop(remembered, None)
                    self._last[remembered] = done.result()
                    while len(self._last) > _REMEMBERED_READS:
                        del self._last[next(iter(self._last))]

        task.add_done_callback(keep)
        result = await bounded_owner_read(task)
        if result == OwnerUnavailable("timeout") and remembered in self._last:
            return cast(T, self._last[remembered])
        return result

    def _forget(self, account_id: str) -> None:
        self._waiting.pop(account_id, None)
        for remembered in [item for item in self._last if item[0] == account_id]:
            del self._last[remembered]


class AccountAccess:
    """Shared by operator reads and manual intervention; the runtime owns the supervisors."""

    def __init__(
        self,
        data_dir: Path,
        supervisors: Callable[[], Mapping[str, AccountSupervisor]],
        configuration: Callable[[], TradingConfiguration | None],
        runtime_state: Callable[[], str],
        evidence: OperatorEvidence,
        account_error: Callable[[str], str | None] = lambda _: None,
    ) -> None:
        """`account_error` is the last reason an account stopped, kept after its supervisor ends."""
        self.data_dir = data_dir
        self.supervisors = supervisors
        self.configuration = configuration
        self.runtime_state = runtime_state
        self.evidence = evidence
        self.account_error = account_error

    @property
    def application_database(self) -> Path:
        return self.data_dir / "application.db"

    async def retained_account(
        self,
        database: Path,
        *,
        timeout: float,
        before_seq: int | None = None,
        limit: int = 50,
    ) -> tuple[AccountOverview, LedgerSnapshot, AccountEventPage]:
        """Read a retained ledger off the event loop; a stalled read raises TimeoutError."""
        return await asyncio.wait_for(
            asyncio.to_thread(
                self.evidence.retained_account, database, before_seq=before_seq, limit=limit
            ),
            timeout=timeout,
        )

    async def retained_feed(
        self, database: Path, *, before_seq: int | None, limit: int, timeout: float
    ) -> AccountFeedPage:
        """Read a retained account's feed off the event loop."""
        return await asyncio.wait_for(
            asyncio.to_thread(
                self.evidence.retained_feed, database, before_seq=before_seq, limit=limit
            ),
            timeout=timeout,
        )

    def retained_paths(self) -> dict[str, Path]:
        root = self.data_dir / "accounts"
        if not root.exists():
            return {}
        if root.is_symlink():
            raise RuntimeError("Account state directory is invalid")
        paths: dict[str, Path] = {}
        for account_dir in root.iterdir():
            if account_dir.name.startswith("."):
                continue  # not an account: a folder staged mid-move (account_records)
            if account_dir.is_symlink() or not account_dir.is_dir():
                raise RuntimeError("Account evidence path is invalid")
            database = account_dir / "execution.sqlite3"
            if database.is_symlink():
                raise RuntimeError("Account evidence path is invalid")
            if database.exists():
                paths[account_dir.name] = database
        return paths

    def retained_page_paths(self, before_account_id: str | None, capacity: int) -> dict[str, Path]:
        root = self.data_dir / "accounts"
        if not root.exists():
            return {}
        if root.is_symlink():
            raise RuntimeError("Account state directory is invalid")
        paths: list[tuple[str, Path]] = []
        for account_dir in root.iterdir():
            if account_dir.name.startswith("."):
                continue  # not an account: a folder staged mid-move (account_records)
            if account_dir.is_symlink() or not account_dir.is_dir():
                raise RuntimeError("Account evidence path is invalid")
            database = account_dir / "execution.sqlite3"
            if database.is_symlink():
                raise RuntimeError("Account evidence path is invalid")
            if not database.exists():
                continue
            account_id = account_dir.name
            if before_account_id is not None and account_id >= before_account_id:
                continue
            heapq.heappush(paths, (account_id, database))
            if len(paths) > capacity:
                heapq.heappop(paths)
        return dict(paths)

    def manual_command_ledger_path(self, account_id: str) -> Path:
        if (
            not account_id
            or len(account_id) > 64
            or not account_id.isascii()
            or not all(character.isalnum() or character in "_-" for character in account_id)
        ):
            raise ValueError("Manual account history is unavailable")
        accounts_root = self.data_dir / "accounts"
        account_dir = accounts_root / account_id
        database = account_dir / "execution.sqlite3"
        if (
            accounts_root.is_symlink()
            or not accounts_root.is_dir()
            or account_dir.is_symlink()
            or not account_dir.is_dir()
            or database.is_symlink()
            or not database.is_file()
        ):
            raise ValueError("Manual account history is unavailable")
        return database
