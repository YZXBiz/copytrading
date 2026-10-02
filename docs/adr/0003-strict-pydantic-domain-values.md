# ADR-0003: Strict Pydantic models in the execution domain

## Status
Accepted, September 2026.

## Context
Execution values need validated money, quantities, and timestamps. Pydantic provides validation and serialization, but its default lax mode accepts floats and strings for `Decimal` fields, so a float could enter the ledger silently.

## Decision
Execution domain values derive from `Value`, a frozen Pydantic model with `strict=True`. Text converts to numbers and times only at JSON boundaries (pipe requests, persisted snapshots, broker wire models), which validate in JSON mode. Domain models do not use `mode="before"` validators, because they route JSON input through Python-mode validation.

## Consequences
* Positive: invalid numeric types fail at construction, not in a later calculation.
* Negative: the domain depends on Pydantic; it is treated as a stable extension of the type system, not a framework.
* Negative: tests must build domain values with exact types or decode through the real boundary.
