# AI Workflow Quick Reference

## 🚀 Starting New AI Conversations

### Essential Context Files

Always include these files when starting a new AI chat:

1. **AI_CODING_GUIDELINES.md** - Core development principles
2. **MILESTONES.md** - Current project goals and progress
3. **README.md** - Project overview and setup

### Quick Start Template

Copy and paste this when starting new AI threads:

```
Please read these project files first:
- AI_CODING_GUIDELINES.md
- MILESTONES.md
- README.md

I'm working on [describe your task]. Please follow our modular "Lego blocks" approach and the three-stage workflow (make it work → make it pretty → make it fast).
```

## 🎯 Best Practices

### Before Each Task

- [ ] AI has read current guidelines
- [ ] Current milestone is clear
- [ ] Task scope is defined
- [ ] Component boundaries are identified

### During Development

- [ ] Following 500-line file limit
- [ ] Building testable components
- [ ] Using proper logging levels
- [ ] Maintaining loose coupling

### After Implementation

- [ ] Tests are written and passing
- [ ] Code is refactored for clarity
- [ ] Documentation is updated
- [ ] Performance optimization if needed

## 🔄 Workflow Integration

### Zed Editor Setup

1. Keep `AI_CODING_GUIDELINES.md` pinned in your project panel
2. Reference it frequently during development
3. Use project search to find existing components before creating new ones

### File Organization

- Each component in its own directory
- Tests alongside implementation files
- Configuration separate from logic
- Clear naming reflecting component relationships

## 📋 Common AI Prompts

### Code Review

```
Please review this code against our AI_CODING_GUIDELINES.md. Focus on:
- Modularity and testability
- File size limits
- Component boundaries
- Logging practices
```

### Refactoring

```
This code needs refactoring following our "Lego blocks" principle. Please suggest how to break it into smaller, reusable components while maintaining the same functionality.
```

### New Feature

```
I need to implement [feature]. Please design this as modular components following our guidelines, starting with the interface/contract design.
```

## 🎯 Success Metrics

Your AI collaboration is successful when:

- Components can be easily replaced without breaking others
- Tests provide confidence in changes and run smoothly and successfully
- Code reads like well-organized documentation and is self documenting as in variable and function names make it easy to understand the purpose of each part without having to write lengthy comments
- New team members can understand and contribute quickly
- Technical debt decreases over time

Remember: **Synchronization over silence** - always clarify before assuming!
