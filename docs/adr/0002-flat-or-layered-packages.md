# ADR-0002: A package is flat or fully layered

## Status
Accepted, September 2026.

## Context
`execution` and `trading` hold the trading rules that must not depend on I/O. `sources` and `parsing` are small and cohesive. Layering every package would add folders without adding a boundary; layering none would let business rules import SQLite or broker clients.

## Decision
* `execution` and `trading` are layered: `domain`, `application`, `adapters`, `presentation`, and, for `trading`, `entrypoints` (the runtime that drives capture, parsing, and account processing and wires concrete stores). A layered package contains only layers and `__init__.py`.
* Application layers depend on ports, never on their adapters. Trading use cases read retained evidence through `OperatorEvidence`.
* Flat packages name their I/O modules (`parsing`: `sqlite`, `providers`; `sources`: `sqlite`, `session`, `source`, `attachments`). Their other modules are policy and may not import those modules or an external SDK.
* Package `__init__.py` files do not re-export; each name has one import path.

## Consequences
* Positive: the dependency rule is checked by tests, not implied by folder names.
* Positive: small packages stay flat and readable.
* Negative: `trading/entrypoints/runtime.py` knows concrete stores; it is the outermost trading layer by design, and application code may not import it.
