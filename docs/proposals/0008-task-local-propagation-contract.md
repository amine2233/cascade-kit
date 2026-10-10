---
id: "0008"
title: "Task-local propagation contract"
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

# Proposal 0008 — Task-local propagation contract

> Format: mini (triage score 3/6 — C1 behaviour contract, C4 crosses ReduxKit, C5 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose documenting and testing exactly where `DependencyValues` overrides propagate, and documenting a capture snippet for the places they do not, so that ReduxKit effects behave identically in tests and production. Unlike leaving it implicit, effect authors know which scheduling APIs keep overrides, at the cost of one test per row.

## Context and problem

`DependencyValues.current` is a `@TaskLocal` (`CascadeKit.swift:181`). Overrides reach structured children and `Task {}`, but not `Task.detached`, GCD callbacks, or escaping closures that run later. A test already pins the `Task.detached` behaviour (`detachedTaskLosesOverride`, `Tests/CascadeKitTests/CascadeKitTests.swift:335`). If ReduxKit effects run through any non-propagating API, overrides silently stop applying and the real service is hit. Whether ReduxKit does so is unknown (to verify).

## Goals and non-goals

**Goals**

- **G1** — A documented table lists every scheduling API and whether overrides propagate.
- **G2** — The docs show the capture snippet below for non-propagating APIs; no new API unless ReduxKit proves a need (Q1).
- **G3** — A test per row of the table.

**Non-goals**

- **NG1** — Making overrides propagate through `Task.detached` (not possible with task-locals).
- **NG2** — Changing ReduxKit (separate repository).

## Proposal

| API | Overrides propagate? |
| --- | --- |
| `async let`, child task, `TaskGroup` | Yes |
| `Task {}` | Yes |
| `Task.detached` | No |
| `DispatchQueue.async`, callbacks | No |

```text
let values = DependencyValues.current
Task.detached { await DependencyValues.$current.withValue(values) { await effect() } }
```

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | Yes, if… | Capture helper replaced by documented snippet; test name resolved; ReduxKit question made approval precondition |
| Do nothing | Zero work | Silent real-service calls | Rejected |
| Docs only | Cheap | No tool for the failing cases | Rejected |
| Global (non task-local) override | Reaches every thread | Breaks parallel tests | Rejected |
| Capture helper API | Shorter call site | Speculative until ReduxKit needs it | Deferred |
| Docs, tests, capture snippet | Explicit, no new API | Callers write 2 lines | Chosen |

## Risks

- **Compatibility:** none (docs and tests only).
- **Observability:** none; failure mode is a test hitting a real service, mitigated by 0006.
- **Rollback:** revert.

## Open questions

1. Which APIs do ReduxKit effects use to run? Precondition for approval: if only `Task {}`, this proposal reduces to docs and tests. (needs: Amine, ReduxKit maintainer)
2. Is a deterministic GCD test practical with Swift Testing (continuation, no sleeps)? (needs: implementer)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
