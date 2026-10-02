# ADR-0001: Organize the engine by capability

## Status
Accepted, September 2026.

## Context
The engine began with global `domain/`, `application/`, and `adapters/` folders. They held a two-account simulation beside platform code (IPC, telemetry, backup), so the names promised a business core that was not there, and installation identity hid inside the simulation store.

## Decision
Top-level packages name capabilities: `host`, `diagnostics`, `backup`, `shared`, `sources`, `parsing`, `trading`, and `execution`. `bootstrap.py` is the only composition root. Layer folders appear only inside a capability that has real policy to protect (see ADR-0002).

## Consequences
* Positive: a package name says what it owns; installation identity, IPC, and diagnostics have their own homes.
* Positive: `engine/tests/test_architecture.py` states allowed dependencies per package and fails on any other import.
* Negative: dependency rules are listed explicitly and must be updated when a package gains a legitimate collaborator.
