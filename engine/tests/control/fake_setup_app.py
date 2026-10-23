"""Stands in for the app's setup handler: it keeps a draft, asks the real engine to authorize
each request without its keys, and answers with the same contract the app does."""

import copy
import json
from dataclasses import dataclass, field
from typing import Any

from copytrading_engine.control import wire
from copytrading_engine.control.service import ControlContext
from copytrading_engine.host.pipe.server import PipeServer
from copytrading_engine.shared.route_keys import guru_for_channel

DEFAULT_LIMITS = {
    "max_order_usd": "100",
    "max_symbol_usd": "600",
    "max_total_usd": "2500",
    "daily_loss_cap_usd": "250",
    "max_entries_per_day": "30",
    "max_signal_age_seconds": "600",
    "order_timeout_seconds": "60",
    "poll_seconds": "2.0",
    "extended_hours": "true",
    "overnight": "false",
    "copy_exits": "true",
    "approve_orders": "false",
    "max_above_signal_pct": "0",
    "max_below_signal_pct": "1",
}


_NOT_POLICY = frozenset({"id", "environment", "saved_name", "keys_typed"})


def apply_facts(
    saved: dict[str, Any], draft: dict[str, Any], *, copying: bool, start: bool = False
) -> dict[str, list]:
    """What applying `draft` over `saved` does to live accounts, by the rules the app's
    `agentApplyFacts` follows; `agent-setup-apply-facts.json` holds the cases both check."""
    origins = {account["id"]: account for account in saved["accounts"]}

    def policy(account: dict[str, Any]) -> dict[str, Any]:
        return {key: value for key, value in account.items() if key not in _NOT_POLICY}

    def gurus(state: dict[str, Any], account: str) -> list[str]:
        return sorted(route["channel"] for route in state["routes"] if route["account"] == account)

    typed = any(account["keys_typed"] for account in draft["accounts"])
    drafted = [(item["id"], item["environment"], item["saved_name"]) for item in draft["accounts"]]
    same_shape = drafted == [
        (item["id"], item["environment"], item["id"]) for item in saved["accounts"]
    ]
    same_routes = sorted(map(str, draft["routes"])) == sorted(map(str, saved["routes"]))
    limits_only = same_shape and same_routes and not typed
    changed = not limits_only or any(
        policy(account) != policy(origins[account["id"]]) for account in draft["accounts"]
    )
    # Copying starts again when it runs and more than limits change, or when it is paused and
    # `setup apply --start` asks for it.
    restarts = (copying and changed and not limits_only) or (not copying and start)
    facts: dict[str, list] = {
        "made_live": [],
        "new_live_keys": [],
        "changed_live": [],
        "starts_live": [],
    }
    for account in draft["accounts"]:
        if account["environment"] != "live":
            continue
        name = account["id"]
        origin = origins.get(account["saved_name"]) if account["saved_name"] else None
        renamed = account["saved_name"] != name
        made_live = origin is None or origin["environment"] != "live" or renamed
        if made_live:
            facts["made_live"].append(name)
        if account["keys_typed"]:
            facts["new_live_keys"].append(name)
        if (
            not made_live
            and origin is not None
            and (
                policy(origin) != policy(account)
                or gurus(draft, name) != gurus(saved, origin["id"])
            )
        ):
            facts["changed_live"].append(name)
        if restarts:
            facts["starts_live"].append(name)
    return facts


@dataclass
class Draft:
    channels: list[str] = field(default_factory=lambda: ["111"])
    authors: list[str] = field(default_factory=list)
    service: str = "deepseek"
    model: str = "deepseek-flash"
    accounts: dict[str, dict[str, Any]] = field(
        default_factory=lambda: {
            "paper-main": {
                "environment": "paper",
                "limits": dict(DEFAULT_LIMITS),
                "recovery_preference": "manual",
                "saved_name": "paper-main",
            }
        }
    )
    gurus: dict[str, dict[str, Any]] = field(default_factory=dict)
    alerts: bool = False


class FakeSetupApp:
    def __init__(self, server: PipeServer) -> None:
        self._server = server
        self.saved = Draft()
        self.draft = copy.deepcopy(self.saved)
        # Every key the app received, to prove keys arrive and never come back.
        self.received: list[str] = []
        self.typed: set[str] = set()
        self.applied = 0
        self.fail_checks = False
        self.copying = True
        self.started = 0

    async def handle(self, line: str, context: ControlContext) -> str:
        request = wire.REQUEST.validate_json(line)
        facts = self._facts(start=request.start) if isinstance(request, wire.ApplySetup) else None
        authorization = {
            "version": 1,
            "request_id": "authorize",
            "operation": "authorize_setup",
            "setup": {
                "operation": request.operation,
                "request_id": request.request_id,
                "apply": facts,
            },
            "context": context.model_dump(mode="json"),
        }
        reply = json.loads(await self._server.handle_line(json.dumps(authorization).encode()))
        if reply["ok"]["type"] == "control":
            return reply["ok"]["line"]
        assert reply["ok"]["type"] == "setup_allowed"
        result = self._run(request)
        return wire.Response(request_id=request.request_id, ok=result).model_dump_json()

    def _facts(self, *, start: bool) -> dict[str, list]:
        return apply_facts(
            self._state(self.saved, saved=True),
            self._state(self.draft, saved=False),
            copying=self.copying,
            start=start,
        )

    def _state(self, state: Draft, *, saved: bool) -> dict[str, Any]:
        """The fake's setup in the shape `agent-setup-apply-facts.json` uses."""
        accounts = []
        for name, item in state.accounts.items():
            account: dict[str, Any] = {
                "id": name,
                "environment": item["environment"],
                "recovery_preference": item["recovery_preference"],
            }
            account.update(item["limits"])
            if not saved:
                account["saved_name"] = item.get("saved_name")
                account["keys_typed"] = f"account:{name}" in self.typed
            accounts.append(account)
        routes = [
            {"channel": item["channel"] or state.channels[0], "account": item["account"]}
            for item in state.gurus.values()
        ]
        return {"accounts": accounts, "routes": routes}

    def _keep(self, name: str, value: Any) -> None:
        if value is not None:
            self.received.append(value.get_secret_value())
            self.typed.add(name)

    def _run(self, request: wire.Request) -> wire.Result:
        draft = self.draft
        match request:
            case wire.EditSetupDiscord():
                draft.channels = list(request.channel_ids or draft.channels)
                if request.author_ids is not None:
                    draft.authors = list(request.author_ids)
                self._keep("discord", request.token)
            case wire.EditSetupModel():
                draft.service = request.service or draft.service
                draft.model = request.model or draft.model
                self._keep("model", request.key)
            case wire.EditSetupAccount(action="add"):
                draft.accounts[request.account_id] = {
                    "environment": request.environment or "paper",
                    "limits": dict(DEFAULT_LIMITS),
                    "recovery_preference": "manual",
                    "saved_name": None,
                }
                self._edit_account(request, request.account_id)
            case wire.EditSetupAccount(action="edit"):
                self._edit_account(request, request.account_id)
            case wire.EditSetupAccount(action="remove"):
                del draft.accounts[request.account_id]
            case wire.EditSetupGuru(action="add"):
                draft.gurus[request.guru] = {
                    "channel": request.channel_id,
                    "author": request.author_id,
                    "account": request.account_id,
                }
            case wire.EditSetupGuru():
                draft.gurus.pop(request.guru, None)
            case wire.EditSetupAlerts():
                draft.alerts = request.enabled if request.enabled is not None else draft.alerts
                self._keep("alerts", request.token)
            case wire.ImportSetup():
                self.received.append(request.text.get_secret_value())
                return wire.SetupImported(
                    filled=("Discord token",), missing=("A guru",), setup=self._view()
                )
            case wire.ApplySetup():
                return self._apply(start=request.start)
            case wire.DiscardSetup():
                self.draft = copy.deepcopy(self.saved)
                self.typed.clear()
        return self._view()

    def _edit_account(self, request: wire.EditSetupAccount, name: str) -> None:
        account = self.draft.accounts[name]
        if request.environment is not None:
            account["environment"] = request.environment
        for change in request.limits:
            account["limits"][change.field] = change.value
        if request.recovery_preference is not None:
            account["recovery_preference"] = request.recovery_preference
        if request.key is not None:
            self._keep(f"account:{name}", request.key)
            self._keep(f"account:{name}", request.secret)

    def _apply(self, *, start: bool) -> wire.SetupApplied:
        checks = (
            wire.SetupCheckView(connection="discord", state="passed"),
            wire.SetupCheckView(
                connection="account",
                subject="paper-main",
                state="failed" if self.fail_checks else "passed",
                reason="broker_auth_or_permissions_failed" if self.fail_checks else None,
                message="paper-main: Alpaca didn't accept these keys. Check that they are for "
                "a paper or live account as chosen."
                if self.fail_checks
                else None,
            ),
        )
        if self.fail_checks:
            return wire.SetupApplied(
                status="failed_checks",
                message="Some connections need attention. Nothing was saved.",
                checks=checks,
            )
        self.applied += 1
        if start and not self.copying:
            self.copying = True
            self.started += 1
        self.saved = copy.deepcopy(self.draft)
        for name, item in self.saved.accounts.items():
            item["saved_name"] = name
        self.typed.clear()
        return wire.SetupApplied(status="applied", checks=checks)

    def _view(self) -> wire.SetupView:
        draft = self.draft

        def key(name: str) -> wire.KeyState:
            return "entered" if name in self.typed else "saved"

        return wire.SetupView(
            saved=True,
            unsaved_changes=draft != self.saved or bool(self.typed),
            copying="copying" if self.copying else "paused",
            discord=wire.SetupDiscordView(
                channel_ids=tuple(draft.channels),
                author_ids=tuple(draft.authors),
                token=key("discord"),
            ),
            model=wire.SetupModelView(service=draft.service, model=draft.model, key=key("model")),
            accounts=tuple(
                wire.SetupAccountView(
                    account_id=name,
                    environment=item["environment"],
                    keys=key(f"account:{name}")
                    if name in self.saved.accounts or f"account:{name}" in self.typed
                    else "missing",
                    limits=tuple(
                        wire.LimitChange(field=field, value=value)
                        for field, value in item["limits"].items()
                    ),
                    recovery_preference=item["recovery_preference"],
                )
                for name, item in draft.accounts.items()
            ),
            gurus=tuple(
                wire.SetupGuruView(
                    guru_id=guru_for_channel("discord", item["channel"] or draft.channels[0]),
                    name=name,
                    channel_id=item["channel"] or draft.channels[0],
                    author_id=item["author"] or None,
                    account_id=item["account"],
                    full_position_usd=None,
                    repeat_window_minutes=10,
                    playbook_characters=0,
                )
                for name, item in draft.gurus.items()
            ),
            alerts=wire.SetupAlertsView(enabled=draft.alerts, service="telegram", token="missing"),
        )
