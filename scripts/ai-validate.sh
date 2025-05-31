#!/bin/bash
# AI Code Validation Script - Application Code Only
# Validates only source code, tests, and configuration - excludes dependencies and build artifacts
# Exit code 0 = all validations passed, non-zero = validation failed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Global validation status
VALIDATION_FAILED=0
TOTAL_CHECKS=0
PASSED_CHECKS=0

# Function to log validation step
log_step() {
    echo -e "${BLUE}🔍 $1${NC}"
}

# Function to log success
log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

# Function to log failure
log_failure() {
    echo -e "${RED}❌ $1${NC}"
    VALIDATION_FAILED=1
}

# Function to run command with validation
validate_command() {
    local description="$1"
    local command="$2"
    local directory="${3:-$PWD}"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_step "$description"
    
    if cd "$directory" && eval "$command" >/dev/null 2>&1; then
        log_success "$description passed"
        cd "$PROJECT_ROOT"
        return 0
    else
        log_failure "$description failed"
        cd "$PROJECT_ROOT"
        return 1
    fi
}

# Function to find application source files only
find_rust_files() {
    find "$PROJECT_ROOT" -name "*.rs" -type f \
        -not -path "*/target/*" \
        -not -path "*/.cargo/*" \
        -not -path "*/build/*" \
        -not -path "*/deps/*"
}

find_typescript_files() {
    find "$PROJECT_ROOT" -name "*.ts" -o -name "*.tsx" -type f \
        -not -path "*/node_modules/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        -not -path "*/out/*" \
        -not -path "*/.next/*" \
        -not -path "*/coverage/*" \
        -not -path "*/.cache/*"
}

find_javascript_files() {
    find "$PROJECT_ROOT" -name "*.js" -o -name "*.jsx" -type f \
        -not -path "*/node_modules/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        -not -path "*/out/*" \
        -not -path "*/.next/*" \
        -not -path "*/coverage/*" \
        -not -path "*/.cache/*" \
        -not -name "*.config.js" \
        -not -name "*.min.js"
}

find_python_files() {
    find "$PROJECT_ROOT" -name "*.py" -type f \
        -not -path "*/__pycache__/*" \
        -not -path "*/venv/*" \
        -not -path "*/.venv/*" \
        -not -path "*/env/*" \
        -not -path "*/.env/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        -not -path "*/.pytest_cache/*" \
        -not -path "*/.coverage/*" \
        -not -path "*/.tox/*"
}

find_shell_files() {
    find "$PROJECT_ROOT" -name "*.sh" -type f \
        -not -path "*/node_modules/*" \
        -not -path "*/target/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        -not -path "*/.git/*"
}

find_yaml_files() {
    find "$PROJECT_ROOT" \( -name "*.yaml" -o -name "*.yml" \) -type f \
        -not -path "*/node_modules/*" \
        -not -path "*/target/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        -not -path "*/.git/*"
}

find_json_files() {
    find "$PROJECT_ROOT" -name "*.json" -type f \
        -not -path "*/node_modules/*" \
        -not -path "*/target/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        -not -path "*/coverage/*" \
        -not -path "*/.git/*" \
        -not -name "package-lock.json" \
        -not -name "*.lock.json"
}

# Function to validate Rust code
validate_rust() {
    if [ ! -f "$PROJECT_ROOT/backend/Cargo.toml" ]; then
        echo -e "${YELLOW}⚠️  No Rust project found, skipping Rust validation${NC}"
        return 0
    fi
    
    local rust_files
    rust_files=$(find_rust_files | head -1)
    if [ -z "$rust_files" ]; then
        echo -e "${YELLOW}⚠️  No Rust source files found, skipping Rust validation${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}=== Rust Validation ===${NC}"
    
    validate_command "Rust syntax check" "cargo check --workspace --all-targets --all-features" "$PROJECT_ROOT/backend"
    validate_command "Rust linting" "cargo clippy --workspace --all-targets --all-features -- -D warnings" "$PROJECT_ROOT/backend"
    validate_command "Rust formatting" "cargo fmt --check" "$PROJECT_ROOT/backend"
    validate_command "Rust tests" "cargo test --workspace" "$PROJECT_ROOT/backend"
}

# Function to validate TypeScript/React code
validate_typescript() {
    if [ ! -f "$PROJECT_ROOT/frontend/package.json" ]; then
        echo -e "${YELLOW}⚠️  No TypeScript project found, skipping TypeScript validation${NC}"
        return 0
    fi
    
    local ts_files
    ts_files=$(find_typescript_files | head -1)
    if [ -z "$ts_files" ]; then
        echo -e "${YELLOW}⚠️  No TypeScript source files found, skipping TypeScript validation${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}=== TypeScript/React Validation ===${NC}"
    
    validate_command "TypeScript compilation" "npx tsc --noEmit" "$PROJECT_ROOT/frontend"
    validate_command "ESLint validation" "npx eslint src --ext .js,.jsx,.ts,.tsx --max-warnings 0" "$PROJECT_ROOT/frontend"
    validate_command "Prettier formatting" "npx prettier --check 'src/**/*.{js,jsx,ts,tsx,json,css,scss,md}'" "$PROJECT_ROOT/frontend"
    validate_command "React tests" "npm test -- --watchAll=false --coverage --testTimeout=30000" "$PROJECT_ROOT/frontend"
}

# Function to validate Python code
validate_python() {
    local python_files
    python_files=$(find_python_files | head -1)
    
    if [ -z "$python_files" ]; then
        echo -e "${YELLOW}⚠️  No Python source files found, skipping Python validation${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}=== Python Validation ===${NC}"
    
    # Syntax validation
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_step "Python syntax validation"
    local python_syntax_failed=0
    while IFS= read -r -d '' file; do
        if ! python -m py_compile "$file" 2>/dev/null; then
            echo -e "${RED}Syntax error in: $file${NC}"
            python_syntax_failed=1
        fi
    done < <(find_python_files -print0)
    
    if [ $python_syntax_failed -eq 0 ]; then
        log_success "Python syntax validation passed"
    else
        log_failure "Python syntax validation failed"
    fi
    
    # Check if Python tools are available and validate
    if command -v flake8 >/dev/null 2>&1; then
        # Create temporary flake8 config to exclude build directories
        local temp_config=$(mktemp)
        cat > "$temp_config" << EOF
[flake8]
max-line-length = 88
extend-ignore = E203,W503
exclude = 
    __pycache__,
    venv,
    .venv,
    env,
    .env,
    build,
    dist,
    .pytest_cache,
    .coverage,
    .tox,
    node_modules,
    target
EOF
        validate_command "Python linting (flake8)" "flake8 --config='$temp_config' ." "$PROJECT_ROOT"
        rm -f "$temp_config"
    else
        echo -e "${YELLOW}⚠️  flake8 not available, skipping Python linting${NC}"
    fi
    
    if command -v black >/dev/null 2>&1; then
        # Validate only Python source files
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_step "Python formatting (black)"
        local black_failed=0
        while IFS= read -r -d '' file; do
            if ! black --check --diff "$file" >/dev/null 2>&1; then
                echo -e "${RED}Formatting issue in: $file${NC}"
                black_failed=1
            fi
        done < <(find_python_files -print0)
        
        if [ $black_failed -eq 0 ]; then
            log_success "Python formatting (black) passed"
        else
            log_failure "Python formatting (black) failed"
        fi
    else
        echo -e "${YELLOW}⚠️  black not available, skipping Python formatting check${NC}"
    fi
    
    if command -v isort >/dev/null 2>&1; then
        # Validate import sorting only on source files
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_step "Python import sorting"
        local isort_failed=0
        while IFS= read -r -d '' file; do
            if ! isort --check-only --diff "$file" >/dev/null 2>&1; then
                echo -e "${RED}Import sorting issue in: $file${NC}"
                isort_failed=1
            fi
        done < <(find_python_files -print0)
        
        if [ $isort_failed -eq 0 ]; then
            log_success "Python import sorting passed"
        else
            log_failure "Python import sorting failed"
        fi
    else
        echo -e "${YELLOW}⚠️  isort not available, skipping import sorting check${NC}"
    fi
    
    # Run pytest if available
    if command -v pytest >/dev/null 2>&1; then
        validate_command "Python tests" "pytest -v --tb=short" "$PROJECT_ROOT"
    else
        echo -e "${YELLOW}⚠️  pytest not available, skipping Python tests${NC}"
    fi
}

# Function to validate Shell scripts
validate_shell() {
    local shell_files
    shell_files=$(find_shell_files | head -1)
    
    if [ -z "$shell_files" ]; then
        echo -e "${YELLOW}⚠️  No Shell source files found, skipping Shell validation${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}=== Shell Script Validation ===${NC}"
    
    # Syntax validation
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_step "Shell syntax validation"
    local shell_syntax_failed=0
    while IFS= read -r -d '' file; do
        if ! bash -n "$file" 2>/dev/null; then
            echo -e "${RED}Syntax error in: $file${NC}"
            shell_syntax_failed=1
        fi
    done < <(find_shell_files -print0)
    
    if [ $shell_syntax_failed -eq 0 ]; then
        log_success "Shell syntax validation passed"
    else
        log_failure "Shell syntax validation failed"
    fi
    
    # ShellCheck validation if available
    if command -v shellcheck >/dev/null 2>&1; then
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        log_step "ShellCheck linting"
        local shellcheck_failed=0
        while IFS= read -r -d '' file; do
            if ! shellcheck "$file" 2>/dev/null; then
                echo -e "${RED}ShellCheck issues in: $file${NC}"
                shellcheck_failed=1
            fi
        done < <(find_shell_files -print0)
        
        if [ $shellcheck_failed -eq 0 ]; then
            log_success "ShellCheck linting passed"
        else
            log_failure "ShellCheck linting failed"
        fi
    else
        echo -e "${YELLOW}⚠️  shellcheck not available, skipping Shell linting${NC}"
    fi
}

# Function to validate YAML files
validate_yaml() {
    local yaml_files
    yaml_files=$(find_yaml_files | head -1)
    
    if [ -z "$yaml_files" ]; then
        echo -e "${YELLOW}⚠️  No YAML source files found, skipping YAML validation${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}=== YAML Validation ===${NC}"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_step "YAML syntax validation"
    local yaml_failed=0
    while IFS= read -r -d '' file; do
        if ! python -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            echo -e "${RED}YAML syntax error in: $file${NC}"
            yaml_failed=1
        fi
    done < <(find_yaml_files -print0)
    
    if [ $yaml_failed -eq 0 ]; then
        log_success "YAML syntax validation passed"
    else
        log_failure "YAML syntax validation failed"
    fi
    
    # Docker Compose validation
    if [ -f "$PROJECT_ROOT/docker-compose.yaml" ]; then
        validate_command "Docker Compose validation" "docker-compose -f docker-compose.yaml config" "$PROJECT_ROOT"
    fi
}

# Function to validate JSON files
validate_json() {
    local json_files
    json_files=$(find_json_files | head -1)
    
    if [ -z "$json_files" ]; then
        echo -e "${YELLOW}⚠️  No JSON source files found, skipping JSON validation${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}=== JSON Validation ===${NC}"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_step "JSON syntax validation"
    local json_failed=0
    while IFS= read -r -d '' file; do
        if ! python -m json.tool "$file" >/dev/null 2>&1; then
            echo -e "${RED}JSON syntax error in: $file${NC}"
            json_failed=1
        fi
    done < <(find_json_files -print0)
    
    if [ $json_failed -eq 0 ]; then
        log_success "JSON syntax validation passed"
    else
        log_failure "JSON syntax validation failed"
    fi
}

# Function to check for common AI output issues
validate_ai_patterns() {
    echo -e "\n${YELLOW}=== AI Pattern Validation ===${NC}"
    
    # Check for orphaned XML/HTML tags in source files only
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_step "Checking for orphaned XML/HTML tags"
    local orphaned_tags=0
    while IFS= read -r -d '' file; do
        # Simple heuristic: count opening vs closing tags
        local opening_tags
        local closing_tags
        opening_tags=$(grep -o '<[^/][^>]*>' "$file" 2>/dev/null | wc -l)
        closing_tags=$(grep -o '</[^>]*>' "$file" 2>/dev/null | wc -l)
        
        if [ "$opening_tags" -ne "$closing_tags" ] && [ "$opening_tags" -gt 0 ]; then
            echo -e "${RED}Potential orphaned tags in: $file (opening: $opening_tags, closing: $closing_tags)${NC}"
            orphaned_tags=1
        fi
    done < <(find_typescript_files -name "*.tsx" -print0; find_javascript_files -name "*.jsx" -print0)
    
    if [ $orphaned_tags -eq 0 ]; then
        log_success "No orphaned XML/HTML tags found"
    else
        log_failure "Potential orphaned XML/HTML tags detected"
    fi
    
    # Check for mismatched brackets in source files only
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    log_step "Checking for bracket balance"
    local bracket_issues=0
    
    # Combine all source files for bracket checking
    {
        find_rust_files -print0
        find_typescript_files -print0
        find_javascript_files -print0
        find_python_files -print0
    } | while IFS= read -r -d '' file; do
        # Count different bracket types
        local open_braces
        local close_braces
        local open_brackets
        local close_brackets
        local open_parens
        local close_parens
        
        open_braces=$(grep -o '{' "$file" 2>/dev/null | wc -l)
        close_braces=$(grep -o '}' "$file" 2>/dev/null | wc -l)
        open_brackets=$(grep -o '\[' "$file" 2>/dev/null | wc -l)
        close_brackets=$(grep -o '\]' "$file" 2>/dev/null | wc -l)
        open_parens=$(grep -o '(' "$file" 2>/dev/null | wc -l)
        close_parens=$(grep -o ')' "$file" 2>/dev/null | wc -l)
        
        if [ "$open_braces" -ne "$close_braces" ] || [ "$open_brackets" -ne "$close_brackets" ] || [ "$open_parens" -ne "$close_parens" ]; then
            echo -e "${RED}Bracket mismatch in: $file${NC}"
            echo -e "  Braces: $open_braces open, $close_braces close"
            echo -e "  Brackets: $open_brackets open, $close_brackets close"
            echo -e "  Parentheses: $open_parens open, $close_parens close"
            bracket_issues=1
        fi
    done
    
    if [ $bracket_issues -eq 0 ]; then
        log_success "No bracket balance issues found"
    else
        log_failure "Bracket balance issues detected"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🤖 AI Code Validation Pipeline${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo -e "Project: Ruuvi Home"
    echo -e "Scope: Application source code only"
    echo -e "Timestamp: $(date)"
    echo -e ""
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Run all validations
    validate_rust
    validate_typescript
    validate_python
    validate_shell
    validate_yaml
    validate_json
    validate_ai_patterns
    
    # Final summary
    echo -e "\n${BLUE}==============================${NC}"
    echo -e "${BLUE}Validation Summary${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo -e "Total checks: $TOTAL_CHECKS"
    echo -e "Passed: $PASSED_CHECKS"
    echo -e "Failed: $((TOTAL_CHECKS - PASSED_CHECKS))"
    echo -e ""
    
    if [ $VALIDATION_FAILED -eq 0 ]; then
        echo -e "${GREEN}🎉 ALL VALIDATIONS PASSED!${NC}"
        echo -e "${GREEN}Code is ready for commit and human review.${NC}"
        exit 0
    else
        echo -e "${RED}💥 VALIDATION FAILED!${NC}"
        echo -e "${RED}Please fix the issues above before proceeding.${NC}"
        echo -e "${YELLOW}AI must not submit code until all validations pass.${NC}"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    -h|--help)
        echo "AI Code Validation Script - Application Source Code Only"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help     Show this help message"
        echo "  --rust         Validate only Rust source code"
        echo "  --typescript   Validate only TypeScript source code"
        echo "  --python       Validate only Python source code"
        echo "  --shell        Validate only Shell scripts"
        echo "  --yaml         Validate only YAML configuration files"
        echo "  --json         Validate only JSON configuration files"
        echo "  --patterns     Validate only AI patterns"
        echo ""
        echo "Excludes: node_modules, target, build, dist, __pycache__, .git, and other build artifacts"
        echo "With no options, validates all supported languages and patterns."
        exit 0
        ;;
    --rust)
        validate_rust
        exit $?
        ;;
    --typescript)
        validate_typescript
        exit $?
        ;;
    --python)
        validate_python
        exit $?
        ;;
    --shell)
        validate_shell
        exit $?
        ;;
    --yaml)
        validate_yaml
        exit $?
        ;;
    --json)
        validate_json
        exit $?
        ;;
    --patterns)
        validate_ai_patterns
        exit $?
        ;;
    "")
        main
        ;;
    *)
        echo -e "${RED}Error: Unknown option $1${NC}"
        echo "Use --help for usage information"
        exit 1
        ;;
esac