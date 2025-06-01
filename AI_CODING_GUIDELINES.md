# AI Coding Guidelines (Generic)

## 🚨 CRITICAL: Code Quality Enforcement

**NEVER use direct tool commands when project has standardized workflows:**

```bash
# ❌ AVOID (examples):
cargo clippy          # If project uses make lint
npm run lint          # If project uses make lint
python -m flake8      # If project uses make lint
```

**ALWAYS use project's standardized targets:**

```bash
# ✅ REQUIRED (adapt to your project):
make lint             # Project's linting workflow
make test             # Project's testing workflow
make dev              # Project's development workflow
```

**Why**: Local vs CI consistency. Direct tool commands may cause failures that only appear in CI/CD.

## 🚨 CRITICAL: Source Code Repository Integrity

**NEVER modify files inside the source repository:**

```bash
# ❌ FORBIDDEN:
cat > "$PROJECT_DIR/scripts/deploy.sh" << EOF
cat > "$PROJECT_DIR/src/generated.py" << EOF
echo "data" > "$PROJECT_DIR/config/generated.conf"
```

**ONLY acceptable repository modifications:**

```bash
# ✅ ALLOWED:
cat > "$PROJECT_DIR/.env" << EOF              # Environment files
cat > "$PROJECT_DIR/.env.local" << EOF        # Local config files
cat > "$PROJECT_DIR/config.local.json" << EOF # Local configuration
```

**Generated files MUST go to system or user locations:**

```bash
# ✅ REQUIRED:
cat > "/etc/systemd/system/service.service" << EOF     # System services
cat > "/opt/app-name/bin/app-script" << EOF            # App-specific scripts (secure)
cat > "/home/$USER/.config/app/config" << EOF          # User config
cat > "/var/lib/app/generated.conf" << EOF             # Application data
cat > "/tmp/generated-script.sh" << EOF               # Temporary files
```

**Security Note**: Never use `/usr/local/bin/` for application scripts - it exposes them globally.
Use `/opt/app-name/bin/` with proper ownership (`app-user:app-user`) for security isolation.

**Why**: Scripts that modify the source repository:

- Create dirty git state and conflicts
- Overwrite source code and cause data loss
- Make the repository unreproducible
- Break CI/CD pipelines
- Violate the principle of immutable source code

**Detection**: Any `cat >`, `echo >`, or redirection to `$PROJECT_DIR/**` (except local config files) is **FORBIDDEN**.

## 🎯 Core Principles

**Explicitness**: Write code that can be understood by AI systems. No hidden dependencies.

**Modularity**: Keep files focused and reasonably sized. Single responsibility per component.

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

- One build target instead of multiple scripts
- Concise documentation over verbose explanations
- Single source of truth over distributed information
- Essential content only - remove nice-to-have details

**Review every addition**: Does this make the system simpler or more complex? If more complex, justify or remove.

## 📋 Essential Workflow

### Before Code Changes

- [ ] Understand current project goals and milestones
- [ ] Define task scope explicitly
- [ ] Plan rollback strategy

## 🎨 Automatic Code Formatting

**MANDATORY**: All code must be automatically formatted before commit.

**One-time setup** (adapt to your project):

```bash
# Examples - adapt to your project's setup script:
./scripts/setup-dev.sh
./setup.py install --dev
npm run setup
```

**Pre-commit hooks automatically**:

- Format all code on every commit
- Run linting checks
- Validate file structure
- Sort imports
- Fix trailing whitespace

**Manual formatting** (adapt to your project):

```bash
# Examples - use your project's commands:
make fmt                    # Project-wide formatting
npm run format             # JavaScript/TypeScript
black .                    # Python
cargo fmt                  # Rust
go fmt ./...               # Go

# Or run pre-commit manually:
pre-commit run --all-files
```

**NEVER skip formatting**: Pre-commit hooks prevent commits with formatting issues. This ensures zero formatting conflicts in CI.

### Language-Specific Validation

Adapt these examples to your project's structure and tools:

```bash
# Backend (adapt language and tools):
make lint && make test

# Frontend (adapt framework):
npm run lint && npm test

# Scripts/Tools (adapt language):
flake8 . && pytest
```

### After Every Code Edit

- [ ] **Syntax**: Language-specific check (compile, type check, etc.)
- [ ] **Linting**: Zero warnings using project's lint target
- [ ] **Tests**: Relevant test suites pass
- [ ] **Build**: Successful compilation/build

## 🧪 Testing Strategy

**Unit Tests**: Isolated component testing. Fast feedback.

**Integration Tests**: Component interaction testing. Realistic scenarios.

**End-to-End Tests**: Full system testing. User journey validation.

**Error Handling**: Application code must handle errors properly (avoid panic/crash patterns). Test code can fail fast for debugging.

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

**IDE Integration**: Configure tools to use project standards (project lint targets, not direct tool commands).

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

## 🛠️ Tool Preferences

When available, prefer faster modern alternatives:

- `ripgrep` (`rg`) over `grep` - significantly faster
- `fd` over `find` - faster file searching
- `bat` over `cat` - syntax highlighting
- `exa` over `ls` - better formatting

Adapt tool preferences based on your team's standards and available tooling.
