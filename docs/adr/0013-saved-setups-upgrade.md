# ADR-0013: A saved setup is upgraded, never thrown away

## Status
Accepted, October 2026.

## Context
The saved setup (`trading-configuration.json`, with its keys in the Keychain) records a version.
Until 0.1.0-beta.7 a setup saved at an earlier version was deleted at launch, keys included, and
the owner set everything up again. Beta.6 raised the version from 8 to 9 that way. Everyone typed
their Discord token, model key, Alpaca keys and gurus again; the owner named their account
`primary` instead of `zhap-account-2`, its record belonged to another Alpaca account, and copying
would not start. The rule "no backward compatibility" was being applied to the owner's data as
well as to the code.

At the same time an account's settings were split between the setup (limits, signal age, hours)
and the account's record (what it does after a restart), so a fresh setup brought half of them
back.

## Decision
1. **Code keeps one shape; data moves forward.** The engine and the app read only the current
   setup. Each change to its shape raises `CONFIGURATION_VERSION` and ships one step in
   `SetupUpgrade` (`app/Sources/DesktopCore/SetupUpgrade.swift`) that rewrites the version before
   it. At launch the app runs the steps once, asks the engine for the result's revision, saves the
   file at the current version with the same Keychain item, and loads it. No other code reads an
   old shape.
2. **A step may read the accounts' records, so nothing copies until it is done.** The app
   upgrades after the engine is up, so a step can use what only an account's record knows
   (`SetupUpgrade.Facts`); version 10's step takes each account's after-restart choice from its
   record. Until the upgraded setup is saved, `setupAwaitsUpgrade` holds back every start of
   copying (on launch, after an update, after an engine restart); the launch start runs right
   after, so the engine never runs a setup that is missing a choice.
3. **Steps reach back to 0.1.0-beta.5.** `SetupUpgrade.earliestVersion` (the engine's
   `EARLIEST_UPGRADABLE_VERSION`) is 8, beta.5's setup: 8 → 9 drops the guru examples beta.6
   removed and rebuilds each profile's revision without them. Lower it never; raise it only when a
   step is dropped on purpose.
4. **Backups follow the same rule.** A backup holding an upgradable setup restores as it was, and
   the next launch upgrades it.
5. **Nothing is deleted.** A setup that fails to upgrade stays where it is and the app says why. A
   setup older than the earliest step moves aside to `trading-configuration-before-upgrades.json`,
   its Keychain item kept, so a new setup can be saved; the app says where it is.
6. **Every choice that changes how an account trades lives in the setup.** The account's record
   holds facts and live state: lots, orders, fills, the Alpaca account it belongs to, and whether
   the owner paused new buys. What the account does after a restart moved into the setup (version
   10), shown on the account sheet beside the limits; the record keeps only the value it last ran
   with, as history.

## Consequences
- A format change costs one small, tested step instead of a re-setup for every user.
- Each step is tested by loading a file at the version before it and checking nothing is lost.
- Version 10's step also gives each guru the ID its channel names (`GuruIdentity`), rebuilding
  its profile's revision, so a setup saved with random guru IDs keeps its gurus' history.
