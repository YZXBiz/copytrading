"""Drive the real app window through the acceptance journeys in docs/acceptance.md.

The runner builds a debug bundle, launches it against a fresh temporary state root with the
debug-only authentication bypass, and drives it through Peekaboo's accessibility automation.
It never touches the real installation, its configuration, or its Keychain items.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import TracebackType
from typing import Any

from swift_paths import swift_bin_path

ROOT = Path(__file__).resolve().parents[2]
RELEASE_APP = ROOT / "dist/CopyTrading.app"
DEBUG_APP = ROOT / "dist/ui-test/CopyTrading Debug.app"
APP_NAME = "CopyTrading Debug"
BUNDLE_ID = "dev.copytrading.app.uitest"


ASSISTANT_ANSWER = "Copying is paused, so nothing is being copied right now."


class ScriptedModelServer(ThreadingHTTPServer):
    """A local OpenAI-compatible model that plays one scripted answer.

    The first chat-completions request calls the assistant's `get_status` tool; every later
    request answers in plain text. A request that asks for a stream gets server-sent chunks,
    anything else gets one JSON body, so it serves whichever form the engine's agent uses.
    """

    daemon_threads = True

    def __init__(self) -> None:
        super().__init__(("127.0.0.1", 0), _ScriptedModelHandler)
        self.requests: list[dict[str, Any]] = []
        self._lock = threading.Lock()
        self._thread = threading.Thread(target=self.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.server_address[1]}/v1"

    def __enter__(self) -> ScriptedModelServer:
        self._thread.start()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_val: BaseException | None,
        exc_tb: TracebackType | None,
    ) -> None:
        self.shutdown()
        self.server_close()

    def take(self, body: dict[str, Any]) -> int:
        """Record a request and return its zero-based index."""
        with self._lock:
            self.requests.append(body)
            return len(self.requests) - 1


def _completion(index: int, *, model: str) -> dict[str, Any]:
    base = {"id": f"chatcmpl-{index}", "object": "chat.completion", "created": 1, "model": model}
    usage = {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20}
    if index == 0:
        call = {
            "id": "call_status",
            "type": "function",
            "function": {"name": "get_status", "arguments": "{}"},
        }
        message: dict[str, Any] = {"role": "assistant", "content": None, "tool_calls": [call]}
        finish = "tool_calls"
    else:
        message = {"role": "assistant", "content": ASSISTANT_ANSWER}
        finish = "stop"
    choice = {"index": 0, "finish_reason": finish, "message": message}
    return base | {"choices": [choice], "usage": usage}


def _completion_chunks(index: int, *, model: str) -> list[dict[str, Any]]:
    base = {
        "id": f"chatcmpl-{index}",
        "object": "chat.completion.chunk",
        "created": 1,
        "model": model,
    }

    def chunk(delta: dict[str, Any], finish: str | None) -> dict[str, Any]:
        return base | {"choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}

    if index == 0:
        call = {
            "index": 0,
            "id": "call_status",
            "type": "function",
            "function": {"name": "get_status", "arguments": "{}"},
        }
        return [
            chunk({"role": "assistant", "content": None, "tool_calls": [call]}, None),
            chunk({}, "tool_calls"),
        ]
    words = ASSISTANT_ANSWER.split(" ")
    pieces = [word + " " for word in words[:-1]] + [words[-1]]
    return [
        chunk({"role": "assistant", "content": pieces[0]}, None),
        *(chunk({"content": piece}, None) for piece in pieces[1:]),
        chunk({}, "stop"),
    ]


class _ScriptedModelHandler(BaseHTTPRequestHandler):
    server: ScriptedModelServer

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            body = {}
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._send(404, "application/json", b'{"error": {"message": "not found"}}')
            return
        index = self.server.take(body)
        model = str(body.get("model") or "scripted")
        if body.get("stream"):
            events = [f"data: {json.dumps(c)}\n\n" for c in _completion_chunks(index, model=model)]
            payload = "".join([*events, "data: [DONE]\n\n"]).encode()
            self._send(200, "text/event-stream", payload)
        else:
            self._send(
                200, "application/json", json.dumps(_completion(index, model=model)).encode()
            )

    def _send(self, status: int, content_type: str, payload: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format: str, *args: object) -> None:
        """Keep the journey output to its own results."""


class JourneyFailure(AssertionError):
    """A journey observed the app in the wrong state."""


class JourneySkipped(Exception):
    """A journey needs something this run does not have, such as credentials."""


class ScreenLocked(Exception):
    """macOS locked the GUI session; nothing on screen can be observed until it is unlocked."""


@dataclass
class Element:
    id: str
    role: str
    label: str
    identifier: str
    value: str
    enabled: bool
    secure: bool = False

    @property
    def text(self) -> str:
        return " ".join(part for part in (self.label, self.value, self.identifier) if part)


@dataclass
class Snapshot:
    id: str
    elements: list[Element]

    def find(self, text: str, *, role: str | None = None) -> Element | None:
        """Exact identifier first, then exact label, then substring of label or value."""
        candidates = [e for e in self.elements if role is None or e.role == role]
        for match in (
            lambda e: e.identifier == text,
            lambda e: e.label == text,
            lambda e: text in e.text,
        ):
            found = next((e for e in candidates if match(e)), None)
            if found is not None:
                return found
        return None

    def has(self, text: str) -> bool:
        return self.find(text) is not None


_SUBCOMMANDS = {"list", "switch", "launch", "quit", "value"}


def _command_name(args: tuple[str, ...]) -> str:
    """Never echo argument values: typed text can be a credential."""
    if len(args) > 1 and args[1] in _SUBCOMMANDS:
        return f"{args[0]} {args[1]}"
    return args[0]


def peekaboo(*args: str, timeout: float = 60) -> dict[str, Any]:
    result = subprocess.run(
        ["peekaboo", *args, "--json"], capture_output=True, text=True, timeout=timeout, check=False
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise JourneyFailure(
            f"peekaboo {args[0]} returned no JSON: {result.stderr.strip()}"
        ) from error
    if not payload.get("success"):
        message = (payload.get("error") or {}).get("message", "unknown error")
        if "GUI session is locked" in message:
            raise ScreenLocked("the Mac's screen is locked; unlock it and run the journeys again")
        raise JourneyFailure(f"peekaboo {_command_name(args)} failed: {message}")
    return payload.get("data") or {}


@dataclass
class AppDriver:
    screenshots: Path
    state_root: Path | None = None
    shot_count: int = 0

    def see(self, name: str | None = None) -> Snapshot:
        args = ["see", "--app", APP_NAME]
        if name is not None:
            self.shot_count += 1
            args += ["--path", str(self.screenshots / f"{self.shot_count:02d}-{name}.png")]
        for attempt in range(3):
            try:
                data = peekaboo(*args, timeout=90)
                break
            except JourneyFailure as error:
                # Navigation can race a capture in progress; Peekaboo asks for one fresh retry.
                transient = ("inconsistent response", "AX tree incomplete")
                if not any(text in str(error) for text in transient) or attempt == 2:
                    raise
                time.sleep(1)
        elements = [
            Element(
                id=str(raw.get("id", "")),
                role=str(raw.get("role", "")),
                label=str(raw.get("label") or raw.get("title") or ""),
                identifier=str(raw.get("identifier") or ""),
                value=str(raw.get("value") or ""),
                enabled=bool(raw.get("is_enabled", True)),
                secure="secure" in str(raw.get("role_description") or ""),
            )
            for raw in data.get("ui_elements", [])
        ]
        return Snapshot(id=str(data.get("snapshot_id", "")), elements=elements)

    def click(self, text: str, *, role: str | None = None, real: bool = False) -> None:
        """Press an element; `real` sends an actual mouse click, which also ends field editing."""
        for attempt in range(3):
            snapshot = self.see()
            element = snapshot.find(text, role=role)
            if element is None:
                raise JourneyFailure(f"no element matching {text!r}")
            if not element.enabled:
                raise JourneyFailure(f"{text!r} is disabled")
            try:
                if real:
                    peekaboo(
                        "click",
                        "--on",
                        element.id,
                        "--snapshot",
                        snapshot.id,
                        "--foreground",
                        "--input-strategy",
                        "synthOnly",
                        "--no-auto-focus",
                    )
                else:
                    peekaboo(
                        "click", "--on", element.id, "--snapshot", snapshot.id, "--app", APP_NAME
                    )
                break
            except JourneyFailure as error:
                # The window can re-layout between observing and clicking; observe again.
                message = str(error).lower()
                raced = "stale" in message or "identity validation" in message
                if not raced or attempt == 2:
                    raise
                time.sleep(0.5)
        time.sleep(0.6)

    def type(self, text: str, into: str) -> None:
        """Type into a field the way a user does, so SwiftUI bindings see every keystroke.

        Accessibility value writes change what a field shows without updating its binding, and
        background clicks cannot focus fields, so this briefly brings the app to the front.
        Plain fields are read back and retried once; secure fields cannot be read back, so the
        journey's own outcome has to prove them.
        """
        for attempt in range(2):
            element, snapshot = self._field(into)
            peekaboo("app", "switch", "--to", APP_NAME, "--foreground", "--verify")
            time.sleep(0.5)
            peekaboo(
                "click",
                "--on",
                element.id,
                "--snapshot",
                snapshot.id,
                "--foreground",
                "--input-strategy",
                "synthOnly",
                "--no-auto-focus",
            )
            time.sleep(0.3)
            peekaboo("type", text, "--foreground", "--clear", "--accept-dispatched")
            time.sleep(0.4)
            if element.secure or self._field(into)[0].value == text:
                return
            if attempt == 1:
                self.see(f"typing-failed-{into.lower().replace(' ', '-')}")
                raise JourneyFailure(f"typing into {into!r} did not take effect")

    def type_focused(self, text: str, into: str) -> None:
        """Type into the field that already has keyboard focus, then read it back.

        For a field the app focuses itself, such as the assistant's composer, which does not
        take Peekaboo's synthesized keystrokes but does take the ones System Events sends.
        Keystrokes follow whichever app is frontmost, so this refuses to type unless the
        app under test is.
        """
        peekaboo("app", "switch", "--to", APP_NAME, "--foreground", "--verify")
        time.sleep(0.5)
        quoted = text.replace("\\", "\\\\").replace('"', '\\"')
        # System Events names the process after its executable, "CopyTrading", which the
        # installed app shares; the debug bundle's process id tells them apart.
        pids = subprocess.run(
            ["pgrep", "-f", f"{DEBUG_APP.name}/Contents/MacOS/CopyTrading"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.split()
        if len(pids) != 1:
            raise JourneyFailure(f"expected one {APP_NAME} process, found {len(pids)}")
        # Launch Services knows the front app at once; System Events can lag behind it.
        deadline = time.monotonic() + 3
        while _front_pid() != int(pids[0]):
            if time.monotonic() > deadline:
                raise JourneyFailure(f"refused to type {into!r}: {APP_NAME} is not frontmost")
            time.sleep(0.1)
        script = f"""
tell application "System Events"
    tell (first process whose unix id is {int(pids[0])}) to keystroke "{quoted}"
end tell
"""
        typed = subprocess.run(
            ["osascript", "-e", script], capture_output=True, text=True, timeout=30, check=False
        )
        if typed.returncode != 0:
            raise JourneyFailure(f"refused to type {into!r}: {typed.stderr.strip()}")
        time.sleep(0.4)
        if self._field(into)[0].value != text:
            self.see(f"typing-failed-{into.lower().replace(' ', '-')}")
            raise JourneyFailure(f"typing into {into!r} did not take effect")

    def field_value(self, label: str) -> str:
        """The current text of a plain field; secure fields report only their masking."""
        return self._field(label)[0].value

    def _field(self, into: str) -> tuple[Element, Snapshot]:
        snapshot = self.see()
        fields = [e for e in snapshot.elements if e.role in ("textField", "secureTextField")]
        element = next((e for e in fields if e.label == into), None) or next(
            (e for e in fields if into in e.label), None
        )
        if element is None:
            labels = sorted(e.label for e in fields)
            raise JourneyFailure(f"no text field labeled {into!r}; fields on screen: {labels}")
        return element, snapshot

    def press(self, keys: str) -> None:
        """Send a key chord to the focused element; Peekaboo refuses `--app` for raw chords."""
        peekaboo("app", "switch", "--to", APP_NAME, "--foreground", "--verify")
        peekaboo("press", keys, "--foreground")
        time.sleep(0.4)

    def open_screen(self, screen: str) -> Snapshot:
        # Settings replaces the sidebar with its own pages; close it to reach the screens.
        if screen != "settings" and self.see().has("settings.close"):
            self.click("settings.close")
        self.click(f"navigation.{screen}")
        return self.see(screen)

    def open_settings(self, page: str = "general") -> Snapshot:
        """Opens a Settings page by its sidebar identifier: general, engine, agents, logs, …"""
        if not self.see().has("settings.close"):
            self.click("navigation.settings")
        self.click(f"settings.page.{page}")
        return self.see(f"settings-{page}")

    def open_connection(self, kind: str) -> None:
        """Opens a Connections panel; an empty interpreter asks which provider first. Waits for
        the panel to finish growing out of its card, since a click mid-way can miss a field."""
        self.click(f"connections.{kind}")
        if kind == "interpreter" and self.see().has("connections.choose.anthropic"):
            self.click("connections.choose.anthropic")
        time.sleep(0.8)

    def wait_for(self, text: str, *, timeout: float = 60, name: str | None = None) -> Snapshot:
        deadline = time.monotonic() + timeout
        while True:
            snapshot = self.see()
            if snapshot.has(text):
                return self.see(name) if name else snapshot
            if time.monotonic() > deadline:
                self.see(f"timeout-{text[:24].replace(' ', '-')}")
                raise JourneyFailure(f"{text!r} did not appear within {timeout:.0f}s")
            time.sleep(1.5)

    def expect(self, snapshot: Snapshot, *texts: str) -> None:
        missing = [text for text in texts if not snapshot.has(text)]
        if missing:
            raise JourneyFailure(f"missing on screen: {', '.join(missing)}")

    def expect_absent(self, snapshot: Snapshot, *texts: str) -> None:
        present = [text for text in texts if snapshot.has(text)]
        if present:
            raise JourneyFailure(f"unexpectedly on screen: {', '.join(present)}")


def _front_pid() -> int | None:
    """The process Launch Services treats as the front app, which receives keystrokes."""
    front = subprocess.run(["lsappinfo", "front"], capture_output=True, text=True, check=False)
    info = subprocess.run(
        ["lsappinfo", "info", "-only", "pid", front.stdout.strip()],
        capture_output=True,
        text=True,
        check=False,
    )
    _, _, value = info.stdout.strip().partition("=")
    return int(value) if value.isdigit() else None


def build_debug_bundle() -> None:
    """The release bundle supplies the runtime; the debug executable carries the test unlock."""
    if not RELEASE_APP.is_dir():
        raise SystemExit("build the release bundle first: make desktop-build")
    subprocess.run(
        ["arch", "-arm64", "swift", "build", "--package-path", str(ROOT / "app")], check=True
    )
    if DEBUG_APP.exists():
        shutil.rmtree(DEBUG_APP)
    DEBUG_APP.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", str(RELEASE_APP), str(DEBUG_APP)], check=True)
    executable = DEBUG_APP / "Contents/MacOS/CopyTrading"
    shutil.copy2(swift_bin_path() / "CopyTrading", executable)
    info = DEBUG_APP / "Contents/Info.plist"
    for key, value in (
        ("CFBundleIdentifier", BUNDLE_ID),
        ("CFBundleName", APP_NAME),
        ("CFBundleDisplayName", APP_NAME),
    ):
        subprocess.run(
            ["/usr/libexec/PlistBuddy", "-c", f"Set :{key} {value}", str(info)], check=True
        )
    subprocess.run(["codesign", "--force", "--deep", "-s", "-", str(DEBUG_APP)], check=True)


def launch(state_root: Path, *, quit_first: bool = True) -> None:
    if quit_first:
        quit_app()
    subprocess.run(
        [
            "open",
            "-n",
            "--env",
            "COPYTRADING_UI_TEST_UNLOCK=1",
            "--env",
            f"COPYTRADING_STATE_ROOT={state_root}",
            str(DEBUG_APP),
        ],
        check=True,
    )
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        try:
            windows = peekaboo("window", "list", "--app", APP_NAME).get("windows", [])
        except JourneyFailure:
            windows = []  # the app registers with Launch Services a moment after `open` returns
        # The title follows the selected screen, and Peekaboo does not always report a subrole,
        # so any titled on-screen window counts.
        if any(w.get("window_title") and w.get("is_on_screen", True) for w in windows):
            return
        time.sleep(1)
    raise JourneyFailure("main window did not open")


def _bundle_processes() -> list[str]:
    """Every process started from the debug bundle: the app and its engine."""
    found = subprocess.run(
        ["pgrep", "-f", f"{DEBUG_APP.name}/Contents/"], capture_output=True, text=True, check=False
    )
    return found.stdout.split()


def quit_app() -> list[str]:
    """Quit the way a user does and return whatever survived; then clean up forcibly."""
    subprocess.run(
        ["osascript", "-e", f'tell application id "{BUNDLE_ID}" to quit'],
        capture_output=True,
        timeout=90,
        check=False,
    )
    deadline = time.monotonic() + 60
    while _bundle_processes() and time.monotonic() < deadline:
        time.sleep(1)
    survivors = _bundle_processes()
    if survivors:
        subprocess.run(["kill", "-9", *survivors], check=False)
        time.sleep(1)
    return survivors


@dataclass
class Result:
    journey: str
    status: str
    detail: str = ""
    seconds: float = 0


@dataclass
class Runner:
    driver: AppDriver
    results: list[Result] = field(default_factory=list)

    def run(self, journey: str, body: Callable[[AppDriver], None]) -> None:
        started = time.monotonic()
        try:
            body(self.driver)
            result = Result(journey, "passed")
        except JourneySkipped as skip:
            result = Result(journey, "skipped", str(skip))
        except (JourneyFailure, subprocess.TimeoutExpired) as failure:
            result = Result(journey, "failed", str(failure))
        result.seconds = time.monotonic() - started
        self.results.append(result)
        print(f"{result.status.upper():8} {journey} {result.detail}", flush=True)


SCREENS = {
    "today": "Today",
    "activity": "Activity",
    "people": "People",
    "accounts": "Accounts",
    "connections": "Connections",
    "gettingStarted": "Getting Started",
    "diagnostics": "Diagnostics",
    "settings": "Close Settings",
}


def j1_launch_and_unlock(app: AppDriver) -> None:
    snapshot = app.wait_for("navigation.today", timeout=30, name="unlocked")
    app.expect(snapshot, *(f"navigation.{s}" for s in SCREENS))
    # Nothing is saved on a fresh state root, so the app settles on the guide once it has loaded.
    app.wait_for("About 10 minutes", timeout=60, name="opens-on-guide")


def j2_engine_starts(app: AppDriver) -> None:
    app.open_settings("engine")
    app.wait_for("Local engine, Ready", timeout=90, name="engine-ready")


def j3_first_run_guidance(app: AppDriver) -> None:
    """With nothing saved, the app opens on Getting Started; its first step opens Connections."""
    guide = app.open_screen("gettingStarted")
    app.expect(guide, "Status: Not set up yet", "guide.step.0", "Find a channel ID", "0 of 5")
    app.click("guide.openDiscord")
    connections = app.see("connections-from-guide")
    app.expect(
        connections, "Discord", "Interpreter", "Alerts", "Channel IDs", "Where do I find this?"
    )
    today = app.open_screen("today")
    app.expect(today, "Your trading day, at a glance", "today.gettingStarted")


def j4_every_screen(app: AppDriver) -> None:
    empty_states = {
        "today": "Your trading day, at a glance",
        "activity": "Every post, and what came of it",
        "people": "The traders you choose to copy",
        "accounts": "Your accounts, inside your limits",
        "connections": "Discord token and channels",
        "gettingStarted": "About 10 minutes",
    }
    for screen, title in SCREENS.items():
        snapshot = app.open_screen(screen)
        if not any(e.label == title or e.value == title for e in snapshot.elements):
            raise JourneyFailure(f"{screen} did not show its title {title!r}")
        if screen in empty_states:
            app.expect(snapshot, empty_states[screen])


def j20_toolbar(app: AppDriver) -> None:
    """With nothing set up, copying cannot start and the freshness label says so."""
    snapshot = app.open_screen("today")
    copying = snapshot.find("toolbar.copying")
    if copying is None or copying.enabled:
        raise JourneyFailure("Start Copying must be present and disabled before setup")
    app.expect(snapshot, "Not copying")
    app.click("toolbar.refresh")
    app.open_screen("people")
    app.click("people.addGuru")
    app.expect(app.see("guru-from-people"), "Where they post", "Remove Guru")
    app.click("Remove Guru")
    app.expect(app.see("guru-removed"), "The traders you choose to copy")


def j21_settings_pages(app: AppDriver) -> None:
    """Every Settings page opens from its own sidebar; back retraces them and close returns."""
    expected = {
        "general": ("When CopyTrading Opens", "settings.asksForOwner", "settings.startsCopying"),
        "appearance": (
            "settings.appearance.system",
            "settings.appearance.dark",
            "Motion and Transparency",
        ),
        "updates": ("Check for Updates", "Version on this Mac"),
        "engine": ("Local engine", "Run Self-Test", "Self-Test"),
        "agents": ("Allow Agents To", "Read and pause", "Nothing"),
        "backups": ("Create Backup…", "Restore from Backup…"),
        "logs": ("Log Health", "Log Retention", "settings.support.saveLog"),
    }
    app.open_screen("today")
    for page, texts in expected.items():
        app.expect(app.open_settings(page), *texts)
    app.click("settings.back")
    app.expect(app.see("settings-back"), "Create Backup…")
    app.click("settings.close")
    app.expect(app.see("settings-closed"), "navigation.today", "Your trading day, at a glance")


def j5_self_test(app: AppDriver) -> None:
    app.open_settings("engine")
    app.click("system.runSelfTest")
    snapshot = app.wait_for("Last result", timeout=120, name="self-test")
    result = snapshot.find("Last result")
    if result is None or ("Completed" not in result.text and "Delivered" not in result.text):
        raise JourneyFailure(f"self-test did not succeed: {result.text if result else 'no result'}")


def j6_setup_editing(app: AppDriver) -> None:
    """Accounts and gurus are added where they live and wait, unsaved, in the changes bar."""
    app.open_screen("accounts")
    app.click("accounts.addAccount")
    sheet = app.see("account-sheet")
    app.expect(sheet, "Alpaca keys", "Position limits (USD)", "Remove Account")
    app.click("Done")
    accounts = app.see("account-added")
    app.expect(accounts, "accounts.draft.primary", "Not saved yet", "setup.status", "setup.check")
    app.open_screen("people")
    app.click("Add Guru")
    guru = app.see("guru-sheet")
    app.expect(guru, "Where they post", "Copies into", "playbook.learn")
    app.click("Done")
    people = app.see("guru-added")
    app.expect(people, "people.draftGuru", "Unnamed guru")
    # Leave the setup as found, so later journeys start from nothing saved and nothing typed.
    app.click("people.draftGuru")
    app.click("Remove Guru")
    app.open_screen("accounts")
    app.click("accounts.draft.primary")
    app.click("Remove Account")
    cleaned = app.see("setup-cleaned")
    app.expect(cleaned, "Your accounts, inside your limits")
    app.expect_absent(cleaned, "setup.status")


def _relock(app: AppDriver) -> None:
    """Locking drops everything typed into the setup; unlocking returns to a clean draft."""
    app.click("Lock")
    app.wait_for("CopyTrading is locked", timeout=20)
    app.click("app.unlock")
    app.wait_for("navigation.today", timeout=30)


def j7_validation_gate(app: AppDriver) -> None:
    """An edit raises the changes bar; Check Setup runs only while paused, Start waits for it."""
    app.open_screen("connections")
    app.open_connection("discord")
    app.type("123456789012345678", into="Channel IDs")
    snapshot = app.see("changes-bar")
    check = snapshot.find("setup.check")
    start = snapshot.find("setup.startCopying")
    if check is None or start is None:
        raise JourneyFailure("the changes bar did not offer Check Setup and Start Copying")
    if start.enabled:
        raise JourneyFailure("Start Copying was enabled before a passing check")
    paused = check.enabled
    app.click("connections.done")
    _relock(app)
    if not paused:
        raise JourneySkipped("Check Setup is disabled until copying is paused")


def j23_learn_playbook(app: AppDriver) -> None:
    """The guru editor offers Learn from Channel and explains what it still needs."""
    app.open_screen("people")
    app.click("people.addGuru")
    sheet = app.see("route-sheet-playbook")
    app.expect(sheet, "Playbook", "playbook.learn", "playbook.text")
    app.expect_absent(sheet, "Ticker aliases")
    # The route editor is a sheet: a pinned background click resolves to the main window.
    app.click("playbook.learn", real=True)
    failed = app.wait_for("playbook.failure", timeout=30, name="learn-needs-channel")
    failure = failed.find("playbook.failure")
    if failure is None or "channel" not in failure.text.lower():
        raise JourneyFailure(
            f"Learn did not say a channel is needed: {failure.text if failure else ''}"
        )
    app.click("Remove Guru")


def j8_credential_gate(app: AppDriver) -> None:
    """Typed paper keys reach the draft; validation names exactly the credentials still missing.

    The live Alpaca round trip itself is covered by engine/tests/trading/test_paper_broker_probe.py.
    """
    key = os.environ.get("COPYTRADING_TEST_ALPACA_KEY", "")
    secret = os.environ.get("COPYTRADING_TEST_ALPACA_SECRET", "")
    if not key or not secret:
        raise JourneySkipped("set COPYTRADING_TEST_ALPACA_KEY and COPYTRADING_TEST_ALPACA_SECRET")
    app.open_screen("connections")
    app.open_connection("discord")
    app.type("123456789012345678", into="Channel IDs")
    app.click("connections.done")
    app.open_connection("interpreter")
    app.type("claude-sonnet-5-5", into="Model")
    app.click("connections.done")
    app.open_screen("accounts")
    app.click("accounts.addAccount")
    app.wait_for("Alpaca keys", timeout=15, name="paper-account-sheet")
    app.type(key, into="Alpaca API key")
    app.type(secret, into="Alpaca API secret")
    app.click("Done")
    app.open_screen("people")
    app.click("people.addGuru")
    app.type("Journey Guru", into="Name")
    guru = app.see("guru-adopted-channel")
    app.expect(guru, "First channel in Connections (123456789012345678)")
    app.click("Done")
    app.click("setup.check")
    banner = app.wait_for("Enter the", timeout=30, name="credential-gate")
    message = next(e.text for e in banner.elements if "Enter the" in e.text)
    # Broker keys are checked first, account by account, then the Discord and model credentials.
    # Whatever is still missing, the paper account's typed keys must not be among it.
    if "“primary”" in message:
        raise JourneyFailure(f"the typed paper keys did not reach the draft: {message}")
    names_rest = "Discord token" in message and "model API key" in message
    if "Alpaca" not in message and not names_rest:
        raise JourneyFailure(f"unexpected validation message: {message}")
    _relock(app)


def j12_diagnostics(app: AppDriver) -> None:
    """The log is read from disk: the self-test's stages appear and the filters narrow them."""
    app.open_screen("diagnostics")
    records = app.wait_for("Self-test completed", timeout=30, name="diagnostics-records")
    app.expect(records, "Self-test captured", "diagnostics.refresh", "on this Mac")
    app.click("Problems")
    filtered = app.wait_for("No problems recorded", timeout=15, name="diagnostics-problems")
    app.expect_absent(filtered, "Self-test completed")
    app.click("All")
    app.wait_for("Self-test completed", timeout=15, name="diagnostics-all")


def j14_retention(app: AppDriver) -> None:
    snapshot = app.open_settings("logs")
    save = snapshot.find("settings.logs.save")
    if save is None:
        raise JourneyFailure("log retention Save button missing")
    if save.enabled:
        raise JourneyFailure("Save is enabled before any change")
    app.click("increment arrow button", role="button")
    app.click("settings.logs.save")
    app.wait_for("Saved. Applies when the engine next starts.", timeout=15, name="retention-saved")


def j19_engine_stop_start(app: AppDriver) -> None:
    """Stopping the engine keeps the owner unlocked, and the main window offers Start."""
    app.open_settings("engine")
    app.click("settings.stopEngine")
    app.wait_for("Local engine, Stopped", timeout=60, name="engine-stopped")
    stopped = app.wait_for("engine.start", timeout=15, name="engine-stopped-banner")
    app.expect_absent(stopped, "CopyTrading is locked")
    app.expect(stopped, "The local engine is stopped. Nothing is being copied.")
    app.click("engine.start")
    app.open_settings("engine")
    app.wait_for("Local engine, Ready", timeout=90, name="engine-restarted")


def _agent_command(app: AppDriver, *arguments: str) -> subprocess.CompletedProcess[str]:
    """Run the bundled `copytrading` command the way a coding agent would."""
    assert app.state_root is not None
    return subprocess.run(
        [str(DEBUG_APP / "Contents/Helpers/copytrading"), *arguments],
        env={
            "PATH": "/usr/bin:/bin",
            "HOME": str(Path.home()),
            "COPYTRADING_STATE_ROOT": str(app.state_root),
        },
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


def j18_agent_access(app: AppDriver) -> None:
    """Agents reach the app only after the owner allows them, and only as far as allowed."""
    if app.state_root is None:
        raise JourneySkipped("needs the run's state root")
    app.open_settings("agents")
    if _agent_command(app, "status").returncode != 3:
        raise JourneyFailure("an agent reached the app before access was allowed")
    app.click("Read and pause")
    app.wait_for("Listening", timeout=30, name="agent-access-on")
    status = _agent_command(app, "status", "--json")
    if status.returncode != 0 or '"engine_state":"running"' not in status.stdout:
        raise JourneyFailure(f"the agent could not read status: exit {status.returncode}")
    if _agent_command(app, "pause").returncode != 0:
        raise JourneyFailure("the agent could not pause processing")
    if _agent_command(app, "accounts", "resume", "any").returncode != 5:
        raise JourneyFailure("read-and-pause access must refuse proposals")
    app.wait_for("Get status", timeout=20, name="agent-audit")
    app.click("Nothing")
    deadline = time.monotonic() + 20
    while _agent_command(app, "status").returncode != 3:
        if time.monotonic() > deadline:
            raise JourneyFailure("agents could still connect after access was turned off")
        time.sleep(1)
    app.see("agent-access-off")


def j22_setup_keeps_typing(app: AppDriver) -> None:
    """What was typed into Connections survives switching screens, but not locking."""
    app.open_screen("connections")
    app.open_connection("discord")
    app.type("987654321", into="Channel IDs")
    app.click("connections.done")
    app.open_screen("today")
    app.open_screen("connections")
    app.expect(app.see("discord-tile"), "Discord, 1 channel")
    app.open_connection("discord")
    if app.field_value("Channel IDs") != "987654321":
        raise JourneyFailure("Connections lost what was typed after switching screens")
    app.click("connections.done")
    _relock(app)
    app.open_screen("connections")
    app.open_connection("discord")
    if app.field_value("Channel IDs") != "":
        raise JourneyFailure("Locking did not clear what was typed into Connections")
    app.click("connections.close")


def j25_getting_started(app: AppDriver) -> None:
    """The guide ticks Connect Discord as soon as a channel and a token are typed."""
    guide = app.open_screen("gettingStarted")
    app.expect(guide, "Get set up", "Your day in CopyTrading", "Staying safe", "Shortcuts")
    step = guide.find("guide.step.0")
    if step is None or "To do" not in step.text:
        raise JourneyFailure("Connect Discord was ticked before anything was typed")
    app.open_screen("connections")
    app.open_connection("discord")
    app.type("123456789012345678", into="Channel IDs")
    app.type("ui-journey-placeholder", into="Discord token")
    app.click("connections.done")
    ticked = app.open_screen("gettingStarted")
    step = ticked.find("guide.step.0")
    if step is None or "Done" not in step.text:
        raise JourneyFailure("Connect Discord did not tick after a channel and token were typed")
    app.expect(ticked, "1 of 5")
    _relock(app)


def _paper_setup() -> dict[str, str]:
    """A real paper setup from the opt-in test environment; journeys that need one skip without."""
    variables = {
        "channel": "COPYTRADING_TEST_DISCORD_CHANNEL",
        "discord_token": "COPYTRADING_TEST_DISCORD_TOKEN",
        "model_key": "COPYTRADING_TEST_DEEPSEEK_KEY",
        "alpaca_key": "COPYTRADING_TEST_ALPACA_KEY",
        "alpaca_secret": "COPYTRADING_TEST_ALPACA_SECRET",
    }
    setup = {name: os.environ.get(variable, "") for name, variable in variables.items()}
    missing = [variables[name] for name, value in setup.items() if not value]
    if missing:
        raise JourneySkipped(f"set {', '.join(missing)}")
    setup["model"] = os.environ.get("COPYTRADING_TEST_DEEPSEEK_MODEL", "deepseek-flash")
    return setup


def _check_paper_setup(app: AppDriver, setup: dict[str, str], *, name: str) -> Snapshot:
    """Fill Connections, a paper account, and a guru from nothing, and pass Check Setup."""
    app.open_screen("connections")
    app.open_connection("discord")
    app.type(setup["channel"], into="Channel IDs")
    app.type(setup["discord_token"], into="Discord token")
    app.click("connections.done")
    app.click("connections.interpreter")
    app.click("connections.choose.deepseek")
    app.type(setup["model"], into="Model")
    app.type(setup["model_key"], into="API key")
    app.click("connections.done")
    app.open_screen("accounts")
    app.click("accounts.addAccount")
    app.wait_for("Alpaca keys", timeout=15)
    app.type(setup["alpaca_key"], into="Alpaca API key")
    app.type(setup["alpaca_secret"], into="Alpaca API secret")
    app.click("Done")
    app.open_screen("people")
    app.click("people.addGuru")
    app.type("Journey Guru", into="Name")
    app.click("Done")
    guide = app.open_screen("gettingStarted")
    app.expect(guide, "4 of 5")
    app.click("setup.check")
    checked = app.wait_for("Everything checks out", timeout=180, name=name)
    start = checked.find("setup.startCopying")
    if start is None or not start.enabled:
        raise JourneyFailure("a passing check did not enable Start Copying")
    return checked


def j27_first_check(app: AppDriver) -> None:
    """From nothing saved, the real services pass Check Setup and Start Copying becomes ready.

    Uses the paper-only test credentials and stops before Start Copying, so nothing is saved and
    no key reaches the Keychain. Saving and starting are covered by J31 and the contract suite.
    """
    _check_paper_setup(app, _paper_setup(), name="first-check-passed")
    _relock(app)


def _agent_result(app: AppDriver, expected_exit: int, *arguments: str) -> dict[str, Any]:
    """Run the command with `--json`, insist on its exit code, and return the result."""
    completed = _agent_command(app, *arguments, "--json")
    if completed.returncode != expected_exit:
        raise JourneyFailure(
            f"`copytrading {' '.join(arguments)}` exited {completed.returncode}, "
            f"expected {expected_exit}: {completed.stderr.strip()[:200]}"
        )
    return json.loads(completed.stdout)["ok"]


def _wait_for_account(app: AppDriver, account_id: str, *, timeout: float) -> dict[str, Any]:
    """The account as the running engine reports it, once processing has started it."""
    deadline = time.monotonic() + timeout
    while True:
        status = _agent_result(app, 0, "status")
        account = next((a for a in status["accounts"] if a["account_id"] == account_id), None)
        if status["processing"]["state"] == "running" and account is not None:
            return account
        if time.monotonic() > deadline:
            app.see("timeout-processing")
            raise JourneyFailure(
                f"processing did not start {account_id}: {status['processing']['state']}, "
                f"error {status['processing']['error_code']}"
            )
        time.sleep(3)


def j31_agent_approval(app: AppDriver) -> None:
    """An agent's request runs only after the owner approves it in the window, and only once.

    Saves and starts a real paper setup, so it runs last. New accounts start with entries off and
    the journey never resumes them, so nothing can be bought; `main` deletes the saved keys.
    """
    if app.state_root is None:
        raise JourneySkipped("needs the run's state root")
    setup = _paper_setup()
    app.open_settings("agents")
    app.click("Read, pause, and ask for approval")
    app.wait_for("Listening", timeout=30, name="agent-approval-access")
    _check_paper_setup(app, setup, name="approval-setup-checked")
    app.click("setup.startCopying")
    before = _wait_for_account(app, "primary", timeout=180)
    if before["recovery_preference"] != "manual":
        raise JourneyFailure(f"a new account starts with recovery {before['recovery_preference']}")

    # Approving: the change waits for the owner, then runs exactly once.
    asked = _agent_result(app, 10, "accounts", "recovery", "primary", "automatic")
    sheet = app.wait_for("Set recovery in primary", timeout=30, name="approval-sheet")
    app.expect(sheet, "An agent is asking for approval", "Reject", "Approve…")
    if _wait_for_account(app, "primary", timeout=5)["recovery_preference"] != "manual":
        raise JourneyFailure("the recovery change ran before the owner approved it")
    app.click("Approve…")
    approved = _agent_result(app, 0, "proposals", "wait", asked["proposal_id"], "--timeout", "60")
    if approved["state"] != "succeeded":
        raise JourneyFailure(f"the approved request ended {approved['state']}")
    if _wait_for_account(app, "primary", timeout=5)["recovery_preference"] != "automatic":
        raise JourneyFailure("the approved recovery change did not reach the account")
    app.see("approval-done")

    # Rejecting: the agent learns the outcome and the account never changes.
    resume = _agent_result(app, 10, "accounts", "resume", "primary")
    app.wait_for("Resume new entries in primary", timeout=30, name="resume-sheet")
    app.click("Reject")
    rejected = _agent_result(app, 7, "proposals", "wait", resume["proposal_id"], "--timeout", "60")
    if rejected["state"] != "rejected":
        raise JourneyFailure(f"the rejected request ended {rejected['state']}")
    after = _wait_for_account(app, "primary", timeout=5)
    if after["entry_permission"] != before["entry_permission"]:
        raise JourneyFailure("a rejected resume still changed the account's entries")
    _agent_result(app, 0, "pause")


def _forget_test_keychain(state_root: Path) -> int:
    """Delete the Keychain items a journey's setup saved for this throwaway installation.

    Returns how many items are left, so a run never silently leaves test keys behind.
    """
    identity = next(state_root.rglob("installation-id"), None)
    if identity is None:
        return 0
    service = f"dev.copytrading.app.trading.{identity.read_text().strip().lower()}"
    for _ in range(64):
        deleted = subprocess.run(
            ["security", "delete-generic-password", "-s", service],
            capture_output=True,
            check=False,
        )
        if deleted.returncode != 0:
            break
    found = subprocess.run(
        ["security", "find-generic-password", "-s", service], capture_output=True, check=False
    )
    return 1 if found.returncode == 0 else 0


def j28_connections_panel(app: AppDriver) -> None:
    """⊕ offers every connection in one picker; the interpreters are grouped, and a local
    model asks for an address and no key; an alerts offer closed untouched stays off."""
    page = app.open_screen("connections")
    app.expect(page, "Discord token and channels", "More services", "Setup Tips")
    app.click("connections.new")
    picker = app.see("connections-picker")
    app.expect(
        picker,
        "Create New",
        "connections.choose.discord",
        "connections.choose.interpreter",
        "Telegram Alerts",
    )
    app.click("connections.choose.interpreter")
    interpreters = app.see("connections-interpreters")
    app.expect(
        interpreters,
        "Popular",
        "connections.choose.openai",
        "connections.choose.deepseek",
        "Your Own Model",
    )
    app.click("connections.choose.ollama")
    local = app.see("connections-ollama")
    app.expect(local, "connections.provider", "Base URL", "API key")
    app.click("connections.close")
    app.click("connections.new")
    app.click("connections.choose.alerts")
    app.expect(app.see("connections-alerts"), "Chat ID", "Bot token", "Where do I find this?")
    app.click("connections.close")
    closed = app.see("connections-alerts-closed")
    app.expect(closed, "Telegram bot", "connections.idea.channelID", "connections.hideIdeas")


def j30_assistant(app: AppDriver) -> None:
    """The assistant answers from a local OpenAI-compatible model and closes on Esc.

    The model is a scripted stub that checks whether copying is running, then answers. The setup
    draft's interpreter is enough: nothing is saved and no key is involved.
    """
    with ScriptedModelServer() as stub:
        app.open_screen("connections")
        app.click("connections.interpreter")
        app.click("connections.choose.openai_compatible")
        time.sleep(0.8)
        app.expect(app.see("assistant-model-editor"), "connections.provider", "Base URL", "Model")
        app.type(stub.base_url, into="Base URL")
        app.type("scripted", into="Model")
        app.click("connections.done")

        # Checks name what the owner sees rather than the panel's containers, so they hold
        # under any accessibility reader, including ones that flatten groups.
        app.press("cmd+j")
        empty = app.wait_for("assistant.composer", timeout=15, name="assistant-empty")
        app.expect(empty, *(f"assistant.suggestion.{i}" for i in range(4)))
        app.expect_absent(empty, "assistant.openConnections")

        app.type_focused("Is copying running?", into="Question for the assistant")
        app.press("Return")
        app.wait_for("Checked whether copying is running", timeout=60, name="assistant-step")
        answered = app.wait_for("Copying is paused", timeout=60, name="assistant-answer")
        app.expect(answered, "Is copying running?", "Checked whether copying is running")
        if len(stub.requests) != 2:
            raise JourneyFailure(f"the model was asked {len(stub.requests)} times, not twice")

        # A real Esc from the focused composer closes the panel.
        app.press("escape")
        time.sleep(0.8)
        closed = app.see("assistant-closed")
        app.expect_absent(closed, "assistant.composer", "Copying is paused")
        app.expect(closed, "Ask the Assistant")
    _relock(app)


def j26_help_menu(app: AppDriver) -> None:
    """Help opens the guide and its shortcut reference, and a section's help names its steps."""
    app.open_screen("today")
    peekaboo("menu", "click", "--app", APP_NAME, "--path", "Help > Keyboard Shortcuts")
    time.sleep(1)
    shortcuts = app.see("help-shortcuts")
    app.expect(shortcuts, "Show or hide the sidebar", "Move through posts in Activity")
    app.open_screen("today")
    peekaboo("menu", "click", "--app", APP_NAME, "--path", "Help > Getting Started")
    time.sleep(1)
    app.expect(app.see("help-guide"), "About 10 minutes")


def j15_lock(app: AppDriver) -> None:
    app.click("Lock")
    snapshot = app.wait_for("CopyTrading is locked", timeout=20, name="locked")
    app.expect_absent(snapshot, "navigation.today")


def j17_crash_recovery(app: AppDriver) -> None:
    """A crash closes the engine's pipe; the engine exits and the next launch starts cleanly."""
    if app.state_root is None:
        raise JourneySkipped("needs the run's state root")
    app_pids = subprocess.run(
        ["pgrep", "-f", f"{DEBUG_APP.name}/Contents/MacOS/CopyTrading"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.split()
    orphans_before = set(_bundle_processes()) - set(app_pids)
    subprocess.run(["kill", "-9", *app_pids], check=False)
    time.sleep(3)
    launch(app.state_root, quit_first=False)
    app.wait_for("navigation.today", timeout=60)
    app.open_settings("engine")
    app.wait_for("Local engine, Ready", timeout=90, name="relaunched-after-crash")
    survivors = orphans_before & set(_bundle_processes())
    if survivors:
        raise JourneyFailure(
            f"{len(survivors)} process(es) from before the crash are still running"
        )


JOURNEYS: list[tuple[str, Callable[[AppDriver], None]]] = [
    ("J1 launch and unlock", j1_launch_and_unlock),
    ("J2 engine starts", j2_engine_starts),
    ("J3 first-run guidance", j3_first_run_guidance),
    ("J4 every screen", j4_every_screen),
    ("J20 toolbar", j20_toolbar),
    ("J21 settings pages", j21_settings_pages),
    ("J5 self-test", j5_self_test),
    ("J6 setup editing", j6_setup_editing),
    ("J7 validation gate", j7_validation_gate),
    ("J23 learn a playbook", j23_learn_playbook),
    ("J8 credential gate", j8_credential_gate),
    ("J12 diagnostics", j12_diagnostics),
    ("J14 retention settings", j14_retention),
    ("J19 engine stop and start", j19_engine_stop_start),
    ("J18 agent access", j18_agent_access),
    ("J22 setup keeps typing", j22_setup_keeps_typing),
    ("J28 connections panel", j28_connections_panel),
    ("J25 getting started", j25_getting_started),
    ("J30 assistant", j30_assistant),
    ("J26 help menu", j26_help_menu),
    ("J27 first check", j27_first_check),
    ("J15 lock", j15_lock),
    ("J17 crash recovery", j17_crash_recovery),
    # Last: starting copying saves a setup that the journeys above expect to be empty.
    ("J31 agent approval", j31_agent_approval),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--only", help="comma-separated journey IDs, e.g. J1,J5")
    parser.add_argument("--keep-state", action="store_true")
    args = parser.parse_args()

    if shutil.which("peekaboo") is None:
        raise SystemExit("install Peekaboo first: brew install steipete/tap/peekaboo")
    if not args.skip_build:
        build_debug_bundle()

    # The per-user temporary directory; /tmp is a symlink, which the app's state checks reject.
    state_root = Path(tempfile.mkdtemp(prefix="copytrading-ui-journey."))
    screenshots = ROOT / "dist/ui-test/screenshots"
    shutil.rmtree(screenshots, ignore_errors=True)
    screenshots.mkdir(parents=True)
    runner = Runner(AppDriver(screenshots, state_root))
    selected = {item.strip().upper() for item in args.only.split(",")} if args.only else None
    try:
        launch(state_root)
        for name, body in JOURNEYS:
            if selected is None or name.split()[0] in selected:
                runner.run(name, body)
    except ScreenLocked as locked:
        print(f"\nSTOPPED  {locked}; results so far are incomplete, not failures.")
        return 2
    finally:
        survivors = quit_app()
        runner.results.append(
            Result(
                "J16 clean quit",
                "failed" if survivors else "passed",
                f"{len(survivors)} process(es) outlived Quit" if survivors else "",
            )
        )
        print(f"{runner.results[-1].status.upper():8} J16 clean quit {runner.results[-1].detail}")
        if _forget_test_keychain(state_root):
            runner.results.append(
                Result("Keychain cleanup", "failed", "test keys remain in the login Keychain")
            )
            print(f"FAILED   Keychain cleanup {runner.results[-1].detail}")
        if args.keep_state:
            print(f"state kept at {state_root}")
        else:
            shutil.rmtree(state_root, ignore_errors=True)

    failed = [r for r in runner.results if r.status == "failed"]
    print(
        f"\n{len(runner.results) - len(failed)} of {len(runner.results)} journeys did not fail; "
        f"screenshots in {screenshots.relative_to(ROOT)}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    os.environ.setdefault("PEEKABOO_NO_COLOR", "1")
    sys.exit(main())
