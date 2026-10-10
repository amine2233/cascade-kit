# ``CascadeKit``

Dependency injection for Swift with two setup styles that work together: implicit task-local `@Dependency` and an explicit scoped `Container`.

## Overview

CascadeKit has one key type and two ways to set it up.

- **Implicit style.** Declare a ``DependencyKey``, read it with ``Dependency``, override it for a scope with `withDependencies` or `withTestDependencies`. Best for apps, reducers and tests.
- **Explicit style.** Register factories on an ``AppScope`` and resolve them with `make` or `resolve`. Best for composition roots and servers, with an app to request hierarchy through ``RequestScope``.
- **Both together.** Bind a container with `withDependencies { $0.container = app }` and `@Dependency` returns the container's registrations.

The package has no dependencies and requires iOS 18 or macOS 15.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CompleteGuide>
- <doc:MigratingFromV1>

### Examples

- <doc:Examples>

### Dependencies

- ``DependencyKey``
- ``DependencyValues``
- ``DependencyContext``
- ``Dependency``

### Containers

- ``Container``
- ``AppScope``
- ``RequestScope``
- ``ServiceLifetime``
- ``Factory``

### Storage

- ``StorageKey``
- ``ServiceStorage``

### Errors

- ``CascadeKitError``
