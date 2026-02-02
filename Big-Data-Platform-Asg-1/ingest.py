#!/usr/bin/env python3
import argparse
import csv
import io
import os
from typing import Dict, Iterable, List, Optional, Tuple

from google.cloud import storage
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider


def download_gcs_object(bucket: str, blob_name: str, project: Optional[str] = None) -> bytes:
    """
    Downloads a GCS object into memory and returns raw bytes.
    Uses ADC (Application Default Credentials).
    """
    client = storage.Client(project=project) if project else storage.Client()
    b = client.bucket(bucket)
    blob = b.blob(blob_name)
    if not blob.exists():
        raise FileNotFoundError(f"GCS object not found: gs://{bucket}/{blob_name}")
    return blob.download_as_bytes()


def parse_csv_bytes(data: bytes, encoding: str = "utf-8") -> Tuple[List[str], Iterable[Dict[str, str]]]:
    """
    Parses CSV bytes into (fieldnames, row iterator).
    Handles messy CSV by using Python's csv module with standard quoting rules.
    """
    text = data.decode(encoding, errors="replace")
    # Use newline='' to let csv module handle embedded newlines inside quoted fields.
    f = io.StringIO(text, newline="")
    reader = csv.DictReader(f)
    if reader.fieldnames is None:
        raise ValueError("CSV has no header row (fieldnames are missing).")
    fieldnames = [h.strip() for h in reader.fieldnames]
    # Yield rows with stripped keys; keep values as-is (may include commas/newlines in fields).
    def rows():
        for r in reader:
            out = {}
            for k, v in r.items():
                if k is None:
                    continue
                out[k.strip()] = v if v is not None else ""
            yield out
    return fieldnames, rows()


def parse_parquet_bytes(data: bytes):
    """
    Parses Parquet bytes -> pandas DataFrame (requires pyarrow).
    """
    import pandas as pd
    import pyarrow.parquet as pq
    import pyarrow as pa

    table = pq.read_table(pa.BufferReader(data))
    return table.to_pandas()


def cassandra_connect(
    hosts: List[str],
    port: int,
    username: Optional[str] = None,
    password: Optional[str] = None,
):
    """
    Connect to Cassandra cluster.
    If username/password are provided, uses PlainTextAuthProvider.
    """
    auth_provider = None
    if username and password:
        auth_provider = PlainTextAuthProvider(username=username, password=password)

    cluster = Cluster(contact_points=hosts, port=port, auth_provider=auth_provider)
    session = cluster.connect()
    return cluster, session


def ensure_keyspace(session, keyspace: str, rf: int = 3):
    session.execute(
        f"""
        CREATE KEYSPACE IF NOT EXISTS {keyspace}
        WITH replication = {{'class': 'SimpleStrategy', 'replication_factor': {rf}}}
        """
    )


def ensure_table_text(session, keyspace: str, table: str, columns: List[str], pk: str):
    """
    Creates a simple "bronze" table where all columns are TEXT.
    pk is either:
      - 'id' (single column PK), or
      - '(col1, col2)' for composite partition key, optionally with clustering columns.
    Example pk strings:
      - 'id'
      - '((city, zip), ts)'
    """
    # Cassandra identifiers should be lower + underscores. We'll keep exactly what you pass.
    col_defs = ",\n  ".join([f"{c} text" for c in columns])
    session.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {keyspace}.{table} (
          {col_defs},
          PRIMARY KEY ({pk})
        )
        """
    )


def insert_rows_text(
    session,
    keyspace: str,
    table: str,
    columns: List[str],
    rows: Iterable[Dict[str, str]],
    batch_size: int = 200,
):
    """
    Inserts rows using a prepared statement.
    Treats missing fields as empty string.
    """
    cols_sql = ", ".join(columns)
    qmarks = ", ".join(["?"] * len(columns))
    stmt = session.prepare(f"INSERT INTO {keyspace}.{table} ({cols_sql}) VALUES ({qmarks})")

    # For speed, use execute_concurrent_with_args if available.
    try:
        from cassandra.concurrent import execute_concurrent_with_args
        concurrent = True
    except Exception:
        concurrent = False

    buffer = []
    total = 0

    def flush(buf):
        nonlocal total
        if not buf:
            return
        if concurrent:
            execute_concurrent_with_args(session, stmt, buf, concurrency=50, raise_on_first_error=True)
        else:
            for args in buf:
                session.execute(stmt, args)
        total += len(buf)
        print(f"Inserted {total} rows")

    for r in rows:
        args = []
        for c in columns:
            v = r.get(c, "")
            # Cassandra PK columns cannot be null; keep empty string instead of None.
            if v is None:
                v = ""
            args.append(str(v))
        buffer.append(tuple(args))
        if len(buffer) >= batch_size:
            flush(buffer)
            buffer = []

    flush(buffer)


def main():
    ap = argparse.ArgumentParser(description="Load a GCS object (CSV/Parquet) into Cassandra.")
    ap.add_argument("--project", default=None, help="GCP project (optional if ADC already has it).")
    ap.add_argument("--bucket", required=True, help="GCS bucket name.")
    ap.add_argument("--blob", required=True, help="GCS object path, e.g. landing/raw/listings-6.csv")

    ap.add_argument("--cassandra-hosts", default="10.0.0.10,10.0.0.11,10.0.0.12")
    ap.add_argument("--cassandra-port", type=int, default=9042)
    ap.add_argument("--cassandra-user", default=None)
    ap.add_argument("--cassandra-pass", default=None)

    ap.add_argument("--keyspace", required=True)
    ap.add_argument("--table", required=True)
    ap.add_argument("--primary-key", required=True, help="Example: id  OR  ((city, zip), ts)")

    ap.add_argument("--encoding", default="utf-8")
    ap.add_argument("--batch-size", type=int, default=200)

    # If provided, we create table with these columns. Otherwise, we infer from CSV header / parquet columns.
    ap.add_argument("--columns", default=None, help="Comma-separated columns list (optional).")

    args = ap.parse_args()

    data = download_gcs_object(args.bucket, args.blob, project=args.project)
    ext = os.path.splitext(args.blob.lower())[1]

    if ext == ".parquet":
        df = parse_parquet_bytes(data)
        inferred_cols = list(df.columns)
        rows = ( {c: ("" if df.iloc[i][c] is None else df.iloc[i][c]) for c in inferred_cols}
                 for i in range(len(df)) )
        columns = inferred_cols
    else:
        columns, rows = parse_csv_bytes(data, encoding=args.encoding)

    # Override columns if user provided
    if args.columns:
        columns = [c.strip() for c in args.columns.split(",") if c.strip()]

    hosts = [h.strip() for h in args.cassandra_hosts.split(",") if h.strip()]
    cluster, session = cassandra_connect(
        hosts=hosts,
        port=args.cassandra_port,
        username=args.cassandra_user,
        password=args.cassandra_pass,
    )

    try:
        ensure_keyspace(session, args.keyspace, rf=3)
        ensure_table_text(session, args.keyspace, args.table, columns=columns, pk=args.primary_key)
        session.set_keyspace(args.keyspace)

        insert_rows_text(
            session,
            keyspace=args.keyspace,
            table=args.table,
            columns=columns,
            rows=rows,
            batch_size=args.batch_size,
        )
        print("Done.")
    finally:
        session.shutdown()
        cluster.shutdown()


if __name__ == "__main__":
    main()
