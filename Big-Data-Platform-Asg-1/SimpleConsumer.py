from cassandra.cluster import Cluster
import time
from concurrent.futures import ThreadPoolExecutor

# Cassandra node IP address (external IP)
#CASSANDRA_NODES = ['34.88.149.182'] # List of Cassandra node IPs (use actual IPs)
#CASSANDRA_NODES = ['34.88.149.182', '34.88.32.103']
CASSANDRA_NODES = ['34.88.167.211', '34.88.93.8', '34.88.126.103']
KEYSPACE = 'amazon'  # Your keyspace
QUERY = "SELECT count(*) FROM amazon.reviews_by_product"  # Example query to run

# Connect to Cassandra (specific nodes)
def connect_to_cassandra(node_ip):
    try:
        cluster = Cluster([node_ip])  # Connect to a single node (could be a random node from the list)
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
def run_concurrent_queries():
    # Use ThreadPoolExecutor to run queries concurrently on multiple nodes
    with ThreadPoolExecutor(max_workers=len(CASSANDRA_NODES)) as executor:
        # Submit the query for each node in the list
        futures = [executor.submit(query_cassandra, node_ip, QUERY) for node_ip in CASSANDRA_NODES]
        
        # Wait for all futures to complete and gather results
        for future in futures:
            future.result()  # Block until the future is done

def main():
    # Run concurrent queries on the Cassandra nodes
    run_concurrent_queries()

if __name__ == '__main__':
    main()
