"""One durable extraction step; independent of transport and provider implementation."""

import datetime as dt
import logging
from collections.abc import Callable, Mapping
from contextlib import AbstractContextManager, nullcontext

from copytrading_engine.parsing.application import outcome, transform, without_model
from copytrading_engine.parsing.contracts import ExtractionStore, RequestReservation
from copytrading_engine.parsing.contracts import RawMessage as _RawMessage
from copytrading_engine.parsing.extraction import DecodeError, Decoder
from copytrading_engine.parsing.history import recent_calls
from copytrading_engine.parsing.readiness import ModelReadiness
from copytrading_engine.parsing.retry_policy import next_retry_at
from copytrading_engine.parsing.routes import Route, freeze_routes
from copytrading_engine.shared.correlation import WorkflowAttempt, bind_workflow_attempt
from copytrading_engine.shared.route_keys import choose_route
from copytrading_engine.shared.signals import StockSignal

log = logging.getLogger(__name__)


class ParseWorker:
    def __init__(
        self,
        store: ExtractionStore,
        decoder: Decoder,
        routes: Mapping[str, Route],
        model: str,
        max_age: int = 120,
        daily_limit: int = 200,
        *,
        observe: Callable[[str], AbstractContextManager] = lambda _: nullcontext(),
        observe_workflow: Callable[[WorkflowAttempt], AbstractContextManager] = lambda _: (
            nullcontext()
        ),
        on_decision: Callable[[str], None] = lambda _: None,
    ) -> None:
        self.store, self.decoder, self.routes = store, decoder, freeze_routes(routes)
        self.model, self.max_age, self.daily_limit = model, max_age, daily_limit
        self.model_health = ModelReadiness()
        self.observe = observe
        self.observe_workflow = observe_workflow
        self.on_decision = on_decision

    @property
    def model_ready(self) -> bool:
        return self.model_health.ready

    async def process_next(self, now: dt.datetime) -> bool:
        job = await self.store.next(now)
        if job is None:
            return False
        key, raw, attempts = job.key, job.raw, job.attempts
        chosen = choose_route(self.routes, raw.source, raw.channel_id, raw.author_id)
        route, route_error = chosen.route, chosen.error
        age = (now - raw.timestamp).total_seconds()
        result = None
        reason = None
        if raw.image_count > 0:
            reason = "attachments_require_human_review"
        elif route is None:
            reason = route_error or "source_profile_not_configured"
        elif age < -5:
            reason = "future_signal"
        elif age > self.max_age:
            reason = "stale_signal"
        elif (result := without_model(raw, route, self.model)) is not None:
            pass
        elif attempts >= 3:
            reason = "decode_attempts_exhausted"
        else:
            reservation = RequestReservation(
                key=key,
                expected_attempts=attempts,
                day=now.astimezone(dt.UTC).date(),
                daily_limit=self.daily_limit,
                retry_at=next_retry_at(now, attempts),
            )
            if await self.store.reserve(reservation):
                correlation = WorkflowAttempt(job.workflow_id, job.trace_id, None, attempts + 1)
                with bind_workflow_attempt(correlation):
                    with self.observe_workflow(correlation):
                        result = await self._decode(key, raw, route, attempts + 1, now)
            else:
                reason = "daily_model_request_budget_exhausted"
        if reason:
            if reason in {"stale_signal", "future_signal"}:
                log.warning(
                    "signal_timing_rejected id=%s reason=%s source_at=%s processed_at=%s "
                    "age_seconds=%s max_age_seconds=%s",
                    key,
                    reason,
                    raw.timestamp.isoformat(),
                    now.isoformat(),
                    age,
                    self.max_age,
                )
            result = self._review(raw, route, reason)
        if result is not None:
            await self.store.finish(key, result)
            self.on_decision(result.decision)
            log.info("decoded id=%s decision=%s", key, result.decision)
        return True

    async def _decode(
        self, key: str, raw: _RawMessage, route: Route, attempt: int, now: dt.datetime
    ) -> StockSignal | None:
        try:
            # The guru's book as the reader sees it beside the post (ADR-0010).
            recent = recent_calls(await self.store.past_calls(raw.channel_id, key))
            with self.observe(key):
                result = await transform(raw, route, self.decoder, self.model, recent)
            self.model_health.record()
            return result
        except DecodeError as exc:
            # Provider internals are not durable business state or safe log fields.
            self.model_health.record(exc.reason)
            issues = exc.issues
            await self.store.diagnose(key, attempt, now, exc.reason, issues)
            log.warning(
                "decode_failed id=%s reason=%s attempt=%s issues=%s",
                key,
                exc.reason,
                attempt,
                [(issue.path, issue.code) for issue in issues],
            )
            return None if exc.retryable else self._review(raw, route, exc.reason)

    def _review(self, raw: _RawMessage, route: Route | None, reason: str) -> StockSignal:
        """A post held for the owner keeps the guru and playbook revision its route names."""
        return outcome(
            raw,
            "review",
            reason,
            model=self.model,
            guru_id=route.guru_id if route is not None else None,
            profile_revision=route.profile_revision if route is not None else None,
        )
