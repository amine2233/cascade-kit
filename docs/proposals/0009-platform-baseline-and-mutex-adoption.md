---
id: "0009"
title: "Platform baseline and Mutex adoption"
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

# Proposal 0009 — Platform baseline and Mutex adoption

> Format: mini (triage score 2/6 — C1 deployment contract, C5 options).
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose raising the baseline to iOS 18 / macOS 15 if no consumer is below it (Q1), and replacing the `Lock` wrapper over `NSLock` with `Synchronization.Mutex` used directly, so that the `@unchecked Sendable` class and the Foundation dependency go away. Unlike keeping `NSLock` and iOS 13 with a documented invariant, at the cost of dropping older OS versions.

## Context and problem

`Package.swift:8` declares only `.macOS(.v10_15)` and `.iOS(.v13)`. `Lock` wraps `NSLock` and is `@unchecked Sendable` (`CascadeKit.swift:13`), with a comment that `Mutex` needs iOS 18 / macOS 15 (`:10-12`). The `Lock` class is the package's only `@unchecked Sendable` type. Cost of doing nothing: one internal class with a documented invariant. Windows and Android are unverified: there is no CI job for either.

## Goals and non-goals

**Goals**

- **G1** — `Package.swift` declares iOS 18 and macOS 15; other platforms are added only when CI builds them.
- **G2** — `Lock` is deleted; `Storage` and `_defaultCache` use `Mutex` directly, with no `@unchecked` in the package.
- **G3** — CI builds on Linux. Windows and Android are out of scope for v2.

**Non-goals**

- **NG1** — Back-deployment below the new baseline.
- **NG2** — New platform support commitments (tvOS, watchOS, visionOS) without CI.

## Proposal

```text
platforms: [.macOS(.v15), .iOS(.v18)]
private let items = Mutex<[ObjectIdentifier: any AnyStorageValue]>([:])
```

`Mutex` is `Sendable` and has `withLock`, so the wrapper is redundant. Call sites adapt to `Mutex.withLock` (`inout sending State`). Availability on Linux without an OS gate (to verify on the CI toolchain). Re-entrancy still deadlocks; the documentation note stays. Lands after 0007.

| Case | Behaviour |
| --- | --- |
| Consumer targets iOS 17 | Cannot depend on v2; stays on v1 |

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | Yes, if… | Premise changed to consumer evidence; Lock wrapper deleted for direct Mutex; G3 settled to Linux only; platforms limited to CI-covered; rollback policy stated |
| Do nothing | Back-deploys to iOS 13 | `@unchecked`; stale baseline | Rejected for v2 |
| `OSAllocatedUnfairLock` | Older OS support | Apple platforms only | Rejected |
| Keep `NSLock` and iOS 13, document the invariant | No break; one internal class | Keeps `@unchecked`, stale baseline | Fallback if Q1 shows older consumers |
| Keep `NSLock`, raise OS only | Smaller change | Keeps `@unchecked` | Rejected |
| `Mutex` | Checked, portable | Needs iOS 18 | Chosen |

## Risks

- **Compatibility:** drops iOS 13–17 and macOS 10.15–14; breaking for those consumers, and a major version bump.
- **Rollback:** pin v1, which receives no further fixes (stated policy).
- **Portability:** Windows and Android unverified (to verify).

## Open questions

1. Is any known consumer below iOS 18? Precondition for approval; the baseline raise needs this evidence, not a stack preference. (needs: Amine)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
