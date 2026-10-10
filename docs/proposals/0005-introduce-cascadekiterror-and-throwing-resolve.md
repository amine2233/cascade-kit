---
id: "0005"
title: "Introduce CascadeKitError and throwing resolve"
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

# Proposal 0005 — Introduce CascadeKitError and throwing resolve

> Format: mini (triage score 2/6 — C1 public API, C5 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose a single `CascadeKitError` enum and a throwing `resolve(_:)` on `Container`, keeping `make(_:)` as the crashing convenience, so that a missing registration is testable and recoverable on a server. Unlike `fatalError` only, callers can choose to handle the failure, at the cost of one more entry point.

## Context and problem

`make` calls `fatalError("No factory registered for …")` when no factory exists locally or in any parent (`CascadeKit.swift:424`). The crash cannot be tested, and a request handler cannot turn it into a 500 response. The module defines no Error type, while the project rule is one Error type per module.

## Goals and non-goals

**Goals**

- **G1** — `try container.resolve(K.self)` throws `CascadeKitError.serviceNotRegistered` instead of trapping (unit test).
- **G2** — The module defines exactly one Error type.
- **G3** — `make` behaviour is unchanged.

**Non-goals**

- **NG1** — Throwing factories (separate decision).
- **NG2** — Typed throws.

## Proposal

```text
public enum CascadeKitError: Error, Sendable, Equatable {
    case serviceNotRegistered(String)   // String(describing: K.self)
}

let db = try container.resolve(DatabaseKey.self)
let db = container.make(DatabaseKey.self)   // traps, as today
```

`resolve` walks `parent` recursively and throws only at the root. `make` calls `resolve` and on error calls `fatalError("No factory registered for \(K.self).")` itself, so the crash message is unchanged (`try!` would not preserve it). Both share the singleton path, so this lands after 0003. The enum is not `@frozen`; adding a case later is source-breaking for exhaustive switches. The same enum is the home for any future error in the module.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | Yes, if… | make now calls fatalError itself; chain question closed; non-frozen enum stated; sequenced after 0003 |
| Do nothing | Zero work | Untestable crash path | Rejected |
| Make `make` throw | One entry point | Every call site needs `try`; noisy for startup wiring | Rejected |
| Return optional | No Error type | Loses the reason | Rejected |
| `resolve` plus `make` | Both needs served | Two entry points | Chosen |

## Risks

- **Compatibility:** additive.
- **Rollback:** revert.
- **Observability:** error carries the key type name.

## Open questions

1. None open; carrying the container chain was considered and rejected as YAGNI.

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
