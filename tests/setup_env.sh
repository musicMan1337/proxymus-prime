#!/bin/bash

set -e  # Exit on any error

VENV_DIR="venv"
PYTHON_CMD="python3"

echo "Setting up Python test environment..."

# Check if Python 3 is available
if ! command -v $PYTHON_CMD &> /dev/null; then
    echo "ERROR: $PYTHON_CMD is not installed or not in PATH"
    exit 1
fi

echo "Found Python: $($PYTHON_CMD --version)"

# Check if virtual environment already exists and is activated
if [[ "$VIRTUAL_ENV" != "" ]]; then
    echo "Virtual environment already activated: $VIRTUAL_ENV"
    echo "Using existing environment..."
elif [[ -d "$VENV_DIR" ]]; then
    echo "Virtual environment exists at $VENV_DIR"
    echo "Activating existing environment..."
    source $VENV_DIR/bin/activate
    echo "Activated: $VIRTUAL_ENV"
else
    echo "Creating new virtual environment at $VENV_DIR..."
    $PYTHON_CMD -m venv $VENV_DIR

    echo "Activating virtual environment..."
    source $VENV_DIR/bin/activate
    echo "Activated: $VIRTUAL_ENV"

    echo "Upgrading pip..."
    python -m pip install --upgrade pip
fi

# Install/upgrade test dependencies
echo "Installing test dependencies..."
if [[ -f "tests/requirements.txt" ]]; then
    pip install -r tests/requirements.txt
else
    echo "WARNING: tests/requirements.txt not found, installing basic dependencies..."
    pip install pytest requests pytest-html pytest-xdist
fi

echo "✅ Python environment setup complete!"
echo ""
echo "To activate this environment in the future, run:"
echo "  source $VENV_DIR/bin/activate"
echo ""
echo "To run tests:"
echo "  python -m pytest tests/test_proxy.py -v"
echo "  # or"
echo "  bash ./tests/run_tests.sh"