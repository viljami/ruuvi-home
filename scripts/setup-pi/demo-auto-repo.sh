#!/bin/bash
# Demo Script: Automatic Repository Detection
# Shows how the setup script can automatically detect GitHub repository name

set -e

# Colors for output
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_NC='\033[0m'

# Get script directory and source config library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

echo -e "${COLOR_BLUE}🔍 Automatic Repository Detection Demo${COLOR_NC}"
echo "========================================"
echo ""

# Show current Git status
echo -e "${COLOR_CYAN}Current Git Repository:${COLOR_NC}"
if git rev-parse --git-dir >/dev/null 2>&1; then
    local_remote=$(git remote get-url origin 2>/dev/null || echo "No remote configured")
    echo "  Remote URL: $local_remote"

    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "  Current branch: $current_branch"

    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    echo "  Latest commit: $commit_hash"
else
    echo "  ❌ Not in a Git repository"
    exit 1
fi

echo ""
echo -e "${COLOR_CYAN}Repository Detection:${COLOR_NC}"

# Clear any existing GITHUB_REPO
unset GITHUB_REPO

# Attempt auto-detection
if detect_repository_name; then
    echo -e "  ✅ ${COLOR_GREEN}Auto-detected: $GITHUB_REPO${COLOR_NC}"

    # Show what this means for container images
    echo ""
    echo -e "${COLOR_CYAN}Container Image URLs:${COLOR_NC}"
    echo "  Registry: ghcr.io"
    echo "  Frontend: ghcr.io/$GITHUB_REPO/frontend:latest"
    echo "  API Server: ghcr.io/$GITHUB_REPO/api-server:latest"
    echo "  MQTT Reader: ghcr.io/$GITHUB_REPO/mqtt-reader:latest"
    echo "  MQTT Simulator: ghcr.io/$GITHUB_REPO/mqtt-simulator:latest"

    echo ""
    echo -e "${COLOR_CYAN}Usage Examples:${COLOR_NC}"
    echo "  # Registry mode (auto-detects repo):"
    echo "  export DEPLOYMENT_MODE=registry"
    echo "  sudo ./scripts/setup-pi/setup-pi.sh"
    echo ""
    echo "  # Manual override still works:"
    echo "  export GITHUB_REPO=custom/repository"
    echo "  export DEPLOYMENT_MODE=registry"
    echo "  sudo ./scripts/setup-pi/setup-pi.sh"

    echo ""
    echo -e "${COLOR_GREEN}🎉 Repository detection is working!${COLOR_NC}"
    echo "You can now run the setup script without manually setting GITHUB_REPO."
else
    echo -e "  ❌ ${COLOR_YELLOW}Auto-detection failed${COLOR_NC}"
    echo ""
    echo "Possible reasons:"
    echo "  • Not a GitHub repository"
    echo "  • No remote origin configured"
    echo "  • Remote URL format not recognized"
    echo ""
    echo "Solutions:"
    echo "  • Set manually: export GITHUB_REPO=owner/repo"
    echo "  • Add GitHub remote: git remote add origin https://github.com/owner/repo"
    echo "  • Use local mode: export DEPLOYMENT_MODE=local"
fi
