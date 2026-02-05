from cassandra.cluster import Cluster
from cassandra.policies import DCAwareRoundRobinPolicy
import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
import re
from collections import defaultdict
import statistics

# External IP addresses of Cassandra nodes
CASSANDRA_NODES = ['34.88.167.211', '34.88.93.8', '34.88.126.103']
KEYSPACE = 'amazon'  # Your keyspace
QUERY = "SELECT count(*) FROM amazon.reviews_by_product"  # Example query to run

# Set up logging to capture important data
logging.basicConfig(
    filename='performance.log',  # Log file name
    level=logging.INFO,  # Log level (INFO for performance info)
    format='%(asctime)s - %(message)s'  # Format for log entries
)

# Global cluster and session (reuse connections)
cluster = None
session = None

# Function to create a cluster connection once
def create_cluster():
    global cluster
    if cluster is None:
        cluster = Cluster(
            contact_points=CASSANDRA_NODES,
            load_balancing_policy=DCAwareRoundRobinPolicy(local_dc='datacenter1'),
            protocol_version=4
        )
    return cluster

# Connect to Cassandra once and reuse session
def connect_to_cassandra():
    global session
    try:
        if session is None:
            cluster = create_cluster()
            session = cluster.connect(KEYSPACE)
        return session
    except Exception as e:
        logging.error(f"Failed to connect to Cassandra: {e}")
        return None

# Query Cassandra and measure the time taken
def query_cassandra(query, query_number):
    start_time = time.time()
    
    try:
        # Use the shared session
        session = connect_to_cassandra()
        if session:
            result = session.execute(query)
            end_time = time.time()
            
            # Calculate the query response time
            query_time = end_time - start_time
            
            # Get the number of rows returned (for SELECT count(*))
            row_count = result.one()[0]
            
            # Log the results for success
            logging.info(f"Query {query_number} executed successfully with {row_count} rows in {query_time:.4f} seconds.")
            
            return {
                'success': True,
                'query_number': query_number,
                'response_time': query_time,
                'row_count': row_count,
                'error': None
            }
        else:
            logging.error(f"Query {query_number} failed: Could not connect to Cassandra.")
            return {
                'success': False,
                'query_number': query_number,
                'response_time': None,
                'row_count': None,
                'error': 'Connection failed'
            }
    except Exception as e:
        end_time = time.time()
        query_time = end_time - start_time
        logging.error(f"Query {query_number} failed with error: {e}")
        return {
            'success': False,
            'query_number': query_number,
            'response_time': query_time,
            'row_count': None,
            'error': str(e)
        }

# Function to run concurrent queries and collect results
def run_concurrent_queries(concurrency_level, total_queries):
    results = []
    start_time = time.time()
    
    logging.info(f"Starting {total_queries} queries with concurrency level: {concurrency_level}")
    
    # Use ThreadPoolExecutor to run queries concurrently
    with ThreadPoolExecutor(max_workers=concurrency_level) as executor:
        # Submit all queries
        futures = [executor.submit(query_cassandra, QUERY, i+1) for i in range(total_queries)]
        
        # Collect results as they complete
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
    
    end_time = time.time()
    total_time = end_time - start_time
    
    logging.info(f"Completed {total_queries} queries with concurrency level {concurrency_level} in {total_time:.4f} seconds.")
    
    return results, total_time

# Function to calculate metrics from results
def calculate_metrics(results, total_time, concurrency_level):
    total_queries = len(results)
    successful_queries = [r for r in results if r['success']]
    failed_queries = [r for r in results if not r['success']]
    
    # Success rate
    success_rate = (len(successful_queries) / total_queries * 100) if total_queries > 0 else 0
    
    # Response times for successful queries
    response_times = [r['response_time'] for r in successful_queries if r['response_time'] is not None]
    
    # Average response time
    avg_response_time = statistics.mean(response_times) if response_times else 0
    
    # Median response time
    median_response_time = statistics.median(response_times) if response_times else 0
    
    # Min and Max response time
    min_response_time = min(response_times) if response_times else 0
    max_response_time = max(response_times) if response_times else 0
    
    # Standard deviation
    std_dev_response_time = statistics.stdev(response_times) if len(response_times) > 1 else 0
    
    # Percentiles (95th and 99th)
    if response_times:
        sorted_times = sorted(response_times)
        p95_index = int(len(sorted_times) * 0.95)
        p99_index = int(len(sorted_times) * 0.99)
        p95_response_time = sorted_times[p95_index] if p95_index < len(sorted_times) else sorted_times[-1]
        p99_response_time = sorted_times[p99_index] if p99_index < len(sorted_times) else sorted_times[-1]
    else:
        p95_response_time = 0
        p99_response_time = 0
    
    # Throughput (queries per second)
    throughput = total_queries / total_time if total_time > 0 else 0
    
    # Error rate
    error_rate = (len(failed_queries) / total_queries * 100) if total_queries > 0 else 0
    
    # Error types breakdown
    error_types = defaultdict(int)
    for failure in failed_queries:
        error_msg = failure.get('error', 'Unknown error')
        error_types[error_msg] += 1
    
    metrics = {
        'concurrency_level': concurrency_level,
        'total_queries': total_queries,
        'successful_queries': len(successful_queries),
        'failed_queries': len(failed_queries),
        'success_rate': success_rate,
        'error_rate': error_rate,
        'avg_response_time': avg_response_time,
        'median_response_time': median_response_time,
        'min_response_time': min_response_time,
        'max_response_time': max_response_time,
        'std_dev_response_time': std_dev_response_time,
        'p95_response_time': p95_response_time,
        'p99_response_time': p99_response_time,
        'throughput': throughput,
        'total_time': total_time,
        'error_types': dict(error_types)
    }
    
    return metrics

# Function to print and log metrics
def print_metrics(metrics):
    print("\n" + "="*80)
    print(f"METRICS FOR CONCURRENCY LEVEL: {metrics['concurrency_level']}")
    print("="*80)
    print(f"Total Queries:           {metrics['total_queries']}")
    print(f"Successful Queries:      {metrics['successful_queries']}")
    print(f"Failed Queries:          {metrics['failed_queries']}")
    print(f"Success Rate:            {metrics['success_rate']:.2f}%")
    print(f"Error Rate:              {metrics['error_rate']:.2f}%")
    print("-"*80)
    print(f"Average Response Time:   {metrics['avg_response_time']:.4f} seconds")
    print(f"Median Response Time:    {metrics['median_response_time']:.4f} seconds")
    print(f"Min Response Time:       {metrics['min_response_time']:.4f} seconds")
    print(f"Max Response Time:       {metrics['max_response_time']:.4f} seconds")
    print(f"Std Dev Response Time:   {metrics['std_dev_response_time']:.4f} seconds")
    print(f"95th Percentile:         {metrics['p95_response_time']:.4f} seconds")
    print(f"99th Percentile:         {metrics['p99_response_time']:.4f} seconds")
    print("-"*80)
    print(f"Throughput:              {metrics['throughput']:.2f} queries/second")
    print(f"Total Execution Time:    {metrics['total_time']:.4f} seconds")
    print("-"*80)
    
    if metrics['error_types']:
        print("Error Breakdown:")
        for error_type, count in metrics['error_types'].items():
            print(f"  - {error_type}: {count} occurrences")
    else:
        print("No errors occurred.")
    
    print("="*80 + "\n")
    
    # Also log to file
    logging.info(f"METRICS - Concurrency: {metrics['concurrency_level']}, "
                 f"Success Rate: {metrics['success_rate']:.2f}%, "
                 f"Avg Response Time: {metrics['avg_response_time']:.4f}s, "
                 f"Throughput: {metrics['throughput']:.2f} q/s, "
                 f"Error Rate: {metrics['error_rate']:.2f}%")

# Function to write metrics to a summary file
def write_metrics_summary(all_metrics, output_file='performance_summary.txt'):
    with open(output_file, 'w') as f:
        f.write("="*80 + "\n")
        f.write("CASSANDRA QUERY PERFORMANCE SUMMARY\n")
        f.write("="*80 + "\n\n")
        
        # Summary table
        f.write(f"{'Concurrency':<15}{'Success Rate':<15}{'Avg Time (s)':<15}{'Throughput (q/s)':<20}{'Error Rate':<15}\n")
        f.write("-"*80 + "\n")
        
        for metrics in all_metrics:
            f.write(f"{metrics['concurrency_level']:<15}"
                   f"{metrics['success_rate']:<15.2f}"
                   f"{metrics['avg_response_time']:<15.4f}"
                   f"{metrics['throughput']:<20.2f}"
                   f"{metrics['error_rate']:<15.2f}\n")
        
        f.write("\n" + "="*80 + "\n\n")
        
        # Detailed metrics for each concurrency level
        for metrics in all_metrics:
            f.write(f"\nCONCURRENCY LEVEL: {metrics['concurrency_level']}\n")
            f.write("-"*80 + "\n")
            f.write(f"Total Queries:           {metrics['total_queries']}\n")
            f.write(f"Successful Queries:      {metrics['successful_queries']}\n")
            f.write(f"Failed Queries:          {metrics['failed_queries']}\n")
            f.write(f"Success Rate:            {metrics['success_rate']:.2f}%\n")
            f.write(f"Error Rate:              {metrics['error_rate']:.2f}%\n")
            f.write(f"Average Response Time:   {metrics['avg_response_time']:.4f} seconds\n")
            f.write(f"Median Response Time:    {metrics['median_response_time']:.4f} seconds\n")
            f.write(f"Min Response Time:       {metrics['min_response_time']:.4f} seconds\n")
            f.write(f"Max Response Time:       {metrics['max_response_time']:.4f} seconds\n")
            f.write(f"Std Dev Response Time:   {metrics['std_dev_response_time']:.4f} seconds\n")
            f.write(f"95th Percentile:         {metrics['p95_response_time']:.4f} seconds\n")
            f.write(f"99th Percentile:         {metrics['p99_response_time']:.4f} seconds\n")
            f.write(f"Throughput:              {metrics['throughput']:.2f} queries/second\n")
            f.write(f"Total Execution Time:    {metrics['total_time']:.4f} seconds\n")
            
            if metrics['error_types']:
                f.write("\nError Breakdown:\n")
                for error_type, count in metrics['error_types'].items():
                    f.write(f"  - {error_type}: {count} occurrences\n")
            
            f.write("\n" + "="*80 + "\n")

# Main function
def main():
    # Test different concurrency levels
    concurrency_levels = [10, 50, 100, 200, 500]  # Adjust based on your needs
    queries_per_level = 100  # Total queries to run at each concurrency level
    
    all_metrics = []
    
    logging.info("="*80)
    logging.info("Starting Cassandra performance testing with varying concurrency levels")
    logging.info("="*80)
    
    # Connect to Cassandra once at the start
    connect_to_cassandra()
    
    # Test each concurrency level
    for concurrency in concurrency_levels:
        print(f"\nTesting with concurrency level: {concurrency}")
        
        # Run queries
        results, total_time = run_concurrent_queries(concurrency, queries_per_level)
        
        # Calculate metrics
        metrics = calculate_metrics(results, total_time, concurrency)
        all_metrics.append(metrics)
        
        # Print metrics
        print_metrics(metrics)
        
        # Small delay between tests
        time.sleep(2)
    
    # Write summary to file
    write_metrics_summary(all_metrics)
    print(f"\nPerformance summary written to 'performance_summary.txt'")
    
    # Close connections
    if session:
        session.shutdown()
    if cluster:
        cluster.shutdown()
    
    logging.info("Performance testing completed successfully")
    logging.info("="*80)

if __name__ == '__main__':
    main()