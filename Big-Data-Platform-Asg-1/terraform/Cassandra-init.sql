sudo docker exec -it cassandra-node-1 cqlsh

CREATE KEYSPACE IF NOT EXISTS energy_weather
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};

USE energy_weather;

CREATE TABLE IF NOT EXISTS bronze (
  city text,
  zip text,
  ts timestamp,
  egridregion text,
  temperaturef int,
  humidity int,
  data_availability_weather int,
  wetbulbtemperaturef double,
  coal bigint,
  hydro bigint,
  naturalgas bigint,
  nuclear bigint,
  other bigint,
  petroleum bigint,
  solar bigint,
  wind bigint,
  data_availability_energy int,
  onsitewuefixedapproach double,
  onsitewuefixedcoldwater double,
  offsitewue double,
  PRIMARY KEY ((city, zip), ts)
) WITH CLUSTERING ORDER BY (ts ASC);


USE energy_weather;
DESCRIBE TABLE bronze;


Partition by (city, zip) so each city/zip’s time-series stays together
Cluster by ts so range queries by time are fast