"""Registered adapters for model-provider clients."""

from .registry import (
    DecoderFactory,
    ManagedDecoder,
    ProviderRegistry,
    builtin_registry,
)

__all__ = [
    "DecoderFactory",
    "ManagedDecoder",
    "ProviderRegistry",
    "builtin_registry",
]
