#!/usr/bin/env python3
import docker
import time
import json
import matplotlib.pyplot as plt
from datetime import datetime
import threading
import os

class ResourceMonitor:
    def __init__(self, containers=['nginx_proxy', 'redis', 'backend_server_1', 'backend_server_2', 'backend_server_3']):
        self.docker_client = docker.from_env()
        self.containers = containers
        self.monitoring = False
        self.data = {container: {'cpu': [], 'memory': [], 'timestamps': []} for container in containers}

    def start_monitoring(self, duration=300, interval=1):
        """Monitor resources for specified duration"""
        self.monitoring = True
        start_time = time.time()

        while self.monitoring and (time.time() - start_time) < duration:
            timestamp = datetime.now()

            for container_name in self.containers:
                try:
                    container = self.docker_client.containers.get(container_name)
                    if container.status != 'running':
                        continue

                    stats = container.stats(stream=False)

                    # CPU calculation - handle missing fields gracefully
                    try:
                        cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - \
                                   stats['precpu_stats']['cpu_usage']['total_usage']
                        system_delta = stats['cpu_stats']['system_cpu_usage'] - \
                                      stats['precpu_stats']['system_cpu_usage']

                        # Handle different Docker API versions
                        if 'percpu_usage' in stats['cpu_stats']['cpu_usage']:
                            num_cpus = len(stats['cpu_stats']['cpu_usage']['percpu_usage'])
                        else:
                            num_cpus = stats['cpu_stats'].get('online_cpus', 1)

                        if system_delta > 0:
                            cpu_percent = (cpu_delta / system_delta) * num_cpus * 100
                        else:
                            cpu_percent = 0.0

                    except (KeyError, ZeroDivisionError):
                        # Skip this measurement if data is incomplete
                        continue

                    # Memory calculation
                    try:
                        memory_usage = stats['memory_stats']['usage'] / (1024 * 1024)  # MB
                    except KeyError:
                        continue

                    self.data[container_name]['cpu'].append(cpu_percent)
                    self.data[container_name]['memory'].append(memory_usage)
                    self.data[container_name]['timestamps'].append(timestamp)

                except Exception:
                    # Container disappeared or other error - silently continue
                    continue

            time.sleep(interval)

    def stop_monitoring(self):
        self.monitoring = False

    def save_data(self, filename='resource_monitoring.json'):
        # Convert timestamps to strings for JSON serialization
        json_data = {}
        for container, data in self.data.items():
            json_data[container] = {
                'cpu': data['cpu'],
                'memory': data['memory'],
                'timestamps': [ts.isoformat() for ts in data['timestamps']]
            }

        with open(filename, 'w') as f:
            json.dump(json_data, f, indent=2)

        print(f'Data saved to {filename}')

    def plot_resources(self):
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8))

        for container_name in self.containers:
            if self.data[container_name]['timestamps']:
                ax1.plot(self.data[container_name]['timestamps'],
                        self.data[container_name]['cpu'],
                        label=container_name)
                ax2.plot(self.data[container_name]['timestamps'],
                        self.data[container_name]['memory'],
                        label=container_name)

        ax1.set_title('CPU Usage Over Time')
        ax1.set_ylabel('CPU %')
        ax1.legend()
        ax1.grid(True)

        ax2.set_title('Memory Usage Over Time')
        ax2.set_ylabel('Memory (MB)')
        ax2.set_xlabel('Time')
        ax2.legend()
        ax2.grid(True)

        if os.path.exists('tests/results/resource_usage.png'):
            os.remove('tests/results/resource_usage.png')

        plt.tight_layout()
        plt.savefig('tests/results/resource_usage.png', dpi=300, bbox_inches='tight')
        plt.show()

# Usage example
if __name__ == "__main__":
    monitor = ResourceMonitor()

    # Start monitoring in background
    monitor_thread = threading.Thread(target=monitor.start_monitoring, args=(60, 1))
    monitor_thread.start()

    # Your load test would run here
    time.sleep(60)

    monitor.stop_monitoring()
    monitor_thread.join()
    monitor.save_data()
    monitor.plot_resources()
