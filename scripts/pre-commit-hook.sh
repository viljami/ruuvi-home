#!/bin/bash
# Pre-commit hook for Ruuvi Home project
# Runs basic lint checks before allowing commits

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the repository root
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

echo -e "${YELLOW}🔍 Running pre-commit checks...${NC}"

# Function to check staged Rust files
check_staged_rust_files() {
    local staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.rs$' || true)
    
    if [ -z "$staged_files" ]; then
        echo -e "${GREEN}✓ No Rust files staged${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Checking staged Rust files...${NC}"
    
    # Change to backend directory
    cd backend
    
    # Quick format check
    if ! cargo fmt --check >/dev/null 2>&1; then
        echo -e "${RED}✗ Code formatting issues found${NC}"
        echo -e "${YELLOW}Run 'cargo fmt' to fix formatting${NC}"
        return 1
    fi
    
    # Quick clippy check on workspace
    if ! cargo clippy --workspace --all-targets -- \
        -D clippy::expect_used \
        -D clippy::unwrap_used \
        -D clippy::panic \
        -A clippy::expect_used_in_tests \
        -A clippy::unwrap_used_in_tests \
        >/dev/null 2>&1; then
        echo -e "${RED}✗ Clippy found issues${NC}"
        echo -e "${YELLOW}Run './scripts/check-lints.sh' for detailed output${NC}"
        return 1
    fi
    
    # Check for forbidden patterns in staged files
    local violations=0
    for file in $staged_files; do
        # Skip test files
        if [[ "$file" =~ /tests/ ]] || [[ "$file" =~ test\.rs$ ]] || [[ "$file" =~ _test\.rs$ ]]; then
            continue
        fi
        
        # Check for expect/unwrap in non-test code
        if git show ":$file" | grep -n "\.expect(" | grep -v "#\[cfg(test)\]" >/dev/null 2>&1; then
            echo -e "${RED}Found .expect() in staged file: $file${NC}"
            violations=$((violations + 1))
        fi
        
        if git show ":$file" | grep -n "\.unwrap(" | grep -v "#\[cfg(test)\]" >/dev/null 2>&1; then
            echo -e "${RED}Found .unwrap() in staged file: $file${NC}"
            violations=$((violations + 1))
        fi
    done
    
    if [ $violations -gt 0 ]; then
        echo -e "${RED}✗ Found forbidden patterns in staged files${NC}"
        echo -e "${YELLOW}Use proper error handling instead of expect/unwrap in application code${NC}"
        return 1
    fi
    
    cd "$REPO_ROOT"
    echo -e "${GREEN}✓ Rust files passed pre-commit checks${NC}"
    return 0
}

# Function to check commit message format
check_commit_message() {
    local commit_msg_file="$1"
    
    if [ -f "$commit_msg_file" ]; then
        local commit_msg=$(head -n1 "$commit_msg_file")
        
        # Check for conventional commit format or ticket/milestone format
        if [[ "$commit_msg" =~ ^(feat|fix|docs|style|refactor|test|chore|T[0-9]+|M[0-9]+\.[0-9]+): ]] || \
           [[ "$commit_msg" =~ ^[a-z]+ ]]; then
            echo -e "${GREEN}✓ Commit message format looks good${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Commit message format could be improved${NC}"
            echo -e "${YELLOW}Consider using: feat/fix/docs/etc: description or T12345: description${NC}"
            # Don't fail on commit message format, just warn
            return 0
        fi
    fi
}

# Main execution
main() {
    local exit_code=0
    
    # Run checks
    check_staged_rust_files || exit_code=1
    
    # Check commit message if available (for commit-msg hook)
    if [ -n "${1:-}" ]; then
        check_commit_message "$1"
    fi
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}🎉 Pre-commit checks passed!${NC}"
    else
        echo -e "${RED}❌ Pre-commit checks failed${NC}"
        echo -e "${YELLOW}Fix the issues above before committing${NC}"
        echo -e "${YELLOW}Or run './scripts/check-lints.sh' for more detailed analysis${NC}"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"