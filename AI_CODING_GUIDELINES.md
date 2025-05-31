# AI Coding Guidelines

## 🎯 Core Directive
Write code that can be understood, modified, and extended by AI systems. Prioritize explicitness, modularity, and reversibility in all decisions.

## 📋 Pre-Code Checklist
Before writing any code, verify:
- [ ] Current milestone understood from VISION.md, STRATEGY.md, MILESTONES.md
- [ ] Task scope is explicitly defined
- [ ] Dependencies identified
- [ ] Test strategy planned
- [ ] Rollback plan exists

## 🧱 Structural Imperatives

### Rule: Maximum 500 Lines Per File
**Rationale**: AI context windows and human cognitive load
**Action**: Split files before reaching limit
**Exception**: Generated code with clear markers

### Rule: Single Responsibility Per Component
**Test**: Can you describe the component's purpose in one sentence?
**Action**: If not, decompose into smaller components
**Pattern**: Use composition over inheritance

### Rule: Explicit Dependencies
**Never**: Import global state or hidden dependencies
**Always**: Use dependency injection or explicit imports
**Pattern**: Constructor injection, parameter passing, or configuration objects

## 🔄 Pragmatic Programmer Principles for AI

### DRY (Don't Repeat Yourself)
**AI Application**: Generate templates and abstractions instead of copy-paste
**Implementation**: Create generators, config-driven code, or shared libraries
**Detection**: If writing similar code twice, abstract immediately

### Orthogonality
**Definition**: Components should be independent and replaceable
**Test**: Can you change one component without affecting others?
**Implementation**: Use interfaces, event systems, and clear boundaries

### Reversibility
**Principle**: All decisions should be easily undoable
**Implementation**: 
- Feature flags for new functionality
- Database migrations with rollback scripts
- Configuration over hardcoded values
- Version all APIs

### Tracer Bullets
**Application**: Build end-to-end skeleton first, then flesh out
**Pattern**: API endpoint → database → UI in minimal form
**Benefit**: Early feedback and integration testing

### Power of Plain Text
**Rule**: Use human and AI readable formats
**Preferred**: JSON, YAML, Markdown over binary formats
**Storage**: Configuration, logs, and data exchange in plain text
**Benefit**: Version control, debugging, and AI parsing

### Ubiquitous Automation
**Mandate**: Automate repetitive tasks immediately
**Targets**: Testing, deployment, code formatting, documentation generation
**Tools**: Scripts, CI/CD, code generators, linters

## 🏗️ Three-Stage Development Cycle

### Stage 1: Make It Work
**Goal**: Solve the core problem
**Quality**: Minimal viable implementation
**Tests**: Basic happy path test
**Documentation**: Implementation notes only

### Stage 2: Make It Right
**Goal**: Clean, maintainable code
**Quality**: Well-structured, documented
**Tests**: Edge cases and error conditions
**Documentation**: API docs and usage examples

### Stage 3: Make It Fast
**Goal**: Optimize performance
**Quality**: Measurable improvements
**Tests**: Performance regression tests
**Documentation**: Performance characteristics

## 🔌 Coupling and Cohesion Rules

### Minimize Coupling
**Data Coupling**: Pass only required data
**Stamp Coupling**: Use specific data structures, not generic objects
**Control Coupling**: Avoid passing control flags
**Content Coupling**: Never access internal data directly

### Maximize Cohesion
**Functional**: All elements contribute to single task
**Sequential**: Output of one element feeds next
**Communicational**: Elements operate on same data
**Temporal**: Elements executed at same time

## 🧪 Testing Strategy

### Unit Tests (Isolation)
**Scope**: Single function/method
**Mock**: All dependencies
**Coverage**: All code paths
**Speed**: Sub-second execution

### Integration Tests (Interaction)
**Scope**: Component boundaries
**Real**: Actual dependencies where feasible
**Coverage**: Interface contracts
**Speed**: Seconds to minutes

### Functional Tests (End-to-end)
**Scope**: User workflows
**Environment**: Production-like
**Coverage**: Critical business paths
**Speed**: Minutes acceptable

## 🔍 Code Validation Pipeline

### Mandatory Pre-Commit Validation
**Principle**: All AI-generated code MUST pass validation before any commit or submission
**Scope**: Application source code, tests, and configuration files only
**Excludes**: Build artifacts, dependencies, node_modules, target directories, __pycache__, binaries
**Rationale**: Prevents syntax errors, orphaned tags, misplaced brackets, and duplicate functions

### Language-Specific Validation Commands

#### Rust Projects
```bash
# Syntax and compilation check
cargo check --workspace --all-targets --all-features

# Linting with strict rules
cargo clippy --workspace --all-targets --all-features -- -D warnings

# Code formatting
cargo fmt --check

# Test execution
cargo test --workspace

# Full validation pipeline
cargo check && cargo clippy -- -D warnings && cargo fmt --check && cargo test
```

#### TypeScript/React Projects
```bash
# TypeScript compilation check
npx tsc --noEmit

# ESLint validation
npx eslint src --ext .js,.jsx,.ts,.tsx --max-warnings 0

# Prettier formatting check
npx prettier --check "src/**/*.{js,jsx,ts,tsx,json,css,scss,md}"

# Test execution
npm test -- --watchAll=false --coverage --testTimeout=30000

# Full validation pipeline
npx tsc --noEmit && npx eslint src --ext .js,.jsx,.ts,.tsx --max-warnings 0 && npx prettier --check "src/**/*.{js,jsx,ts,tsx,json,css,scss,md}" && npm test -- --watchAll=false
```

#### Python Projects
```bash
# Syntax validation
python -m py_compile *.py

# Import validation (dry run)
python -c "import sys; [__import__(f[:-3]) for f in sys.argv[1:]]" *.py

# Linting with flake8
flake8 --max-line-length=88 --extend-ignore=E203,W503 .

# Code formatting check
black --check --diff .

# Import sorting check
isort --check-only --diff .

# Type checking (if mypy available)
mypy . || echo "mypy not available, skipping type check"

# Test execution
pytest -v --cov=. --cov-report=term

# Full validation pipeline
python -m py_compile *.py && flake8 . && black --check . && isort --check-only . && pytest -v
```

#### Shell Scripts
```bash
# Syntax validation
bash -n script.sh

# Shellcheck linting
shellcheck -e SC1091 *.sh

# Execute with dry-run flag (if supported)
bash -x script.sh --dry-run 2>/dev/null || echo "No dry-run support"

# Full validation pipeline
bash -n *.sh && shellcheck *.sh
```

#### YAML Files
```bash
# Syntax validation using Python
python -c "import yaml; yaml.safe_load(open('file.yaml'))"

# Or using yq if available
yq eval . file.yaml > /dev/null

# Docker Compose validation
docker-compose -f docker-compose.yaml config > /dev/null
```

#### JSON Files
```bash
# Syntax validation
python -m json.tool file.json > /dev/null

# Or using jq if available
jq empty file.json
```

### Universal Validation Script
Use `scripts/ai-validate.sh` for project-wide validation of source code only:

```bash
# Comprehensive validation excluding build artifacts and dependencies
./scripts/ai-validate.sh

# Language-specific validation
./scripts/ai-validate.sh --rust       # Rust source code only
./scripts/ai-validate.sh --typescript # TypeScript source code only  
./scripts/ai-validate.sh --python     # Python source code only
./scripts/ai-validate.sh --shell      # Shell scripts only
```

**Excluded from validation:**
- `node_modules/`, `target/`, `build/`, `dist/`, `__pycache__/`
- Package lock files, build artifacts, compiled binaries
- Third-party dependencies and vendor code
- Generated files and temporary directories
- IDE and editor configuration files

### AI Code Generation Rules

#### Before Any Code Edit
1. **Syntax Validation**: Run appropriate validation command
2. **Compilation Check**: Ensure code compiles/transpiles
3. **Linting**: Fix all linting issues
4. **Test Execution**: Run relevant tests

#### After Any Code Edit
1. **Re-validate**: Run validation pipeline again
2. **Test Coverage**: Ensure tests still pass
3. **Integration Check**: Verify with dependent components
4. **Performance Check**: Ensure no regression

#### Error Detection Patterns
Watch for these common AI output issues:
- **Orphaned XML/HTML tags**: `<div>` without `</div>`
- **Mismatched brackets**: `{`, `[`, `(` without proper closing
- **Duplicate functions**: Same function defined twice
- **Import conflicts**: Circular or missing imports
- **Type mismatches**: Incorrect variable types
- **Indentation errors**: Mixed tabs/spaces

#### Recovery Strategies
When validation fails:
1. **Isolate the error**: Run validation on smallest possible scope
2. **Check syntax first**: Use language-specific syntax validators
3. **Verify structure**: Ensure proper nesting and closing
4. **Test incrementally**: Add code in small chunks
5. **Rollback if needed**: Return to last working state

### IDE Integration Safeguards
To prevent IDE integration bugs:
- **Auto-save validation**: Run syntax check on file save
- **Pre-commit hooks**: Mandatory validation before git commit
- **CI/CD integration**: Fail builds on validation errors
- **Real-time feedback**: Show validation status in development

### AI Validation Enforcement

#### Mandatory Validation Workflow
**Rule**: AI MUST validate ALL code changes before submission
**Implementation**: Use `diagnostics` tool and `scripts/ai-validate.sh` after every edit
**Scope**: Application source code, tests, and configuration files only
**Exclusions**: Build artifacts, dependencies, generated files, binaries

#### Validation Command Templates
For each language, AI must use these exact commands on source code only:

**Rust Validation Pattern:**
```bash
cd backend && cargo check --workspace && cargo clippy -- -D warnings && cargo fmt --check
```

**TypeScript Validation Pattern:**
```bash
cd frontend && npx tsc --noEmit && npx eslint src --ext .ts,.tsx --max-warnings 0
```

**Python Validation Pattern (Source Files Only):**
```bash
./scripts/ai-validate.sh --python  # Excludes __pycache__, venv, build dirs
```

**Shell Validation Pattern (Application Scripts Only):**
```bash
./scripts/ai-validate.sh --shell   # Excludes build and dependency dirs
```

**Comprehensive Validation:**
```bash
./scripts/ai-validate.sh           # All source code, excludes artifacts
```

#### AI Validation Checklist
Before any code submission, AI must:
- [ ] Run syntax validation for target language (source code only)
- [ ] Execute linting tools with zero warnings (application code only)
- [ ] Verify code formatting compliance (exclude generated files)
- [ ] Run relevant test suites (application tests only)
- [ ] Check for compilation/build success (source compilation only)
- [ ] Use `diagnostics` tool to verify no errors
- [ ] Confirm no orphaned tags or brackets (in source files)
- [ ] Validate imports and dependencies (application code only)
- [ ] Execute `./scripts/ai-validate.sh` and ensure exit code 0

#### Failure Response Protocol
If validation fails:
1. **STOP**: Do not proceed with additional changes
2. **IDENTIFY**: Isolate the specific error
3. **FIX**: Address only the validation error
4. **REVALIDATE**: Run validation again
5. **REPORT**: Inform user if unable to resolve

## 📊 Logging and Observability

### Log Levels with Context
```
DEBUG: Variable states, control flow, algorithm steps
INFO: Business events, state transitions, user actions
WARN: Recoverable errors, degraded performance, retries
ERROR: Unrecoverable failures, exceptions, data corruption
```

### Required Context
- **Timestamp**: ISO 8601 format
- **Component**: Module/service identifier
- **Action**: What operation was attempted
- **Result**: Success/failure with details
- **Duration**: For performance monitoring

## 🚫 Anti-Patterns for AI

### Avoid These Patterns
- **God Objects**: >500 lines or >10 responsibilities
- **Deep Nesting**: >3 levels of indentation
- **Magic Values**: Unexplained constants or strings
- **Global State**: Shared mutable variables
- **Circular Dependencies**: A depends on B depends on A
- **Tight Coupling**: Changes ripple across multiple files

### Detection Signals
- Difficulty writing tests
- Need to change multiple files for single feature
- Cannot explain component purpose simply
- Copy-pasting code blocks
- "Just make it work" without plan for Stage 2

## 🎛️ Configuration Management

### Environment Variables
**Pattern**: `APP_COMPONENT_SETTING`
**Types**: String, number, boolean, JSON
**Documentation**: Default values and descriptions
**Validation**: At startup with clear error messages

### Configuration Files
**Format**: YAML or JSON for complex structures
**Location**: Single config directory
**Versioning**: Include schema version
**Environment**: Override via environment-specific files

## 🔄 Error Handling Patterns

### Fail Fast Principle
**Implementation**: Validate inputs immediately
**Pattern**: Guard clauses at function start
**Benefit**: Easier debugging and cleaner code

### Error Propagation
**Local Errors**: Handle at component boundary
**System Errors**: Propagate with context
**User Errors**: Transform to user-friendly messages
**Logging**: All errors logged with full context

## 📐 Estimation and Planning

### Story Point Estimation
**1 Point**: <2 hours, well-understood task
**2 Points**: Half day, minor complexity
**3 Points**: 1 day, some unknowns
**5 Points**: 2-3 days, significant complexity
**8+ Points**: Break down further

### Task Breakdown Rules
**Maximum**: 8 story points per task
**Dependencies**: Explicitly mapped
**Assumptions**: Documented and validated
**Risks**: Identified with mitigation plans

## 🔧 Tool and Technology Choices

### Selection Criteria
1. **Community**: Active development and support
2. **Documentation**: Comprehensive and current
3. **Integration**: Works with existing stack
4. **Performance**: Meets requirements
5. **Learning Curve**: Team can adopt efficiently

### Technology Debt
**Definition**: Suboptimal technology choices requiring future rework
**Tracking**: Document in technical debt register
**Payment**: Allocate 20% of development time to debt reduction

## 🎯 Decision Making Framework

### When to Refactor
- Code violates any structural imperatives
- Tests are difficult to write or maintain
- Same logic appears in 3+ places
- Component has grown beyond single responsibility

### When to Rewrite
- Technology stack fundamentally incompatible
- Performance requirements cannot be met
- Security vulnerabilities in core architecture
- Maintenance cost exceeds rewrite cost

### Documentation Requirements
**Decisions**: Why not just what
**Trade-offs**: What was considered and rejected
**Assumptions**: What we believe to be true
**Risks**: What could go wrong

## 🚀 Deployment and Operations

### Release Principles
**Blue-Green**: Zero-downtime deployments
**Feature Flags**: Gradual rollouts
**Monitoring**: Health checks and metrics
**Rollback**: Automated if key metrics degrade

### Production Readiness
- [ ] All tests passing
- [ ] Performance benchmarks met
- [ ] Security scan completed
- [ ] Documentation updated
- [ ] Rollback plan tested

## 🤖 AI-Specific Optimizations

### Code Organization for AI Comprehension
**File Naming**: Descriptive, hierarchical
**Function Naming**: Verb-noun pattern
**Variable Naming**: No abbreviations
**Comments**: Explain why, not what

### Context Preservation
**README per directory**: Purpose and contents
**Change logs**: What changed and why
**Architecture docs**: System overview and interactions
**API documentation**: All public interfaces

### AI Collaboration Patterns
**Explicit Interfaces**: Clear input/output contracts
**Type Annotations**: Where language supports
**Error Messages**: Actionable and specific
**Test Names**: Describe expected behavior

## ✅ Mandatory AI Validation Checklist

### Before Writing Any Code
- [ ] Read VISION.md, STRATEGY.md, MILESTONES.md for current context
- [ ] Understand task scope and requirements explicitly
- [ ] Identify target language and validation tools required
- [ ] Confirm development stage (Make it Work/Right/Fast)
- [ ] Plan test strategy and rollback approach

### During Code Generation
- [ ] Follow single responsibility principle
- [ ] Keep files under 500 lines
- [ ] Use explicit dependencies and interfaces
- [ ] Apply appropriate error handling patterns
- [ ] Include necessary logging with context
- [ ] Write code that is AI-readable and modular

### After Every Code Edit (MANDATORY)
- [ ] **Syntax Validation**: Run language-specific syntax check
  - Rust: `cargo check --workspace --all-targets --all-features`
  - TypeScript: `npx tsc --noEmit`
  - Python: `python -m py_compile *.py`
  - Shell: `bash -n script.sh`
- [ ] **Linting**: Execute linting tools with zero warnings
  - Rust: `cargo clippy -- -D warnings`
  - TypeScript: `npx eslint src --ext .ts,.tsx --max-warnings 0`
  - Python: `flake8 . && black --check .`
  - Shell: `shellcheck script.sh`
- [ ] **Formatting**: Verify code formatting compliance
- [ ] **Compilation**: Ensure successful build/compilation
- [ ] **Testing**: Run relevant test suites
- [ ] **Diagnostics**: Use `diagnostics` tool to verify no errors

### Code Quality Verification
- [ ] No orphaned XML/HTML tags or brackets
- [ ] No duplicate functions or circular dependencies
- [ ] All imports and dependencies resolved
- [ ] No magic numbers or hardcoded values
- [ ] Error handling follows fail-fast principle
- [ ] Logging includes proper context and levels

### Integration Verification
- [ ] Component boundaries respected
- [ ] Interfaces remain stable
- [ ] No breaking changes to existing APIs
- [ ] Configuration externalized properly
- [ ] Performance requirements maintained

### Documentation and Traceability
- [ ] Code changes align with milestone goals
- [ ] Decision rationale documented where needed
- [ ] Test coverage maintained or improved
- [ ] API documentation updated if needed
- [ ] Commit message follows project format

### Emergency Protocols
If validation fails:
- [ ] STOP all further code generation
- [ ] Isolate and identify specific error
- [ ] Fix only the validation error
- [ ] Re-run complete validation pipeline
- [ ] Escalate to human if unable to resolve

### Final Submission Checklist
- [ ] All validation steps completed successfully
- [ ] Tests pass with no regressions
- [ ] Code follows all structural imperatives
- [ ] No anti-patterns present
- [ ] Ready for human review and potential commit

---

This document serves as the definitive guide for AI-assisted development. **ALL CODE MUST PASS VALIDATION** before submission. No exceptions.