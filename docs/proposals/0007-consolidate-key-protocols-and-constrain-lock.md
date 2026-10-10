---
id: "0007"
title: "Consolidate key protocols and constrain Lock"
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

# Proposal 0007 — Consolidate key protocols and constrain Lock

> Format: mini (triage score 1/6 — C5 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose reusing `StorageKey` in place of `ServiceKey`, moving `Factory.Scope` to a top-level `ServiceLifetime`, splitting removal out of `Storage.set`, and renaming the `register` label `scope:` to `lifetime:`. Unlike leaving the shapes, the API has fewer duplicate concepts and a safer lock, at the cost of small breaking edits.

## Context and problem

- `ServiceKey` (`CascadeKit.swift:356`) is the same shape as `StorageKey` (`:41`); three key protocols exist in total.
- `Factory<Service>.Scope` (`:362`) does not use the generic parameter, forcing `Factory<K.Value>.Scope` at call sites (`:392`).
- `Storage.set(_:to: nil)` (`:91`) doubles as removal.

## Goals and non-goals

**Goals**

- **G1** — At most two key protocols remain (`StorageKey`, `DependencyKey`).
- **G2** — `register(_:scope:)` call sites read `.singleton` with no generic qualification.
- **G3** — The `register` label reads `lifetime:` to match `ServiceLifetime`.

**Non-goals**

- **NG1** — Making `Lock` public (it stays internal; the README mention is removed).
- **NG2** — Touching `Lock` or `DependencyKey: Sendable`; the lock rework lives in 0009.

## Proposal

```text
register(DatabaseKey.self, lifetime: .singleton) { _ in … }     // ServiceLifetime
storage.set(Key.self, to: value)                                  // value non-optional
storage.removeValue(for: Key.self)                                // new
```

`ServiceKey` is deleted; service keys conform to `StorageKey`.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | Yes, if… | Lock constraint and DependencyKey Sendable cut (Lock moves to 0009); lifetime label rename stated; public break stated |
| Do nothing | Zero work | Duplicate concepts, unsafe lock | Rejected |
| Keep `ServiceKey` as typealias | Softer migration | Keeps two names for one idea | Rejected (v2 allows breaking) |
| Use `Synchronization.Mutex` | Compiler-checked | Needs iOS 18 (see 0009) | Deferred |

## Risks

- **Compatibility:** breaking for `Storage.set` (public, `:91`), `ServiceKey`, `Factory.Scope` and the `scope:` label; all mechanical.
- **Migration:** mechanical.
- **Rollback:** revert.

## Open questions

1. Does anything outside the package use `StorageKey` with non-Sendable state? (needs: Amine)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
