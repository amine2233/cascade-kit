---
id: "0003"
title: "Build-once singletons and shutdown hooks in Container"
type: mini
status: in-review
authors: ["Amine BENSALAH <amine.bensalah@intech-consulting.fr>"]
reviewers: []
decider: "Amine BENSALAH"
created: 2026-10-10
review-deadline: 2026-10-15
discussion: ""           # PR link
supersedes: ""           # "<id> §x.y" when replacing (part of) another proposal
amends: ""               # proposal this one extends without contradicting
amended-by: ""
superseded-by: ""
---

# Proposal 0003 — Build-once singletons and shutdown hooks in Container

> Format: mini (triage score 2/6 — C1 behaviour contract, C5 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose making singleton construction build-once under concurrency and adding an `onShutdown` parameter to `register`, so that a container service (for example a connection pool) is never built twice or leaked, and `shutdown()` tears down what was registered. Unlike the documented "warm up single-threaded" workaround, this makes the guarantee structural, at the cost of a per-key once-cell.

## Context and problem

- `make` checks the cache, builds outside the lock, then `storage.set` (`CascadeKit.swift:413-418`). Two concurrent first calls both run the factory; one instance replaces the other and its shutdown never runs. The doc comment (`:403-406`) calls it "benign" and tells callers to warm up at boot.
- `register` (`:390`) has no `onShutdown`; the cache write at `:417` passes none either. `Application.shutdown()` (`:435`) therefore drains nothing for container services, although `Storage.set` supports hooks (`:91`).
- The same race exists for `liveValue` in `_defaultCache` (`:206-213`); handled in 0006.

## Goals and non-goals

**Goals**

- **G1** — Under N concurrent first `make` calls, the factory runs exactly once per singleton key (test with `TaskGroup`).
- **G2** — `register(..., onShutdown:)` hooks run on `shutdown()` exactly once.
- **G3** — Factories MUST still run outside the storage lock so recursive `make` of a different key cannot deadlock.
- **G4** — `shutdown()` runs the hook of every built singleton.

**Non-goals**

- **NG1** — Async factories.
- **NG2** — General cycle detection. Exception: re-entry of the same key on the same task MUST trap (needed by 0001, whose bridge makes it easy to hit).

## Proposal

Store the hook on the `Factory` (`Factory.onShutdown`, set by `register`) and pass it at the cache write, so `CacheKey` values get the hook. Install a per-key once-cell in `Storage` under the lock; the first caller builds outside the lock and publishes; concurrent callers wait on the cell. Longer dependency cycles are programmer errors (today they already recurse infinitely) and are out of scope (NG2); same-key re-entry on one task traps, tracked with a task-local build stack. Transient services are never cached, so they have no shutdown.

```text
app.register(DatabaseKey.self, onShutdown: { $0.close() }) { _ in PostgresPool(url: url) }   // singleton only
```

| Case | Behaviour |
| --- | --- |
| Concurrent first `make` | One build, all callers get the same instance |
| `shutdown()` | Hooks run once, outside the lock |

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | Yes, if… | Hook wiring specified on Factory; cycles declared out of scope; throws row removed; first-write-wins alternative added |
| Do nothing | Zero work | Leaks pools under load | Rejected |
| Hold the lock while building | Trivial | Deadlocks on recursive `make` | Rejected |
| Document warm-up at boot | Zero code | Pushes the race onto every caller | Rejected |
| First-write-wins cache write, shutdown the loser | One small edit | Factory still runs twice (a pool opens connections twice); misses G1 | Rejected |
| Per-key once-cell | Correct, exactly once | More code in `Storage` | Chosen |

## Risks

- **Compatibility:** `register` gains a defaulted parameter; source compatible.
- **Performance:** one extra lock round-trip on the cold path.
- **Rollback:** revert; no persisted data.

## Open questions

1. Should `Request` run shutdown hooks too? Today `Request` has no `shutdown()`. (needs: Amine)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
