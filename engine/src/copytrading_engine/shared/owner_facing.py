"""Errors whose message is a fixed sentence written for the owner to read."""


class OwnerFacingError(ValueError):
    """Never built from tokens, paths, or raw provider or Discord text."""
