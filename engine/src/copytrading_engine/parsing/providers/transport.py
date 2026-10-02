"""Bounded capture at the SDK's serialized HTTP request/response stream boundary."""

import json
from collections.abc import AsyncIterator, Callable
from typing import cast

import httpx2 as httpx

from copytrading_engine.shared.correlation import WorkflowAttempt, current_workflow_attempt
from copytrading_engine.shared.payload_capture import (
    CaptureKind,
    CaptureStatus,
    JsonValue,
    PayloadCapture,
    ProviderName,
)


class _BoundedBytes:
    def __init__(self, maximum: int) -> None:
        self.maximum = maximum
        self.total = 0
        self.parts: list[bytes] = []
        self.retained = 0
        self.complete = False

    def append(self, chunk: bytes) -> None:
        self.total += len(chunk)
        remaining = self.maximum - self.retained
        if remaining > 0:
            retained = chunk[:remaining]
            self.parts.append(retained)
            self.retained += len(retained)

    def finish(self) -> None:
        self.complete = True

    def value(self) -> bytes | None:
        if self.total > self.maximum:
            return None
        return b"".join(self.parts)


class _TeeStream(httpx.AsyncByteStream):
    def __init__(self, source: httpx.AsyncByteStream, capture: _BoundedBytes) -> None:
        self._source = source
        self._capture = capture
        self._closed = False

    async def __aiter__(self) -> AsyncIterator[bytes]:
        try:
            async for chunk in self._source:
                self._capture.append(chunk)
                yield chunk
        except BaseException:
            await self.aclose()
            raise
        else:
            self._capture.finish()

    async def aclose(self) -> None:
        if self._closed:
            return
        self._closed = True
        await self._source.aclose()


class DiagnosticHTTPTransport(httpx.AsyncBaseTransport):
    """Tee SDK wire bodies into redacted diagnostics without retaining unbounded bytes."""

    def __init__(
        self,
        inner: httpx.AsyncBaseTransport,
        sink: PayloadCapture | None,
        *,
        provider: ProviderName,
        maximum_bytes: int = 48 * 1024,
    ) -> None:
        if not 1 <= maximum_bytes <= 48 * 1024:
            raise ValueError("provider payload capture limit is outside supported bounds")
        self._inner = inner
        self._sink = sink
        self._provider = provider
        self._maximum_bytes = maximum_bytes

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        attempt = current_workflow_attempt()
        request_bytes = _BoundedBytes(self._maximum_bytes)
        try:
            available_request_body = request.content
        except httpx.RequestNotRead:
            available_request_body = None
        if available_request_body is not None:
            request_bytes.append(available_request_body)
            request_bytes.finish()
        else:
            request.stream = _TeeStream(cast(httpx.AsyncByteStream, request.stream), request_bytes)
        try:
            response = await self._inner.handle_async_request(request)
        except BaseException:
            self._emit(
                "model_request",
                request_bytes,
                attempt,
                status=_stream_status(request_bytes),
            )
            self._emit("model_response", None, attempt, status="missing")
            raise
        self._emit(
            "model_request",
            request_bytes,
            attempt,
            status=_stream_status(request_bytes),
            method=request.method,
            path=request.url.path,
        )
        response_bytes = _BoundedBytes(self._maximum_bytes)
        if response.is_stream_consumed:
            response_bytes.append(response.content)
            response_bytes.finish()
            self._emit(
                "model_response",
                response_bytes,
                attempt,
                status=_stream_status(response_bytes),
                method=request.method,
                path=request.url.path,
                status_code=response.status_code,
            )
            return response
        response.stream = _ResponseTeeStream(
            cast(httpx.AsyncByteStream, response.stream),
            response_bytes,
            lambda: self._emit(
                "model_response",
                response_bytes,
                attempt,
                status=_stream_status(response_bytes),
                method=request.method,
                path=request.url.path,
                status_code=response.status_code,
            ),
            lambda: self._emit(
                "model_response",
                response_bytes,
                attempt,
                status="incomplete" if response_bytes.total else "missing",
                method=request.method,
                path=request.url.path,
                status_code=response.status_code,
            ),
        )
        return response

    async def aclose(self) -> None:
        await self._inner.aclose()

    def _emit(
        self,
        kind: CaptureKind,
        capture: _BoundedBytes | None,
        attempt: WorkflowAttempt | None,
        *,
        status: CaptureStatus,
        method: str | None = None,
        path: str | None = None,
        status_code: int | None = None,
    ) -> None:
        if self._sink is None:
            return
        payload = (
            None
            if capture is None
            else _wire_payload(capture.value(), status_code, method=method, path=path)
        )
        source_bytes = 0 if capture is None else capture.total
        try:
            self._sink.record_payload(
                capture_kind=kind,
                workflow_id=attempt.workflow_id if attempt else None,
                trace_id=attempt.trace_id if attempt else None,
                destination_id=attempt.destination_id if attempt else None,
                attempt=attempt.attempt if attempt else None,
                provider=self._provider,
                payload=payload,
                source_bytes=source_bytes,
                max_bytes=self._maximum_bytes,
                status=status,
            )
        except Exception:  # noqa: BLE001 - instrumentation must not alter provider behavior
            # Instrumentation is a best-effort side effect and cannot alter provider behavior.
            return


class _ResponseTeeStream(_TeeStream):
    def __init__(
        self,
        source: httpx.AsyncByteStream,
        capture: _BoundedBytes,
        on_complete: Callable[[], None],
        on_incomplete: Callable[[], None],
    ) -> None:
        super().__init__(source, capture)
        self._on_complete = on_complete
        self._on_incomplete = on_incomplete
        self._reported = False

    async def __aiter__(self) -> AsyncIterator[bytes]:
        try:
            async for chunk in self._source:
                self._capture.append(chunk)
                yield chunk
        except BaseException:
            self._report_incomplete()
            await super().aclose()
            raise
        else:
            self._capture.finish()
            self._report_complete()

    async def aclose(self) -> None:
        if not self._reported:
            self._report_incomplete()
        await super().aclose()

    def _report_complete(self) -> None:
        if not self._reported:
            self._reported = True
            self._on_complete()

    def _report_incomplete(self) -> None:
        if not self._reported:
            self._reported = True
            self._on_incomplete()


def _stream_status(capture: _BoundedBytes) -> CaptureStatus:
    if capture.total > capture.maximum:
        return "oversize"
    if capture.complete:
        return "complete"
    return "incomplete" if capture.total else "missing"


def _wire_payload(
    body: bytes | None,
    status_code: int | None,
    *,
    method: str | None,
    path: str | None,
) -> dict[str, JsonValue] | None:
    if body is None:
        return None
    text = body.decode("utf-8", errors="replace")
    try:
        serialized: JsonValue = json.loads(text)
    except json.JSONDecodeError:
        serialized = text
    result: dict[str, JsonValue] = {"body": serialized}
    if method is not None:
        result["method"] = method
    if path is not None:
        result["path"] = path
    if status_code is not None:
        result["status_code"] = status_code
    return result
