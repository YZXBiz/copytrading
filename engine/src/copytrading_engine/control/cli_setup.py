"""`copytrading setup …`: read and change the app's setup, the draft Connections edits.

Keys, tokens and secrets are read only from standard input (`--secret-stdin`) or a file
(`--from-file PATH`), never from an argument or the environment, and nothing here prints one.
"""

import argparse
import getpass
import os
import stat
from collections.abc import Callable
from typing import Final, TextIO, assert_never, get_args

from pydantic import SecretStr, ValidationError

from copytrading_engine.control import wire

# How long `setup apply` waits for the app: every connection check, a pause when copying runs,
# and the start.
APPLY_TIMEOUT_SECONDS: Final = 300.0
MAX_SECRET_FILE_BYTES: Final = 64 * 1024
SWITCHES: Final = ("extended_hours", "overnight", "copy_exits", "approve_orders")
# What an account does after a restart, in the account sheet's words, and the setup's value.
AFTER_RESTART: Final[dict[str, wire.RecoveryPreference]] = {
    "wait-for-me": "manual",
    "carry-on": "automatic",
}
AFTER_RESTART_WORDS: Final[dict[wire.RecoveryPreference, str]] = {
    "manual": "Wait for me",
    "automatic": "Carry on by itself",
}

type Prompt = Callable[[str], str]

SERVER_REFUSAL: Final = (
    "`copytrading setup` changes the CopyTrading app's setup, and only the app may receive "
    "keys. The CopyTrading answering here is a server, which is set up in copytrading.toml."
)


def reads_secret(args: argparse.Namespace) -> bool:
    """The command reads a key or a setup file, so it first checks the app is answering."""
    return args.command == "setup" and (
        bool(getattr(args, "secret_stdin", False))
        or getattr(args, "from_file", None) is not None
        or args.action == "import"
    )


def add_setup_parser(commands: argparse._SubParsersAction, output: argparse.ArgumentParser) -> None:
    secret = argparse.ArgumentParser(add_help=False)
    source = secret.add_mutually_exclusive_group()
    source.add_argument(
        "--secret-stdin",
        action="store_true",
        help="read the key from standard input (asked for without echo at a terminal)",
    )
    source.add_argument("--from-file", metavar="PATH", help="read the key from a file")
    limits = argparse.ArgumentParser(add_help=False)
    for field in wire.LIMIT_FIELDS:
        limits.add_argument(
            f"--{field.replace('_', '-')}",
            dest=field,
            metavar="VALUE",
            help="true or false" if field in SWITCHES else "a number",
        )

    setup = commands.add_parser(
        "setup",
        help="read and change the setup: Discord, model, accounts, gurus, alerts",
        description="Change the setup Connections shows. Edits wait in the app's unsaved setup "
        "until `setup apply` checks every connection, saves, and starts copying with it. "
        "Keys are read from standard input or a file, never from an argument.",
    )
    actions = setup.add_subparsers(dest="action", required=True)
    actions.add_parser("show", parents=[output], help="the setup; keys only as saved or missing")

    discord = actions.add_parser(
        "discord",
        parents=[output, secret],
        help="Discord channels, authors, and token (--secret-stdin or --from-file)",
    )
    discord.add_argument("--channels", metavar="IDS", help="channel IDs, comma-separated")
    discord.add_argument(
        "--authors", metavar="IDS", help='author IDs, comma-separated; "" copies every author'
    )

    model = actions.add_parser(
        "model",
        parents=[output, secret],
        help="the model service, model, and API key (--secret-stdin or --from-file)",
    )
    model.add_argument("--service", choices=_choices(wire.ModelService))
    model.add_argument("--model", metavar="NAME")
    model.add_argument(
        "--base-url", metavar="URL", help='for ollama and openai_compatible; "" clears it'
    )

    account = actions.add_parser("account", help="Alpaca accounts, their keys and limits")
    account_actions = account.add_subparsers(dest="item_action", required=True)
    for verb, words in (("add", "a new account"), ("edit", "an account")):
        command = account_actions.add_parser(
            verb,
            parents=[output, secret, limits],
            help=f"{words}: environment, keys (key ID then secret, one per line), limits",
        )
        command.add_argument("account_id", metavar="NAME")
        command.add_argument("--environment", choices=("paper", "live"))
        command.add_argument(
            "--after-restart",
            choices=tuple(AFTER_RESTART),
            help="after CopyTrading restarts, wait for your Start Copying (wait-for-me, the "
            "default) or carry on by itself (carry-on)",
        )
        if verb == "edit":
            command.add_argument("--rename", metavar="NAME")
    account_actions.add_parser("remove", parents=[output], help="remove an account").add_argument(
        "account_id", metavar="NAME"
    )

    guru = actions.add_parser("guru", help="gurus: who is copied, from where, into which account")
    guru_actions = guru.add_subparsers(dest="item_action", required=True)
    for verb, words in (("add", "a new guru"), ("edit", "a guru, by name or ID")):
        command = guru_actions.add_parser(verb, parents=[output], help=words)
        command.add_argument("guru", metavar="NAME" if verb == "add" else "GURU")
        if verb == "edit":
            command.add_argument("--rename", metavar="NAME")
        command.add_argument(
            "--channel", metavar="ID", help='channel ID; "" follows the first source channel'
        )
        command.add_argument("--author", metavar="ID", help='author ID; "" copies every author')
        command.add_argument("--account", metavar="NAME", help="the one account they copy into")
        command.add_argument(
            "--full-position",
            metavar="USD",
            help="the guru's whole position in dollars: a 1/6 call buys a sixth of it; until set, "
            "the account's maximum per stock",
        )
        command.add_argument("--playbook-file", metavar="PATH", help="how this guru writes")
        command.add_argument(
            "--repeat-window",
            metavar="MINUTES",
            type=int,
            help="skip the same call again within this many minutes; 0 copies every post",
        )
    guru_actions.add_parser("remove", parents=[output], help="remove a guru").add_argument(
        "guru", metavar="GURU"
    )

    alerts = actions.add_parser(
        "alerts",
        parents=[output, secret],
        help="alerts by Telegram or Discord, and their token (--secret-stdin or --from-file)",
    )
    switch = alerts.add_mutually_exclusive_group()
    switch.add_argument("--on", dest="enabled", action="store_const", const=True)
    switch.add_argument("--off", dest="enabled", action="store_const", const=False)
    alerts.add_argument("--service", choices=("telegram", "discord"))
    alerts.add_argument("--chat-id", metavar="ID", help="Telegram's chat ID")

    imported = actions.add_parser(
        "import",
        parents=[output],
        help="fill the setup from a file in Import Setup's label format, or from a setup "
        "CopyTrading saved (one saved by an earlier version is upgraded first)",
    )
    imported.add_argument("file", metavar="FILE")

    apply = actions.add_parser(
        "apply",
        parents=[output],
        help="check every connection, save, and start copying with the setup",
    )
    apply.add_argument(
        "--start",
        action="store_true",
        help="also start copying if it is paused or has never started (live accounts wait for "
        "the owner's approval and Touch ID)",
    )
    apply.add_argument("--timeout", type=float, default=APPLY_TIMEOUT_SECONDS)
    actions.add_parser("discard", parents=[output], help="drop the unsaved changes")


def _choices(alias: object) -> tuple[str, ...]:
    return get_args(getattr(alias, "__value__", alias))


def no_answer(args: argparse.Namespace, seconds: object) -> str:
    """What to do when a request was sent and no answer came: its outcome is unknown."""
    waited = f" within {seconds:g} seconds" if isinstance(seconds, int | float) else ""
    if args.command == "setup" and args.action == "apply":
        return (
            f"CopyTrading didn't answer{waited}, so whether the setup was applied is not known; "
            "it may still be checking. Run `copytrading setup show`: no unsaved changes means it "
            "was saved, and it shows whether copying runs. Running `copytrading setup apply` "
            "again is safe: the same setup is never saved or started twice."
        )
    return (
        f"CopyTrading didn't answer{waited}, so whether the request took effect is not known. "
        "Check with `copytrading status` before trying again."
    )


def timeout_for(args: argparse.Namespace) -> float | None:
    """`setup apply` waits for the app's checks and start; everything else uses the default."""
    if args.command == "setup" and args.action == "apply":
        return args.timeout
    return None


def setup_request(
    args: argparse.Namespace,
    request_id: str,
    stdin: TextIO,
    prompt: Prompt = getpass.getpass,
) -> wire.Request:
    """Translate `setup …` arguments into one contract request, reading any key they name."""
    try:
        return _request(args, request_id, stdin, prompt)
    except ValidationError as error:
        # Errors hide their input, so no key can appear here; name the fields only.
        problems = "; ".join(
            f"{'.'.join(str(part) for part in item['loc']) or 'request'}: {item['msg']}"
            for item in error.errors(include_input=False, include_url=False)
        )
        raise ValueError(problems) from None


def _request(
    args: argparse.Namespace, request_id: str, stdin: TextIO, prompt: Prompt
) -> wire.Request:
    match args.action, getattr(args, "item_action", None):
        case "show", _:
            return wire.GetSetup(request_id=request_id)
        case "discord", _:
            token = _one_secret(args, stdin, prompt, "Discord token")
            return wire.EditSetupDiscord(
                request_id=request_id,
                channel_ids=_ids(args.channels),
                author_ids=_ids(args.authors),
                token=token,
            )
        case "model", _:
            key = _one_secret(args, stdin, prompt, "Model API key")
            return wire.EditSetupModel(
                request_id=request_id,
                service=args.service,
                model=args.model,
                base_url=args.base_url,
                key=key,
            )
        case "account", "add" | "edit" as verb:
            keys = _secrets(args, stdin, prompt, ("Alpaca API key ID", "Alpaca secret key"))
            key, secret = (keys[0], keys[1]) if keys else (None, None)
            return wire.EditSetupAccount(
                request_id=request_id,
                action=verb,
                account_id=args.account_id,
                rename=getattr(args, "rename", None),
                environment=args.environment,
                key=key,
                secret=secret,
                limits=tuple(
                    wire.LimitChange(field=field, value=str(getattr(args, field)))
                    for field in wire.LIMIT_FIELDS
                    if getattr(args, field) is not None
                ),
                recovery_preference=(
                    None if args.after_restart is None else AFTER_RESTART[args.after_restart]
                ),
            )
        case "account", "remove":
            return wire.EditSetupAccount(
                request_id=request_id, action="remove", account_id=args.account_id
            )
        case "guru", "add" | "edit" as verb:
            return wire.EditSetupGuru(
                request_id=request_id,
                action=verb,
                guru=args.guru,
                rename=getattr(args, "rename", None),
                channel_id=args.channel,
                author_id=args.author,
                account_id=args.account,
                full_position_usd=args.full_position,
                playbook=None if args.playbook_file is None else _text(args.playbook_file),
                repeat_window_minutes=args.repeat_window,
            )
        case "guru", "remove":
            return wire.EditSetupGuru(request_id=request_id, action="remove", guru=args.guru)
        case "alerts", _:
            token = _one_secret(args, stdin, prompt, "Alert token or webhook URL")
            return wire.EditSetupAlerts(
                request_id=request_id,
                enabled=args.enabled,
                service=args.service,
                chat_id=args.chat_id,
                token=token,
            )
        case "import", _:
            return wire.ImportSetup(request_id=request_id, text=SecretStr(_text(args.file)))
        case "apply", _:
            return wire.ApplySetup(request_id=request_id, start=args.start)
        case "discard", _:
            return wire.DiscardSetup(request_id=request_id)
        case action, item:
            raise ValueError(f"Unsupported command: setup {action} {item or ''}".strip())


def _ids(value: str | None) -> tuple[str, ...] | None:
    """Comma-separated IDs, as Connections takes them; full-width commas too."""
    if value is None:
        return None
    return tuple(part.strip() for part in value.replace("\uff0c", ",").split(",") if part.strip())


def _text(path: str) -> str:
    """A small regular file's text. It is opened once and read at most one byte past the limit,
    so a pipe, a device, or a file still growing is refused rather than read forever."""
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except FileNotFoundError:
        raise ValueError(f"{path} does not exist") from None
    except OSError as error:
        raise ValueError(f"{path} cannot be read ({error.strerror})") from None
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError(f"{path} is not a regular file")
        data = b""
        while len(data) <= MAX_SECRET_FILE_BYTES:
            chunk = os.read(descriptor, MAX_SECRET_FILE_BYTES + 1 - len(data))
            if not chunk:
                break
            data += chunk
    except OSError as error:
        raise ValueError(f"{path} cannot be read ({error.strerror})") from None
    finally:
        os.close(descriptor)
    if len(data) > MAX_SECRET_FILE_BYTES:
        raise ValueError(f"{path} is larger than a setup file can be (64 KB)")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise ValueError(f"{path} is not a text file") from None


def _one_secret(
    args: argparse.Namespace, stdin: TextIO, prompt: Prompt, name: str
) -> SecretStr | None:
    values = _secrets(args, stdin, prompt, (name,))
    return values[0] if values else None


def _secrets(
    args: argparse.Namespace, stdin: TextIO, prompt: Prompt, names: tuple[str, ...]
) -> tuple[SecretStr, ...] | None:
    """The keys a command takes, one per line, from stdin or a file; None when it takes none."""
    if args.from_file is not None:
        lines = _text(args.from_file).splitlines()
        where = args.from_file
    elif args.secret_stdin:
        if stdin.isatty():
            return tuple(SecretStr(_typed(prompt, name)) for name in names)
        lines = stdin.read(MAX_SECRET_FILE_BYTES + 1).splitlines()
        where = "standard input"
    else:
        return None
    values = [line.strip() for line in lines if line.strip()]
    if len(values) != len(names):
        expected = " and ".join(names) if len(names) > 1 else names[0]
        layout = ", one per line, in that order" if len(names) > 1 else " alone on one line"
        raise ValueError(f"{where} must hold the {expected}{layout}")
    return tuple(SecretStr(value) for value in values)


def _typed(prompt: Prompt, name: str) -> str:
    value = prompt(f"{name}: ").strip()
    if not value:
        raise ValueError(f"No {name} was typed")
    return value


# Text output


def setup_exit_code(result: wire.SetupApplied) -> int:
    """0 once the setup took effect or had nothing to apply, 6 when it did not."""
    return 0 if result.status in ("applied", "unchanged") else 6


def _key(state: wire.KeyState) -> str:
    match state:
        case "saved":
            return "saved"
        case "missing":
            return "missing"
        case "entered":
            return "entered, not saved yet"
        case "not_needed":
            return "not needed"
        case _:
            assert_never(state)


def _check(check: wire.SetupCheckView | None) -> str:
    if check is None:
        return ""
    match check.state:
        case "passed":
            return "  [connected]"
        case "not_configured":
            return "  [not set up]"
        case "failed":
            return "  [needs attention]"
        case _:
            assert_never(check.state)


def _problem(check: wire.SetupCheckView | None) -> list[str]:
    if check is None or check.state != "failed":
        return []
    return [f"              ! {check.message or check.reason or 'the check failed'}"]


def _ids_text(values: tuple[str, ...], empty: str) -> str:
    return ", ".join(values) if values else empty


def _dollars(value: str | None) -> str:
    return "—" if not value else f"${value}"


def _limit(change: wire.LimitChange) -> str:
    return f"{change.field.replace('_', ' ')} {change.value}"


def render_setup(setup: wire.SetupView) -> str:
    if not setup.saved:
        state = "not saved yet"
    elif setup.unsaved_changes:
        state = "saved, with unsaved changes"
    else:
        state = "saved"
    lines = [f"Setup       {state}; {wire.COPYING_WORDS[setup.copying]}"]
    discord = setup.discord
    lines.append(
        f"Discord     channels {_ids_text(discord.channel_ids, 'none')}; "
        f"authors {_ids_text(discord.author_ids, 'any')}; token {_key(discord.token)}"
        + _check(discord.check)
    )
    lines += _problem(discord.check)
    model = setup.model
    lines.append(
        f"Model       {model.service} {model.model or '(no model)'}"
        + (f" at {model.base_url}" if model.base_url else "")
        + f"; key {_key(model.key)}"
        + _check(model.check)
    )
    lines += _problem(model.check)
    for account in setup.accounts:
        lines.append(
            f"Account     {account.account_id} ({account.environment}); keys {_key(account.keys)}; "
            f"after a restart {AFTER_RESTART_WORDS[account.recovery_preference]}"
            + _check(account.check)
        )
        lines += _problem(account.check)
        lines.append("              " + ", ".join(_limit(item) for item in account.limits))
    if not setup.accounts:
        lines.append("Account     none")
    for guru in setup.gurus:
        lines.append(
            f"Guru        {guru.name} ({guru.guru_id or 'no ID until they have a channel'}); "
            f"channel {guru.channel_id or '—'}, "
            f"author {guru.author_id or 'any'}, account {guru.account_id or 'none'}, "
            f"full position {_dollars(guru.full_position_usd)}, "
            + (
                f"skips re-posts within {guru.repeat_window_minutes} min"
                if guru.repeat_window_minutes
                else "copies every post"
            )
            + f", playbook {guru.playbook_characters} characters"
        )
    if not setup.gurus:
        lines.append("Guru        none")
    alerts = setup.alerts
    if alerts.enabled:
        lines.append(
            f"Alerts      {alerts.service}"
            + (f" chat {alerts.chat_id}" if alerts.chat_id else "")
            + f"; token {_key(alerts.token)}"
            + _check(alerts.check)
        )
        lines += _problem(alerts.check)
    else:
        lines.append("Alerts      off")
    if setup.unsaved_changes or not setup.saved:
        lines.append("Run `copytrading setup apply` to check every connection, save, and start.")
    return "\n".join(lines)


def render_imported(result: wire.SetupImported) -> str:
    lines = ["Filled from the file: " + (", ".join(result.filled) or "nothing")]
    if result.missing:
        lines.append("Still needed: " + ", ".join(result.missing))
    lines.append(render_setup(result.setup))
    return "\n".join(lines)


def render_applied(result: wire.SetupApplied) -> str:
    match result.status:
        case "applied":
            head = "Applied: the setup is saved, and copying uses it."
        case "unchanged":
            head = "Nothing to apply: the saved setup is already the current one."
        case "failed_checks":
            head = "Not applied: some connections need attention. Nothing was saved."
        case "failed":
            head = "Not applied."
        case _:
            assert_never(result.status)
    lines = [head]
    if result.message and result.message not in head:
        lines.append(result.message)
    for check in result.checks:
        name = check.subject or check.connection
        match check.state:
            case "passed":
                lines.append(f"  ok      {name}")
            case "not_configured":
                lines.append(f"  -       {name}: not set up")
            case "failed":
                lines.append(f"  failed  {check.message or f'{name}: {check.reason}'}")
    return "\n".join(lines)


def describe_apply_proposal(subject: wire.ApplySetupSubject) -> str:
    parts = [
        (f"makes {', '.join(subject.made_live)} live" if subject.made_live else ""),
        (f"saves new keys for {', '.join(subject.new_live_keys)}" if subject.new_live_keys else ""),
        (f"changes {', '.join(subject.changed_live)}" if subject.changed_live else ""),
        (f"copies into live {', '.join(subject.starts_live)}" if subject.starts_live else ""),
    ]
    detail = "; ".join(part for part in parts if part)
    return "apply the setup" + (f" ({detail})" if detail else "")
