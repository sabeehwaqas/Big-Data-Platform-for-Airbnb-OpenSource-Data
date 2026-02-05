from cassandra.cluster import Cluster
import time
from concurrent.futures import ThreadPoolExecutor
import random

# Cassandra node IP addresses (external IPs)
CASSANDRA_NODES = ['34.88.149.182', '34.88.32.103', '34.88.174.120']  # Replace with your actual IPs
KEYSPACE = 'amazon'  # Your keyspace
QUERY = "SELECT count(*) FROM amazon.reviews_by_product"  # Query to run

# Connect to Cassandra (specific node)
def connect_to_cassandra(node_ip):
    try:
        # Connect to a single node
        cluster = Cluster([node_ip])  # Connect to one node (could be a random node from the list)
        session = cluster.connect(KEYSPACE)
        return session
    except Exception as e:
        print(f"Failed to connect to Cassandra node {node_ip}: {e}")
        return None

# Query Cassandra and measure the time taken
def query_cassandra(node_ip, query):
    start_time = time.time()  # Record the start time
    
    # Connect to the node and execute the query
    session = connect_to_cassandra(node_ip)
    if session:
        result = session.execute(query)
        end_time = time.time()  # Record the end time
        
        # Calculate the query response time
        query_time = end_time - start_time
        
        # Get the number of rows returned (for SELECT count(*))
        row_count = result.one()[0]  # The result of count(*) will be in the first column
        
        # Print the results
        print(f"Node {node_ip} query executed successfully.")
        print(f"Number of rows returned: {row_count}")
        print(f"Response time: {query_time:.4f} seconds.")
        
        session.shutdown()  # Close the session
        return query_time, row_count

# Function to run concurrent queries
def run_concurrent_queries(num_queries=100):
    # Use ThreadPoolExecutor to run queries concurrently on multiple nodes
    with ThreadPoolExecutor(max_workers=num_queries) as executor:
        # Submit the query for each node in the list, randomly selecting a node for each query
        futures = [executor.submit(query_cassandra, random.choice(CASSANDRA_NODES), QUERY) for _ in range(num_queries)]
        
        # Wait for all futures to complete and gather results
        for future in futures:
            future.result()  # Block until the future is done

def main():
    # Run concurrent queries on the Cassandra nodes
    run_concurrent_queries(num_queries=20)

if __name__ == '__main__':
    main()
