"""Drive the real app window through the acceptance journeys in docs/acceptance.md.

The runner builds a debug bundle, launches it against a fresh temporary state root with the
debug-only authentication bypass, and drives it through Peekaboo's accessibility automation.
It never touches the real installation, its configuration, or its Keychain items.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import TracebackType
from typing import Any
from zoneinfo import ZoneInfo

from local_signing import local_identity
from swift_paths import swift_bin_path

ROOT = Path(__file__).resolve().parents[2]
RELEASE_APP = ROOT / "dist/CopyTrading.app"
DEBUG_APP = ROOT / "dist/ui-test/CopyTrading Debug.app"
APP_NAME = "CopyTrading Debug"
BUNDLE_ID = "dev.copytrading.app.uitest"
APP_LOG = ROOT / "dist/ui-test/app-stderr.log"
APPEARANCE_KEY = "appearance"  # AppAppearance.storageKey in the app


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


# Peekaboo reports these while it is still finding the app, before it acts, so a retry
# cannot click or type twice.
_BEFORE_ACTING = ("Application inventory was unavailable", "Application inventory did not complete")


def peekaboo(*args: str, timeout: float = 60) -> dict[str, Any]:
    for attempt in range(3):
        result = subprocess.run(
            ["peekaboo", *args, "--json"],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise JourneyFailure(
                f"peekaboo {args[0]} returned no JSON: {result.stderr.strip()}"
            ) from error
        if payload.get("success"):
            return payload.get("data") or {}
        message = (payload.get("error") or {}).get("message", "unknown error")
        if "GUI session is locked" in message:
            raise ScreenLocked("the Mac's screen is locked; unlock it and run the journeys again")
        if attempt < 2 and any(marker in message for marker in _BEFORE_ACTING):
            time.sleep(1.0)
            continue
        raise JourneyFailure(f"peekaboo {_command_name(args)} failed: {message}")
    raise AssertionError("unreachable")


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
                if "reason=window minimized" in str(error) and attempt < 2:
                    # Something outside the app hid its window (the app never minimizes itself):
                    # put it back on screen and look again.
                    with contextlib.suppress(JourneyFailure):
                        peekaboo("window", "restore", "--app", APP_NAME)
                    peekaboo("app", "switch", "--to", APP_NAME, "--foreground", "--verify")
                    time.sleep(1)
                    continue
                # Navigation can race a capture in progress; Peekaboo asks for one fresh retry.
                transient = ("inconsistent response", "AX tree incomplete")
                if not any(text in str(error) for text in transient) or attempt == 2:
                    raise
                time.sleep(1)
        if name is not None:
            self._capture_sheets(f"{self.shot_count:02d}-{name}")
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

    def _capture_sheets(self, stem: str) -> None:
        """A sheet is a window of its own, missing from the main window's capture: save each one
        beside the screenshot, so the shot shows what the owner sees."""
        with contextlib.suppress(JourneyFailure):
            windows = peekaboo("window", "list", "--app", APP_NAME).get("windows", [])
            for index, window in enumerate(windows[1:], start=1):
                if window.get("window_id"):
                    subprocess.run(
                        [
                            "/usr/sbin/screencapture",
                            "-x",
                            "-o",
                            "-l",
                            str(window["window_id"]),
                            str(self.screenshots / f"{stem}-sheet{index}.png"),
                        ],
                        check=False,
                        timeout=30,
                    )

    def click(
        self,
        text: str,
        *,
        role: str | None = None,
        real: bool = False,
        outcome_checked: bool = False,
    ) -> None:
        """Press an element; `real` sends an actual mouse click, which also ends field editing.

        `outcome_checked` is for a press the journey proves by its result afterwards. While the app
        is busy approving, Peekaboo can lose the reply to a click that landed; that is not a failure
        when the caller then checks what the click was meant to do.
        """
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
                if outcome_checked and ("indeterminate" in message or "no pressable" in message):
                    break
                if not raced or attempt == 2:
                    raise JourneyFailure(f"clicking {text!r}: {error}") from error
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

    def press_action(self, text: str) -> None:
        """Press a control through Accessibility alone, which works while it is scrolled out of
        view; a pointer click needs it on screen."""
        snapshot = self.see()
        element = snapshot.find(text)
        if element is None:
            raise JourneyFailure(f"no element matching {text!r}")
        peekaboo(
            "click",
            "--on",
            element.id,
            "--snapshot",
            snapshot.id,
            "--app",
            APP_NAME,
            "--input-strategy",
            "actionOnly",
        )
        time.sleep(0.6)

    def scroll_down(self, within: str, *, ticks: int = 10) -> None:
        """Scroll the area that holds a visible element, to reach what sits below it."""
        peekaboo("app", "switch", "--to", APP_NAME, "--foreground", "--verify")
        time.sleep(0.5)
        snapshot = self.see()
        element = snapshot.find(within)
        if element is None:
            raise JourneyFailure(f"no element matching {within!r} to scroll from")
        peekaboo(
            "scroll",
            "--direction",
            "down",
            "--amount",
            str(ticks),
            "--on",
            element.id,
            "--snapshot",
            snapshot.id,
            # SwiftUI scroll views have no Accessibility scroll action; use real wheel events.
            "--foreground",
        )
        time.sleep(0.6)

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
        """Opens a Connections panel; with no interpreter yet, Anthropic's own row opens one. Waits
        for the panel to finish growing out of its row, since a click mid-way can miss a field."""
        if kind == "interpreter" and self.see().has("connections.provider.anthropic"):
            self.click("connections.provider.anthropic")
        else:
            self.click(f"connections.{kind}")
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

    def wait_gone(self, text: str, *, timeout: float = 60) -> Snapshot:
        """Waits for something to leave the screen, such as a sheet that closes once its
        connection checks out."""
        deadline = time.monotonic() + timeout
        while True:
            snapshot = self.see()
            if not snapshot.has(text):
                return snapshot
            if time.monotonic() > deadline:
                self.see(f"timeout-gone-{text[:24].replace(' ', '-')}")
                raise JourneyFailure(f"{text!r} was still on screen after {timeout:.0f}s")
            time.sleep(1.5)

    def connect(self) -> None:
        """Connect checks the service first; the panel closes once it answers."""
        self.click("connections.done")
        self.wait_gone("connections.done", timeout=90)

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
    # The owner's Apple Development identity keeps Keychain trust across rebuilds, so a state
    # kept with --keep-state can be reused without macOS asking for the saved keys again.
    identity = local_identity() or "-"
    subprocess.run(
        [
            "codesign",
            "--force",
            "--deep",
            "--sign",
            identity,
            "--identifier",
            BUNDLE_ID,
            str(DEBUG_APP),
        ],
        check=True,
    )


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
            # A debug build reports the errors behind a failed start or restore here.
            "--stderr",
            str(APP_LOG),
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


def _saved_appearance() -> str | None:
    """The appearance the debug app saved, as SwiftUI's AppStorage keeps it."""
    read = subprocess.run(
        ["defaults", "read", BUNDLE_ID, APPEARANCE_KEY], capture_output=True, text=True, check=False
    )
    return read.stdout.strip() or None


def j37_everyday_buttons(app: AppDriver) -> None:
    """Buttons that do not trade do their job: Run Self-Test fills the log, Search narrows it,
    Save log… writes it to disk, Appearance switches, Settings stops and starts the engine, and
    each Getting Started step opens the part of Connections it names."""
    diagnostics = app.open_screen("diagnostics")
    app.expect(diagnostics, "diagnostics.runSelfTest")
    app.click("diagnostics.runSelfTest")
    app.wait_for("Self-test completed", timeout=60, name="self-test-logged")
    app.type("completed", into="Search")
    narrowed = app.see("diagnostics-search")
    app.expect(narrowed, "Self-test completed")
    app.expect_absent(narrowed, "Self-test captured")
    app.type("", into="Search")
    app.click("diagnostics.refresh")
    app.wait_for("Self-test captured", timeout=30)

    folder = Path(tempfile.mkdtemp(prefix="copytrading-ui-log.")).resolve()
    try:
        app.open_settings("logs")
        app.click("settings.support.saveLog", real=True)
        _choose_in_file_panel(app, folder, "journey-log.jsonl")
        saved = folder / "journey-log.jsonl"
        deadline = time.monotonic() + 30
        while not saved.is_file():
            if time.monotonic() > deadline:
                app.see("log-not-saved")
                raise JourneyFailure("Save log… did not write the log")
            time.sleep(1)
        records = [json.loads(line) for line in saved.read_text().splitlines() if line.strip()]
        if not records:
            raise JourneyFailure("Save log… wrote an empty log")
    except JourneyFailure:
        app.press("escape")  # a save panel left open would keep the app from quitting
        raise
    finally:
        shutil.rmtree(folder, ignore_errors=True)

    app.open_settings("appearance")
    for choice in ("dark", "system"):
        app.click(f"settings.appearance.{choice}")
        time.sleep(1)
        if _saved_appearance() != choice:
            raise JourneyFailure(f"choosing {choice} did not save it ({_saved_appearance()!r})")

    app.open_settings("engine")
    app.click("settings.stopEngine")
    app.wait_for("settings.startEngine", timeout=60, name="engine-stopped-in-settings")
    app.click("settings.startEngine")
    app.wait_for("Local engine, Ready", timeout=90, name="engine-started-in-settings")

    if app.state_root is not None and any(app.state_root.rglob("trading-configuration.json")):
        return  # a kept setup (--reuse-state): the guide's steps are done, and nothing to tidy
    for row, (step, lands_on) in enumerate(
        (
            ("guide.openDiscord", "Channel IDs"),
            ("guide.openInterpreter", "connections.provider.deepseek"),
            ("guide.openAccounts", "Alpaca keys"),
            ("guide.openPeople", "Where they post"),
        )
    ):
        app.open_screen("gettingStarted")
        app.click(f"guide.step.{row}")  # a checklist row opens to show what it offers
        app.click(step)
        app.wait_for(lands_on, timeout=15, name=f"guide-{step.split('.')[-1]}")
        for close in ("connections.close", "Done"):
            if app.see().find(close) is not None:
                app.click(close)
                break
    # Leave the setup as found, so later journeys start from nothing saved.
    app.open_screen("connections")
    for row, remove in (
        ("connections.guru", "Remove Guru"),
        ("connections.account.primary", "Remove Account"),
    ):
        if app.see().find(row) is not None:
            app.click(row)
            app.click(remove)


def j3_first_run_guidance(app: AppDriver) -> None:
    """With nothing saved, the app opens on Getting Started; a step opens its help when clicked,
    and the first step's button opens Connections."""
    guide = app.open_screen("gettingStarted")
    app.expect(
        guide, "Status: Not set up yet", "guide.step.0", "0 of 5", "How a post becomes a trade"
    )
    app.click("guide.step.0")
    app.expect(app.see("guide-step-open"), "Find a channel ID")
    app.click("guide.openDiscord")
    connections = app.see("connections-from-guide")
    app.expect(connections, "Discord", "Interpreter", "Alerts", "Channel IDs", "Step by step")
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
    app.click("people.openConnections")
    app.click("connections.gurus.add")
    app.expect(app.see("guru-from-connections"), "Where they post", "Remove Guru")
    app.click("Remove Guru")
    app.expect(app.see("guru-removed"), "connections.gurus.add", "Add a guru")


def j21_settings_pages(app: AppDriver) -> None:
    """Every Settings page opens from its own sidebar; back retraces them and close returns."""
    expected = {
        "general": (
            "When CopyTrading Opens",
            "settings.asksForOwner",
            "settings.startsCopying",
            "While Copying",
            "settings.keepsMacAwake",
        ),
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
    app.click("system.runSelfTest", outcome_checked=True)
    snapshot = app.wait_for("Last result", timeout=120, name="self-test")
    result = snapshot.find("Last result")
    if result is None or ("Completed" not in result.text and "Delivered" not in result.text):
        raise JourneyFailure(f"self-test did not succeed: {result.text if result else 'no result'}")


def j6_setup_editing(app: AppDriver) -> None:
    """Accounts and gurus are added in Connections; People and Accounts wait for a saved setup."""
    connections = app.open_screen("connections")
    app.expect(connections, "Broker accounts", "Gurus", "0 of 4 steps done", "setup.startCopying")
    app.click("connections.accounts.paper")
    sheet = app.see("account-sheet")
    app.expect(
        sheet,
        "Alpaca keys",
        "Position limits (USD)",
        "Maximum per stock",
        "Maximum below signal price (%)",
        "Ask me before sending orders",
        "Remove Account",
    )
    app.click("Done")
    app.expect(
        app.see("account-added"),
        "connections.account.primary",
        "Needs keys",
        "connections.accounts.add",
    )
    app.click("connections.gurus.add")
    guru = app.see("guru-sheet")
    # One guru copies into one account, sized from that account's maximum per stock.
    app.expect(
        guru,
        "Where they post",
        "playbook.learn",
        "Re-posted calls",
        "Skip re-posted calls",
        "Counts as a re-post within",
        "Copies into",
        "guru.sizingSummary",
    )
    # The re-post check is on at ten minutes; off, every post is copied and the minutes go away.
    app.click("Skip re-posted calls", role="checkbox")
    app.wait_gone("Counts as a re-post within", timeout=10)
    app.expect(
        app.see("guru-reposts-off"), "Every post is copied, even one that repeats an earlier call."
    )
    app.click("Skip re-posted calls", role="checkbox")
    app.wait_for("Counts as a re-post within", timeout=10, name="guru-reposts-on")
    app.click("Done")
    app.expect(app.see("guru-added"), "connections.guru", "Unnamed guru")
    # Unsaved accounts and gurus stay in Connections.
    app.expect(
        app.open_screen("people"), "The traders you choose to copy", "people.openConnections"
    )
    app.expect(app.open_screen("accounts"), "Your accounts, inside your limits")
    # Leave the setup as found, so later journeys start from nothing saved and nothing typed.
    app.open_screen("connections")
    app.click("connections.guru")
    app.click("Remove Guru")
    app.click("connections.account.primary")
    app.click("Remove Account")
    app.expect(app.see("setup-cleaned"), "connections.accounts.paper", "0 of 4 steps done")


def _relock(app: AppDriver) -> None:
    """Locking drops everything typed into the setup; unlocking returns to a clean draft."""
    app.click("Lock")
    app.wait_for("CopyTrading is locked", timeout=20)
    app.click("app.unlock")
    app.wait_for("navigation.today", timeout=30)


def j7_validation_gate(app: AppDriver) -> None:
    """Start Copying waits for all four steps; each step ticks as it is filled in."""
    app.open_screen("connections")
    app.open_connection("discord")
    app.type("123456789012345678", into="Channel IDs")
    app.click("connections.done")
    snapshot = app.see("start-waits")
    start = snapshot.find("setup.startCopying")
    if start is None:
        raise JourneyFailure("Connections did not offer Start Copying")
    if start.enabled:
        raise JourneyFailure("Start Copying was enabled before every step was done")
    app.expect(snapshot, "0 of 4 steps done", "Next: Connect Discord.")
    _relock(app)


def j23_learn_playbook(app: AppDriver) -> None:
    """The guru editor offers Learn from Channel and explains what it still needs."""
    app.open_screen("connections")
    app.click("connections.gurus.add")
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
    """Typed paper keys reach the draft; Start Copying waits for the credentials still missing.

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
    app.click("connections.accounts.paper")
    app.wait_for("Alpaca keys", timeout=15, name="paper-account-sheet")
    app.type(key, into="Alpaca API key")
    app.type(secret, into="Alpaca API secret")
    app.click("Done")
    app.wait_gone("Alpaca keys", timeout=60)
    app.click("connections.gurus.add")
    app.type("Journey Guru", into="Name")
    guru = app.see("guru-adopted-channel")
    app.expect(guru, "First channel in Connections (123456789012345678)")
    app.click("Done")
    gated = app.see("credential-gate")
    # The typed keys count; the Discord token and the model key are still missing.
    app.expect(
        gated, "Not saved yet", "Needs a token", "Needs an API key", "Next: Connect Discord."
    )
    app.expect_absent(gated, "Needs keys")
    start = gated.find("setup.startCopying")
    if start is None or start.enabled:
        raise JourneyFailure("Start Copying was enabled with credentials missing")
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
    app.expect(guide, "Get set up", "How a post becomes a trade", "Before you go", "Shortcuts")
    step = guide.find("guide.step.0")
    if step is None or "To do" not in step.text:
        raise JourneyFailure("Connect Discord was ticked before anything was typed")
    app.open_screen("connections")
    app.open_connection("discord")
    app.type("123456789012345678", into="Channel IDs")
    app.type("ui-journey-placeholder", into="Discord token")
    app.click("connections.close")
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


def _start_paper_setup(app: AppDriver, setup: dict[str, str]) -> None:
    """Fill Connections from nothing, top to bottom, and choose Start Copying."""
    app.open_screen("connections")
    app.open_connection("discord")
    app.type(setup["channel"], into="Channel IDs")
    app.type(setup["discord_token"], into="Discord token")
    app.connect()
    app.click("connections.provider.deepseek")
    app.type(setup["model"], into="Model")
    app.type(setup["model_key"], into="API key")
    app.connect()
    app.click("connections.accounts.paper")
    app.wait_for("Alpaca keys", timeout=15)
    app.type(setup["alpaca_key"], into="Alpaca API key")
    app.type(setup["alpaca_secret"], into="Alpaca API secret")
    app.click("Done")
    app.wait_gone("Alpaca keys", timeout=60)
    app.expect(app.see("connections-checked"), "Connected")
    app.click("connections.gurus.add")
    app.type("Journey Guru", into="Name")
    app.click("Done")
    app.expect(app.see("setup-filled"), "Ready to start. Every connection is checked first.")
    app.expect(app.open_screen("gettingStarted"), "4 of 5")
    app.open_screen("connections")
    app.click("setup.startCopying")


def _agent_result(app: AppDriver, expected_exit: int, *arguments: str) -> dict[str, Any]:
    """Run the command with `--json`, insist on its exit code, and return the result."""
    completed = _agent_command(app, *arguments, "--json")
    if completed.returncode != expected_exit:
        raise JourneyFailure(
            f"`copytrading {' '.join(arguments)}` exited {completed.returncode}, "
            f"expected {expected_exit}: {(completed.stderr or completed.stdout).strip()[:300]}"
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
    _start_paper_setup(app, setup)
    before = _wait_for_account(app, "primary", timeout=180)
    _wait_for_keep_awake(timeout=30)
    _check_mcp_reads_the_running_setup(app)
    if before["recovery_preference"] != "manual":
        raise JourneyFailure(f"a new account starts with recovery {before['recovery_preference']}")

    # Approving: the change waits for the owner, then runs exactly once.
    asked = _agent_result(app, 10, "accounts", "recovery", "primary", "automatic")
    sheet = app.wait_for("In primary, after a restart", timeout=30, name="approval-sheet")
    app.expect(sheet, "An agent is asking for approval", "Reject", "Approve…")
    if _wait_for_account(app, "primary", timeout=5)["recovery_preference"] != "manual":
        raise JourneyFailure("the recovery change ran before the owner approved it")
    app.click("Approve…", outcome_checked=True)
    approved = _agent_result(app, 0, "proposals", "wait", asked["proposal_id"], "--timeout", "60")
    if approved["state"] != "succeeded":
        raise JourneyFailure(f"the approved request ended {approved['state']}")
    if _wait_for_account(app, "primary", timeout=5)["recovery_preference"] != "automatic":
        raise JourneyFailure("the approved recovery change did not reach the account")
    app.see("approval-done")

    # Rejecting: the agent learns the outcome and the account never changes.
    resume = _agent_result(app, 10, "accounts", "resume", "primary")
    app.wait_for("Resume new entries in primary", timeout=30, name="resume-sheet")
    app.click("Reject", outcome_checked=True)
    rejected = _agent_result(app, 7, "proposals", "wait", resume["proposal_id"], "--timeout", "60")
    if rejected["state"] != "rejected":
        raise JourneyFailure(f"the rejected request ended {rejected['state']}")
    after = _wait_for_account(app, "primary", timeout=5)
    if after["entry_permission"] != before["entry_permission"]:
        raise JourneyFailure("a rejected resume still changed the account's entries")
    _check_every_cli_command(app, asked["proposal_id"])
    _agent_result(app, 0, "pause")
    _check_locked_app_still_pauses(app)


def _expect_exit(app: AppDriver, expected: int, *arguments: str) -> None:
    completed = _agent_command(app, *arguments)
    if completed.returncode != expected:
        raise JourneyFailure(
            f"`copytrading {' '.join(arguments)}` exited {completed.returncode}, "
            f"expected {expected}: {(completed.stderr or completed.stdout).strip()[:300]}"
        )


def _check_every_cli_command(app: AppDriver, approved_id: str) -> None:
    """Every `copytrading` command answers the running setup, in text and in JSON."""
    accounts = _agent_result(app, 0, "accounts")
    if [item["account_id"] for item in accounts["items"]] != ["primary"]:
        raise JourneyFailure(f"`accounts` listed {accounts['items']}")
    _expect_exit(app, 0, "accounts")
    _agent_result(app, 0, "activity")
    _expect_exit(app, 0, "activity")
    events = _agent_result(app, 0, "events", "primary")
    if not events["items"]:
        raise JourneyFailure("`events primary` lost the approved recovery change")
    _expect_exit(app, 0, "events", "primary")
    if _agent_result(app, 0, "proposals", "show", approved_id)["state"] != "succeeded":
        raise JourneyFailure("`proposals show` disagrees with the approved request")
    schema = _agent_command(app, "schema")
    if schema.returncode != 0 or {"request", "response"} - json.loads(schema.stdout).keys():
        raise JourneyFailure("`schema` did not print the contract's JSON Schema")

    # Manual orders refer to a post's reading; unknown ones fail without asking the owner:
    # a missing command is not found, and a missing correction makes the request invalid.
    _agent_result(app, 0, "manual", "list", "primary", "no-such-post")
    _expect_exit(app, 6, "manual", "show", "primary", "no-such-command")
    _expect_exit(
        app, 2, "manual", "preview", "primary", "--correction", "none", "--instruction", "0"
    )
    _expect_exit(app, 6, "manual", "confirm", "primary", "--preview", "none")
    _expect_exit(app, 2, "accounts", "recovery", "primary", "sometimes")

    # Pausing an account is safer, so it runs at once without asking.
    _agent_result(app, 0, "accounts", "pause", "primary")
    if _wait_for_account(app, "primary", timeout=5)["entry_permission"] != "paused":
        raise JourneyFailure("`accounts pause` did not pause the account's entries")


def _check_locked_app_still_pauses(app: AppDriver) -> None:
    """A locked app refuses reads but still lets an agent pause."""
    app.click("Lock")
    app.wait_for("CopyTrading is locked", timeout=20)
    _expect_exit(app, 4, "status")
    _expect_exit(app, 0, "pause")
    app.click("app.unlock")
    app.wait_for("navigation.today", timeout=30)


def _choose_in_file_panel(app: AppDriver, folder: Path, name: str | None = None) -> None:
    """Answer the open or save panel the way a person does: Go to Folder, then confirm."""
    time.sleep(1.5)
    app.press("cmd+shift+g")
    time.sleep(0.8)
    peekaboo("type", str(folder), "--foreground", "--clear", "--accept-dispatched")
    app.press("Return")
    time.sleep(1.0)
    if name is not None:
        peekaboo("type", name, "--foreground", "--clear", "--accept-dispatched")
        time.sleep(0.3)
    app.press("Return")


def j33_backup_and_restore(app: AppDriver) -> None:
    """A connected account's records back up, preview, and restore through Settings → Backups.

    Runs after J31, whose saved paper setup it backs up; the restored account comes back with
    entries off and manual recovery, which is what a restore promises.
    """
    if app.state_root is None:
        raise JourneySkipped("needs the run's state root")
    _paper_setup()
    folder = Path(tempfile.mkdtemp(prefix="copytrading-ui-backup.")).resolve()
    archive = folder / "Journey-Backup.zip"
    try:
        app.open_settings("backups")
        app.click("Create Backup…", real=True)
        _choose_in_file_panel(app, folder, archive.name)
        made = app.wait_for("Backup saved and checked", timeout=120, name="backup-created")
        app.expect(made, "Last verified backup")
        if not archive.is_file():
            raise JourneyFailure("the backup said it was created but no file is there")

        app.click("Restore from Backup…", real=True)
        _choose_in_file_panel(app, archive)
        preview = app.wait_for("Restore Preview", timeout=120, name="restore-preview")
        app.expect(preview, "Same installation", "primary", "Restore This Backup")
        app.click("Restore This Backup", outcome_checked=True)
        done = app.wait_for("Restored.", timeout=240, name="restore-activated")
        app.expect_absent(done, "Before it can restore")
        # A restore leaves copying paused, so read the account rather than wait for processing.
        accounts = _agent_result(app, 0, "accounts")["items"]
        restored = next((a for a in accounts if a["account_id"] == "primary"), None)
        if restored is None or (restored["entry_permission"], restored["recovery_preference"]) != (
            "disabled",
            "manual",
        ):
            raise JourneyFailure(f"the restored account came back as {restored}")
    except JourneyFailure:
        app.press("escape")  # a file panel left open would keep the app from quitting
        raise
    finally:
        shutil.rmtree(folder, ignore_errors=True)


TEST_SYMBOLS = (
    "SOFI",
    "NIO",
    "PLUG",
    "LCID",
    "AAL",
    "SNAP",
    "RIG",
    "GRAB",
    "HOOD",
    "RIVN",
    "PFE",
    "KGC",
    "VALE",
    "NOK",
    "MARA",
    "RIOT",
    "CLSK",
    "BTG",
    "AMC",
    "T",
    "BAC",
    "INTC",
    "LYFT",
    "CCL",
    "ITUB",
    "ABEV",
    "BBD",
    "KMI",
    "HBAN",
    "KEY",
    "VZ",
    "PCG",
    "NU",
    "CPNG",
    "XPEV",
    "CSCO",
    "KO",
    "PBR",
    "ET",
    "NCLH",
)


def _latest_price(setup: dict[str, str], symbol: str) -> Decimal:
    """The last trade on Alpaca's data feed, read with the paper keys."""
    request = urllib.request.Request(
        f"https://data.alpaca.markets/v2/stocks/{symbol}/trades/latest",
        headers={
            "APCA-API-KEY-ID": setup["alpaca_key"],
            "APCA-API-SECRET-KEY": setup["alpaca_secret"],
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return Decimal(str(json.load(response)["trade"]["p"]))


def _post_test_call(setup: dict[str, str], text: str) -> None:
    """Post one call into the test channel as the test account, the way a guru would."""
    posted = subprocess.run(
        # The engine's environment has the Discord client the engine itself reads with.
        [
            "uv",
            "run",
            "--directory",
            str(ROOT / "engine"),
            "--frozen",
            "python",
            str(ROOT / "app/scripts/discord_test_post.py"),
            setup["channel"],
            text,
        ],
        env={**os.environ, "COPYTRADING_TEST_DISCORD_TOKEN": setup["discord_token"]},
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    if posted.returncode != 0:
        raise JourneyFailure(f"the test post failed: {posted.stderr.strip()[-300:]}")


def _copying_with_entries(app: AppDriver) -> None:
    """Copying on, automatic recovery, and entries on, asking the owner where the app asks."""
    # Copying is paused after a restore; start it again from the toolbar. The button toggles, so
    # it is pressed only when it offers Start: an earlier journey may have left copying on.
    app.open_screen("today")
    toolbar = app.see().find("toolbar.copying")
    if toolbar is not None and "Start" in toolbar.label:
        app.click("toolbar.copying")
    _wait_for_account(app, "primary", timeout=180)

    # A restored account waits for the owner to choose automatic recovery again.
    if _wait_for_account(app, "primary", timeout=10)["recovery_preference"] != "automatic":
        asked = _agent_result(app, 10, "accounts", "recovery", "primary", "automatic")
        app.wait_for("In primary, after a restart", timeout=30, name="recovery-sheet")
        app.click("Approve…", outcome_checked=True)
        done = _agent_result(app, 0, "proposals", "wait", asked["proposal_id"], "--timeout", "60")
        if done["state"] != "succeeded":
            raise JourneyFailure(f"setting automatic recovery ended {done['state']}")

    # Entries start off after setup and after a restore; turning them on asks the owner.
    if _wait_for_account(app, "primary", timeout=10)["entry_permission"] != "enabled":
        resume = _agent_result(app, 10, "accounts", "resume", "primary")
        app.wait_for("Resume new entries in primary", timeout=30, name="resume-sheet")
        app.click("Approve…", outcome_checked=True)
        done = _agent_result(app, 0, "proposals", "wait", resume["proposal_id"], "--timeout", "60")
        if done["state"] != "succeeded":
            raise JourneyFailure(f"resuming entries ended {done['state']}")


def _trading_hours() -> bool:
    """Regular hours, a little inside the bell. Copying, previews, and sales check the quote's
    age, and the free IEX feed goes quiet outside regular hours, so quotes read as stale."""
    now = dt.datetime.now(ZoneInfo("America/New_York"))
    return now.weekday() < 5 and dt.time(9, 35) <= now.time() <= dt.time(15, 50)


def _set_ask_before_orders(app: AppDriver, on: bool) -> None:
    """Flip "Ask me before sending orders" in the account sheet and apply it with Start Copying.

    A saved setup changes only while copying is paused ("Pause copying to save these changes")."""
    toolbar = app.see().find("toolbar.copying")
    if toolbar is not None and "Pause" in toolbar.label:
        app.click("toolbar.copying")
        app.wait_for("Start Copying", timeout=60)
    app.open_screen("connections")
    app.click("connections.account.primary")
    switch = app.see().find("Ask me before sending orders", role="checkbox")
    if switch is None:
        raise JourneyFailure("the account sheet has no 'Ask me before sending orders' switch")
    if (switch.value == "1") != on:
        app.click("Ask me before sending orders", role="checkbox")
    app.click("Done")
    start = app.see().find("setup.startCopying")
    if start is not None and start.enabled:
        app.click("setup.startCopying")
    else:
        toolbar = app.see().find("toolbar.copying")
        if toolbar is not None and "Start" in toolbar.label:
            app.click("toolbar.copying")
    _wait_for_account(app, "primary", timeout=180)


def _post_and_wait_for_hold(app: AppDriver, setup: dict[str, str], symbol: str) -> None:
    price = (_latest_price(setup, symbol) * Decimal("1.004")).quantize(Decimal("0.01"))
    _post_test_call(setup, f"Bought {symbol} at {price}")
    app.open_screen("activity")
    app.click("Waiting for You")
    app.wait_for("activity.copy", timeout=240, name=f"held-{symbol.lower()}")


def j36_approve_and_skip(app: AppDriver) -> None:
    """With "Ask me before sending orders" on, a real call waits in Activity: Skip drops it, and
    Approve… copies it into Alpaca paper through the review sheet. The lot is then sold.

    Needs a saved paper setup (after J31, or --reuse-state) and Alpaca's trading hours.
    """
    if app.state_root is None:
        raise JourneySkipped("needs the run's state root")
    setup = _paper_setup()
    if not _trading_hours():
        raise JourneySkipped("the market is not in regular hours")
    _copying_with_entries(app)
    _set_ask_before_orders(app, True)
    unused = _unposted_symbols(app)
    if len(unused) < 2:
        raise JourneySkipped("no unused test symbols left today")
    try:
        # Skip: the call leaves the waiting list and nothing is bought.
        _post_and_wait_for_hold(app, setup, unused[0])
        app.click("activity.skip")
        app.wait_gone("activity.copy", timeout=30)
        if _lots(app, unused[0]):
            raise JourneyFailure("a skipped call still bought shares")

        # Approve: review the held call, preview it, and confirm one order.
        symbol = unused[1]
        _post_and_wait_for_hold(app, setup, symbol)
        app.click("activity.copy")
        app.wait_for("Save Correction", timeout=30, name="approval-sheet")
        app.click("Save Correction")
        app.wait_for("Preview Orders", timeout=60, name="approval-saved")
        app.click("Preview Orders")
        app.wait_for("Review 1 Ready Order…", timeout=60, name="approval-preview")
        app.click("Review 1 Ready Order…")
        app.click("Confirm 1 order(s)", outcome_checked=True)
        deadline = time.monotonic() + 180
        while not (bought := [lot for lot in _lots(app, symbol) if _open(lot)]):
            if time.monotonic() > deadline:
                app.see("timeout-approved-order")
                raise JourneyFailure(f"the approved call did not buy {symbol} on Alpaca paper")
            time.sleep(5)
        app.click("Close")
        # An approved call stops waiting: a second approval must not be offered.
        approved = next(
            item
            for item in _agent_result(app, 0, "activity", "--limit", "20")["items"]
            if f"Bought {symbol} " in str(item.get("untrusted_source_text") or "")
        )
        outcomes = {o for d in approved["destinations"] for o in d["instruction_outcomes"]}
        if outcomes != {"approved_by_owner"}:
            raise JourneyFailure(f"the approved call still reads {sorted(outcomes)}")
        app.open_screen("activity")
        app.click("Waiting for You")
        deadline = time.monotonic() + 30
        while app.see().find(f"Bought {symbol} ") is not None:
            if time.monotonic() > deadline:
                app.see(f"still-waiting-{symbol.lower()}")
                raise JourneyFailure("the approved call is still listed under Waiting for You")
            time.sleep(3)
        app.see(f"approved-{symbol.lower()}")
        _sell_lot(app, symbol, bought[0])
    finally:
        _set_ask_before_orders(app, False)
        # Leave nothing that could copy the next post in the test channel by itself.
        _agent_result(app, 0, "accounts", "pause", "primary")


def j38_today_chart(app: AppDriver) -> None:
    """With a saved setup, Today's chart opens its day picker and its range details, and the
    toolbar opens and closes the assistant. Run after J31, or with --reuse-state."""
    if app.state_root is None:
        raise JourneySkipped("needs the run's state root")
    _paper_setup()
    today = app.open_screen("today")
    if today.find("today.day") is None:
        raise JourneySkipped("needs a saved setup with an equity chart")
    app.click("today.day")
    picker = app.wait_for("Chart day", timeout=15, name="chart-day-picker")
    app.expect(picker, "Done")
    app.click("Done")
    app.wait_gone("Done", timeout=10)  # the button itself is labelled "Chart day, …"
    app.click("today.rangeDetails")
    app.expect(app.wait_for("High", timeout=15, name="range-details"), "Low")
    app.click("toolbar.assistant")
    app.wait_for("assistant.panel", timeout=15, name="assistant-open")
    app.click("toolbar.assistant")
    app.wait_gone("assistant.panel", timeout=15)


def j35_copy_and_sell(app: AppDriver) -> None:
    """A real call in the test channel is held for approval, approved into Alpaca paper, and the
    lot it bought is sold from Accounts.

    Needs a saved paper setup (run after J31, or with --reuse-state) and an open market. It posts
    one short call in the test channel and trades one share on Alpaca paper.
    """
    if app.state_root is None:
        raise JourneySkipped("needs the run's state root")
    setup = _paper_setup()
    if not _trading_hours():
        raise JourneySkipped("the market is not in regular hours")

    _copying_with_entries(app)

    # A lot an earlier run bought and never sold is sold first, so a rerun does not buy again.
    held = [(s, lot) for s in TEST_SYMBOLS for lot in _lots(app, s) if _open(lot)]
    if held:
        symbol, lot = held[0]
    else:
        # A call identical to an earlier one is skipped as a repeat, so each run picks the
        # first cheap symbol the account has not bought today.
        unposted = _unposted_symbols(app)
        if not unposted:
            raise JourneySkipped("every test symbol was already posted today")
        symbol = unposted[0]
        # Quote a little above the last trade so the copied limit order fills on paper, as a
        # real guru's buy usually does; a limit exactly at the last price can time out.
        price = (_latest_price(setup, symbol) * Decimal("1.004")).quantize(Decimal("0.01"))
        _post_test_call(setup, f"Bought {symbol} at {price}")
        deadline = time.monotonic() + 240
        while not (bought := [lot for lot in _lots(app, symbol) if _open(lot)]):
            if time.monotonic() > deadline:
                app.open_screen("activity")
                app.see("timeout-copied-call")
                raise JourneyFailure(f"the posted call did not buy {symbol} on Alpaca paper")
            time.sleep(5)
        lot = bought[0]

    _sell_lot(app, symbol, lot)
    _agent_result(app, 0, "accounts", "pause", "primary")


def _sell_lot(app: AppDriver, symbol: str, lot: dict[str, Any]) -> None:
    """Sell one lot from Accounts: review first, then sell, and wait for the fill."""
    app.open_screen("accounts")
    # A lot bought moments ago appears once Accounts next syncs with the broker.
    app.wait_for(f"accounts.position.{symbol}", timeout=60, name="accounts-position")
    app.click(f"accounts.position.{symbol}")
    app.click(f"accounts.lot.sell.{lot['lot_id']}")
    app.click("lotSale.review.button")
    app.wait_for("lotSale.sell", timeout=60, name="lot-sale-review")
    app.click("lotSale.sell", outcome_checked=True)
    app.wait_for("lotSale.outcome", timeout=60, name="lot-sale-sent")
    deadline = time.monotonic() + 120
    while any(left["lot_id"] == lot["lot_id"] and _open(left) for left in _lots(app, symbol)):
        if time.monotonic() > deadline:
            raise JourneyFailure("the lot sale did not fill on Alpaca paper within two minutes")
        time.sleep(5)
    app.click("Done")


def _unposted_symbols(app: AppDriver) -> list[str]:
    """Test symbols with no call in the channel yet: a second identical call is a repeat."""
    posts = " ".join(
        str(item.get("untrusted_source_text") or "")
        for item in _agent_result(app, 0, "activity", "--limit", "100")["items"]
    )
    return [symbol for symbol in TEST_SYMBOLS if f"Bought {symbol} " not in posts]


def _open(lot: dict[str, Any]) -> bool:
    return Decimal(str(lot["remaining_qty"])) > 0


def _lots(app: AppDriver, symbol: str) -> list[dict[str, Any]]:
    """The copier's lots of one symbol in the primary account, as the agent sees them."""
    accounts = _agent_result(app, 0, "accounts")["items"]
    primary = next((a for a in accounts if a["account_id"] == "primary"), None)
    if primary is None:
        return []
    return [
        lot
        for position in primary["positions"]
        if position["symbol"] == symbol
        for lot in position["lots"]
    ]


def _check_mcp_reads_the_running_setup(app: AppDriver) -> None:
    """`copytrading mcp` answers an MCP client with the same setup the window shows."""
    assert app.state_root is not None
    server = subprocess.Popen(
        [str(DEBUG_APP / "Contents/Helpers/copytrading"), "mcp"],
        env={
            "PATH": "/usr/bin:/bin",
            "HOME": str(Path.home()),
            "COPYTRADING_STATE_ROOT": str(app.state_root),
        },
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    assert server.stdin is not None
    assert server.stdout is not None
    output = server.stdout
    replies: dict[int, dict[str, Any]] = {}

    def send(message: dict[str, Any]) -> None:
        assert server.stdin is not None
        server.stdin.write(json.dumps(message) + "\n")
        server.stdin.flush()

    def reply(request_id: int, method: str, params: dict[str, Any]) -> dict[str, Any]:
        send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + 30
        while request_id not in replies:
            remaining = deadline - time.monotonic()
            # Wait for a line with a deadline: a hung server must fail the journey, not stall it.
            if remaining <= 0 or not select.select([output], [], [], remaining)[0]:
                raise JourneyFailure(f"MCP {method} got no reply")
            line = output.readline()
            if not line:
                raise JourneyFailure(f"MCP server exited during {method}")
            message = json.loads(line)
            if "id" in message:
                replies[message["id"]] = message
        answer = replies[request_id]
        if "error" in answer:
            raise JourneyFailure(f"MCP {method} failed: {answer['error']}")
        return answer["result"]

    try:
        reply(
            1,
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "ui-journeys", "version": "1"},
            },
        )
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        tools = {tool["name"] for tool in reply(2, "tools/list", {})["tools"]}
        missing = {"get_status", "list_accounts", "list_activity", "pause_processing"} - tools
        if missing:
            raise JourneyFailure(f"the MCP server lacks {sorted(missing)}")
        status = reply(3, "tools/call", {"name": "get_status", "arguments": {}})
        accounts = reply(4, "tools/call", {"name": "list_accounts", "arguments": {}})
        if status.get("isError") or accounts.get("isError"):
            raise JourneyFailure(f"an MCP read failed: {status} {accounts}")
        if "primary" not in json.dumps(accounts):
            raise JourneyFailure("MCP list_accounts did not include the account the window shows")
    finally:
        server.terminate()
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()


def _wait_for_keep_awake(timeout: float) -> None:
    """While copying, macOS must list the app under test as keeping the Mac awake.

    The assertion has to belong to the debug app's own process: another CopyTrading on this Mac
    holds one with the same name when it copies.
    """
    pids = subprocess.run(
        ["pgrep", "-f", str(DEBUG_APP / "Contents/MacOS/CopyTrading")],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.split()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        assertions = subprocess.run(
            ["pmset", "-g", "assertions"], capture_output=True, text=True, check=False
        ).stdout.splitlines()
        if any(
            "CopyTrading is copying trades" in line and any(f"pid {pid}(" in line for pid in pids)
            for line in assertions
        ):
            return
        time.sleep(1)
    raise JourneyFailure("copying did not keep the Mac awake: no CopyTrading sleep assertion")


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
    """Every service is a row with Connect; More services lists the rest in place; a local model
    asks for an address and no key; an alerts panel closed untouched stays off."""
    page = app.open_screen("connections")
    app.expect(
        page,
        "Discord token and channels",
        "connections.provider.anthropic",
        "connections.provider.deepseek",
        "connections.provider.ollama",
        "More services",
        "Setup Tips",
    )
    app.click("connections.interpreter.more")
    expanded = app.see("connections-more-services")
    app.expect(
        expanded, "connections.provider.openrouter", "connections.provider.groq", "Fewer services"
    )
    app.click("connections.provider.ollama")
    time.sleep(0.8)
    local = app.see("connections-ollama")
    app.expect(local, "Connect to Ollama", "Base URL", "API key")
    app.click("connections.close")
    app.click("connections.alerts")
    time.sleep(0.8)
    app.expect(
        app.see("connections-alerts"), "Connect to Telegram", "Chat ID", "Bot token", "Step by step"
    )
    app.click("connections.close")
    closed = app.see("connections-alerts-closed")
    app.expect(closed, "Telegram bot", "connections.idea.channelID", "connections.hideIdeas")


def j32_connection_check(app: AppDriver) -> None:
    """Connect checks the service there and then: a server that isn't there keeps the panel
    open and says what to fix, and the row says it couldn't connect."""
    app.open_screen("connections")
    app.click("connections.provider.openai_compatible")
    time.sleep(0.8)
    # Port 9 is the discard port: nothing listens there, so the check fails without a network.
    app.type("http://127.0.0.1:9/v1", into="Base URL")
    app.type("journey-model", into="Model")
    app.click("connections.done")
    failed = app.wait_for("connections.problem", timeout=90, name="connection-check-failed")
    app.expect(failed, "Nothing answered at that address", "connections.done")
    app.click("connections.close")
    app.expect(app.see("connection-check-row"), "Couldn't connect")
    _relock(app)


def j30_assistant(app: AppDriver) -> None:
    """The assistant answers from a local OpenAI-compatible model and closes on Esc.

    The model is a scripted stub that checks whether copying is running, then answers. The setup
    draft's interpreter is enough: nothing is saved and no key is involved.
    """
    with ScriptedModelServer() as stub:
        app.open_screen("connections")
        app.click("connections.provider.openai_compatible")
        time.sleep(0.8)
        app.expect(app.see("assistant-model-editor"), "Connect to", "Base URL", "Model")
        app.type(stub.base_url, into="Base URL")
        app.type("scripted", into="Model")
        app.click("connections.close")

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
    ("J37 everyday buttons", j37_everyday_buttons),
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
    ("J32 connection check", j32_connection_check),
    ("J25 getting started", j25_getting_started),
    ("J30 assistant", j30_assistant),
    ("J26 help menu", j26_help_menu),
    ("J15 lock", j15_lock),
    ("J17 crash recovery", j17_crash_recovery),
    # Last: starting copying saves a setup that the journeys above expect to be empty.
    ("J31 agent approval", j31_agent_approval),
    ("J33 backup and restore", j33_backup_and_restore),
    ("J38 today chart", j38_today_chart),
    ("J35 copy and sell", j35_copy_and_sell),
    ("J36 approve and skip", j36_approve_and_skip),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--only", help="comma-separated journey IDs, e.g. J1,J5")
    parser.add_argument("--keep-state", action="store_true")
    parser.add_argument(
        "--reuse-state",
        type=Path,
        help="run on a state kept by --keep-state (for example after J31) instead of a fresh one; "
        "it and its saved keys are kept for the next run",
    )
    parser.add_argument(
        "--discard-state",
        type=Path,
        help="delete a kept state and the test keys it saved in the login Keychain, then exit",
    )
    args = parser.parse_args()

    if args.discard_state is not None:
        target = args.discard_state.resolve()
        temporary = Path(tempfile.gettempdir()).resolve()
        if not (target.name.startswith("copytrading-ui-journey.") and target.parent == temporary):
            raise SystemExit(f"not a journey state in {temporary}: {args.discard_state}")
        if _forget_test_keychain(target):
            raise SystemExit("test keys remain in the login Keychain")
        shutil.rmtree(target, ignore_errors=True)
        return 0
    if shutil.which("peekaboo") is None:
        raise SystemExit("install Peekaboo first: brew install steipete/tap/peekaboo")
    if not args.skip_build:
        build_debug_bundle()

    # The per-user temporary directory; /tmp is a symlink, which the app's state checks reject.
    reusing = args.reuse_state is not None
    if reusing and not args.reuse_state.is_dir():
        raise SystemExit(f"no kept state at {args.reuse_state}")
    state_root = (
        args.reuse_state if reusing else Path(tempfile.mkdtemp(prefix="copytrading-ui-journey."))
    )
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
        if not reusing and not args.keep_state and _forget_test_keychain(state_root):
            runner.results.append(
                Result("Keychain cleanup", "failed", "test keys remain in the login Keychain")
            )
            print(f"FAILED   Keychain cleanup {runner.results[-1].detail}")
        if args.keep_state or reusing:
            print(f"state kept at {state_root}")
            print(
                "  its test keys stay in the login Keychain until you run:\n"
                f"  app/scripts/ui_journeys.py --discard-state {state_root}"
            )
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
