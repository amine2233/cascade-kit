---
id: "0004"
title: "Preserve caller actor in withDependencies"
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

# Proposal 0004 — Preserve caller actor in withDependencies

> Format: mini (triage score 1/6 — C5 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose adding `isolation: isolated (any Actor)? = #isolation` to the async `withDependencies` and `withTestDependencies`, so that `@MainActor` callers can pass non-Sendable closures without "sending risks data race" errors. Unlike leaving them nonisolated, the operation stays on the caller's actor, at the cost of a slightly larger signature.

## Context and problem

The async overloads at `CascadeKit.swift:292` and `:312` are nonisolated, so on Swift 6 the operation leaves the caller's actor. A `@MainActor` view model capturing main-actor state in `operation` is expected to fail to compile or to need `@Sendable` workarounds (reproduction and compiler error to be added by the 30-minute spike before approval, to verify). The platform `TaskLocal.withValue` already accepts an `isolation:` parameter.

## Goals and non-goals

**Goals**

- **G1** — A `@MainActor` caller can use `withDependencies` with a closure touching main-actor state, with no `Sendable` annotation (compile test).
- **G2** — Call sites without actors are unchanged.

**Non-goals**

- **NG1** — Changing the sync overloads.

## Proposal

```text
public func withDependencies<R>(
    isolation: isolated (any Actor)? = #isolation,
    _ mutate: (inout DependencyValues) -> Void,
    operation: () async throws -> R
) async rethrows -> R
```

Pass `isolation` through to `$current.withValue(_:operation:isolation:)`. `withTestDependencies` MUST forward `isolation` to the inner `withDependencies`. `isolation:` goes first, matching the standard library. Tests: a `@MainActor` caller compiles (G1) and an actor-less caller still compiles (G2).

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | Yes, if… | Spike precondition noted; isolation forwarding and placement fixed; baseline question added |
| Do nothing | Zero work | Friction on every `@MainActor` test and reducer | Rejected |
| Mark closures `@Sendable` | No signature change | Pushes the burden to callers | Rejected |
| `@MainActor` overload | Simple | Not general for custom actors | Rejected |

## Risks

- **Compatibility:** source compatible (defaulted parameter).
- **Toolchain:** needs `#isolation`, so Swift 6.0; already the tools version.
- **Rollback:** revert.

## Open questions

1. Availability of `TaskLocal.withValue(isolation:)` at the current baseline (`iOS 13`, `Package.swift:8`) conflicts with nothing only if 0009 lands or the API is available; check. (needs: implementer)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
