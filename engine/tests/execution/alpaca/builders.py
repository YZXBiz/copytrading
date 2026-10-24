"""An Alpaca broker wired to a scripted HTTP transport."""

from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import (
    AlpacaBroker,
    AlpacaCredentials,
)


def make_broker(key, secret, *, environment="paper", transport=None, clock=None):
    credentials = AlpacaCredentials(SecretStr(key), SecretStr(secret))
    if clock is None:
        return AlpacaBroker(credentials, environment, transport=transport)
    return AlpacaBroker(credentials, environment, transport=transport, clock=clock)
