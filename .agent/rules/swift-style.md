---
trigger: model_decision
description: Swift coding style and architecture conventions
---

# Swift Code Style Guidelines

## Core Style

- Naming: PascalCase for types, camelCase for properties and methods.
- Language: Use English for identifiers and comments unless existing context requires otherwise.
- Dependency: Prefer dependency injection for services and environment values.

## File Organization

- Group files by feature/domain.
- Use PascalCase file names for types.
- Use `+` suffix files for type extensions.
- Keep extensions focused and modular.

## Modern Swift Features

- Prefer `@Observable` over `ObservableObject` and `@Published`.
- Prefer Swift concurrency (`async/await`, `Task`, `actor`, `@MainActor`).
- Use result builders for declarative APIs when appropriate.
- Use line breaks for long property-wrapper declarations.
- Use opaque return types (`some`) for protocol-backed returns when suitable.

## Code Structure

- Use early returns to reduce nesting.
- Use `guard` for required optional unwrapping.
- Keep single responsibility per type/extension.
- Prefer value types over reference types when practical.

## Error Handling

- Use typed errors.
- Propagate with `throws`/`try`.
- Use optional chaining and `guard let`/`if let` appropriately.
- Use `Result` where explicit success/failure modeling is valuable.

## Architecture

- Prefer protocol-oriented design.
- Prefer dependency injection over singletons.
- Prefer composition over inheritance.
- Use Factory/Repository patterns where they simplify responsibilities.

## Debug Assertions

- Use `assert()` for development-time invariants.
- Use `assertionFailure()` for logically unreachable paths.
- Use `precondition()` only for truly fatal programmer errors.

## Memory Management

- Use `weak` to break retain cycles.
- Use `unowned` only when lifetime guarantees are strict.
- Use capture lists in closures when needed.
- Use `deinit` for cleanup responsibilities.
