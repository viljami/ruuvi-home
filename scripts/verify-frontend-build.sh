#!/bin/bash
# Frontend Build Verification Script
# Ensures frontend builds correctly and basic functionality works

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to frontend directory
cd "$(dirname "$0")/../frontend"

echo -e "${YELLOW}🏗️  Verifying frontend build...${NC}"

# Function to check if required files exist
check_required_files() {
    local missing_files=()
    
    if [ ! -f "package.json" ]; then
        missing_files+=("package.json")
    fi
    
    if [ ! -f "public/index.html" ]; then
        missing_files+=("public/index.html")
    fi
    
    if [ ! -f "public/manifest.json" ]; then
        missing_files+=("public/manifest.json")
    fi
    
    if [ ! -f "src/App.tsx" ]; then
        missing_files+=("src/App.tsx")
    fi
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo -e "${RED}✗ Missing required files: ${missing_files[*]}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ All required files present${NC}"
    return 0
}

# Function to install dependencies
install_dependencies() {
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    
    if ! npm ci --silent; then
        echo -e "${RED}✗ Failed to install dependencies${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Dependencies installed${NC}"
    return 0
}

# Function to run smoke tests
run_smoke_tests() {
    echo -e "${YELLOW}🧪 Running smoke tests...${NC}"
    
    # Set environment for testing
    export NODE_ENV=test
    export CI=true
    
    if ! npm test -- --testNamePattern="App Smoke Tests" --watchAll=false --verbose=false; then
        echo -e "${RED}✗ Smoke tests failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Smoke tests passed${NC}"
    return 0
}

# Function to build the frontend
build_frontend() {
    echo -e "${YELLOW}🔨 Building frontend...${NC}"
    
    # Set production environment
    export NODE_ENV=production
    export GENERATE_SOURCEMAP=false
    export INLINE_RUNTIME_CHUNK=false
    export IMAGE_INLINE_SIZE_LIMIT=0
    
    if ! npm run build; then
        echo -e "${RED}✗ Frontend build failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Frontend build completed${NC}"
    return 0
}

# Function to verify build output
verify_build_output() {
    echo -e "${YELLOW}🔍 Verifying build output...${NC}"
    
    if [ ! -d "build" ]; then
        echo -e "${RED}✗ Build directory not found${NC}"
        return 1
    fi
    
    if [ ! -f "build/index.html" ]; then
        echo -e "${RED}✗ index.html not found in build${NC}"
        return 1
    fi
    
    if [ ! -f "build/manifest.json" ]; then
        echo -e "${RED}✗ manifest.json not found in build${NC}"
        return 1
    fi
    
    # Check for static assets
    if [ ! -d "build/static" ]; then
        echo -e "${RED}✗ Static assets directory not found${NC}"
        return 1
    fi
    
    # Check build size (should be reasonable)
    local build_size=$(du -sh build | cut -f1)
    echo -e "${GREEN}✓ Build output verified (size: $build_size)${NC}"
    
    # Check for critical files in static directory
    local js_files=$(find build/static -name "*.js" | wc -l)
    local css_files=$(find build/static -name "*.css" | wc -l)
    
    if [ "$js_files" -eq 0 ]; then
        echo -e "${YELLOW}⚠ No JavaScript files found in build${NC}"
    else
        echo -e "${GREEN}✓ JavaScript files: $js_files${NC}"
    fi
    
    if [ "$css_files" -eq 0 ]; then
        echo -e "${YELLOW}⚠ No CSS files found in build${NC}"
    else
        echo -e "${GREEN}✓ CSS files: $css_files${NC}"
    fi
    
    return 0
}

# Function to run linting
run_linting() {
    echo -e "${YELLOW}🔍 Running frontend linting...${NC}"
    
    if ! npm run lint; then
        echo -e "${YELLOW}⚠ Linting issues found (non-critical)${NC}"
    else
        echo -e "${GREEN}✓ Linting passed${NC}"
    fi
    
    return 0
}

# Function to verify Docker build
verify_docker_build() {
    echo -e "${YELLOW}🐳 Verifying Docker build compatibility...${NC}"
    
    # Check if Dockerfile exists
    if [ ! -f "../docker/frontend.Dockerfile" ]; then
        echo -e "${RED}✗ Frontend Dockerfile not found${NC}"
        return 1
    fi
    
    # Verify Docker build context
    cd ..
    if docker build -f docker/frontend.Dockerfile -t ruuvi-frontend-test .; then
        echo -e "${GREEN}✓ Docker build successful${NC}"
        
        # Clean up test image
        docker rmi ruuvi-frontend-test >/dev/null 2>&1 || true
    else
        echo -e "${RED}✗ Docker build failed${NC}"
        return 1
    fi
    
    cd frontend
    return 0
}

# Main execution
main() {
    local exit_code=0
    
    echo -e "${YELLOW}🏠 Ruuvi Home Frontend Build Verification${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    
    # Run all checks
    check_required_files || exit_code=1
    
    if [ $exit_code -eq 0 ]; then
        install_dependencies || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        run_linting || true  # Non-critical
    fi
    
    if [ $exit_code -eq 0 ]; then
        run_smoke_tests || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        build_frontend || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        verify_build_output || exit_code=1
    fi
    
    if [ $exit_code -eq 0 ]; then
        verify_docker_build || exit_code=1
    fi
    
    echo -e "${YELLOW}=========================================${NC}"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}🎉 Frontend build verification completed successfully!${NC}"
        echo -e "${GREEN}✓ All checks passed${NC}"
        echo -e "${GREEN}✓ Build is ready for deployment${NC}"
    else
        echo -e "${RED}❌ Frontend build verification failed${NC}"
        echo -e "${YELLOW}Please fix the issues above before deployment${NC}"
    fi
    
    exit $exit_code
}

# Run main function
main "$@"