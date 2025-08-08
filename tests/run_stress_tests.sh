#!/bin/bash

# Usage: ./run_stress_tests.sh <test_type> <duration> <scenario>
# test_type: stress, monitor, combined, custom, all (default all)
# duration: in seconds (default 300)
# scenario: light, medium, heavy, peak, extreme (for custom only)

# Examples:
# bash tests/run_stress_tests.sh
# bash tests/run_stress_tests.sh stress
# bash tests/run_stress_tests.sh monitor 600
# bash tests/run_stress_tests.sh combined 300
# bash tests/run_stress_tests.sh custom 300 heavy
# bash tests/run_stress_tests.sh all 300

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
    sleep 5
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
SCENARIO=${3:-""}   # Optional specific scenario

case $TEST_TYPE in
    "stress")
        echo "Running stress tests..."
        python tests/stress_test.py
        ;;
    "monitor")
        echo "Running resource monitoring for ${DURATION} seconds..."
        python tests/scripts/monitor_resources.py --duration $DURATION
        ;;
    "combined")
        echo "Running combined stress test with monitoring..."
        python tests/scripts/combined_stress_monitor.py $DURATION &
        MONITOR_PID=$!
        wait $MONITOR_PID
        ;;
    "custom")
        if [[ -z "$SCENARIO" ]]; then
            echo "ERROR: Custom scenario required"
            echo "Usage: $0 custom <duration> <scenario_name>"
            echo "Available scenarios: light, medium, heavy, peak, extreme"
            exit 1
        fi

        echo "Running custom scenario: $SCENARIO"
        python tests/scripts/custom_scenario.py $SCENARIO
        ;;
    "all"|*)
        echo "Running full stress test suite with monitoring..."
        python tests/scripts/full_stress_monitor.py $DURATION &
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
