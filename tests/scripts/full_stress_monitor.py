#!/usr/bin/env python3
import sys
import argparse
sys.path.append('tests')
sys.path.append('tests/suites')

from monitor_resources import ResourceMonitor
from stress_test import run_stress_tests
import threading
import time

def main():
    parser = argparse.ArgumentParser(description='Run full stress test with monitoring')
    parser.add_argument('duration', type=int, nargs='?', default=300, help='Monitoring duration in seconds')
    parser.add_argument('--levels', help='Comma-separated test levels to run')
    args = parser.parse_args()

    monitor = ResourceMonitor()
    monitor_thread = threading.Thread(target=monitor.start_monitoring, args=(args.duration, 1))
    monitor_thread.start()

    print('Monitoring started, waiting 5 seconds...')
    time.sleep(5)

    # Run stress tests with specified levels
    run_stress_tests(args.levels)

    print('Stress tests complete, stopping monitoring...')
    monitor.stop_monitoring()
    monitor_thread.join()
    monitor.save_data('tests/results/full_stress_monitoring.json')

    try:
        monitor.plot_resources()
        print('Resource plots saved as resource_usage.png')
    except Exception as e:
        print(f'Could not generate plots: {e}')

    print('Full stress test suite complete!')
    print('Results saved in:')
    print('  - tests/results/stress_test_results.json')
    print('  - tests/results/full_stress_monitoring.json')
    print('  - tests/results/resource_usage.png (if matplotlib available)')

if __name__ == "__main__":
    main()
