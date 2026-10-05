# ADR-0008: An account can ask the owner to approve every order

## Status
Accepted, October 2026. Extends ADR-0005 and ADR-0007.

## Context
Copy trading sends orders without a person in the loop, which is the point. Some owners want
extra scrutiny anyway, on a live account or while they learn to trust a guru's reading, and want
nothing to reach the broker until they say so. ADR-0005 already requires the owner's Touch ID
before an agent's request runs; the same guarantee was missing for the app's own copying.

The reader is an AI model, and the temptation is to put the approval where agent frameworks put
it: as a deferred tool call the model asks for. The reader has no order tools. It reads a post
into one contract, and code decides (ADR-0007). An approval inside the model would be the wrong
place: the model could not be trusted to ask, and a missed prompt would send an order.

## Decision
1. **A per-account switch, off by default.** `approve_orders` is set in the account's behavior
   settings and applies to paper and live accounts alike. Off, nothing changes.
2. **The gate is in the engine's decision, after every check.** A call that would have become
   an order (it passed risk, sizing, price and session checks) is instead recorded as held with
   the reason `approval_required`. A call that would have been skipped anyway is not held, so the
   owner is asked only about orders that would really go out. No order, no broker call.
3. **The hold is the waiting-for-you path of ADR-0007.** `approval_required` joins
   `HELD_FOR_OWNER`, so the call shows in Activity with an alert, expires at the same trading-day
   boundary, and can be skipped. The card says "Waiting for your approval" and the button reads
   Approve….
4. **Approving is the owner's hand-copy, with Touch ID.** Approve… opens the call already filled
   in, previews it fresh against the account and market, and sends it through the guarded
   manual path, which plans afresh and is never held again. The app asks for Touch ID before any
   order the owner sends by hand to a live account or to an account that asks for approval, in
   one prompt for the batch. A refused prompt sends nothing. Selling a lot from Accounts follows
   the same rule.
5. **The check is the app's.** As with agent requests and live lot sales, the engine trusts the
   app on the local pipe to have asked; the setting guarantees that nothing leaves the engine
   by itself, which is the part only the engine can guarantee.

## Consequences
- A held call waits for a person. If the owner is away the day ends and the call expires, like
  any other waiting call.
- Exits are held too. An account that approves everything must approve its sells, and a held
  sell leaves the shares owned until it is approved or the day ends.
- Hand-copying into a live account now asks for Touch ID even without the switch.
