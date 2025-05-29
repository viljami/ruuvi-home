#!/bin/bash
# Ruuvi Home - Python Virtual Environment Setup Script
# Creates and configures a dedicated Python virtual environment

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Directory containing this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VENV_DIR="${SCRIPT_DIR}/venv"
SIMULATOR_DIR="${SCRIPT_DIR}/docker/mqtt-simulator"

# Check Python version
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed.${NC}"
    echo "Please install Python 3 and try again."
    exit 1
fi

# Create venv directory if it doesn't exist
mkdir -p "$VENV_DIR"

echo -e "${YELLOW}Setting up Python virtual environment in ${VENV_DIR}...${NC}"

# Create virtual environment
python3 -m venv "$VENV_DIR"

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Upgrade pip
echo -e "${YELLOW}Upgrading pip...${NC}"
pip install --upgrade pip

# Install requirements if they exist
if [ -f "${SIMULATOR_DIR}/requirements.txt" ]; then
    echo -e "${YELLOW}Installing MQTT simulator requirements...${NC}"
    pip install -r "${SIMULATOR_DIR}/requirements.txt"
fi

# Display activation instructions
echo -e "\n${GREEN}Virtual environment created successfully!${NC}"
echo -e "\nTo activate the virtual environment, run:"
echo -e "${YELLOW}source ${VENV_DIR}/bin/activate${NC}"
echo -e "\nTo deactivate when finished, run:"
echo -e "${YELLOW}deactivate${NC}"
echo -e "\nTo run MQTT simulator tests:"
echo -e "${YELLOW}cd ${SIMULATOR_DIR} && python -m pytest tests/ -v${NC}"

# Create activation script for convenience
cat > "${SCRIPT_DIR}/activate-venv.sh" << EOF
#!/bin/bash
# Activate the Python virtual environment
source "${VENV_DIR}/bin/activate"
echo "Virtual environment activated. Type 'deactivate' to exit."
EOF

chmod +x "${SCRIPT_DIR}/activate-venv.sh"
echo -e "\nFor quick activation, you can also run:"
echo -e "${YELLOW}source ./activate-venv.sh${NC}"