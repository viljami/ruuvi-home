# AI Coding Guidelines

## 🧱 Project Structure & Rules

### 0. Git practices

- Do not push code wihtout prompting
- Align git commits to the format: start with a verb in present to describe what happened and why, it's ok to use fix/feat keywords in the beginning if there is no ticket code or milestone clearly related - otherwise use ticket(T12345) or milestone (M1.2)

### 1. Modular Code

- All code must be testable:
  - **Unit tests** = test the piece in isolation
  - **Functional tests** = test how pieces work together
- Avoid mixed concerns in one file.
- Design interfaces/contracts first, implementations second.
- Prefer dependency injection over hardcoded dependencies.

### 2. Short Files

- Maximum **500 lines per file**
- Keep together by association, e.g. files affecting user inder user folder, there might be exeptions like high level functional programming library like functions map but then group them to gether and reuse from the context relevant folders like the user. Another example could be project related files. Under these associative folders ensure to split futher with separation of concerns on that level
- Enforce this via separation:
  - Logic (e.g., JS/TS)
  - Presentation (e.g., HTML/CSS/templates)
  - Config (e.g., JSON/YAML)

### 3. Component First

- Identify small, repeatable components first.
- Compose larger components from smaller, tested ones.
- Build views from these reusable building blocks.
- When encountering repetition, abstract it or suggest scaffolding/config generation.
- Each component should have a single, clear responsibility.
- Avoid circular dependencies—if A needs B and B needs A, extract shared logic to C.

### 4. Three-Stage Workflow

Apply this at all times:

1. **Make it work**
   - Solve the task simply
   - Add basic test
2. **Make it pretty**
   - Refactor for clarity and modularity
   - Add edge case tests
3. **Make it fast**
   - Optimize while keeping all tests green

**Always ask if unsure.**

---

## 🔌 Loose Coupling Principles

- **Configuration over hardcoding**: Use environment variables, config files, or dependency injection
- **Interface over implementation**: Define contracts that can be swapped out
- **Events over direct calls**: Use pub/sub patterns where appropriate
- **Data over logic**: Prefer data-driven solutions that can be changed without code changes

---

## 🪵 Logging Guidelines

Use logging levels with clear intent:

- `debug` – For developers: describe state and control flow
- `info` – For business understanding: describe meaningful events or state changes
- `warn` – For recoverable anomalies
- `error` – For logic-stopping failures

Logs should always include **context** and **action**.

---

## 📖 Documentation Standards

- **README.md** in each major directory explaining its purpose
- **Inline comments** for complex business logic only
- **Function/method signatures** should be self-documenting
- **API documentation** for all public interfaces
- **Decision logs** for architectural choices (why, not what)

---

## 📍 Project Compass

Look for these at the root of the project:

- `VISION.md` – Why the project exists
- `STRATEGY.md` – How the goals will be achieved
- `MILESTONES.md` – What goals exist and how progress is tracked

These may evolve—**re-read as needed**.

Align your actions and code with these reference files.

---

## 🧠 AI-Specific Instructions

- Never assume repetition is needed—**prefer configuration or generation**.
- Avoid scaffolding boilerplate in multiple places—**suggest templates or abstractions**.
- When code feels redundant or structurally noisy, **propose reducing complexity**.
- Use folders, filenames, and structure to reflect component relationships clearly.
- **Think "Lego blocks"**: each piece should be removable and replaceable without unraveling everything else.

---

## 🚫 Anti-Patterns to Avoid

- **God objects/functions**: If it does more than one thing, split it
- **Deep nesting**: Prefer early returns and guard clauses
- **Magic numbers/strings**: Use named constants or configuration
- **Copy-paste code**: Abstract into reusable functions/components
- **Tight coupling**: Components shouldn't know internal details of others
- global variables

---

## 🤝 Human-AI Alignment

If the task is vague or underspecified:

- **Pause before assuming**.
- **Clarify with the human**:
  - Ensure they understand what they're asking for.
  - Confirm you share the same assumptions and context.

This includes:

- Ambiguous instructions
- Missing dependencies
- Mismatched milestones
- Unexpected outputs

Always prefer **synchronization over silence**.

---

## ✅ Final Checklist (Every Time You Join)

Before you generate or propose anything:

- [ ] Have I read this file in full?
- [ ] Do I understand the current milestone?
- [ ] Am I respecting modularity and component boundaries?
- [ ] Is each file under 500 lines?
- [ ] Are logs included and scoped correctly?
- [ ] Do I know if I'm in stage 1, 2, or 3 of the dev cycle?
- [ ] Have I confirmed the human and I share the same task-level context?
- [ ] Am I building "Lego blocks" that can be easily replaced, not "knitted" code that requires unraveling?

---

You are part of a thoughtful, sustainable, and human-centered development process. Thank you for contributing with care and precision.
