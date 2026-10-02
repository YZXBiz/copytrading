"""The whole engine on a pinned weekday morning: Zhao's channel and reader in front, the real
routing, risk, ledger, and lots in the middle, and one simulated broker per account behind it."""

import asyncio
import datetime as dt
import itertools
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path

from copytrading_engine.execution.adapters.owner import ExecutionOwner
from copytrading_engine.execution.domain.lifecycle import AccountControlCommand
from copytrading_engine.execution.domain.lot_sales import (
    LotSaleConfirmation,
    LotSalePreviewRequest,
)
from copytrading_engine.shared.raw_message import RawMessage
from copytrading_engine.trading.domain.config import TradingConfiguration, TradingSecrets
from copytrading_engine.trading.domain.profiles import ProfileBuilder, ProfileDraft
from copytrading_engine.trading.entrypoints.factories import TradingFactories
from copytrading_engine.trading.entrypoints.runtime import TradingRuntime

from .broker import SimulatedBroker
from .zhao import GURU_ID, NAME, PREFIX, ZhaoChannel, ZhaoReader

CHANNEL = "900000000000000777"
# A Wednesday, 11:00 in New York: regular hours, so market orders and full-session rules apply.
MARKET_MORNING = dt.datetime(2026, 9, 30, 15, 0, tzinfo=dt.UTC)
SETTLED = {"done", "stale", "out_of_order", "ignored", "review_required"}


# Roomy limits, so a scenario meets only the limit it is about.
ROOMY = {
    "max_order_usd": "5000",
    "max_symbol_usd": "20000",
    "max_total_usd": "50000",
    "daily_loss_cap_usd": "5000",
    "poll_seconds": 1,
}


@dataclass
class Account:
    cash: str
    amount_usd: str = "500"
    mode: str = "fixed"
    limits: dict = field(default_factory=dict)

    @property
    def policy(self) -> dict:
        return ROOMY | self.limits


class Rig:
    def __init__(self, root: Path, accounts: dict[str, Account], prices: dict[str, str]) -> None:
        self.root = root
        self.accounts = accounts
        self.reader = ZhaoReader()
        self.brokers = {
            name: SimulatedBroker(name, cash=account.cash, prices=prices)
            for name, account in accounts.items()
        }
        self._ids = itertools.count(1)
        self.runtime = TradingRuntime(
            root,
            factories=TradingFactories(
                owner=self._open_owner,
                decoder=self._open_reader,
                session=self._open_channel,
            ),
        )
        self.channel: ZhaoChannel | None = None

    def _open_channel(self, source, channels, authors, stop, report_failure) -> ZhaoChannel:
        self.channel = ZhaoChannel(source)
        return self.channel

    async def _open_owner(self, path, credentials, policy, environment, **_):
        owner = await ExecutionOwner.open(
            path,
            credentials,
            policy,
            environment=environment,
            broker_factory=lambda keys, mode: self.brokers[path.name],
            account_lock_root=self.root / "locks",
        )
        await owner.recover_account(dt.datetime.now(dt.UTC))
        return owner

    async def _open_reader(self, name, config, **_):
        return self.reader

    def configuration(self) -> TradingConfiguration:
        profile = ProfileBuilder().build(
            ProfileDraft(
                guru_id=GURU_ID,
                display_name=NAME,
                prefix=PREFIX,
                playbook="",
                examples=(),
                exit_basis="original_position",
            )
        )
        connections = [
            {"account_id": name, "mode": account.mode, "amount_usd": account.amount_usd}
            for name, account in self.accounts.items()
        ]
        return TradingConfiguration.model_validate(
            {
                "version": 4,
                "source": {"channel_ids": [CHANNEL]},
                "provider": {"name": "deepseek", "model": "scripted-zhao"},
                "accounts": [
                    {"id": name, "environment": "paper", "policy": account.policy}
                    for name, account in self.accounts.items()
                ],
                "profiles": [profile.model_dump(mode="json")],
                "routes": [
                    {
                        "channel_id": CHANNEL,
                        "author_id": None,
                        "guru_id": profile.guru_id,
                        "profile_revision": profile.profile_revision,
                        "connections": connections,
                    }
                ],
            }
        )

    async def __aenter__(self) -> Rig:
        secrets = TradingSecrets.model_validate(
            {
                "discord_token": "scenario",
                "provider_api_key": "scenario",
                "brokers": [
                    {"account_id": name, "key": f"{name}-key", "secret": "scenario"}
                    for name in self.accounts
                ],
            }
        )
        await self.runtime.start(self.configuration(), secrets)
        await self._until(
            lambda: (
                len([a for a in self.runtime.status().accounts if a.state in {"ready", "running"}])
                == len(self.accounts)
            ),
            "every account to open",
        )
        for name in self.accounts:
            await self.entries(name, "resume")
        return self

    async def __aexit__(self, *_) -> None:
        await self.runtime.shutdown()

    # What Zhao and the owner do.

    async def post(self, text: str, *, expect_destinations: bool = True, age_seconds: int = 0):
        """Zhao posts; returns the post's activity once every account has settled it."""
        assert self.channel is not None, "the runtime has not opened Zhao's channel"
        message_id = str(1_700_000_000_000 + next(self._ids))
        await self.channel.source.add(
            RawMessage(
                schema_version=1,
                event_type="raw_message",
                source="discord",
                channel_id=CHANNEL,
                id=message_id,
                timestamp=dt.datetime.now(dt.UTC) - dt.timedelta(seconds=age_seconds),
                text=f"{PREFIX} {text}",
            )
        )
        source_id = f"discord:{CHANNEL}:{message_id}"
        found = None

        async def settled() -> bool:
            nonlocal found
            page = await self.runtime.operator.source_activity(None, 100)
            found = next((item for item in page.items if item.source_id == source_id), None)
            if found is None or found.parse_status in {"pending", "queued"}:
                return False
            if not expect_destinations:
                return found.decision is not None
            done = {d.account_id for d in found.destinations if d.status in SETTLED}
            return done == set(self.accounts)

        await self._until_async(settled, f"Zhao's post {text!r} to settle")
        return found

    async def entries(self, account: str, action: str) -> None:
        await self.runtime.manual.control_account(
            AccountControlCommand(command_id=str(uuid.uuid4()), account_id=account, action=action)
        )

    async def overview(self, account: str):
        page = await self.runtime.operator.account_overviews()
        return next(item for item in page.items if item.account_id == account)

    async def lots(self, account: str, symbol: str):
        overview = await self.overview(account)
        position = next((p for p in overview.positions if p.symbol == symbol), None)
        return () if position is None else position.lots

    async def sell_lot(self, account: str, lot_id: str, qty: str):
        preview = await self.runtime.manual.preview_lot_sale(
            LotSalePreviewRequest(
                preview_id=str(uuid.uuid4()), account_id=account, lot_id=lot_id, qty=Decimal(qty)
            )
        )
        result = await self.runtime.manual.confirm_lot_sale(
            LotSaleConfirmation(
                command_id=str(uuid.uuid4()),
                preview_id=preview.request.preview_id,
                account_id=account,
                actor="owner",
            )
        )
        return preview, result

    # Waiting.

    async def until(self, read, what: str):
        """Await `read()` until it returns something truthy, as the engine catches up."""
        result = None

        async def ready() -> bool:
            nonlocal result
            result = await read()
            return bool(result)

        await self._until_async(ready, what)
        return result

    async def _until(self, predicate, what: str) -> None:
        for _ in range(200):
            if predicate():
                return
            await asyncio.sleep(0.05)
        raise AssertionError(f"timed out waiting for {what}: {self.runtime.status()}")

    async def _until_async(self, predicate, what: str) -> None:
        for _ in range(300):
            if await predicate():
                return
            await asyncio.sleep(0.05)
        raise AssertionError(f"timed out waiting for {what}: {self.runtime.status()}")


def outcomes(activity, account: str) -> tuple[str, ...]:
    return next(d for d in activity.destinations if d.account_id == account).instruction_outcomes


def orders(activity, account: str):
    return next(d for d in activity.destinations if d.account_id == account).orders
