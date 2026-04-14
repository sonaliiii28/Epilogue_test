"""Run the ALTER TABLE migration for medications table."""
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / '.env')

import psycopg

db = os.environ.get('DATABASE_URL', 'postgresql://postgres:postgres@127.0.0.1:54322/postgres')

# Connect as supabase_admin (table owner) to run ALTER TABLE
admin_db = db.replace('postgres:postgres@', 'supabase_admin:postgres@')

print('Connecting to', admin_db)
conn = psycopg.connect(admin_db)
conn.autocommit = True
cur = conn.cursor()

try:
    cur.execute('ALTER TABLE medications ADD COLUMN IF NOT EXISTS notes text')
    cur.execute('ALTER TABLE medications ADD COLUMN IF NOT EXISTS deprescribed_at timestamptz')
    print('Migration successful!')
    
    # Verify columns exist
    cur.execute("""
        SELECT column_name, data_type 
        FROM information_schema.columns 
        WHERE table_name = 'medications' 
        AND column_name IN ('notes', 'deprescribed_at')
        ORDER BY column_name
    """)
    for row in cur.fetchall():
        print(f'  Column: {row[0]} ({row[1]})')
except Exception as e:
    print(f'Error: {e}')

cur.close()
conn.close()
