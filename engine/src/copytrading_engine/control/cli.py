"""`copytrading`: check and steer a running CopyTrading from a terminal or an agent."""

import argparse
import asyncio
import datetime as dt
import json
import sys
from collections.abc import Callable, Sequence
from decimal import Decimal
from fractions import Fraction
from typing import Final, TextIO, assert_never

from copytrading_engine.control import cli_setup, wire
from copytrading_engine.control.client import (
    OLDER_CLIENT,
    AppUnavailable,
    ControlClient,
    NoAnswer,
    ProtocolMismatch,
    RequestTooLarge,
    UnsafeSocket,
    is_server_socket,
    new_request_id,
    socket_path,
)

WAIT_INTERVAL_SECONDS: Final = 1.0

EXIT_OK: Final = 0
EXIT_FAILURE: Final = 1
EXIT_USAGE: Final = 2
EXIT_APP_UNAVAILABLE: Final = 3
EXIT_LOCKED: Final = 4
EXIT_REFUSED: Final = 5
EXIT_NOT_COMPLETED: Final = 6
EXIT_PROPOSAL_CLOSED: Final = 7
EXIT_APPROVAL_PENDING: Final = 10


def error_exit_code(code: wire.ErrorCode) -> int:
    match code:
        case "access_off":
            return EXIT_APP_UNAVAILABLE
        case "locked":
            return EXIT_LOCKED
        case "invalid_request":
            return EXIT_USAGE
        case "forbidden" | "busy" | "cooling_down" | "proposal_limit" | "conflict":
            return EXIT_REFUSED
        case "not_found" | "unavailable":
            return EXIT_NOT_COMPLETED
        case "expired" | "rejected":
            return EXIT_PROPOSAL_CLOSED
        case _:
            assert_never(code)


def proposal_exit_code(proposal: wire.ProposalView) -> int:
    match proposal.state:
        case "pending" | "running":
            return EXIT_APPROVAL_PENDING
        case "succeeded":
            return EXIT_OK
        case "failed" | "outcome_unknown":
            return EXIT_NOT_COMPLETED
        case "rejected" | "expired" | "discarded":
            return EXIT_PROPOSAL_CLOSED
        case _:
            assert_never(proposal.state)


def _parser() -> argparse.ArgumentParser:
    output = argparse.ArgumentParser(add_help=False)
    output.add_argument("--json", action="store_true", help="print the raw contract response")
    paged = argparse.ArgumentParser(add_help=False)
    paged.add_argument("--limit", type=int, default=50, help="items per page (1-100)")

    parser = argparse.ArgumentParser(
        prog="copytrading",
        description="Check, steer and set up a running CopyTrading. Actions that can trade, "
        "and setup that touches a live account, only create proposals; the owner approves "
        "them in the app.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", parents=[output], help="engine, processing and accounts")

    accounts = commands.add_parser("accounts", parents=[output, paged], help="accounts")
    accounts.add_argument("--before", dest="before_account_id")
    account_actions = accounts.add_subparsers(dest="action")
    account_actions.add_parser(
        "pause", parents=[output], help="stop copying into an account"
    ).add_argument("account_id")
    account_actions.add_parser(
        "resume", parents=[output], help="propose copying into an account again"
    ).add_argument("account_id")
    recovery = account_actions.add_parser(
        "recovery", parents=[output], help="propose a recovery preference"
    )
    recovery.add_argument("account_id")
    recovery.add_argument("preference", choices=("manual", "automatic"))

    limits = account_actions.add_parser(
        "limits",
        parents=[output],
        help="propose new limits and settings for an account (the owner approves in the app)",
    )
    limits.add_argument("account_id")
    for field in wire.LIMIT_FIELDS:
        limits.add_argument(
            f"--{field.replace('_', '-')}",
            dest=field,
            metavar="VALUE",
            help="true or false" if field in _SWITCHES else "a number",
        )

    activity = commands.add_parser("activity", parents=[output, paged], help="source activity")
    activity.add_argument("--before", dest="before_seq", type=int)
    events = commands.add_parser("events", parents=[output, paged], help="account events")
    events.add_argument("account_id")
    events.add_argument("--before", dest="before_seq", type=int)

    manual = commands.add_parser("manual", help="reviewed manual orders")
    manual_actions = manual.add_subparsers(dest="action", required=True)
    manual_list = manual_actions.add_parser("list", parents=[output, paged])
    manual_list.add_argument("account_id")
    manual_list.add_argument("source_id")
    manual_list.add_argument("--before", dest="before_command_id")
    manual_show = manual_actions.add_parser("show", parents=[output])
    manual_show.add_argument("account_id")
    manual_show.add_argument("command_id")
    manual_preview = manual_actions.add_parser("preview", parents=[output])
    manual_preview.add_argument("account_id")
    manual_preview.add_argument("--correction", dest="correction_id", required=True)
    manual_preview.add_argument("--instruction", dest="instruction_index", type=int, required=True)
    manual_confirm = manual_actions.add_parser(
        "confirm", parents=[output], help="propose confirming a previewed order"
    )
    manual_confirm.add_argument("account_id")
    manual_confirm.add_argument("--preview", dest="preview_id", required=True)

    commands.add_parser(
        "start",
        parents=[output],
        help="propose starting copying with Start Copying's checks (approved in the app)",
    )
    commands.add_parser("pause", parents=[output], help="pause all processing")

    proposals = commands.add_parser("proposals", parents=[output], help="owner approvals")
    proposal_actions = proposals.add_subparsers(dest="action")
    proposal_actions.add_parser("show", parents=[output]).add_argument("proposal_id")
    wait = proposal_actions.add_parser("wait", parents=[output])
    wait.add_argument("proposal_id")
    wait.add_argument("--timeout", type=float, default=300.0)

    cli_setup.add_setup_parser(commands, output)

    commands.add_parser("schema", help="print the contract's JSON Schema")
    commands.add_parser("mcp", help="serve the same operations as an MCP stdio server")
    return parser


def request_for(args: argparse.Namespace, stdin: TextIO | None = None) -> wire.Request:
    """Translate parsed arguments into exactly one contract request."""
    request_id = new_request_id()
    if args.command == "setup":
        return cli_setup.setup_request(args, request_id, stdin or sys.stdin)
    match args.command, getattr(args, "action", None):
        case "status", _:
            return wire.GetStatus(request_id=request_id)
        case "accounts", None:
            return wire.ListAccounts(
                request_id=request_id, before_account_id=args.before_account_id, limit=args.limit
            )
        case "accounts", "pause":
            return wire.PauseAccount(request_id=request_id, account_id=args.account_id)
        case "accounts", "resume":
            return wire.ProposeResumeAccount(request_id=request_id, account_id=args.account_id)
        case "accounts", "recovery":
            return wire.ProposeRecoveryPreference(
                request_id=request_id, account_id=args.account_id, preference=args.preference
            )
        case "accounts", "limits":
            changes = tuple(
                wire.LimitChange(field=field, value=str(getattr(args, field)))
                for field in wire.LIMIT_FIELDS
                if getattr(args, field) is not None
            )
            if not changes:
                raise ValueError("Name at least one setting, such as --max-order-usd 300")
            return wire.ProposeSetAccountLimits(
                request_id=request_id, account_id=args.account_id, changes=changes
            )
        case "activity", _:
            return wire.ListActivity(
                request_id=request_id, before_seq=args.before_seq, limit=args.limit
            )
        case "events", _:
            return wire.ListAccountEvents(
                request_id=request_id,
                account_id=args.account_id,
                before_seq=args.before_seq,
                limit=args.limit,
            )
        case "manual", "list":
            return wire.ListManualCommands(
                request_id=request_id,
                account_id=args.account_id,
                source_id=args.source_id,
                before_command_id=args.before_command_id,
                limit=args.limit,
            )
        case "manual", "show":
            return wire.GetManualCommand(
                request_id=request_id, account_id=args.account_id, command_id=args.command_id
            )
        case "manual", "preview":
            return wire.PreviewManualOrder(
                request_id=request_id,
                account_id=args.account_id,
                correction_id=args.correction_id,
                instruction_index=args.instruction_index,
            )
        case "manual", "confirm":
            return wire.ProposeManualOrder(
                request_id=request_id, account_id=args.account_id, preview_id=args.preview_id
            )
        case "start", _:
            return wire.ProposeStartProcessing(request_id=request_id)
        case "pause", _:
            return wire.PauseProcessing(request_id=request_id)
        case "proposals", None:
            return wire.ListProposals(request_id=request_id)
        case "proposals", "show" | "wait":
            return wire.GetProposal(request_id=request_id, proposal_id=args.proposal_id)
        case command, action:
            raise ValueError(f"Unsupported command: {command} {action}")


def main(
    argv: Sequence[str] | None = None,
    *,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
    stdin: TextIO | None = None,
    client_factory: Callable[[], ControlClient] | None = None,
) -> int:
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    parser = _parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exit_request:
        return exit_request.code if isinstance(exit_request.code, int) else EXIT_USAGE
    if args.command == "schema":
        print(json.dumps(wire.json_schema(), indent=2, sort_keys=True), file=stdout)
        return EXIT_OK
    if args.command == "mcp":
        # Imported only here so ordinary commands never load the MCP SDK.
        from copytrading_engine.control.mcp_server import serve

        serve()
        return EXIT_OK
    if args.command == "setup" and client_factory is None and is_server_socket():
        print(cli_setup.SERVER_REFUSAL, file=stderr)
        return EXIT_APP_UNAVAILABLE
    # A command that reads a key first makes sure the app is the one answering (below).
    request: wire.Request | None = None
    if not cli_setup.reads_secret(args):
        try:
            request = request_for(args, stdin)
        except ValueError as error:
            print(f"Invalid arguments: {error}", file=stderr)
            return EXIT_USAGE
    timeout = cli_setup.timeout_for(args)
    client = (
        client_factory()
        if client_factory
        else ControlClient(socket_path())
        if timeout is None
        else ControlClient(socket_path(), timeout=timeout)
    )
    try:
        return asyncio.run(_execute(client, args, request, stdin, stdout, stderr))
    except RequestTooLarge as large:
        print(
            f"The request is too large ({large.args[0]:,} bytes): CopyTrading takes at most "
            f"{wire.MAX_LINE_BYTES // 1024} KB. For `setup import`, keep only the setup's lines "
            "in the file.",
            file=stderr,
        )
        return EXIT_USAGE
    except NoAnswer as silent:
        print(cli_setup.no_answer(args, silent.args[0] if silent.args else None), file=stderr)
        return EXIT_NOT_COMPLETED
    except AppUnavailable:
        print("CopyTrading is not running, or agent access is turned off.", file=stderr)
        return EXIT_APP_UNAVAILABLE
    except UnsafeSocket as unsafe:
        print(f"Refusing to use {unsafe}: it is not the app's private socket.", file=stderr)
        return EXIT_FAILURE
    except ProtocolMismatch as mismatch:
        if str(mismatch) == OLDER_CLIENT:
            print(f"CopyTrading answered with something new: {OLDER_CLIENT}.", file=stderr)
            return EXIT_FAILURE
        print(f"Unexpected answer from CopyTrading: {mismatch}", file=stderr)
        return EXIT_FAILURE


async def _execute(
    client: ControlClient,
    args: argparse.Namespace,
    request: wire.Request | None,
    stdin: TextIO | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    if request is None:
        # Keys go only to the Mac app: it must answer `get_setup` before any key is read.
        checked = await client.send(wire.GetSetup(request_id=new_request_id()))
        if checked.error is not None:
            print(checked.error.message, file=stderr)
            return error_exit_code(checked.error.code)
        if not isinstance(checked.ok, wire.SetupView):
            raise ProtocolMismatch("the socket did not answer as the CopyTrading app")
        try:
            request = request_for(args, stdin)
        except ValueError as error:
            print(f"Invalid arguments: {error}", file=stderr)
            return EXIT_USAGE
    response = await client.send(request)
    if args.command == "proposals" and args.action == "wait":
        response = await _wait(client, response, args.timeout)
    if args.json:
        print(response.model_dump_json(), file=stdout)
    if response.error is not None:
        if not args.json:
            print(response.error.message, file=stderr)
        return error_exit_code(response.error.code)
    result = response.ok
    if result is None:
        raise ProtocolMismatch("response has no result")
    if not args.json:
        print(render(result), file=stdout)
    if isinstance(result, wire.ProposalView):
        return proposal_exit_code(result)
    if isinstance(result, wire.SetupApplied):
        return cli_setup.setup_exit_code(result)
    return EXIT_OK


async def _wait(client: ControlClient, response: wire.Response, timeout: float) -> wire.Response:
    """Poll a proposal until the owner decides, it expires, or the wait times out."""
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while (
        isinstance(response.ok, wire.ProposalView)
        and response.ok.state in ("pending", "running")
        and loop.time() < deadline
    ):
        await asyncio.sleep(WAIT_INTERVAL_SECONDS)
        response = await client.send(
            wire.GetProposal(request_id=new_request_id(), proposal_id=response.ok.proposal_id)
        )
    return response


# Text output


_SWITCHES: Final = ("extended_hours", "overnight", "copy_exits", "approve_orders")


def _words(code: str | None) -> str:
    return "—" if code is None else code.replace("_", " ")


def _unavailable(reason: str) -> str:
    """Why an account could not be shown; an earlier version's history is kept, not broken."""
    if reason == "earlier_version":
        return "history kept from an earlier version of CopyTrading"
    return f"unavailable ({_words(reason)})"


def _copying(word: wire.CopyingWord, detail: str | None) -> str:
    """One of the app's five words, with the reason under it when there is one."""
    return wire.COPYING_WORDS[word] + (f" ({_words(detail)})" if detail else "")


_BUYS: dict[str, wire.CopyingWord] = {
    "enabled": "copying",
    "paused": "sells_only",
    "disabled": "not_started",
}


def _time(value: dt.datetime) -> str:
    return value.astimezone().strftime("%Y-%m-%d %H:%M:%S")


def _amount(value: Decimal | None) -> str:
    return "—" if value is None else f"{value.normalize():f}"


def _dollars(value: Decimal | None) -> str:
    """Dollars with cents, keeping any finer digits a price really has: $25.10, $121.385."""
    if value is None:
        return "—"
    exponent = value.normalize().as_tuple().exponent
    places = max(2, -exponent if isinstance(exponent, int) else 2)
    return f"${value:,.{places}f}"


def render(result: wire.Result) -> str:
    match result:
        case wire.StatusView():
            return _render_status(result)
        case wire.AccountsPage():
            return _render_accounts(result)
        case wire.ActivityPage():
            return _render_activity(result)
        case wire.AccountEventsPage():
            lines = [f"Events for {result.account_id}"]
            lines += [
                f"  #{item.sequence}  {_time(item.at)}  {_words(item.kind)}"
                + (f"  {_words(item.status)}" if item.status else "")
                + (f"  ({_words(item.reason)})" if item.reason else "")
                for item in result.items
            ]
            return "\n".join(lines + _next("--before", result.next_before_seq))
        case wire.ManualCommandsPage():
            lines = [f"Manual commands for {result.account_id}"]
            lines += [_render_command(item) for item in result.items]
            return "\n".join(lines + _next("--before", result.next_before_command_id))
        case wire.ManualCommand():
            return _render_command(result.command)
        case wire.ManualPreview():
            return _render_preview(result)
        case wire.ProposalView():
            return _render_proposal(result)
        case wire.ProposalsPage():
            if not result.items:
                return "No proposals."
            return "\n".join(_render_proposal(item) for item in result.items)
        case wire.ProcessingPaused():
            processing = result.processing
            return f"{_copying(processing.copying, processing.copying_detail)}."
        case wire.AccountControlView():
            word = _BUYS.get(result.entry_permission, "not_started")
            return f"{result.account_id}: {wire.COPYING_WORDS[word]}."
        case wire.SetupView():
            return cli_setup.render_setup(result)
        case wire.SetupImported():
            return cli_setup.render_imported(result)
        case wire.SetupApplied():
            return cli_setup.render_applied(result)
        case _:
            assert_never(result)


def _next(flag: str, value: object) -> list[str]:
    return [] if value is None else [f"More: {flag} {value}"]


def _render_status(status: wire.StatusView) -> str:
    processing = status.processing
    lines = [
        f"Engine      {_words(status.engine_state)}",
        f"Copying     {_copying(processing.copying, processing.copying_detail)}",
        f"Source      {'connected' if processing.source_connected else 'not connected'}",
        f"Model       {'ready' if processing.model_ready else 'not ready'}",
        f"Queued      {processing.pending_source} messages, {processing.pending_signals} signals",
    ]
    for account in status.accounts:
        lines.append(
            f"Account     {account.account_id}  "
            f"{_copying(account.copying, account.copying_detail)}, "
            f"after a restart {_words(account.recovery_preference)}"
        )
    return "\n".join(lines)


def _render_accounts(page: wire.AccountsPage) -> str:
    lines: list[str] = []
    for account in page.items:
        lines.append(
            f"{account.account_id} ({account.environment})  "
            f"{_copying(account.copying, account.copying_detail)}, "
            f"after a restart {_words(account.recovery_preference)}, "
            f"risk {_words(account.risk_status)}, exposure {_dollars(account.total_exposure_usd)}"
        )
        for position in account.positions:
            if not (position.owned_qty or position.external_qty or position.lots):
                continue  # a stock traded before and now at zero is history, not a position
            lines.append(
                f"  {position.symbol}  app {_amount(position.owned_qty)}, "
                f"external {_amount(position.external_qty)}"
            )
            lines += [
                f"    lot {lot.lot_id}  {_amount(lot.remaining_qty)} of "
                f"{_amount(lot.original_qty)} at {_dollars(lot.average_price)}"
                f"{f'  from {lot.guru_id}' if lot.guru_id else ''}"
                f"{f'  ({lot.source_id})' if lot.source_id else ''}"
                for lot in position.lots
            ]
        if account.ownership_incidents:
            lines.append(f"  {account.ownership_incidents} ownership incident(s) need review")
    lines += [f"{item.account_id}: {_unavailable(item.reason)}" for item in page.unavailable]
    return "\n".join(lines or ["No accounts."]) + "".join(
        "\n" + line for line in _next("--before", page.next_before_account_id)
    )


def _share(fraction: Decimal) -> str:
    """A share as the guru writes it: 1/6, not 16.666…%."""
    near = Fraction(fraction).limit_denominator(12)
    if abs(Decimal(near.numerator) / Decimal(near.denominator) - fraction) < Decimal("0.0001"):
        return f"{near.numerator}/{near.denominator}"
    return f"{(fraction * 100).quantize(Decimal('0.01')).normalize():f}%"


def _instruction(step: wire.InstructionItem) -> str:
    if step.action == "close":
        verb, size = "sell all", ""
    elif step.usd_amount is not None:
        verb, size = step.action, f"{_dollars(step.usd_amount)} of "
    else:
        verb = "buy" if step.action == "buy" else "sell"
        size = f"{_share(step.fraction)} of " if step.fraction is not None else ""
    price = _dollars(step.price) if step.price is not None else "the market"
    return f"{verb} {size}{step.symbol} at {price}"


def _destination(target: wire.DestinationView) -> str:
    """An account's outcome, and why any call in the post placed no order."""
    line = f"  → {target.account_id}: {_words(target.status)}"
    reasons = [
        f"call {index}: {_words(outcome)}"
        for index, outcome in enumerate(target.instruction_outcomes, 1)
        if outcome != "order_linked"
    ]
    return line + (f" ({'; '.join(reasons)})" if reasons else "")


def _render_activity(page: wire.ActivityPage) -> str:
    lines: list[str] = []
    for item in page.items:
        lines.append(
            f"#{item.sequence}  {_time(item.source_at)}  parse {_words(item.parse_status)}, "
            f"delivery {_words(item.delivery_status)}"
            + (f", {_words(item.decision)}" if item.decision else "")
        )
        lines.append("  Source text (untrusted):")
        lines += [f"  │ {text}" for text in item.untrusted_source_text.splitlines() or [""]]
        lines += [f"  Understood as: {_instruction(step)}" for step in item.understood_as]
        lines += [_destination(target) for target in item.destinations]
    lines += [
        f"Rejected {item.source_id} at {_time(item.rejected_at)}: {_words(item.reason)}"
        for item in page.rejected
    ]
    return "\n".join((lines or ["No activity."]) + _next("--before", page.next_before_seq))


def _render_command(command: wire.ManualCommandView) -> str:
    return (
        f"{command.command_id}  {_words(command.status)}  confirmed {_time(command.confirmed_at)}"
        + (f"  ({_words(command.reason)})" if command.reason else "")
    )


def _render_preview(preview: wire.ManualPreview) -> str:
    instruction = preview.instruction
    lines = [
        f"Preview {preview.preview_id} for {preview.account_id} ({preview.environment}), "
        f"expires {_time(preview.expires_at)}",
        f"  Instruction: {instruction.action} {instruction.symbol} at "
        + (_dollars(instruction.price) if instruction.price is not None else "the market"),
    ]
    if preview.plan is None:
        lines.append("  Blocked: " + ", ".join(_words(reason) for reason in preview.reasons))
    else:
        plan = preview.plan
        lines.append(
            f"  Order: {plan.side} {_amount(plan.quantity)} {plan.type}"
            + (f" at {_dollars(plan.limit_price)}" if plan.limit_price is not None else "")
            + f" ({_words(plan.session)} session)"
        )
        lines.append(
            f"  To ask the owner: copytrading manual confirm {preview.account_id} "
            f"--preview {preview.preview_id}"
        )
    lines += [
        f"  Check {_words(check.name)}: {check.status}"
        + (f" ({_words(check.reason)})" if check.reason else "")
        for check in preview.checks
    ]
    return "\n".join(lines)


def _render_proposal(proposal: wire.ProposalView) -> str:
    subject = proposal.subject
    match subject:
        case wire.ResumeAccountSubject():
            what = f"start copying into {subject.account_id}"
        case wire.RecoverySubject():
            what = f"set recovery for {subject.account_id} to {subject.preference}"
        case wire.StartProcessingSubject():
            what = "start copying"
        case wire.ApplySetupSubject():
            what = cli_setup.describe_apply_proposal(subject)
        case wire.LimitsSubject():
            what = f"change {subject.account_id}: " + ", ".join(
                f"{_words(change.field)} = {change.value}" for change in subject.changes
            )
        case wire.ManualOrderSubject():
            what = (
                f"{subject.side} {_amount(subject.quantity)} {subject.symbol} "
                f"({subject.order_type}"
                + (f" at {_dollars(subject.limit_price)}" if subject.limit_price else "")
                + f") in {subject.account_id} ({subject.environment})"
            )
    if proposal.state == "pending":
        return (
            f"Waiting for approval in CopyTrading: {what}. "
            f"Proposal {proposal.proposal_id}, expires {_time(proposal.expires_at)}."
        )
    outcome = proposal.outcome
    detail = f" ({_words(outcome.code)})" if outcome is not None and outcome.code else ""
    return f"Proposal {proposal.proposal_id} {_words(proposal.state)}{detail}: {what}."
