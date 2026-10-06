"""The saved trading-configuration schema version, shared by trading and backup."""

from typing import Literal

# Bump on any breaking change; older saved configurations are rejected, never migrated.
CONFIGURATION_VERSION: Literal[7] = 7
