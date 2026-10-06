# ADR-0006: Each guru is read through a learned, owner-edited playbook, not code or alias tables

## Status
Accepted, September 2026.

Amended October 2026: the guru's message prefix was removed. Each channel carries one guru, so
every post in it is read; Learn no longer drafts a prefix.

## Context
Reading a guru's posts is the model's job, but guru knowledge had leaked into code and forms:
an alias table (英伟达=NVDA) the owner typed by hand, a hard-coded list of Chinese and English
action words in grounding, a whitelist of trim fractions, and one guru's worked examples inside
the base prompt. Each new guru, or a new habit of an old one (出剩下一半), needed a code change,
and a model that wrote 1/6 with fewer digits sent every 1/6 buy to review.

## Decision
1. **A playbook per guru.** Each profile carries `playbook`, plain text written as guidance for
   the reader model and sent as trusted instructions, separate from the untrusted post.
2. **Learned, then edited.** Learn from Channel reads the channel's recent posts the way the
   live pipeline does and asks the model for a draft: playbook (with one worked line per
   convention), exit basis, and examples. Only examples that are verbatim posts and pass
   the same validation as hand-written ones survive. Nothing is saved until the owner saves.
3. **Examples are the gate.** Validate runs every example through the reader with the playbook;
   any mismatch blocks activation. A bad draft is caught before it trades.
4. **Grounding stays universal.** Code keeps only checks that hold for any guru and language:
   cited words are in the post; prices, tickers, and allocation tokens are complete tokens of the
   post; fractions match within 1e-9; a company name resolves to a ticker only when one playbook
   line states both. The words' meaning is the model's call.
5. **No migration.** Configuration v4 replaces v3. The app discards an older setup file and its
   Keychain item at startup and asks the owner to set up again.

## Consequences
* A new guru is Add Route, Learn, edit, Validate. No code change.
* Reading quality now depends on the learned playbook; the example gate and the owner's edit
  bound that risk. On 赵哥's channel, three of four fresh drafts verified every example; the
  fourth was blocked by the gate, as designed.
* Aliases, unsupported conventions, the review-only profile state, and the example-suggestion
  panel are gone.
