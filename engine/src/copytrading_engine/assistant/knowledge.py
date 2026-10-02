"""The app's own help, given to the assistant as reference for setup questions."""

from importlib.resources import files

HELP = files(__package__).joinpath("help.md").read_text(encoding="utf-8")
