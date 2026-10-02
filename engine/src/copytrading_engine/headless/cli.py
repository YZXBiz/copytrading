"""copytrading-server: run the CopyTrading engine without the Mac app.

This module is the command line only: it parses arguments, asks the server or the engine,
and prints the typed answers. Formatting lives here and nowhere else.
"""

import argparse
import asyncio
import datetime as dt
import sys
from importlib import resources
from pathlib import Path
from typing import TextIO

from pydantic import ValidationError

from copytrading_engine.control.client import server_state_root
from copytrading_engine.control.wire import (
    ManualOrderSubject,
    ProposalSubject,
    ProposalView,
    RecoverySubject,
    ResumeAccountSubject,
)
from copytrading_engine.headless.config import ConfigError, load_secrets, load_setup
from copytrading_engine.headless.engine import (
    EngineRefused,
    ExampleReview,
    SetupNotReady,
    SetupReport,
)
from copytrading_engine.headless.owner import (
    Approve,
    AskStatus,
    CopyingStatus,
    EntriesChanged,
    ListProposals,
    OwnerAnswer,
    OwnerRequest,
    Pause,
    ProposalChanged,
    Proposals,
    Reject,
    Resume,
    SetEntries,
)
from copytrading_engine.headless.server import ServerPaths, check_setup, run_server
from copytrading_engine.headless.sockets import (
    OwnerRequestFailed,
    ServerNotRunning,
    UnsafeStateDirectory,
    ask_owner_socket,
)

DEFAULT_CONFIG = Path("copytrading.toml")

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_USAGE = 2
EXIT_NOT_RUNNING = 3


class UnexpectedAnswer(Exception):
    """The server answered with something other than what this command asked for."""


def main(
    argv: list[str] | None = None, *, out: TextIO = sys.stdout, err: TextIO = sys.stderr
) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_help(out)
        return EXIT_USAGE
    state = Path(args.state_dir).expanduser().resolve() if args.state_dir else server_state_root()
    paths = ServerPaths(state)
    try:
        return _COMMANDS[args.command](args, paths, out, err)
    except ConfigError as problem:
        for line in problem.problems:
            print(f"✗ {line}", file=err)
        return EXIT_USAGE
    except ValidationError as problem:
        # An argument outside the owner contract, such as "my account" for an account id.
        for item in problem.errors(include_url=False):
            print(f"✗ {'.'.join(map(str, item['loc']))}: {item['msg']}", file=err)
        return EXIT_USAGE
    except ServerNotRunning:
        print(
            f"No CopyTrading server is running with state in {paths.root}. "
            "Start one with `copytrading-server run`.",
            file=err,
        )
        return EXIT_NOT_RUNNING
    except (OwnerRequestFailed, EngineRefused, UnsafeStateDirectory, UnexpectedAnswer) as problem:
        print(f"✗ {problem}", file=err)
        return EXIT_FAILED
    except KeyboardInterrupt:
        return EXIT_FAILED


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="copytrading-server",
        description="Run the CopyTrading engine without the Mac app: on a Mac, a Linux server, "
        "or in Docker. Setup comes from copytrading.toml; keys come from the environment.",
    )
    parser.add_argument(
        "--state-dir",
        help=f"where the server keeps its data (default: {server_state_root()})",
    )
    commands = parser.add_subparsers(dest="command", metavar="COMMAND")

    init = commands.add_parser("init", help="write a commented copytrading.toml to start from")
    init.add_argument("path", nargs="?", default=str(DEFAULT_CONFIG))

    for name, text in (
        ("check", "check the file, the keys, and every connection; nothing is saved or traded"),
        ("run", "start copying and keep running until Ctrl-C or SIGTERM"),
    ):
        command = commands.add_parser(name, help=text)
        command.add_argument("--config", "-c", default=str(DEFAULT_CONFIG))

    commands.add_parser("status", help="show whether copying runs and each account's state")
    entries = commands.add_parser("entries", help="turn new buys on or off for an account")
    entries.add_argument("switch", choices=("enable", "disable"))
    entries.add_argument("account")
    commands.add_parser("pause", help="pause copying")
    commands.add_parser("resume", help="check the setup again and resume copying")
    commands.add_parser("proposals", help="list what agents asked you to approve")
    approve = commands.add_parser("approve", help="approve a proposal after showing what it does")
    approve.add_argument("proposal_id")
    approve.add_argument("--yes", "-y", action="store_true", help="do not ask to confirm")
    reject = commands.add_parser("reject", help="reject a proposal")
    reject.add_argument("proposal_id")
    return parser


def _init(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    target = Path(args.path)
    if target.exists():
        print(f"✗ {target} already exists; nothing was changed.", file=err)
        return EXIT_FAILED
    template = resources.files("copytrading_engine.headless").joinpath("template.toml")
    target.write_text(template.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"Wrote {target}. Edit it, set the keys it lists, then run:", file=out)
    print(f"  copytrading-server check --config {target}", file=out)
    return EXIT_OK


def _check(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    setup = load_setup(Path(args.config))
    secrets = load_secrets(setup.configuration)
    print("Checking Discord, the model, and each account…", file=out)
    result = asyncio.run(check_setup(setup, secrets))
    _print_report(result.report, out)
    for review in result.reviews:
        _print_review(review, out)
    print(
        "✓ Ready. Start with `copytrading-server run`."
        if result.passed
        else "✗ Not ready. Fix the lines marked ✗ and check again.",
        file=out,
    )
    return EXIT_OK if result.passed else EXIT_FAILED


def _run(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    setup = load_setup(Path(args.config))
    secrets = load_secrets(setup.configuration)

    def say(line: str) -> None:
        stamp = dt.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{stamp}  {line}", file=out, flush=True)

    try:
        asyncio.run(run_server(setup, secrets, paths, say=say))
    except SetupNotReady as not_ready:
        _print_report(not_ready.report, out)
        print("✗ The setup check did not pass, so copying did not start.", file=err)
        return EXIT_FAILED
    return EXIT_OK


def _status(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    status = _ask(paths, AskStatus(), CopyingStatus)
    print(f"Copying     {status.state}", file=out)
    print(f"Discord     {'connected' if status.source_connected else 'not connected'}", file=out)
    print(f"Model       {'ready' if status.model_ready else 'not ready'}", file=out)
    print(f"Handled     {status.processed_signals} post(s)", file=out)
    if status.error_code:
        print(f"Problem     {_plain(status.error_code)}", file=out)
    for account in status.accounts:
        entries = "entries on" if account.entry_permission == "enabled" else "entries off"
        print(f"Account     {account.id}  {account.state}, {entries}", file=out)
    return EXIT_OK


def _entries(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    request = SetEntries(account=args.account, enabled=args.switch == "enable")
    changed = _ask(paths, request, EntriesChanged)
    print(f"{changed.account_id}: entries {changed.entry_permission}.", file=out)
    return EXIT_OK


def _pause(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    print(f"Copying {_ask(paths, Pause(), CopyingStatus).state}.", file=out)
    return EXIT_OK


def _resume(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    print(f"Copying {_ask(paths, Resume(), CopyingStatus).state}.", file=out)
    return EXIT_OK


def _proposals(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    pending = _pending(paths)
    if not pending:
        print("Nothing is waiting for your approval.", file=out)
    for proposal in pending.values():
        print(
            f"{proposal.proposal_id}  {_describe(proposal.subject)}  "
            f"(expires {proposal.expires_at:%H:%M})",
            file=out,
        )
    return EXIT_OK


def _approve(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    proposal = _pending(paths).get(args.proposal_id)
    if proposal is None:
        print(f"✗ {args.proposal_id} is not waiting for approval.", file=err)
        return EXIT_FAILED
    print(f"Approve: {_describe(proposal.subject)}?", file=out)
    if not args.yes:
        out.flush()
        if input("Type yes to approve: ").strip().lower() != "yes":
            print("Not approved.", file=out)
            return EXIT_FAILED
    # The digest pins the approval to exactly what was shown above.
    request = Approve(proposal_id=proposal.proposal_id, digest=proposal.digest)
    changed = _ask(paths, request, ProposalChanged).proposal
    print(f"{changed.proposal_id}: {changed.state}.", file=out)
    return EXIT_OK if changed.state in {"running", "succeeded"} else EXIT_FAILED


def _reject(args: argparse.Namespace, paths: ServerPaths, out: TextIO, err: TextIO) -> int:
    changed = _ask(paths, Reject(proposal_id=args.proposal_id), ProposalChanged).proposal
    print(f"{changed.proposal_id}: {changed.state}.", file=out)
    return EXIT_OK


_COMMANDS = {
    "init": _init,
    "check": _check,
    "run": _run,
    "status": _status,
    "entries": _entries,
    "pause": _pause,
    "resume": _resume,
    "proposals": _proposals,
    "approve": _approve,
    "reject": _reject,
}


def _ask[T: OwnerAnswer](paths: ServerPaths, request: OwnerRequest, expected: type[T]) -> T:
    answer = asyncio.run(ask_owner_socket(paths.owner_socket, request))
    if not isinstance(answer, expected):
        raise UnexpectedAnswer(f"the server answered {type(answer).__name__}")
    return answer


def _pending(paths: ServerPaths) -> dict[str, ProposalView]:
    proposals = _ask(paths, ListProposals(), Proposals).items
    return {item.proposal_id: item for item in proposals if item.state == "pending"}


def _print_report(report: SetupReport, out: TextIO) -> None:
    for check in report.checks:
        subject = f" {check.subject}" if check.subject else ""
        environment = f" ({check.environment})" if check.environment else ""
        reason = f": {_plain(check.reason_code)}" if check.reason_code else ""
        print(
            f"{'✓' if check.passed else '✗'} {_plain(check.name)}{subject}{environment} — "
            f"{_plain(check.state)}{reason}",
            file=out,
        )


def _print_review(review: ExampleReview, out: TextIO) -> None:
    for example in review.examples:
        reasons = ", ".join(_plain(reason) for reason in example.review_reasons)
        print(
            f"{'✓' if example.matches else '✗'} {review.guru_id} example "
            f"{example.example_index + 1}: expected {example.expected_action} "
            f"{example.expected_symbol}" + (f" — {reasons}" if reasons else ""),
            file=out,
        )


def _describe(subject: ProposalSubject) -> str:
    match subject:
        case ResumeAccountSubject(account_id=account_id):
            return f"turn entries back on in {account_id}"
        case RecoverySubject(account_id=account_id, preference=preference):
            return f"set recovery in {account_id} to {_plain(preference)}"
        case ManualOrderSubject():
            price = f" at ${subject.limit_price}" if subject.limit_price else " at market"
            return (
                f"{subject.side} {subject.quantity} {subject.symbol}{price} "
                f"in {subject.account_id} ({subject.environment})"
            )


def _plain(code: str) -> str:
    return code.replace("_", " ")
