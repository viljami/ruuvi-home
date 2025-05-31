#!/bin/bash
# Lint checking script for Ruuvi Home CI pipeline
# Ensures strict error handling in application code while allowing expect/unwrap in tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to backend directory
cd "$(dirname "$0")/../backend"

echo -e "${YELLOW}🔍 Running Rust lint checks...${NC}"

# Function to check specific lints
check_lints() {
    local lint_type="$1"
    local description="$2"
    
    echo -e "\n${YELLOW}Checking $description...${NC}"
    
    # Run clippy with specific configuration
    if cargo clippy --workspace --all-targets --all-features -- \
        -D clippy::expect_used \
        -D clippy::unwrap_used \
        -D clippy::panic \
        -D clippy::unimplemented \
        -D clippy::todo \
        -A clippy::expect_used_in_tests \
        -A clippy::unwrap_used_in_tests \
        2>/dev/null; then
        echo -e "${GREEN}✓ $description passed${NC}"
        return 0
    else
        echo -e "${RED}✗ $description failed${NC}"
        return 1
    fi
}

# Function to run clippy on specific code patterns
check_application_code() {
    echo -e "\n${YELLOW}Checking application code (non-test) for forbidden patterns...${NC}"
    
    # Check for expect/unwrap in non-test files
    local violations=0
    
    # Find all Rust files except test files
    while IFS= read -r -d '' file; do
        # Skip test files and test modules
        if [[ "$file" =~ /tests/ ]] || [[ "$file" =~ test\.rs$ ]] || [[ "$file" =~ _test\.rs$ ]]; then
            continue
        fi
        
        # Check for expect() calls outside of test modules
        if grep -n "\.expect(" "$file" | grep -v "#\[cfg(test)\]" | grep -v "// test:" | grep -v "// Test:" >/dev/null 2>&1; then
            echo -e "${RED}Found .expect() in application code: $file${NC}"
            grep -n "\.expect(" "$file" | grep -v "#\[cfg(test)\]" | head -3
            violations=$((violations + 1))
        fi
        
        # Check for unwrap() calls outside of test modules
        if grep -n "\.unwrap(" "$file" | grep -v "#\[cfg(test)\]" | grep -v "// test:" | grep -v "// Test:" >/dev/null 2>&1; then
            echo -e "${RED}Found .unwrap() in application code: $file${NC}"
            grep -n "\.unwrap(" "$file" | grep -v "#\[cfg(test)\]" | head -3
            violations=$((violations + 1))
        fi
        
    done < <(find . -name "*.rs" -type f -print0)
    
    if [ $violations -eq 0 ]; then
        echo -e "${GREEN}✓ No forbidden patterns found in application code${NC}"
        return 0
    else
        echo -e "${RED}✗ Found $violations files with forbidden patterns${NC}"
        return 1
    fi
}

# Function to run standard clippy checks
run_standard_clippy() {
    echo -e "\n${YELLOW}Running standard clippy checks...${NC}"
    
    if cargo clippy --workspace --all-targets --all-features -- -D warnings; then
        echo -e "${GREEN}✓ Standard clippy checks passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Standard clippy checks failed${NC}"
        return 1
    fi
}

# Function to check test code permissions
check_test_code() {
    echo -e "\n${YELLOW}Verifying test code can use expect/unwrap...${NC}"
    
    # Run clippy on test code specifically, allowing expect/unwrap
    if cargo clippy --workspace --tests --all-features -- \
        -A clippy::expect_used \
        -A clippy::unwrap_used \
        -D warnings; then
        echo -e "${GREEN}✓ Test code lint checks passed${NC}"
        return 0
    else
        echo -e "${RED}✗ Test code lint checks failed${NC}"
        return 1
    fi
}

# Function to run cargo fmt check
check_formatting() {
    echo -e "\n${YELLOW}Checking code formatting...${NC}"
    
    if cargo fmt --check; then
        echo -e "${GREEN}✓ Code formatting is correct${NC}"
        return 0
    else
        echo -e "${RED}✗ Code formatting issues found${NC}"
        echo -e "${YELLOW}Run 'cargo fmt' to fix formatting${NC}"
        return 1
    fi
}

# Main execution
main() {
    local exit_code=0
    
    echo -e "${YELLOW}🏠 Ruuvi Home Lint Checker${NC}"
    echo -e "${YELLOW}=============================${NC}"
    
    # Check if we're in the right directory
    if [ ! -f "Cargo.toml" ]; then
        echo -e "${RED}Error: Not in Rust project directory${NC}"
        exit 1
    fi
    
    # Run all checks
    check_formatting || exit_code=1
    run_standard_clippy || exit_code=1
    check_application_code || exit_code=1
    check_test_code || exit_code=1
    
    echo -e "\n${YELLOW}=============================${NC}"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}🎉 All lint checks passed!${NC}"
        echo -e "${GREEN}✓ Application code follows strict error handling${NC}"
        echo -e "${GREEN}✓ Test code can use expect/unwrap as needed${NC}"
        echo -e "${GREEN}✓ Code formatting is consistent${NC}"
    else
        echo -e "${RED}❌ Some lint checks failed${NC}"
        echo -e "${YELLOW}Please fix the issues above before merging${NC}"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"