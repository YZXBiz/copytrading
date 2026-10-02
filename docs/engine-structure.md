# Engine structure plan

**Baseline:** `b5b9cb1`, September 27, 2026 — 863 engine tests passed, 4 skipped; 53 app-script tests passed; Ruff and Ty clean.

This plan records decisions from a structure review of `engine/src/copytrading_engine` against *Robust Python* (Viafore, 2021). It changes code organization, type strictness, and failure visibility. It does not change trading policy. No development-format backward compatibility is kept.

## Decisions

1. **Name the simulation workflow as the engine self-test.** It is the credential-free workload behind the managed-runtime and recovery acceptance harnesses, so it stays, under `host/self_test/`, with self-test names in the pipe contract and journal. The app exposes it in Settings → Engine. Installation identity and the single-owner lock move out of its store.
2. **Capability packages at the top level.** `host/` (installation, pipe server, engine status), `diagnostics/` (capture, redaction, the private journal), `backup/` (backup/restore, restore gate, candidate inspection, schema catalog), `shared/` (value contracts, SQLite helper, workflow correlation, route selection), and the feature packages `sources/`, `parsing/`, `trading/`, `execution/`. No global `domain/`/`application/`/`adapters/`.
3. **A package is flat or fully layered.** A layered package contains only layer subpackages and `__init__.py`. `execution/notification_models.py` (a duplicate of `shared/notification_models.py`) is deleted; `ownership.py` and `execution_owner.py` move to `execution/adapters/`; `runtime_contracts.py` moves to `execution/application/ports.py`. No module imports another module's `_private` name.
4. **Each store exports one public `SchemaComponent(name, revision, ddl)`.** `ensure_schema` takes it; the backup catalog and backup validation list those constants explicitly instead of repeating revision literals; the execution ledger exposes a public snapshot reader. A test proves the catalog equals what the stores create. Installation identity becomes its own `installation` component, separate from the self-test tables; the `application.db` format version (`PRAGMA user_version`, also read by the native `OperationalSchemaReader`) changes with it.
5. **Strict domain values.** `execution.domain.values.Value` sets `strict=True`; boundaries (broker, pipe, model output, SQLite JSON) convert explicitly.
6. **Reads show unavailability.** Operator read models carry explicit unavailable states instead of `None`/`{}`. `except Exception` is allowed only in supervisors, telemetry/diagnostics isolation, and cleanup, each with a stated `noqa: BLE001` reason.
7. **Split `TradingRuntime` by caller task.** Lifecycle stays in `TradingRuntime`; `OperatorQueries`, `ManualInterventionService`, and `ProfileEvaluationService` depend on a narrow `AccountAccess` port.
8. **Tests mirror packages.** Property tests cover sizing, redaction, and ownership conservation; mutation probing extends to sizing, ownership, and redaction.
9. **Static checks.** Ruff adds `BLE`, `SLF`, `ANN`, and `RUF`. SQLite rows are decoded with validation, not `cast`. Private-name imports are enforced by the architecture test.

## Sequence

Each step is one commit; `make check` passes after each, and `make desktop-check` after steps that touch Swift.

| # | Step | Status |
|---|---|---|
| 0 | Retain and observe the late account-owner close task | Done |
| 1 | Rename the simulation workflow to the engine self-test | Done |
| 2 | Capability packages, execution layering, duplicate removal, architecture test | Done |
| 3 | `SchemaComponent`, installation identity component, public ledger snapshot reader | Done |
| 4 | Strict domain values | Done |
| 5 | Split `TradingRuntime` | Done |
| 6 | Explicit unavailable read states; `BLE001` | Done |
| 7 | Remaining lint rules; validated SQLite decoding | Done |
| 8 | Test tree, property tests, mutation coverage | Done |
| 9 | Architecture and validation documentation | Done |

Review checkpoints follow steps 2 and 5.

## Outcome notes

- The simulation workflow is kept as the engine self-test rather than deleted, because it drives the managed-runtime and recovery acceptance harnesses.
- Installation identity moved with the schema component step because it shares the `application.db` format version with backup validation and the native schema reader.
- Account operator views moved to `execution/presentation`, removing an execution↔trading import cycle; the architecture test has no exceptions.
- `diagnostics` may import `host` because the journal records the self-test's durable stages.
- The three largest test files were moved but not split: runtime tests cover lifecycle and pipeline behavior, and operator and manual tests already live with their services.
- Follow-up: `trading/` is now layered with an `entrypoints/` layer for the runtime, flat packages' I/O direction is tested, and the decisions are recorded in [ADR-0001 to ADR-0004](adr/).

## Module and test review — September 30, 2026

A second pass against *Robust Python*, *Clean Architecture with Python*, *Architecture Patterns with Python*, and *Python Testing with pytest*. Behavior is unchanged: 990 tests pass, Ruff and Ty are clean, and every policy mutant is killed.

### Source

- **A module has one job.** The four largest modules became packages named for their parts. Each part is imported from where it lives; no `__init__.py` re-exports anything.

  | Was | Now |
  |---|---|
  | `host/pipe_server.py` (an `isinstance` chain) | `host/pipe/`: `requests` (contract models and `RequestHandler`), `responses`, `session` (`PipeSession`: running, stopping, reply-then-stop), `services`, `server` (line framing and error mapping), and `handlers/` with one module per contract area: `trading`, `accounts`, `manual`, `profiles`, `restore`, `control` |
  | `backup/service.py` | `backup/`: `ports`, `manifest`, `files`, `databases`, `configuration`, `archive`, `snapshot`, `service`; restore steps under `backup/restore/`: `candidates`, `gate`, `inspector` |
  | `diagnostics/otel.py` | `diagnostics/telemetry/`: `config`, `events`, `attributes`, `journal`, `local` |
  | `execution/adapters/alpaca.py`, `alpaca_models.py` | `execution/adapters/alpaca/`: `broker`, `models` |

- **Classes that did two jobs are two.** `execution/adapters/owner.py` keeps the async `ExecutionOwner`; the resources it confines to its worker thread live in `resources.py`.
- **One path per operation.** The source store's `add`, `reject`, and `capture_recovery_page` each had a `*_with_evidence` twin that the session probed for with `getattr`. Each is now one method that always carries its evidence, declared by the capture protocol; live and recovered captures share the same transaction helpers.
- **Capabilities are declared, not probed.** Optional collaborators are Protocols checked with `isinstance` (`QuoteBroker`) or required members (`DiagnosticSink.capture_health`, `PayloadCapture`), never `getattr(obj, "name", None)`. The execution owner holds typed `ExecutionResources`, so every call it forwards is type-checked.
- **The ledger stays whole.** `execution/application/ledger.py` is the `TradingLedger` aggregate, the consistency boundary for lots, orders, and ownership (*Architecture Patterns with Python*, chapter 7). Splitting it would scatter its invariants across modules.
- **Dispatch is a table.** Each handler group returns `{request type: handler}`; the server merges them. A test holds the table equal to the request union, so a new request cannot go unanswered.
- **Dead code is deleted, not deprecated.** Removed: `read_credentials`, `authorization_header`, the `redact` wrapper, `ExecutionOwnerPort`, `ExecutionReport.from_stored`, `RecoveryApplication._owned_qty`, three unused telemetry attribute helpers, and `ManagedRestoreEvidenceBroker` (folded into `RestoreEvidenceBroker`).

### Tests

- **Tests mirror packages.** `tests/<package>/` mirrors each capability package. A subpackage gets its own test directory once its tests span several modules: `tests/host/pipe/`, `tests/backup/restore/`, `tests/diagnostics/telemetry/`. Every test directory is a package, so relative imports resolve one way.
- **Large suites split by behavior.** Execution behavior is `test_order_flow`, `test_sizing`, and `test_entry_guards` around one `system` fixture in `conftest.py`; the Alpaca adapter's tests live in `tests/execution/alpaca/`, the runtime's in `tests/trading/runtime/`. `tests/integration/test_diagnostics_journal.py` runs a whole workflow against the real journal and reads back what it recorded.
- **Helpers have homes.** A test module never imports another test module. Test doubles live in `fakes.py` and data builders in `builders.py` next to the tests that use them; fixtures shared within a directory live in its `conftest.py`. `tests/contracts.py` loads the app's contract fixtures for every package that speaks the wire format.
- **Public names only.** Tests reach the engine through public names, the same rule `src` follows; `tests/test_architecture.py` enforces both. Where a test needed a private helper, the helper was a real contract and became public: `signal_reference`, `diagnostics_state_root`, `owner_support_root`, `persist_installation_id`, `ExecutionResources`.
- **Configuration does the repetitive work.** `asyncio_mode = "auto"` marks async tests, so no test carries `@pytest.mark.asyncio`. Every test module opens with one sentence saying what it verifies.
