"""A reading that fails keeps why: the rule and the path, never the post's words."""

from pydantic_ai.exceptions import ModelRetry, UnexpectedModelBehavior

from copytrading_engine.parsing.diagnostics import ValidationIssue, validation_issues
from copytrading_engine.parsing.extraction import GroundingError


def _refused_twice() -> UnexpectedModelBehavior:
    """The chain PydanticAI raises when the retry also fails a reading check, as seen live:
    the run's error, the retry the check asked for, and the check's own error underneath."""
    try:
        try:
            try:
                raise GroundingError(
                    "dollars_not_grounded",
                    "calls.0.size",
                    "words must be the post's dollar amount, such as $200 of or 200 dollars",
                )
            except GroundingError as exc:
                raise ModelRetry(f"{exc.issue.path}: {exc}") from None
        except ModelRetry:
            raise UnexpectedModelBehavior("Exceeded maximum output retries (1)")  # noqa: B904
    except UnexpectedModelBehavior as exc:
        return exc


def test_a_reading_refused_by_a_check_keeps_the_rule_and_its_path():
    assert validation_issues(_refused_twice()) == (
        ValidationIssue(path="calls.0.size", code="dollars_not_grounded"),
    )


def test_an_error_with_no_reading_check_has_no_issues():
    assert validation_issues(UnexpectedModelBehavior("Exceeded maximum output retries (1)")) == ()
