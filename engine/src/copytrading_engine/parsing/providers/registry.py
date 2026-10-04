"""The fixed registry and shared contracts for parser provider adapters."""

from collections.abc import Awaitable, Callable, Mapping
from types import MappingProxyType
from typing import Protocol

from pydantic_ai.models import Model

from copytrading_engine.parsing.extraction import Decoder
from copytrading_engine.parsing.learning import Learner
from copytrading_engine.shared.model_providers import ModelProvider, ProviderConfig
from copytrading_engine.shared.payload_capture import PayloadCapture


class ManagedDecoder(Decoder, Learner, Protocol):
    async def model_names(self) -> tuple[str, ...]:
        """The model names the provider lists for this key."""
        ...

    async def close(self) -> None: ...


DecoderFactory = Callable[..., Awaitable[ManagedDecoder]]
type NamedDecoderFactory = Callable[[str, ProviderConfig], Awaitable[ManagedDecoder]]
"""Create the named provider's decoder; the caller must close it."""


class ProviderRegistry:
    def __init__(self, factories: Mapping[str, DecoderFactory]) -> None:
        self._factories: Mapping[str, DecoderFactory] = MappingProxyType(dict(factories))

    def names(self) -> tuple[str, ...]:
        return tuple(sorted(self._factories))

    async def create(
        self,
        name: str,
        config: ProviderConfig,
        *,
        diagnostics: PayloadCapture | None = None,
    ) -> ManagedDecoder:
        try:
            factory = self._factories[name]
        except KeyError:
            raise ValueError(f"Unknown LLM provider: {name}") from None
        if diagnostics is None:
            return await factory(config)
        return await factory(config, diagnostics=diagnostics)


def builtin_registry() -> ProviderRegistry:
    from .anthropic import create_decoder as create_anthropic_decoder
    from .deepseek import create_decoder as create_deepseek_decoder
    from .openai_compatible import factories as openai_compatible_factories

    return ProviderRegistry(
        {
            "anthropic": create_anthropic_decoder,
            "deepseek": create_deepseek_decoder,
            **openai_compatible_factories(),
        }
    )


async def open_chat_model(
    name: ModelProvider, config: ProviderConfig
) -> tuple[Model, Callable[[], Awaitable[None]]]:
    """The interpreter as a plain chat model, for the assistant; the caller closes it."""
    from . import anthropic, deepseek, openai_compatible

    if name == "anthropic":
        client = anthropic.client(config)
        return anthropic.chat_model(config, client), client.close
    if name == "deepseek":
        client = deepseek.client(config)
        return deepseek.chat_model(config, client), client.close
    service = openai_compatible.SERVICES[name]
    client = openai_compatible.client(service, config)
    return openai_compatible.chat_model(service, config, client), client.close
