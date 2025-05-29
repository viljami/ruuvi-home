#!/bin/bash
# Ruuvi MQTT Simulator Test Runner

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Directory containing this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Ensure dependencies are installed
echo -e "${YELLOW}Checking dependencies...${NC}"
pip install -r requirements.txt

# Run linting
echo -e "${YELLOW}Running code quality checks...${NC}"
flake8 simulator.py tests/ || echo -e "${RED}Linting issues found${NC}"
black --check simulator.py tests/ || echo -e "${YELLOW}Code formatting issues found${NC}"
isort --check-only simulator.py tests/ || echo -e "${YELLOW}Import order issues found${NC}"

# Run tests
echo -e "${YELLOW}Running tests...${NC}"
python -m pytest tests/ -v --cov=simulator --cov-report=term --cov-report=xml:coverage.xml

# Display results
echo -e "\n${GREEN}Tests completed!${NC}"

# Format code if requested
if [ "$1" == "--format" ]; then
    echo -e "${YELLOW}Formatting code...${NC}"
    black simulator.py tests/
    isort simulator.py tests/
fi

# Run the simulator with test mode if requested
if [ "$1" == "--run" ]; then
    echo -e "${YELLOW}Running simulator in test mode...${NC}"
    export MQTT_BROKER="localhost"
    export MQTT_PORT=1883
    export MQTT_TOPIC="ruuvi/gateway/data"
    export PUBLISH_INTERVAL=5.0
    export NUM_SENSORS=2
    python simulator.py
fi