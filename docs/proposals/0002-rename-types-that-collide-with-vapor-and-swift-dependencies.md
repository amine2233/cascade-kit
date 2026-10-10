---
id: "0002"
title: "Rename types that collide with Vapor and swift-dependencies"
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

# Proposal 0002 — Rename types that collide with Vapor and swift-dependencies

> Format: mini (triage score 2/6 — C1 public API, C5 options). v2 allows breaking changes.
> The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as described in RFC 2119.

## Summary

We propose renaming the Vapor-colliding types (`Application`, `Request`, `Storage`) so that a project can import CascadeKit next to Vapor without ambiguity, because those names are identical. The `@Dependency` names mirror swift-dependencies on purpose and stay unless a consumer importing both is named. Unlike documenting module-qualified use, this removes the problem at the source, at the cost of a breaking rename. Sequenced after 0001.

## Context and problem

The `Container` layer targets server-side use (`CascadeKit.swift:338-448`), exactly where Vapor's `Application` and `Request` live. `Storage` (`:67`) also exists in Vapor. The `@Dependency` layer (`:120-336`) mirrors Point-Free's API names one for one, which may be a deliberate drop-in advantage. Whether unqualified use is actually ambiguous in practice is unverified (a local or explicitly imported name can win); a 10-line spike settles it before approval.

## Goals and non-goals

**Goals**

- **G1** — `import CascadeKit` plus `import Vapor` compiles with no ambiguous type.
- **G2** — (Conditional) Same for `import Dependencies`, only if a real consumer importing both is named.

**Non-goals**

- **NG1** — Source compatibility with v1.
- **NG2** — Changing behaviour.
- **NG3** — Renaming the `@Dependency` API by default (see Open questions).

## Proposal

| v1 | v2 |
| --- | --- |
| `Application` | `AppScope` |
| `Request` | `RequestScope` |
| `Storage` | `ServiceStorage` |

Default scope: the three rows above. Fallback, only if G2 is activated: `Dependency` to `Injected`, `DependencyKey` to `InjectionKey`, `DependencyValues` to `InjectionValues`, `withDependencies` to `withInjections`. Names are provisional.

## Alternatives considered

| Option | For | Against | Verdict |
| --- | --- | --- | --- |
| 2026-10-10 | design-proposal-reviewer | Yes, if… | Scope cut to Vapor clashes; swift-dependencies rename made conditional; sequenced after 0001; ambiguity spike required |
| Do nothing | No churn | Ambiguity for any Vapor consumer | Rejected |
| Document `CascadeKit.Application` qualification | No rename | Module-qualified names are noisy; `Dependency` is a property wrapper | Rejected |
| Rename only Vapor clashes | Smaller change | swift-dependencies users still blocked | Fallback |
| Rename the module instead | Qualification works naturally | Does not fix unqualified imports | Rejected |

## Risks

- **Compatibility:** breaking; accepted for v2, noted in CHANGELOG.
- **Migration:** mechanical find-and-replace; list in the v2 migration guide.
- **Security / rollback:** N/A.

## Open questions

1. Does anyone import both CascadeKit and swift-dependencies? If not, G2 stays dropped. (needs: Amine)
2. Is the Vapor clash real once 0001 isolates `Container`? Spike first. (needs: Amine)

## Review log

| Date | Reviewer | Verdict | Changes made |
| --- | --- | --- | --- |

## Decision

<!-- Filled at closing. -->

## Amendments

<!-- Append-only after acceptance. -->
