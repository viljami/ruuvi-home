#!/bin/bash

# Ruuvi Home Development Setup Script
# Sets up pre-commit hooks and development dependencies

set -e

echo "🚀 Setting up Ruuvi Home development environment..."

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to setup virtual environment and install pre-commit
setup_python_env() {
    echo "🐍 Setting up Python virtual environment..."

    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        echo "✅ Created virtual environment"
    else
        echo "✅ Virtual environment already exists"
    fi

    # Activate virtual environment
    source venv/bin/activate

    # Upgrade pip
    pip install --upgrade pip

    echo "📦 Installing pre-commit in virtual environment..."
    pip install pre-commit
}

# Setup Python environment and install pre-commit
setup_python_env

# Activate virtual environment for the rest of the script
source venv/bin/activate

# Install pre-commit hooks
echo "🔧 Installing pre-commit hooks..."
pre-commit install

# Setup MQTT simulator dependencies in virtual environment
echo "🐍 Setting up MQTT simulator dependencies..."
cd docker/mqtt-simulator

# Install Python dependencies in virtual environment
if [ -f "requirements.txt" ]; then
    echo "📦 Installing Python dependencies in virtual environment..."
    pip install -r requirements.txt
    pip install pytest pytest-cov black isort flake8
else
    echo "⚠️  Warning: requirements.txt not found in mqtt-simulator directory"
fi

cd ../..

# Check if Rust is installed for backend
if command_exists cargo; then
    echo "✅ Rust is installed"
    echo "🔧 Setting up Rust environment..."
    cd backend
    echo "📦 Installing Rust components..."
    rustup component add rustfmt clippy
    cd ..
else
    echo "⚠️  Warning: Rust not found. Install Rust from https://rustup.rs/ for backend development"
fi

# Check if Node.js is installed for frontend
if command_exists npm; then
    echo "✅ Node.js is installed"
    if [ -d "frontend" ] && [ -f "frontend/package.json" ]; then
        echo "🔧 Setting up frontend dependencies..."
        cd frontend
        npm install
        cd ..
    fi
else
    echo "⚠️  Warning: Node.js not found. Install Node.js for frontend development"
fi

# Run initial formatting
echo "🎨 Running initial code formatting..."

# Format Python code using virtual environment
if [ -d "docker/mqtt-simulator" ]; then
    cd docker/mqtt-simulator
    echo "🐍 Formatting Python code..."
    make fmt || true
    cd ../..
fi

# Format Rust code
if [ -d "backend" ] && command_exists cargo; then
    cd backend
    echo "🦀 Formatting Rust code..."
    make fmt || true
    cd ..
fi

echo ""
echo "✅ Development environment setup complete!"
echo ""
echo "🎯 Next steps:"
echo "   • Activate virtual environment: source venv/bin/activate"
echo "   • Run 'make dev' in backend/ to check Rust code quality"
echo "   • Run 'make dev' in docker/mqtt-simulator/ to check Python code quality"
echo "   • Pre-commit hooks will now run automatically on git commit"
echo "   • Use 'pre-commit run --all-files' to run hooks on all files"
echo ""
echo "📚 Useful commands:"
echo "   • 'source venv/bin/activate' - Activate Python virtual environment"
echo "   • 'deactivate' - Deactivate virtual environment"
echo "   • 'make help' in backend/ - See all available Rust targets"
echo "   • 'make help' in docker/mqtt-simulator/ - See all available Python targets"
echo "   • 'pre-commit run --all-files' - Run all pre-commit hooks"
echo "   • 'pre-commit autoupdate' - Update pre-commit hook versions"
