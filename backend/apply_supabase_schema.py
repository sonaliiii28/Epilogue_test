"""
Apply `supabase_schema.sql` to the local Supabase Postgres DB using psycopg.
Usage: python apply_supabase_schema.py
Reads DB URL from env var `DATABASE_URL` or uses default local URL.
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).parent
SQL_FILE = ROOT / 'supabase_schema.sql'

def main():
    import psycopg

    db_url = os.environ.get('DATABASE_URL', 'postgresql://postgres:postgres@127.0.0.1:54322/postgres')
    if not SQL_FILE.exists():
        print('schema file not found:', SQL_FILE)
        sys.exit(1)

    with open(SQL_FILE, 'r', encoding='utf8') as f:
        sql = f.read()

    print('Connecting to', db_url)
    with psycopg.connect(db_url) as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            print('Executing schema...')
            cur.execute(sql)
            print('Schema applied successfully')

if __name__ == '__main__':
    main()
