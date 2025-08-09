#!/usr/bin/env python3
import os
import requests
import concurrent.futures
import time
import statistics
import docker
import json
from typing import Dict, List
from requests import adapters
import urllib3
import argparse

# Disable SSL warnings for self-signed certificates in testing
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class StressTestRunner:
    def __init__(self, base_url="https://localhost", verify_ssl=False):
        self.base_url = base_url
        self.verify_ssl = verify_ssl
        self.docker_client = docker.from_env()

    def run_load_test(
        self,
        concurrent_users: int,
        requests_per_user: int,
        endpoint: str = "/",
        timeout: int = 30
    ) -> Dict:
        """Run load test with specified parameters"""

        # Add warmup requests
        print("Warming up servers...")
        warmup_session = requests.Session()
        warmup_session.verify = self.verify_ssl
        for _ in range(3):
            try:
                warmup_session.get(f"{self.base_url}{endpoint}", timeout=5)
                time.sleep(0.1)
            except:
                pass
        warmup_session.close()

        def make_requests(user_id: int) -> List[Dict]:
            results = []

            session = requests.Session()
            session.verify = self.verify_ssl

            adapter = adapters.HTTPAdapter(
                pool_connections=1,
                pool_maxsize=1,
                max_retries=0
            )
            session.mount('https://', adapter)
            session.mount('http://', adapter)

            # Mock different client IPs for proper load balancing
            headers = {
                'X-Forwarded-For': f"192.168.1.{(user_id % 254) + 1}"
            }

            for i in range(requests_per_user):
                start_time = time.time()
                try:
                    response = session.get(f"{self.base_url}{endpoint}", headers=headers, timeout=10)
                    end_time = time.time()

                    results.append({
                        'user_id': user_id,
                        'request_id': i,
                        'status_code': response.status_code,
                        'response_time': end_time - start_time,
                        'success': response.status_code == 200,
                        'error': None if response.status_code == 200 else f"HTTP {response.status_code}",
                        'server_id': response.headers.get('X-Server-ID', 'unknown') if response.status_code == 200 else None
                    })
                except Exception as e:
                    end_time = time.time()
                    results.append({
                        'user_id': user_id,
                        'request_id': i,
                        'status_code': 0,
                        'response_time': end_time - start_time,
                        'success': False,
                        'error': str(e),
                        'server_id': None
                    })

                finally:
                    session.close()

            return results

        print(f"Starting load test: {concurrent_users} users, {requests_per_user} requests each")
        start_time = time.time()

        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrent_users) as executor:
            futures = []

            for i in range(concurrent_users):
                futures.append(executor.submit(make_requests, i))

            all_results = []
            for future in concurrent.futures.as_completed(futures):
                all_results.extend(future.result())

        end_time = time.time()

        return self.analyze_results(all_results, end_time - start_time)

    def analyze_results(self, results: List[Dict], total_time: float) -> Dict:
        """Analyze test results"""
        successful = [r for r in results if r['success']]
        failed = [r for r in results if not r['success']]
        response_times = [r['response_time'] for r in successful]

        # Analyze failure types
        error_types = {}
        for r in failed:
            error = r.get('error', 'Unknown')
            error_types[error] = error_types.get(error, 0) + 1

        analysis = {
            'total_requests': len(results),
            'successful_requests': len(successful),
            'failed_requests': len(failed),
            'success_rate': len(successful) / len(results) if results else 0,
            'total_time': total_time,
            'requests_per_second': len(results) / total_time if total_time > 0 else 0,
            'avg_response_time': statistics.mean(response_times) if response_times else 0,
            'median_response_time': statistics.median(response_times) if response_times else 0,
            'p95_response_time': statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0,
            'p99_response_time': statistics.quantiles(response_times, n=100)[98] if len(response_times) > 100 else 0,
            'error_breakdown': error_types
        }

        # Print error breakdown if there are failures
        if failed:
            print(f"Error breakdown:")
            for error, count in error_types.items():
                print(f"  {error}: {count} ({count/len(results)*100:.1f}%)")

        return analysis

    def get_container_stats(self):
        """Get current container statistics"""
        stats = {}

        for container_name in ['nginx_proxy', 'redis', 'backend_server_1', 'backend_server_2', 'backend_server_3']:
            try:
                container = self.docker_client.containers.get(container_name)
                if container.status != 'running':
                    stats[container_name] = {'error': f'Container not running: {container.status}'}
                    continue

                container_stats = container.stats(stream=False)

                # Calculate CPU percentage
                try:
                    cpu_delta = container_stats['cpu_stats']['cpu_usage']['total_usage'] - \
                               container_stats['precpu_stats']['cpu_usage']['total_usage']
                    system_delta = container_stats['cpu_stats']['system_cpu_usage'] - \
                                  container_stats['precpu_stats']['system_cpu_usage']

                    if 'percpu_usage' in container_stats['cpu_stats']['cpu_usage']:
                        num_cpus = len(container_stats['cpu_stats']['cpu_usage']['percpu_usage'])
                    else:
                        num_cpus = container_stats['cpu_stats'].get('online_cpus', 1)

                    if system_delta > 0:
                        cpu_percent = (cpu_delta / system_delta) * num_cpus * 100
                    else:
                        cpu_percent = 0.0

                except (KeyError, ZeroDivisionError):
                    cpu_percent = 0.0

                # Calculate memory usage
                try:
                    memory_usage = container_stats['memory_stats']['usage'] / (1024 * 1024)  # MB
                except KeyError:
                    memory_usage = 0.0

                stats[container_name] = {
                    'cpu_percent': cpu_percent,
                    'memory_mb': memory_usage
                }

            except Exception as e:
                stats[container_name] = {'error': str(e)}

        return stats

# Test scenario definitions
STRESS_SCENARIOS = [
    {'users': 10, 'requests': 10, 'name': 'Light Load', 'level': 'light'},
    {'users': 25, 'requests': 20, 'name': 'Medium Load', 'level': 'medium'},
    {'users': 50, 'requests': 30, 'name': 'Heavy Load', 'level': 'heavy'},
    {'users': 100, 'requests': 50, 'name': 'Peak Load', 'level': 'peak'},
    {'users': 200, 'requests': 100, 'name': 'Sustained Load', 'level': 'sustained'},
    {'users': 500, 'requests': 50, 'name': 'High Sustained', 'level': 'high_sustained'},
    {'users': 1000, 'requests': 10, 'name': 'Breaking Point', 'level': 'breaking'},
    {'users': 1500, 'requests': 5, 'name': 'System Limit', 'level': 'limit'},
    {'users': 2000, 'requests': 3, 'name': 'Overload Test', 'level': 'overload'},
    {'users': 3000, 'requests': 2, 'name': 'Extreme Overload', 'level': 'extreme_overload'},
    {'users': 5000, 'requests': 1, 'name': 'Connection Limit', 'level': 'connection_limit'},
]

def run_stress_tests(test_levels=None):
    """Run comprehensive stress tests"""
    tester = StressTestRunner()

    # Filter scenarios based on test_levels
    if test_levels:
        levels = [level.strip() for level in test_levels.split(',')]
        test_scenarios = [s for s in STRESS_SCENARIOS if s['level'] in levels]
        if not test_scenarios:
            print(f"No matching test levels found. Available: {[s['level'] for s in STRESS_SCENARIOS]}")
            return
    else:
        test_scenarios = STRESS_SCENARIOS

    results = {}

    for scenario in test_scenarios:
        print(f"\n{'='*50}")
        print(f"Running {scenario['name']} Test")
        print(f"{'='*50}")

        # Get baseline stats
        baseline_stats = tester.get_container_stats()

        # Run load test
        load_results = tester.run_load_test(
            concurrent_users=scenario['users'],
            requests_per_user=scenario['requests']
        )

        # Get post-test stats
        post_stats = tester.get_container_stats()

        results[scenario['name']] = {
            'load_test': load_results,
            'baseline_stats': baseline_stats,
            'post_test_stats': post_stats
        }

        # Print results
        print(f"Success Rate: {load_results['success_rate']:.2%}")
        print(f"Requests/sec: {load_results['requests_per_second']:.2f}")
        print(f"Avg Response Time: {load_results['avg_response_time']:.3f}s")
        print(f"P95 Response Time: {load_results['p95_response_time']:.3f}s")

        # Wait between tests
        time.sleep(5)

    # Save detailed results
    os.makedirs('tests/results', exist_ok=True)
    with open('tests/results/stress_test_results.json', 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n{'='*50}")
    print("Stress Test Summary")
    print(f"{'='*50}")

    for name, result in results.items():
        lr = result['load_test']
        print(f"{name:15} | Success: {lr['success_rate']:6.2%} | RPS: {lr['requests_per_second']:6.1f} | Avg: {lr['avg_response_time']:6.3f}s")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Run stress tests')
    parser.add_argument('--levels', help='Comma-separated test levels (light,medium,heavy,peak,extreme,stress,breaking)')
    args = parser.parse_args()

    run_stress_tests(args.levels)
