sudo docker exec -it cassandra-node-1 cqlsh

CREATE KEYSPACE IF NOT EXISTS amazon
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};

USE amazon;

DROP TABLE IF EXISTS amazon.reviews_by_product;
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
    PRIMARY KEY ((marketplace, product_id), review_date, review_id)
) WITH CLUSTERING ORDER BY (review_date DESC, review_id ASC);



USE energy_weather;
DESCRIBE TABLE bronze;


Partition by (city, zip) so each city/zip’s time-series stays together
Cluster by ts so range queries by time are fast