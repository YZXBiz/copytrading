#!/bin/sh
# Run the engine suite on Linux in Docker, with the repository mounted read-only.
# Usage (from the repository root): sh engine/tools/linux-tests.sh [pytest arguments]
set -eu
repo=$(cd "$(dirname "$0")/../.." && pwd)
image=copytrading-linux-tests
docker build -q -t "$image" - >/dev/null <<'DOCKERFILE'
FROM python:3.14-slim
COPY --from=ghcr.io/astral-sh/uv:0.9 /uv /usr/local/bin/uv
RUN useradd --create-home --uid 1000 tester
DOCKERFILE
docker run --rm -u 1000 -v "$repo":/repo:ro "$image" sh -c '
  set -eu
  mkdir /tmp/repo
  cd /repo
  tar --exclude=./engine/.venv --exclude=./.venv --exclude=./app/.build --exclude=./dist -cf - . \
    | tar -xf - -C /tmp/repo
  cd /tmp/repo/engine
  export UV_PROJECT_ENVIRONMENT=/tmp/venv UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
  uv sync --frozen --no-editable -q
  uv run --frozen --no-editable pytest -q -p no:cacheprovider "$@"
' sh "$@"
