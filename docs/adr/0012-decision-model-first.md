# ADR-0012: A decision model first, the reader behind it

## Status
Accepted, October 2026. Extends ADR-0007 (one reading contract) with a triage step.

## Context
Every post went to the reader (DeepSeek), and a post it could not place waited for the owner, so
"hm", "hi", "how's going", "早上好" and emoji reached Waiting for You as `unclear`. Most posts in a
guru's channel are chat. Hand-written keyword thresholds were tried and dropped: they misfile
Chinese and slang, and they move the decision into code that nobody tunes.

A decision model answers typed questions with calibrated probabilities instead of writing text,
in tens to hundreds of milliseconds, for a fraction of a reading's cost. Pydantic AI supports
them natively (`DecisionModel`: OpenAI's Decisions API as `openai-decisions`, TypeSafe's Jev as
`typesafe`), turns a union of output types into a route question, and hands any route it cannot
fill, or any pick below `decision_route_threshold`, to the model behind it in a `FallbackModel`.

## Decision
1. **Chat is its own answer.** The reader answers either `JustChat`, which carries nothing, or a
   reading of the other kinds; it has no other way to say chat. The engine stores chat as the
   `chatter` kind of `PostReading` and ignores it with reason `chatter` ("Just chat, nothing to
   trade"). `Unclear` is only for a post about a trade the reader cannot place, and still waits for
   the owner. Without triage, the reader answers as prompted JSON, as before.
2. **Decision model first, when the owner sets one up.** The reader agent runs on
   `FallbackModel(decision model, reader)` with the same two answers as tool outputs. A sure pick
   of `JustChat` settles the post without the reader. A reading has the post's own words to cite,
   which a decision model cannot write, so it hands the step to the reader, as it does any pick
   below the route threshold (0.9 to start; the live run put "跑路了", guru slang for "sold
   everything", at 0.57 chat) and any failure or timeout of its backend.
3. **Nothing is let go on a second look.** The reader's checks still hold every reading to the
   post's words and give it one retry. If the retry comes back as chat, the post waits for the
   owner instead: a post the reader already took for something is never ignored on the retry.
4. **Which model answered is recorded.** The signal's `model` is the decision model when it
   settled the post, and `sorted_confidence` is how likely it found the pick, so Activity can say
   "Sorted as chat (98% sure)". The decision model's requests are journaled like the reader's.
5. **Setup.** The saved configuration's optional `triage` section names the provider, model, and
   route threshold; its key travels with the other secrets as `triage_api_key` and is redacted
   like them. A `triage` connection check makes one cheap decision to verify the key. Triage sits
   in front of the DeepSeek reader only: both answer through tool calls, which the other readers
   are not set up for.

## Consequences
* Chat costs a decision call instead of a reading, and never reaches the owner.
* Every decoder has one method, `answer()`, which returns the reading and which model gave it.
* A wrong, confident chat pick would ignore a post. The threshold, the decision model's
  calibration, and the labelled eval set (`tests/parsing/triage_cases.py`) are the guard; the
  reader is still the only path to a trade. `tests/integration/test_triage_live.py` runs the set
  through the real decision model and prints the margin; "hm" stays a trap, never an example.
* With triage on, the DeepSeek reader answers through a tool call rather than prompted JSON.
