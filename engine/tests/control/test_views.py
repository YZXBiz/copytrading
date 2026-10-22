"""What the assistant reads about an account: what it holds, in amounts a person would write."""

import json
from decimal import Decimal

from copytrading_engine.control import views
from copytrading_engine.execution.presentation.operator_views import AccountOverviewPage

from ..contracts import contract


def _page(**changes) -> AccountOverviewPage:
    page = contract("account-overviews-response.json")["ok"]["accounts"]
    account = page["items"][0]
    page["items"] = [account | changes]
    return AccountOverviewPage.model_validate_json(json.dumps(page))


def test_a_sold_out_stock_is_not_listed_as_a_position():
    held = contract("account-overviews-response.json")["ok"]["accounts"]["items"][0]["positions"]
    sold_out = held[0] | {
        "symbol": "SOFI",
        "owned_qty": "0.000000",
        "external_qty": "0",
        "broker_qty": None,
        "lots": [],
    }

    [account] = views.accounts(_page(positions=[*held, sold_out])).items

    assert [position.symbol for position in account.positions] == ["ABC"]


def test_exposure_is_given_in_cents():
    [account] = views.accounts(_page(total_exposure_usd="250.5566221162100057516208928")).items

    assert account.total_exposure_usd == Decimal("250.56")
