#!/usr/bin/env python3
import sys
sys.path.append('tests')
sys.path.append('tests/suites')

from stress_test import StressTestRunner

def main():
    if len(sys.argv) < 2:
        print('ERROR: Scenario name required')
        sys.exit(1)

    scenario_name = sys.argv[1]

    scenarios = {
        'light': {'users': 10, 'requests': 10},
        'medium': {'users': 25, 'requests': 20},
        'heavy': {'users': 50, 'requests': 20},
        'peak': {'users': 100, 'requests': 10},
        'extreme': {'users': 200, 'requests': 5}
    }

    if scenario_name not in scenarios:
        print(f'Invalid scenario: {scenario_name}')
        print('Available scenarios:', ', '.join(scenarios.keys()))
        sys.exit(1)

    tester = StressTestRunner()
    scenario = scenarios[scenario_name]
    print(f'Running {scenario_name} scenario: {scenario}')

    baseline_stats = tester.get_container_stats()
    results = tester.run_load_test(scenario['users'], scenario['requests'])
    post_stats = tester.get_container_stats()

    print(f'Success Rate: {results["success_rate"]:.2%}')
    print(f'Requests/sec: {results["requests_per_second"]:.2f}')
    print(f'Avg Response Time: {results["avg_response_time"]:.3f}s')
    print(f'P95 Response Time: {results["p95_response_time"]:.3f}s')

if __name__ == "__main__":
    main()