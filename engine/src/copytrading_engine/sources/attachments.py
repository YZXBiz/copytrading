"""Fetch only bounded Discord CDN attachments into private operational storage."""

import asyncio
import hashlib
import os
import re
import stat
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from uuid import uuid4

import httpx2 as httpx

from copytrading_engine.sources.application import AttachmentReference, AttachmentStatus
from copytrading_engine.sources.evidence import MAX_ATTACHMENTS_PER_MESSAGE

MAX_ATTACHMENT_BYTES = 1024 * 1024
MAX_MESSAGE_ATTACHMENT_BYTES = 4 * 1024 * 1024
MAX_ATTACHMENT_REDIRECTS = 3
ATTACHMENT_CAPTURE_TIMEOUT_SECONDS = 15
ALLOWED_ATTACHMENT_HOSTS = frozenset({"cdn.discordapp.com", "media.discordapp.net"})
_REDIRECT_CODES = frozenset({301, 302, 303, 307, 308})
_CONTENT_ADDRESS = re.compile(r"^attachments/([0-9a-f]{2})/([0-9a-f]{64})$")


@dataclass(frozen=True, slots=True)
class AttachmentCaptureResult:
    status: AttachmentStatus
    byte_size: int | None = None
    sha256: str | None = None
    managed_path: str | None = None


async def capture_attachments(
    references: Sequence[AttachmentReference],
    managed_root: Path,
    *,
    transport: httpx.AsyncBaseTransport | None = None,
) -> tuple[AttachmentCaptureResult, ...]:
    """Capture at most ten files, with one shared message time and byte budget."""
    references = tuple(references[:MAX_ATTACHMENTS_PER_MESSAGE])
    results: list[AttachmentCaptureResult] = []
    captured_bytes = 0
    timeout = httpx.Timeout(5.0, connect=2.0)
    async with httpx.AsyncClient(
        transport=transport,
        timeout=timeout,
        follow_redirects=False,
        trust_env=False,
    ) as client:
        try:
            async with asyncio.timeout(ATTACHMENT_CAPTURE_TIMEOUT_SECONDS):
                for reference in references:
                    if not reference.url:
                        results.append(AttachmentCaptureResult("missing"))
                        continue
                    if type(reference.declared_size) is not int or reference.declared_size < 0:
                        results.append(AttachmentCaptureResult("download_failed"))
                        continue
                    remaining = MAX_MESSAGE_ATTACHMENT_BYTES - captured_bytes
                    if (
                        reference.declared_size > MAX_ATTACHMENT_BYTES
                        or reference.declared_size > remaining
                    ):
                        results.append(AttachmentCaptureResult("oversize"))
                        continue
                    result = await _capture_one(
                        client,
                        reference.url,
                        managed_root,
                        maximum_bytes=min(MAX_ATTACHMENT_BYTES, remaining),
                    )
                    results.append(result)
                    if result.status == "available" and result.byte_size is not None:
                        captured_bytes += result.byte_size
        except TimeoutError:
            results.extend(
                AttachmentCaptureResult("timed_out") for _ in range(len(results), len(references))
            )
    return tuple(results)


async def _capture_one(
    client: httpx.AsyncClient,
    initial_url: str,
    managed_root: Path,
    *,
    maximum_bytes: int,
) -> AttachmentCaptureResult:
    if not _allowed_url(initial_url):
        return AttachmentCaptureResult("origin_rejected")
    url = initial_url
    for redirect_count in range(MAX_ATTACHMENT_REDIRECTS + 1):
        try:
            async with client.stream("GET", url) as response:
                final_url = str(response.request.url)
                if not _allowed_url(final_url):
                    return AttachmentCaptureResult("origin_rejected")
                if response.status_code in _REDIRECT_CODES:
                    location = response.headers.get("location")
                    if not location or redirect_count == MAX_ATTACHMENT_REDIRECTS:
                        return AttachmentCaptureResult("download_failed")
                    next_url = urljoin(final_url, location)
                    if not _allowed_url(next_url):
                        return AttachmentCaptureResult("origin_rejected")
                    url = next_url
                    continue
                if not 200 <= response.status_code < 300:
                    return AttachmentCaptureResult("download_failed")
                length = response.headers.get("content-length")
                if length is not None:
                    try:
                        if int(length) > maximum_bytes:
                            return AttachmentCaptureResult("oversize")
                    except ValueError:
                        pass
                body = bytearray()
                async for chunk in response.aiter_bytes():
                    if len(body) + len(chunk) > maximum_bytes:
                        return AttachmentCaptureResult("oversize")
                    body.extend(chunk)
                digest = hashlib.sha256(body).hexdigest()
                relative_path = await asyncio.to_thread(
                    _store_content, managed_root, bytes(body), digest
                )
                return AttachmentCaptureResult("available", len(body), digest, relative_path)
        except httpx.TimeoutException:
            return AttachmentCaptureResult("timed_out")
        except httpx.RequestError, OSError, ValueError:
            return AttachmentCaptureResult("download_failed")
    return AttachmentCaptureResult("download_failed")


def _allowed_url(value: str) -> bool:
    try:
        parsed = urlsplit(value)
        return (
            parsed.scheme == "https"
            and parsed.hostname is not None
            and parsed.hostname.casefold() in ALLOWED_ATTACHMENT_HOSTS
            and parsed.port in {None, 443}
            and parsed.username is None
            and parsed.password is None
        )
    except ValueError:
        return False


def _store_content(root: Path, content: bytes, digest: str) -> str:
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    root_fd = os.open(root, directory_flags)
    try:
        os.fchmod(root_fd, 0o700)
        bucket = digest[:2]
        try:
            os.mkdir(bucket, mode=0o700, dir_fd=root_fd)
        except FileExistsError:
            pass
        bucket_fd = os.open(bucket, directory_flags, dir_fd=root_fd)
        try:
            os.fchmod(bucket_fd, 0o700)
            name = digest
            temporary = f".tmp-{uuid4().hex}"
            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | nofollow
            fd = os.open(temporary, flags, 0o600, dir_fd=bucket_fd)
            with os.fdopen(fd, "wb") as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
            try:
                os.link(
                    temporary,
                    name,
                    src_dir_fd=bucket_fd,
                    dst_dir_fd=bucket_fd,
                    follow_symlinks=False,
                )
            except FileExistsError:
                existing_fd = os.open(name, os.O_RDONLY | nofollow, dir_fd=bucket_fd)
                try:
                    existing_stat = os.fstat(existing_fd)
                    if not stat.S_ISREG(existing_stat.st_mode) or existing_stat.st_size != len(
                        content
                    ):
                        raise OSError("managed attachment content-address collision")
                    with os.fdopen(os.dup(existing_fd), "rb") as existing:
                        existing_digest = hashlib.sha256(
                            existing.read(MAX_ATTACHMENT_BYTES + 1)
                        ).hexdigest()
                        if existing_digest != digest:
                            raise OSError("managed attachment content-address collision")
                finally:
                    os.close(existing_fd)
            finally:
                os.unlink(temporary, dir_fd=bucket_fd)
            os.fsync(bucket_fd)
        finally:
            os.close(bucket_fd)
    finally:
        os.close(root_fd)
    return (Path("attachments") / digest[:2] / digest).as_posix()


def read_managed_content(
    root: Path,
    relative_path: str,
    *,
    expected_digest: str,
    expected_size: int,
) -> bytes:
    """Read a registered content-addressed file without following untrusted paths."""
    match = _CONTENT_ADDRESS.fullmatch(relative_path)
    if (
        match is None
        or match.group(1) != expected_digest[:2]
        or match.group(2) != expected_digest
        or not re.fullmatch(r"[0-9a-f]{64}", expected_digest)
        or type(expected_size) is not int
        or not 0 <= expected_size <= MAX_ATTACHMENT_BYTES
    ):
        raise ValueError("attachment_evidence_unavailable")
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    nofollow = getattr(os, "O_NOFOLLOW", 0)
    root_fd = os.open(root, directory_flags)
    try:
        bucket_fd = os.open(match.group(1), directory_flags, dir_fd=root_fd)
        try:
            fd = os.open(match.group(2), os.O_RDONLY | nofollow, dir_fd=bucket_fd)
            try:
                info = os.fstat(fd)
                if not stat.S_ISREG(info.st_mode) or info.st_size != expected_size:
                    raise ValueError("attachment_evidence_unavailable")
                with os.fdopen(os.dup(fd), "rb") as stream:
                    content = stream.read(MAX_ATTACHMENT_BYTES + 1)
            finally:
                os.close(fd)
        finally:
            os.close(bucket_fd)
    finally:
        os.close(root_fd)
    if len(content) != expected_size or hashlib.sha256(content).hexdigest() != expected_digest:
        raise ValueError("attachment_evidence_unavailable")
    return content
