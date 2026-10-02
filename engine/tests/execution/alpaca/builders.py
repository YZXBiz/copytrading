"""An Alpaca broker wired to a scripted HTTP transport."""

from pydantic import SecretStr

from copytrading_engine.execution.adapters.alpaca.broker import (
    AlpacaBroker,
    AlpacaCredentials,
)


def make_broker(key, secret, *, environment="paper", transport=None):
    credentials = AlpacaCredentials(SecretStr(key), SecretStr(secret))
    return AlpacaBroker(credentials, environment, transport=transport)
