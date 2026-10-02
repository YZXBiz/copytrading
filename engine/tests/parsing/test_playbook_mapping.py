"""A company name reaches a ticker only through one explicit playbook line."""

from hypothesis import given
from hypothesis import strategies as st

from copytrading_engine.parsing.extraction import playbook_maps

names = st.text(alphabet=st.characters(categories=("Lo", "Ll")), min_size=1, max_size=8).filter(
    lambda name: not name.isascii()
)
tickers = st.from_regex(r"[A-Z]{1,5}", fullmatch=True)
filler = st.lists(st.from_regex(r"[a-z ]{0,20}", fullmatch=True), max_size=5)


@given(names, tickers, filler)
def test_a_stated_mapping_always_resolves(name, ticker, other_lines):
    playbook = "\n".join([*other_lines, f"{name} means {ticker}"])
    assert playbook_maps(playbook, name, ticker)


@given(names, tickers, tickers)
def test_name_and_ticker_on_different_lines_never_resolve(name, ticker, other):
    playbook = f"{name} is a company\n{other} is a stock"
    assert playbook_maps(playbook, name, ticker) == (False or (ticker == other and False))


@given(names, tickers)
def test_a_longer_ticker_does_not_stand_in_for_a_shorter_one(name, ticker):
    assert not playbook_maps(f"{name} means {ticker}X", name, ticker)
