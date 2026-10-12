"""The journeys' layout check: text boxes that collide, or reach past the window."""

from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from ui_journeys import layout_problems  # noqa: E402 - importable only after the path is set


def _snapshot(*elements, window=((0, 0), (800, 600))):
    return {
        "windowBounds": window,
        "uiMap": {
            f"e{i}": {"role": role, "label": label, "frame": frame}
            for i, (role, label, frame) in enumerate(elements)
        },
    }


def test_two_labels_drawn_over_each_other_are_a_problem():
    # The chart's "PRE-MARKET" written across its "06:30".
    snapshot = _snapshot(
        ("AXStaticText", "PRE-MARKET", ((100, 500), (80, 14))),
        ("AXStaticText", "06:30", ((150, 502), (40, 14))),
    )

    assert layout_problems(snapshot) == ["'PRE-MARKET' overlaps '06:30'"]


def test_side_by_side_and_nested_text_is_fine():
    snapshot = _snapshot(
        ("AXStaticText", "6:30 AM", ((100, 500), (50, 14))),
        ("AXStaticText", "8:00 AM", ((160, 500), (50, 14))),
        ("AXButton", "Buy $100 of NFLX", ((300, 100), (200, 40))),
        ("AXStaticText", "Buy $100 of NFLX", ((320, 110), (160, 20))),
    )

    assert layout_problems(snapshot) == []


def test_text_past_the_window_edge_is_a_problem():
    snapshot = _snapshot(("AXStaticText", "After hours", ((780, 500), (60, 14))))

    assert layout_problems(snapshot) == ["'After hours' reaches past the window's edge"]
