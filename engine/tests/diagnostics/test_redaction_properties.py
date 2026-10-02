"""Generated payloads: no known encoding of a registered secret survives redaction."""

import base64
import html
import json
import re
from urllib.parse import quote, quote_plus

from hypothesis import given, settings
from hypothesis import strategies as st

from copytrading_engine.diagnostics.redaction import redact_with_count

# Every secret carries each character that some encoding rewrites, so each encoding
# below is distinct from the raw secret and a missing form cannot hide behind another.
ENCODING_SENSITIVE = '&"<>+/ ~!$'
SECRETS = st.builds(
    lambda core, specials: (
        "".join(character for pair in zip(core, specials, strict=False) for character in pair)
        + core[len(specials) :]
    ),
    st.text(alphabet="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789", min_size=12),
    st.permutations(ENCODING_SENSITIVE).map("".join),
)
NOISE = st.text(alphabet="abcdefghijklmnopqrstuvwxyz0123456789 :/-", max_size=12)
SAFE_KEYS = st.sampled_from(["message", "detail", "body", "path", "items", "note"])


def _encodings(secret: str) -> tuple[str, ...]:
    """The encodings a secret may take in wire payloads, error strings, and URLs."""
    raw = secret.encode()
    return (
        secret,
        quote(secret, safe=""),
        re.sub(r"%[0-9A-F]{2}", lambda escape: escape.group(0).lower(), quote(secret, safe="")),
        quote_plus(secret),
        base64.b64encode(raw).decode(),
        base64.b64encode(raw).decode().rstrip("="),
        base64.urlsafe_b64encode(raw).decode(),
        base64.urlsafe_b64encode(raw).decode().rstrip("="),
        json.dumps(secret)[1:-1],
        html.escape(secret, quote=True),
        raw.hex(),
    )


@st.composite
def payloads_with(draw: st.DrawFn, secret: str) -> object:
    leaf = [draw(NOISE) + encoded + draw(NOISE) for encoded in _encodings(secret)]
    scalars = st.one_of(st.integers(), st.booleans(), st.none(), NOISE)
    tree = st.recursive(
        scalars,
        lambda children: st.one_of(
            st.lists(children, max_size=3),
            st.dictionaries(SAFE_KEYS, children, max_size=3),
        ),
        max_leaves=8,
    )
    path = draw(st.lists(SAFE_KEYS, min_size=0, max_size=3))
    node: object = leaf
    for key in reversed(path):
        node = {key: node, "sibling": draw(tree)}
    return node


@settings(max_examples=150, deadline=None)
@given(data=st.data(), secret=SECRETS)
def test_no_encoded_secret_survives_redaction(data, secret):
    payload = data.draw(payloads_with(secret))

    redacted = json.dumps(redact_with_count(payload, secrets=(secret,)).value, ensure_ascii=False)

    for encoded in _encodings(secret):
        assert encoded not in redacted


@settings(max_examples=100, deadline=None)
@given(data=st.data(), secret=SECRETS)
def test_redaction_is_idempotent(data, secret):
    payload = data.draw(payloads_with(secret))

    once = redact_with_count(payload, secrets=(secret,)).value

    assert redact_with_count(once, secrets=(secret,)).value == once
