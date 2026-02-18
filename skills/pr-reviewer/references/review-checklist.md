# Review Checklist by Language

## Universal (All Languages)

### Security
- [ ] No secrets, tokens, or passwords in code or config
- [ ] User input validated before use (length, format, allowed values)
- [ ] SQL/query parameters use parameterized queries, not string concat
- [ ] File paths validated (no path traversal)
- [ ] Auth/authz checks on new endpoints or operations
- [ ] Sensitive data not logged at INFO level

### Correctness
- [ ] ID generation has sufficient uniqueness guarantees (no truncated hashes without collision analysis)
- [ ] Sort operations have stable tie-breakers (don't rely on map order or unstable sort alone)
- [ ] Concurrent access to shared state is synchronized
- [ ] Error messages don't leak internal details to users
- [ ] Boundary conditions handled (empty input, max values, zero, negative)
- [ ] Time handling uses UTC consistently; timezone-aware where needed

### Tests
- [ ] New code paths have tests
- [ ] Error/failure paths tested (not just happy path)
- [ ] Edge cases tested (empty, nil, max, duplicate, concurrent)
- [ ] Tests assert meaningful outcomes (not just "no error")
- [ ] Test names describe the scenario, not the function
- [ ] No test pollution (shared state between tests, order-dependent tests)

### API & Schema
- [ ] New fields/endpoints documented
- [ ] Request/response schemas validated
- [ ] Breaking changes flagged and versioned
- [ ] Default values are sensible and documented
- [ ] Pagination implemented for list endpoints

### Backwards Compatibility
- [ ] Config format changes are backwards-compatible or migrated
- [ ] DB schema changes have migration + rollback path
- [ ] API changes don't break existing clients
- [ ] Feature flags for risky changes

---

## Go

### Go-Specific
- [ ] Errors wrapped with `fmt.Errorf("context: %w", err)` — not swallowed
- [ ] `defer` used for cleanup (file handles, locks, connections)
- [ ] Nil checks before pointer dereference — especially on structs returned with errors
- [ ] Context (`ctx`) threaded through and respected (timeouts, cancellation)
- [ ] No goroutine leaks (goroutines have exit conditions)
- [ ] `sync.Mutex` or channels for concurrent map/slice access
- [ ] Exported types/functions have doc comments
- [ ] `errors.Is` / `errors.As` used (not string comparison)
- [ ] Table-driven tests for multiple cases
- [ ] No `init()` functions unless truly necessary

### Go Anti-Patterns
- Using `interface{}` / `any` when a concrete type would work
- Returning `(result, error)` but not checking error at call site
- `panic()` in library code (should return error)
- Global mutable state
- Ignoring `context.Done()` in long operations

---

## Node.js / TypeScript

### Node-Specific
- [ ] `async/await` errors caught (try/catch or `.catch()`)
- [ ] No unhandled promise rejections
- [ ] Dependencies pinned or lock file updated
- [ ] No `eval()`, `Function()`, or dynamic `require()` with user input
- [ ] Environment variables validated at startup, not deep in code
- [ ] TypeScript: no unnecessary `any` types; strict mode enabled
- [ ] `===` used instead of `==`
- [ ] Array/object mutations don't affect shared references

### Node Anti-Patterns
- Callback hell (should use async/await)
- Swallowing errors in catch blocks
- Synchronous file/network ops in hot paths
- `console.log` instead of proper logger
- Missing `await` on async calls (fire-and-forget bugs)

---

## Python

### Python-Specific
- [ ] Type hints on function signatures
- [ ] Exception handling is specific (not bare `except:`)
- [ ] Resource cleanup uses `with` statements (context managers)
- [ ] No mutable default arguments (`def foo(items=[])`)
- [ ] f-strings or `.format()` — not `%` formatting
- [ ] `pathlib` for file paths (not string concat)
- [ ] `__all__` defined for public module APIs
- [ ] Dataclasses or Pydantic for structured data (not raw dicts)

### Python Anti-Patterns
- `import *` polluting namespace
- Catching `Exception` too broadly
- Using `os.system()` instead of `subprocess.run()`
- Mutable class variables shared across instances
- Missing `if __name__ == "__main__"` guard

---

## Rust

### Rust-Specific
- [ ] `unwrap()` / `expect()` only in tests or with documented invariants
- [ ] Error types implement `std::error::Error`
- [ ] `Clone` not used unnecessarily (prefer references)
- [ ] `unsafe` blocks justified and minimized
- [ ] Lifetime annotations clear and correct
- [ ] `clippy` warnings addressed
