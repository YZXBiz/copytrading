"""The journeys' layout check: text boxes that collide, or reach past the window."""

from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from ui_journeys import layout_problems  # noqa: E402 - importable only after the path is set


def _snapshot(*elements, window=((0, 0), (800, 600))):
    """A `peekaboo see` capture: each element's role, label, and ((x, y), (width, height))."""
    return {
        "coordinate_context": {"logical_bounds": window},
        "ui_elements": [
            {"ax_role": role, "label": label, "bounds": {"x": x, "y": y, "width": w, "height": h}}
            for role, label, ((x, y), (w, h)) in elements
        ],
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
        # An invisible tap target over a label is not a collision.
        ("AXButton", "5. You see it: In your account", ((300, 100), (200, 140))),
        ("AXStaticText", "Later", ((320, 110), (60, 20))),
    )

    assert layout_problems(snapshot) == []


def test_text_cut_off_at_the_window_edge_is_a_problem_and_hidden_text_is_not():
    snapshot = _snapshot(
        ("AXStaticText", "After hours", ((780, 500), (60, 14))),
        ("AXStaticText", "Archive", ((-220, 300), (49, 17))),
    )

    assert layout_problems(snapshot) == ["'After hours' is cut off at the window's edge"]


def test_a_capture_without_frames_never_passes_silently():
    snapshot = {"ui_elements": [{"ax_role": "AXStaticText", "label": "Connections"}]}

    assert layout_problems(snapshot) == [
        "no text frames in the capture; the layout check saw nothing"
    ]
