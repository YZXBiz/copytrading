"""The model services an owner can choose to read posts, and where a custom one may live."""

from typing import Literal, get_args
from urllib.parse import urlsplit

from pydantic import BaseModel, ConfigDict, Field, SecretStr

type ModelProvider = Literal[
    "anthropic",
    "openai",
    "google",
    "deepseek",
    "openrouter",
    "groq",
    "xai",
    "mistral",
    "together",
    "fireworks",
    "cerebras",
    "moonshotai",
    "ollama",
    "openai_compatible",
]

MODEL_PROVIDERS: tuple[ModelProvider, ...] = get_args(ModelProvider.__value__)

# Models that run where the owner chooses: the key is optional and the address is theirs.
LOCAL_PROVIDERS: frozenset[ModelProvider] = frozenset({"ollama", "openai_compatible"})

OLLAMA_ENDPOINT = "http://localhost:11434/v1"

_LOOPBACK = {"localhost", "127.0.0.1", "::1"}


def endpoint_problem(url: str) -> str | None:
    """Why an owner-entered model address cannot be used, or None when it can. Plain HTTP is
    allowed only to this Mac, so a key and the posts never cross the network unencrypted."""
    parts = urlsplit(url)
    if parts.scheme not in {"https", "http"} or not parts.hostname:
        return "The address must start with https:// and name a host"
    if parts.username or parts.password or parts.query or parts.fragment:
        return "The address cannot carry a user, password, query, or fragment"
    if parts.scheme == "http" and parts.hostname not in _LOOPBACK:
        return "Plain http:// is allowed only for a model on this Mac (localhost)"
    return None


class ProviderConfig(BaseModel):
    """What a reader needs to reach its model. The key is empty only for a model on this Mac or a
    custom service that takes none; `ProviderConfiguration.reader()` enforces that."""

    model_config = ConfigDict(frozen=True, hide_input_in_errors=True)

    api_key: SecretStr
    model: str = Field(min_length=1)
    timeout: float = Field(gt=0, allow_inf_nan=False)
    base_url: str | None = None
