from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

# Cassandra node IP addresses (use the external IP addresses of your nodes)
CASSANDRA_NODES = ['34.88.167.211']  #<----------------# Replace with actual IPs
KEYSPACE = 'amazon'  # Your keyspace name

# Connect to Cassandra and execute CQL commands
def execute_cql_commands():
    try:
        # Connect to Cassandra cluster
        cluster = Cluster(CASSANDRA_NODES)
        session = cluster.connect()

        # Create the keyspace if it doesn't exist
        create_keyspace = """
        CREATE KEYSPACE IF NOT EXISTS amazon 
        WITH replication = {'class': 'NetworkTopologyStrategy', 'replication_factor': 3};
        """
        session.execute(create_keyspace)
        print("Keyspace created or already exists.")

        # Use the 'amazon' keyspace
        session.set_keyspace(KEYSPACE)
        print(f"Using keyspace: {KEYSPACE}")

        # Drop the existing 'reviews_by_product' table if it exists
        drop_table = "DROP TABLE IF EXISTS amazon.reviews_by_product;"
        session.execute(drop_table)
        print("Dropped table 'reviews_by_product' if it existed.")

        # Create the 'reviews_by_product' table
        create_table = """
        CREATE TABLE IF NOT EXISTS amazon.reviews_by_product (
            marketplace text,
            product_id text,
            review_date date,
            review_id text,
            customer_id bigint,
            product_parent bigint,
            product_title text,
            product_category text,
            star_rating int,
            helpful_votes int,
            total_votes int,
            vine text,
            verified_purchase text,
            review_headline text,
            review_body text,
            PRIMARY KEY ((marketplace, product_id, review_date), review_id)
        ) WITH CLUSTERING ORDER BY (review_id ASC);
        """
        session.execute(create_table)
        print("Table 'reviews_by_product' created successfully.")

        # Close the connection
        cluster.shutdown()

    except Exception as e:
        print(f"Error executing CQL commands: {e}")

if __name__ == '__main__':
    execute_cql_commands()
