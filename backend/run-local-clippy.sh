#!/bin/bash
# Local clippy runner to match CI pipeline strictness
# Run this script to catch issues before pushing to CI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure we're in the backend directory
if [ ! -f "Cargo.toml" ]; then
    echo -e "${RED}Error: Must run from backend directory${NC}"
    exit 1
fi

echo -e "${YELLOW}🔍 Running local clippy checks with CI-level strictness...${NC}"

# Check if nightly is available, use it if possible (matches CI)
if rustup toolchain list | grep -q nightly; then
    echo -e "${YELLOW}Using nightly toolchain (matches CI)${NC}"
    CARGO_CMD="cargo +nightly"
else
    echo -e "${YELLOW}Using stable toolchain (CI uses nightly)${NC}"
    CARGO_CMD="cargo"
fi

# Function to run a check and track results
run_check() {
    local check_name="$1"
    local check_cmd="$2"
    
    echo -e "\n${YELLOW}Running $check_name...${NC}"
    
    if eval "$check_cmd"; then
        echo -e "${GREEN}✓ $check_name passed${NC}"
        return 0
    else
        echo -e "${RED}✗ $check_name failed${NC}"
        return 1
    fi
}

# Track overall success
overall_success=0

# 1. Format check (exactly like CI)
run_check "Code formatting" "$CARGO_CMD fmt --check" || overall_success=1

# 2. Standard clippy with warnings as errors (exactly like CI)
run_check "Standard clippy (warnings as errors)" \
    "$CARGO_CMD clippy --workspace --all-targets --all-features -- -D warnings" || overall_success=1

# 3. Application code checks (no lib or bin targets, no tests)
run_check "Application code lint checks (strict error handling)" \
    "$CARGO_CMD clippy --workspace --lib --bins --all-features -- \
        -D warnings \
        -D clippy::expect_used \
        -D clippy::unwrap_used \
        -D clippy::panic \
        -D clippy::unimplemented \
        -D clippy::todo" || overall_success=1

# 4. Test-specific checks (allowing expect/unwrap in tests)
run_check "Test code lint checks" \
    "$CARGO_CMD clippy --workspace --tests --all-features -- \
        -A clippy::expect_used \
        -A clippy::unwrap_used \
        -A clippy::panic \
        -D warnings" || overall_success=1

# 5. Additional pedantic checks (from workspace lints)
run_check "Pedantic lint checks" \
    "$CARGO_CMD clippy --workspace --all-targets --all-features -- \
        -D clippy::pedantic \
        -A clippy::must_use_candidate \
        -A clippy::missing_errors_doc \
        -A clippy::missing_panics_doc \
        -A clippy::module_name_repetitions" || overall_success=1

echo -e "\n${YELLOW}=============================${NC}"

if [ $overall_success -eq 0 ]; then
    echo -e "${GREEN}🎉 All local clippy checks passed!${NC}"
    echo -e "${GREEN}Your code should pass CI pipeline checks.${NC}"
else
    echo -e "${RED}❌ Some clippy checks failed${NC}"
    echo -e "${YELLOW}Fix these issues before pushing to avoid CI failures.${NC}"
    echo -e "${YELLOW}💡 Tip: Run 'cargo fmt' to fix formatting issues${NC}"
fi

exit $overall_success