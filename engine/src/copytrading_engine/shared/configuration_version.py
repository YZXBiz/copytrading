"""The saved trading-configuration schema version, shared by trading and backup."""

from typing import Literal

# Bump on any change to the saved setup's shape, and ship the app's one-way upgrade from the
# version before it (ADR-0013): a saved setup is the owner's data and is never thrown away.
CONFIGURATION_VERSION: Literal[10] = 10
# The oldest saved setup the app still upgrades; anything older predates upgrades.
EARLIEST_UPGRADABLE_VERSION = 8
