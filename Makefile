.DEFAULT_GOAL := help
ifeq ($(shell uname -s),Darwin)
ARM_PYTHON := $(if $(UV_PYTHON),$(UV_PYTHON),$(shell uv python find cpython-3.14-macos-aarch64-none 2>/dev/null))
endif
ENGINE_ENV := $(if $(ARM_PYTHON),UV_PYTHON=$(ARM_PYTHON),)
PYTHON ?= $(if $(ARM_PYTHON),$(ARM_PYTHON),python3)
APP ?= dist/CopyTrading.app
RUNTIME ?= dist/desktop-runtime/prepared
RELEASE_RUNTIME ?= $(RUNTIME)
RELEASE_OUTPUT ?= dist/releases/v$(RELEASE_VERSION)
RELEASE_TAG ?= v$(RELEASE_VERSION)
.PHONY: help doctor app dev check check-linux check-mutations desktop-build desktop-check desktop-tests desktop-smoke ui-journeys release dmg

help:
	@echo 'make doctor          Check this Mac can build and run CopyTrading'
	@echo 'make app             Build the app from source and open it'
	@echo 'make check-linux     Run the engine tests on Linux in Docker'
	@echo 'make dev             Install the engine environment for your editor'
	@echo 'make check           Engine tests with coverage (80% gate), Ruff, Ty, app-script tests'
	@echo 'make desktop-build   Build the local app bundle'
	@echo 'make desktop-check   Engine checks, Swift lint, and make desktop-tests'
	@echo 'make desktop-tests   Build the app and run every Swift suite against it'
	@echo 'make desktop-smoke   Smoke-test the built app'
	@echo 'make lint-swift      Check Swift formatting (make format-swift fixes it)'
	@echo 'make ui-journeys     Drive the real app window through docs/acceptance.md'
	@echo 'make release RELEASE_VERSION=0.1.0-alpha.1  Build verified preview assets'
	@echo 'make dmg RELEASE_VERSION=0.1.0-alpha.1      Wrap a built release in the drag-to-install DMG'
	@echo 'make check-mutations Probe selected execution policy mutations'

doctor:
	/usr/bin/python3 app/scripts/doctor.py

$(RUNTIME)/runtime.json: app/Resources/Runtime/artifacts.json
	$(PYTHON) app/scripts/prepare_runtime.py --output $(RUNTIME)

app: doctor $(RUNTIME)/runtime.json desktop-build
	open '$(APP)'

dev:
	$(ENGINE_ENV) uv sync --directory engine --frozen

check:
	$(ENGINE_ENV) uv sync --directory engine --frozen --no-editable
	$(ENGINE_ENV) uv run --directory engine --frozen --no-editable pytest -q --cov --cov-fail-under=80 --cov-report=term-missing:skip-covered --cov-report=html:../dist/coverage
	$(ENGINE_ENV) uv run --directory engine --frozen --no-editable ruff check . tools ../app/scripts
	$(ENGINE_ENV) uv run --directory engine --frozen --no-editable ruff format --check . tools ../app/scripts
	$(ENGINE_ENV) uv run --directory engine --frozen --no-editable ty check src tools ../app/scripts
	$(ENGINE_ENV) uv run --directory engine --frozen --no-editable pytest -q -c pyproject.toml ../app/scripts/tests

check-linux:
	sh engine/tools/linux-tests.sh


desktop-build:
	$(ENGINE_ENV) $(PYTHON) app/scripts/build_app.py --app '$(APP)' --runtime '$(RUNTIME)'

desktop-check: check lint-swift desktop-tests

desktop-tests: desktop-build
	arch -arm64 swift build --package-path app -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
	COPYTRADING_RUNTIME_ROOT='$(CURDIR)/dist/CopyTrading.app/Contents/Resources/Runtime' \
		COPYTRADING_ENGINE_ROOT='$(CURDIR)/dist/CopyTrading.app/Contents/Resources/Engine' \
		COPYTRADING_PYTHON_LIBRARY_PATH='$(CURDIR)/dist/CopyTrading.app/Contents/Resources/Runtime/cpython/python/lib/python3.14/site-packages' \
		arch -arm64 swift test --package-path app --no-parallel -Xswiftc -warnings-as-errors
	$(ENGINE_ENV) $(PYTHON) app/scripts/verify_bundle.py --app 'dist/CopyTrading.app'

desktop-smoke:
	$(ENGINE_ENV) $(PYTHON) app/scripts/smoke_app.py --app 'dist/CopyTrading.app'

ui-journeys: desktop-build
	$(ENGINE_ENV) $(PYTHON) app/scripts/ui_journeys.py

release:
	@if [ -z "$(RELEASE_VERSION)" ]; then echo 'set RELEASE_VERSION, for example 0.1.0-alpha.1' >&2; exit 2; fi
	$(ENGINE_ENV) $(PYTHON) app/scripts/release.py \
		--version "$(RELEASE_VERSION)" \
		--tag "$(RELEASE_TAG)" \
		--runtime "$(RELEASE_RUNTIME)" \
		--output "$(RELEASE_OUTPUT)" \
		$(if $(RELEASE_COMMIT),--commit "$(RELEASE_COMMIT)",)

dmg:
	@if [ -z "$(RELEASE_VERSION)" ]; then echo 'set RELEASE_VERSION, for example 0.1.0-alpha.1' >&2; exit 2; fi
	$(PYTHON) app/scripts/build_dmg.py --version "$(RELEASE_VERSION)" --release-dir "$(RELEASE_OUTPUT)"

check-mutations:
	$(ENGINE_ENV) uv sync --directory engine --frozen --no-editable
	$(ENGINE_ENV) uv run --directory engine --frozen --no-editable python tools/check_policy_mutations.py

.PHONY: format-swift lint-swift
format-swift:
	swift format --in-place --recursive app/Sources app/Tests app/Package.swift

lint-swift:
	swift format lint --strict --recursive app/Sources app/Tests app/Package.swift
