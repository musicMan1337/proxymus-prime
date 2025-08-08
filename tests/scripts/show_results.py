#!/usr/bin/env python3
import json
import os

def main():
    if os.path.exists('stress_test_results.json'):
        with open('stress_test_results.json', 'r') as f:
            results = json.load(f)

        for name, result in results.items():
            lr = result['load_test']
            print(f'{name:15} | Success: {lr["success_rate"]:6.2%} | RPS: {lr["requests_per_second"]:6.1f} | Avg: {lr["avg_response_time"]:6.3f}s')

if __name__ == "__main__":
    main()
