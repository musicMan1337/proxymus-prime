#!/bin/bash

set -e  # Exit on any error

# Setup Python environment if needed
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "Setting up Python environment..."
    source tests/setup_env.sh
fi

# Verify we're in virtual environment
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "ERROR: Failed to activate virtual environment"
    exit 1
fi

echo "Using Python environment: $VIRTUAL_ENV"
echo "Python version: $(python --version)"

# Start test environment
echo "Starting test containers..."
docker-compose -f docker-compose.test.yml up -d

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up test containers..."
    docker-compose -f docker-compose.test.yml down
}

# Set trap to ensure cleanup runs even if tests fail
trap cleanup EXIT

# Run tests (disable set -e temporarily so cleanup always runs)
set +e
echo "Running full test suite with HTML report..."
python -m pytest tests/test_proxy.py -v --html=tests/report.html --self-contained-html
TEST_EXIT_CODE=$?
set -e

echo "✅ Tests completed with exit code: $TEST_EXIT_CODE"

# Exit with the test result code
exit $TEST_EXIT_CODE
