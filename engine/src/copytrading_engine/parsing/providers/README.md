# Adding a stock parser provider

The registry offers Anthropic (`anthropic.py`, native structured output), DeepSeek (`deepseek.py`, prompted JSON with thinking disabled), and every OpenAI-style service through `openai_compatible.py`: one adapter whose `SERVICES` table gives each service its address and, where PydanticAI has one, its provider class and model profile. Adding another OpenAI-compatible service is one `SERVICES` entry plus its name in `shared/model_providers.py`; a service with its own wire format gets a module like the ones below.

Providers are selected once during parser startup from the fixed `ProviderRegistry`. A provider owns its client, wire format, bounded decoder, provider-specific error translation, and asynchronous close. The worker owns freshness checks, immutable routes, request budgets, retry policy, validation, evidence grounding, and publication. A provider must not contain trade routing or broker behavior.

## Decoder contract

Implement `Decoder.decode(text, route)` and `ManagedDecoder.close()`:

```python
class ExampleDecoder:
    async def decode(self, text: str, route: Route) -> DecodedMessage: ...

    async def close(self) -> None: ...
```

`DecodedMessage` is frozen and rejects unknown fields. It contains `decision` (`trade`, `ignore`, or `review`), a nonempty bounded `reason`, and at most 20 typed instructions. Only `trade` may contain instructions; ignore and review results have none. The parser applies deterministic grounding and route validation after decode, so a provider response alone cannot authorize an order.

Translate expected provider, timeout, and output-validation failures to `DecodeError(reason, retryable=..., issues=...)`. Use a stable sanitized reason and typed `ValidationIssue` values. Do not retain provider response bodies, prompts, API keys, or exception text in errors or diagnostics. Let cancellation propagate; it is lifecycle control, not a provider failure. The common PydanticAI adapter shows the existing timeout, bounded-output, and sanitized-error pattern.

`ManagedDecoder.close()` is awaited once during startup unwind or process shutdown. If factory construction fails after allocating a client, the factory closes that client before re-raising. The adapter owns client configuration and must disable SDK-level retries where the parser already owns retry timing.

## Registering the factory

Factories accept validated `ProviderConfig` and return an awaitable `ManagedDecoder`. `ProviderConfig` (in `shared/model_providers.py`) contains a `SecretStr` API key, model name, positive finite timeout, and an optional address for local or custom services. A minimal registration looks like this:

```python
from copytrading_engine.parsing.providers.registry import ManagedDecoder, ProviderRegistry
from copytrading_engine.shared.model_providers import ProviderConfig


async def create_example(config: ProviderConfig) -> ManagedDecoder:
    client = ExampleAsyncClient(
        api_key=config.api_key.get_secret_value(),
        timeout=config.timeout,
    )
    try:
        return ExampleDecoder(client, model=config.model)
    except BaseException:
        try:
            await client.close()
        except Exception:
            pass
        raise


registry = ProviderRegistry({"example": create_example})
decoder = await registry.create(
    "example",
    ProviderConfig(api_key=api_key, model="example-model", timeout=20),
)
```

The app contribution adds its factory to `builtin_registry()` in `providers/registry.py`; do not add a module path, plugin loader, fallback chain, or worker branch. Registry names are fixed at startup and unknown names fail before background work starts. Configuration changes, including provider and route changes, require a process restart.

## Tests and packaging

Add tests for the adapter's actual request format, bounded timeout/output, provider error mapping, construction failure cleanup, cancellation, and close-once behavior. Add a fake registered provider test that exercises create, decode, and close through the registry without editing worker code. Keep grounding and request-budget assertions in worker tests. Tests use synthetic text and mocked clients; live provider calls are not a unit or integration test requirement.

From `engine/`, run focused parser and package checks with:

```sh
uv sync --frozen --no-editable
uv run --no-editable pytest -q tests/parsing
uv run --no-editable ruff check .
uv run --no-editable ruff format --check .
uv run --no-editable ty check src
uv build
```

The engine installs its `src/` Python modules and prompt module as package code. Verify the installed engine package imports its entry point and provider modules with network access disabled; the provider must not require a checkout-only source tree or development dependency at runtime.
