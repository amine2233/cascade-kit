---
id: "0006"
title: "Test and preview value semantics"
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

# Proposal 0006 — Test and preview value semantics

> Format: mini (triage score 2/6 — C1 behaviour contract, C5 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose three changes to default-value resolution: unoverridden `testValue` fails loudly instead of falling back to `liveValue`; `testValue` and `previewValue` are cached once per `withTestDependencies` scope; and `liveValue` is built exactly once. Unlike today's silent fallback, a test that forgets an override fails instead of hitting the real service, at the cost of requiring a `testValue` for every key used in tests.

## Context and problem

- `testValue` and `previewValue` default to `liveValue` (`CascadeKit.swift:155-161`). A test that forgets an override calls the real implementation, with no error.
- In `.test` context the default is rebuilt on every read (`:201-203`), so a stateful spy returned from a computed `testValue` loses its recorded calls between two reads in one test.
- `liveValue` is documented as built "once per process" but the cache has a check-then-set race (`:206-213`), so it can be built twice (same class of bug as 0003).

## Goals and non-goals

**Goals**

- **G1** — Reading a key with no override and no `testValue` in `.test` context reports a test failure (or traps with the key name).
- **G2** — Two reads of the same key in one `withTestDependencies` scope return the same instance.
- **G3** — Under concurrent first read, `liveValue` is evaluated once.

**Non-goals**

- **NG1** — Integration with a specific test framework's issue reporting beyond a hook.

## Proposal

- Remove the `testValue` default; the protocol requires it, or provides `unimplemented` behaviour that reports through an overridable `testFailureHandler`.
- `withTestDependencies` creates a per-scope default cache carried in `DependencyValues`; reads in `.test` fill it.
- `_defaultCache` uses the once-cell from 0003.

```text
enum APIClientKey: DependencyKey {
    static let liveValue = APIClient.live
    static let testValue = APIClient.unimplemented   // reports if called
}
```

| Case | Behaviour |
| --- | --- |
| Test overrides key | Override wins |
| No override, `testValue` declared | Same instance for the whole scope |
| No override, no `testValue` | Failure naming the key |
| Preview context | `previewValue`, cached once per process |

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | No, because it bundles three decisions and leaves the failure mechanism undecided | Not yet changed; awaiting decider on split (see conversation) |
| Do nothing | Zero work | Silent real-service calls in tests | Rejected |
| Only document `static let` for test values | Zero code | Not enforceable | Rejected |
| Adopt swift-dependencies | Proven semantics | Third-party dependency | Rejected |
| Fail loudly plus per-scope cache | Safe by default | Boilerplate per key | Chosen |

## Risks

- **Compatibility:** breaking; every key used in tests needs a `testValue` (v2).
- **Migration:** a compiler-visible protocol requirement lists what to fix.
- **Rollback:** revert.

## Open questions

1. Trap, throw, or call a handler on a missing `testValue`? (needs: Amine)
2. Should `previewValue` follow the same rule? (needs: Amine)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
