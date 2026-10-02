"""Typed failures raised by the engine self-test and installation store."""


class WorkflowError(Exception):
    """Base for declared workflow failures safe to map at the IPC boundary."""


class InvalidCommand(WorkflowError):
    """A self-test command violates a domain invariant."""


class IdentityConflict(WorkflowError):
    """A command ID was reused for different canonical command content."""


class UnsupportedSelfTest(WorkflowError):
    """The local deterministic parser does not support the source text."""


class InvalidTransition(WorkflowError):
    """A workflow stage transition is illegal or lost its compare-and-set race."""


class WorkflowNotFound(WorkflowError):
    """The requested command ID has no persisted workflow."""


class StoreUnavailable(WorkflowError):
    """The durable store is unavailable or has an uncertain commit outcome."""


class StoreClosed(WorkflowError):
    """The store is closing or has already been closed."""


class InstallationAlreadyRunning(WorkflowError):
    """Another process currently owns this installation's engine lock."""


class ForeignInstallation(WorkflowError):
    """The persisted database belongs to a different installation identity."""


class UnknownSchemaVersion(WorkflowError):
    """The database schema is not known to this engine version."""
