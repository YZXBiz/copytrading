# ADR-0004: Diagnostics may import the host self-test

## Status
Accepted, September 2026.

## Context
The credential-free engine self-test is the workload that proves diagnostic capture in the runtime acceptance harnesses. The diagnostics journal records the self-test's durable stages, and diagnostic capture decorates host status with capture health.

## Decision
`diagnostics` may import `host` (the self-test model and engine status). `host` does not import `diagnostics`; `bootstrap.py` composes them.

## Consequences
* Positive: acceptance harnesses exercise the same journal path as production traffic.
* Negative: diagnostics knows one host workflow. Removing or replacing the self-test requires moving its stage records with it.
