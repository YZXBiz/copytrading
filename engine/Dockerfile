# The CopyTrading engine as a server: `docker run` it with copytrading.toml and your keys.
# Build from engine/:  docker build -t copytrading-server .
FROM python:3.14-slim AS base
COPY --from=ghcr.io/astral-sh/uv:0.9 /uv /usr/local/bin/uv
ENV UV_LINK_MODE=copy UV_COMPILE_BYTECODE=1 UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock ./
COPY src ./src

FROM base AS build
RUN uv sync --frozen --no-dev --no-editable

FROM python:3.14-slim
RUN useradd --create-home --uid 1000 copytrading \
    && mkdir -p /state /config && chown copytrading /state /config
COPY --from=build /app/.venv /app/.venv
ENV PATH=/app/.venv/bin:$PATH XDG_STATE_HOME=/state
USER copytrading
WORKDIR /config
VOLUME ["/state"]
ENTRYPOINT ["copytrading-server"]
CMD ["run", "--config", "/config/copytrading.toml"]
