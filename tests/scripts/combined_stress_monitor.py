#!/usr/bin/env python3
import sys
import os
sys.path.append('tests')
sys.path.append('tests/suites')

from monitor_resources import ResourceMonitor
from stress_test import run_stress_tests
import threading
import time

def main():
    duration = int(sys.argv[1]) if len(sys.argv) > 1 else 300

    monitor = ResourceMonitor()
    monitor_thread = threading.Thread(target=monitor.start_monitoring, args=(duration, 1))
    monitor_thread.start()

    print('Monitoring started, running stress tests...')
    time.sleep(5)  # Let monitoring stabilize

    # Import and run stress tests
    run_stress_tests()

    print('Stress tests complete, stopping monitoring...')
    monitor.stop_monitoring()
    monitor_thread.join()
    monitor.save_data('tests/results/combined_monitoring.json')

    try:
        monitor.plot_resources()
        print('Resource plots saved as resource_usage.png')
    except Exception as e:
        print(f'Could not generate plots: {e}')

    print('Combined test complete!')

if __name__ == "__main__":
    main()