#!/bin/bash

# Usage: ./run_stress_tests.sh <test_type> <duration> <scenario>
# test_type:
#   stress: Run stress tests only
#   monitor: Monitor resources only (for manual testing)
#   all (default): Run all tests with monitoring
# duration: in seconds (default 300)
# scenario: light, medium, heavy, peak, extreme, stress, breaking,
#           sustained, high_sustained, breaking, limit, overload
#           (Can specify multiple scenarios comma-separated)

# Examples:
# bash tests/run_stress_tests.sh
# bash tests/run_stress_tests.sh stress 300
# bash tests/run_stress_tests.sh monitor 600
# bash tests/run_stress_tests.sh all 300 "light,medium,heavy"

set -e  # Exit on any error

# Setup Python environment if needed
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "Setting up Python environment..."
    source tests/scripts/setup_env.sh
fi

# Verify we're in virtual environment
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "ERROR: Failed to activate virtual environment"
    exit 1
fi

echo "Using Python environment: $VIRTUAL_ENV"
echo "Python version: $(python --version)"

# Start test environment
if ! docker-compose -f docker-compose.test.yml ps | grep -q "Up"; then
    echo "Starting test containers..."
    docker-compose -f docker-compose.test.yml up -d
    echo "Waiting for services to stabilize..."
    sleep 2
else
    echo "Test containers already running"
fi

# Health check
echo "Checking service health..."
python tests/scripts/check_services.py
if [ $? -ne 0 ]; then
    echo "❌ Services not healthy, aborting tests"
    exit 1
fi

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up test containers..."
    # Force stop and remove containers
    docker-compose -f docker-compose.test.yml down --remove-orphans --timeout 5
    # Kill any remaining monitoring processes
    if [ ! -z "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
}

# Set trap to ensure cleanup runs on any exit signal
trap cleanup EXIT INT TERM

# Parse command line arguments
TEST_TYPE=${1:-"all"}
DURATION=${2:-300}  # Default 5 minutes monitoring
SCENARIO=${3:-""}   # Optional specific scenario or test levels

case $TEST_TYPE in
    "stress")
        echo "Running stress tests..."
        if [[ -n "$SCENARIO" ]]; then
            python tests/suites/stress_test.py --levels "$SCENARIO"
        else
            python tests/suites/stress_test.py
        fi
        ;;
    "monitor")
        echo "Running resource monitoring for ${DURATION} seconds..."
        python tests/scripts/monitor_resources.py --duration $DURATION
        ;;
    "all"|*)
        echo "Running full stress test suite with monitoring..."
        if [[ -n "$SCENARIO" ]]; then
            echo "Running specific scenarios: $SCENARIO"
            python tests/scripts/full_stress_monitor.py $DURATION --levels "$SCENARIO" &
        else
            python tests/scripts/full_stress_monitor.py $DURATION &
        fi
        MONITOR_PID=$!
        wait $MONITOR_PID
        ;;
esac

echo "✅ Stress testing completed!"

# Show results summary
if [[ -f "stress_test_results.json" ]]; then
    echo ""
    echo "=== STRESS TEST SUMMARY ==="
    python tests/scripts/show_results.py
fi

# Show resource usage summary
if [[ -f "tests/results/full_stress_monitoring.json" ]] ||
    [[ -f "tests/results/combined_monitoring.json" ]]; then
    echo ""
    echo "=== RESOURCE USAGE SUMMARY ==="
    echo "Check the generated JSON files and PNG plots for detailed resource usage"
fi

exit 0
