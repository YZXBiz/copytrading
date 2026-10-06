"""copytrading.toml and the environment become exactly the setup the app would send."""

from decimal import Decimal
from importlib import resources

import pytest

from copytrading_engine.headless.config import (
    ConfigError,
    broker_key_names,
    load_secrets,
    load_setup,
)

TEMPLATE = resources.files("copytrading_engine.headless").joinpath("template.toml")

KEYS = {
    "COPYTRADING_DISCORD_TOKEN": "discord",
    "COPYTRADING_MODEL_API_KEY": "model",
    "COPYTRADING_ALPACA_PAPER_MAIN_KEY": "key",
    "COPYTRADING_ALPACA_PAPER_MAIN_SECRET": "secret",
}


def write(tmp_path, text: str):
    path = tmp_path / "copytrading.toml"
    path.write_text(text, encoding="utf-8")
    return path


def template_with(tmp_path, old: str, new: str):
    text = TEMPLATE.read_text(encoding="utf-8")
    assert old in text
    return write(tmp_path, text.replace(old, new))


def test_the_template_init_writes_is_a_valid_setup(tmp_path):
    setup = load_setup(write(tmp_path, TEMPLATE.read_text(encoding="utf-8")))

    configuration = setup.configuration
    assert [account.id for account in configuration.accounts] == ["paper-main"]
    [profile] = configuration.profiles
    assert (profile.guru_id, profile.display_name) == ("zhao", "Zhao")
    [route] = configuration.routes
    assert route.profile_revision == profile.profile_revision
    [connection] = route.connections
    # The guru's full position is its account's maximum per stock; a call with no size buys it.
    assert connection.full_position_usd == configuration.accounts[0].policy.max_symbol_usd
    assert connection.default_fraction == 1
    assert configuration.accounts[0].policy.max_order_usd == Decimal("100")
    assert setup.agent_access == "read_pause"


@pytest.mark.parametrize(
    ("settings", "default_fraction", "batches", "sells_refer_to"),
    [
        pytest.param('default_share = "wait"', None, None, "buy_price", id="wait-without-size"),
        pytest.param("default_share = 0.5", Decimal("0.5"), None, "buy_price", id="half"),
        pytest.param("batches = 3", Decimal(1), 3, "buy_price", id="three-batches"),
        pytest.param(
            'sells_refer_to = "whole_position"', Decimal(1), None, "whole_position", id="whole"
        ),
    ],
)
def test_a_gurus_rules_reach_its_profile_and_connection(
    tmp_path, settings, default_fraction, batches, sells_refer_to
):
    path = template_with(tmp_path, 'account = "paper-main"', f'account = "paper-main"\n{settings}')

    configuration = load_setup(path).configuration

    [profile] = configuration.profiles
    [route] = configuration.routes
    assert route.connections[0].default_fraction == default_fraction
    assert (profile.batches, profile.sells_refer_to) == (batches, sells_refer_to)


def test_decimal_settings_stay_exact(tmp_path):
    path = template_with(tmp_path, "max_above_signal_pct = 0 ", "max_above_signal_pct = 0.1 ")

    policy = load_setup(path).configuration.accounts[0].policy

    assert policy.max_above_signal_pct == Decimal("0.1")


def test_a_playbook_can_live_in_its_own_file(tmp_path):
    (tmp_path / "zhao.md").write_text("Buys say Bought.", encoding="utf-8")
    path = template_with(
        tmp_path, '# playbook_file = "zhao-playbook.md"', 'playbook_file = "zhao.md"'
    )

    assert load_setup(path).configuration.profiles[0].playbook == "Buys say Bought."


def test_a_missing_playbook_file_is_named(tmp_path):
    path = template_with(tmp_path, '# playbook_file = "zhao-playbook.md"', 'playbook_file = "x.md"')

    with pytest.raises(ConfigError) as problem:
        load_setup(path)
    assert "gurus[0] (zhao): cannot read" in problem.value.problems[0]


@pytest.mark.parametrize(
    ("old", "new", "expected"),
    [
        ('provider = "deepseek"', 'provider = "skynet"', "model.provider"),
        ('account = "paper-main"', 'account = "nowhere"', "unknown account"),
        ('environment = "paper" ', 'environment = "demo" ', "accounts[0].environment"),
        ('symbol = "NVDA"', 'symbol = "nvidia"', "gurus[0] (zhao)"),
        ("[agents]", "[agents]\ncolour = 1", "agents.colour"),
    ],
)
def test_problems_point_at_the_line_to_fix(tmp_path, old, new, expected):
    with pytest.raises(ConfigError) as problem:
        load_setup(template_with(tmp_path, old, new))

    assert any(expected in line for line in problem.value.problems), problem.value.problems


def test_an_unquoted_discord_id_says_to_quote_it(tmp_path):
    path = template_with(tmp_path, 'channels = ["123456789012345678"]', "channels = [123]")

    with pytest.raises(ConfigError, match="put Discord IDs in quotes"):
        load_setup(path)


def test_a_missing_file_says_how_to_make_one(tmp_path):
    with pytest.raises(ConfigError, match="copytrading-server init"):
        load_setup(tmp_path / "nope.toml")


def test_broken_toml_is_reported_not_raised(tmp_path):
    with pytest.raises(ConfigError, match="not valid TOML"):
        load_setup(write(tmp_path, "[discord\n"))


def test_keys_come_from_the_environment(tmp_path):
    configuration = load_setup(write(tmp_path, TEMPLATE.read_text())).configuration

    secrets = load_secrets(configuration, KEYS)

    assert secrets.discord_token.get_secret_value() == "discord"
    assert secrets.brokers[0].account_id == "paper-main"
    assert secrets.brokers[0].secret.get_secret_value() == "secret"
    assert secrets.notification_token is None


def test_every_missing_key_is_listed_at_once(tmp_path):
    configuration = load_setup(write(tmp_path, TEMPLATE.read_text())).configuration

    with pytest.raises(ConfigError) as problem:
        load_secrets(configuration, {"COPYTRADING_DISCORD_TOKEN": "  "})

    assert problem.value.problems == [
        "Set COPYTRADING_DISCORD_TOKEN in the environment.",
        "Set COPYTRADING_MODEL_API_KEY in the environment.",
        "Set COPYTRADING_ALPACA_PAPER_MAIN_KEY in the environment.",
        "Set COPYTRADING_ALPACA_PAPER_MAIN_SECRET in the environment.",
    ]


def test_a_model_on_this_machine_needs_no_key(tmp_path):
    path = template_with(
        tmp_path,
        'provider = "deepseek"\nname = "deepseek-flash"',
        'provider = "ollama"\nname = "qwen3"\naddress = "http://localhost:11434/v1"',
    )
    keys = {name: value for name, value in KEYS.items() if name != "COPYTRADING_MODEL_API_KEY"}

    secrets = load_secrets(load_setup(path).configuration, keys)

    assert secrets.provider_api_key.get_secret_value() == ""


def test_alerts_need_their_token(tmp_path):
    path = template_with(
        tmp_path, '# [telegram]\n# chat_id = "123456789"', '[telegram]\nchat_id = "42"'
    )

    with pytest.raises(ConfigError, match="COPYTRADING_TELEGRAM_TOKEN"):
        load_secrets(load_setup(path).configuration, KEYS)


def test_discord_alerts_take_their_webhook_from_the_environment(tmp_path):
    path = template_with(tmp_path, "# [discord_alerts]", "[discord_alerts]")
    setup = load_setup(path)

    assert setup.configuration.notification is not None
    assert setup.configuration.notification.service == "discord"
    with pytest.raises(ConfigError, match="COPYTRADING_DISCORD_WEBHOOK_URL"):
        load_secrets(setup.configuration, KEYS)
    url = "https://discord.com/api/webhooks/1/abc"
    secrets = load_secrets(setup.configuration, {**KEYS, "COPYTRADING_DISCORD_WEBHOOK_URL": url})
    assert secrets.notification_token is not None
    assert secrets.notification_token.get_secret_value() == url


def test_alerts_go_to_one_place(tmp_path):
    path = template_with(
        tmp_path,
        '# [telegram]\n# chat_id = "123456789"\n# [discord_alerts]',
        '[telegram]\nchat_id = "42"\n[discord_alerts]',
    )

    with pytest.raises(ConfigError, match="not both"):
        load_setup(path)


def test_account_key_names_are_plain_capitals():
    assert broker_key_names("live-small_2") == (
        "COPYTRADING_ALPACA_LIVE_SMALL_2_KEY",
        "COPYTRADING_ALPACA_LIVE_SMALL_2_SECRET",
    )
