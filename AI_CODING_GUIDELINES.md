# AI Coding Guidelines

## 🚨 CRITICAL: Rust Code Quality Enforcement

**NEVER use direct cargo commands:**

```bash
# ❌ FORBIDDEN:
cargo clippy
cargo fmt --check
cargo test
```

**ALWAYS use Makefile targets:**

```bash
# ✅ REQUIRED:
make lint     # fmt-check + clippy-app + clippy-test
make dev      # lint + test (full workflow)
make test     # run all tests
```

**Why**: Local vs CI consistency. Direct cargo commands cause failures that only appear in CI.

## 🎯 Core Principles

**Explicitness**: Write code that can be understood by AI systems. No hidden dependencies.

**Modularity**: Maximum 500 lines per file. Single responsibility per component.

**Reversibility**: All decisions must be easily undoable. Use feature flags, configuration, interfaces.

## 🔥 SACRED PRINCIPLES: DRY & KISS

**DRY (Don't Repeat Yourself)**: The highest pride for both human and AI programmers.

**KISS (Keep it Simple Sweetheart)**: Simplicity is the ultimate sophistication.

### Zero Tolerance for Redundancy

**NEVER create duplicate information**:

- Same validation commands in multiple files
- Identical explanations across documents
- Repeated code examples or instructions
- Overlapping documentation sections

**MANDATORY before any addition**:

1. Search existing files for similar content
2. If ANY overlap exists, consolidate instead of duplicating
3. If absolutely certain you need repetition: **ASK FOR EXPLICIT CONFIRMATION**
4. Reviewer must approve repetition with clear justification

### Simplicity Requirements

**Always choose the simpler option**:

- One Makefile target instead of multiple scripts
- Concise documentation over verbose explanations
- Single source of truth over distributed information
- Essential content only - remove nice-to-have details

**Review every addition**: Does this make the system simpler or more complex? If more complex, justify or remove.

## 📋 Essential Workflow

### Before Code Changes

- [ ] Understand current milestone (VISION.md, MILESTONES.md)
- [ ] Define task scope explicitly
- [ ] Plan rollback strategy

## 🎨 Automatic Code Formatting

**MANDATORY**: All code must be automatically formatted before commit.

**One-time setup** (run once per development environment):

```bash
./scripts/setup-dev.sh
```

**Pre-commit hooks automatically**:

- Format all code on every commit
- Run linting checks
- Validate file structure
- Sort imports
- Fix trailing whitespace

**Manual formatting** (if needed):

```bash
# Rust (backend)
cd backend && make fmt

# Python (MQTT simulator)
cd docker/mqtt-simulator && make fmt

# All files
pre-commit run --all-files
```

**NEVER skip formatting**: Pre-commit hooks prevent commits with formatting issues. This ensures zero formatting conflicts in CI.

### Language-Specific Validation

**Rust** (backend):

```bash
cd backend && make lint && make test
```

**TypeScript** (frontend):

```bash
cd frontend && npm run lint && npm test
```

**Python** (simulator):

```bash
python -m flake8 . && python -m pytest
```

### After Every Code Edit

- [ ] **Syntax**: Language-specific check (make build, npx tsc --noEmit, etc.)
- [ ] **Linting**: Zero warnings (make lint, npm run lint, flake8)
- [ ] **Tests**: Relevant test suites pass
- [ ] **Build**: Successful compilation/build

## 🧪 Testing Strategy

**Unit Tests**: Isolated component testing. Fast feedback.

**Integration Tests**: Component interaction testing. Realistic scenarios.

**End-to-End Tests**: Full system testing. User journey validation.

**Error Handling**: Application code must handle errors properly (no expect/unwrap). Test code can panic early for debugging.

## 🔄 Development Cycle

1. **Make It Work**: Solve core problem with minimal viable implementation
2. **Make It Right**: Clean, maintainable, documented code
3. **Make It Fast**: Optimize with measurable improvements

## 🚫 Anti-Patterns

**Avoid**:

- Global state and hidden dependencies
- Copy-paste code (abstract immediately)
- Magic numbers and strings
- Tight coupling between components
- Inconsistent naming conventions

**Detection Signals**:

- Hard to test in isolation
- Changes require modifying multiple files
- Difficult to explain component purpose in one sentence

## 🔧 Configuration & Tooling

**Environment Variables**: Use for runtime configuration, never secrets in code.

**Dependency Management**: Explicit version pinning, regular security updates.

**IDE Integration**: Configure tools to use project standards (make lint, not cargo clippy).

## 📊 Logging Standards

**Levels**: ERROR (failures), WARN (degraded), INFO (significant events), DEBUG (troubleshooting).

**Context**: Always include request ID, user ID, operation name, and relevant identifiers.

## 🎯 Decision Framework

**Refactor When**: Code becomes hard to understand, test, or modify. Technical debt accumulates.

**Rewrite When**: Fundamental architecture no longer serves requirements. Refactoring cost exceeds rewrite cost.

**Documentation**: All public APIs, complex algorithms, and architectural decisions must be documented.

## ✅ Validation Checklist

### Code Quality

- [ ] Linting passes with zero warnings
- [ ] Code formatting is consistent
- [ ] Tests cover new functionality
- [ ] Documentation updated
- [ ] Error handling implemented

### Integration

- [ ] Builds successfully
- [ ] Integration tests pass
- [ ] API contracts maintained
- [ ] Performance acceptable
- [ ] Security reviewed

### Deployment

- [ ] Environment compatibility verified
- [ ] Migration scripts tested
- [ ] Rollback plan prepared
- [ ] Monitoring configured
- [ ] Documentation complete

## 🚀 Emergency Protocols

**Build Failures**: Revert immediately if fix not obvious within 15 minutes.

**Test Failures**: Investigate, fix, or disable failing tests with issue tracking.

**Production Issues**: Immediate rollback, then investigate and fix forward.

**Always**: Prioritize system stability over feature delivery.

## Other

Favor `ripgrep` over `grep`, it is 100_000x faster, if istalled the command for ripgrep is `rg`
