from dotenv import load_dotenv
import os
from supabase import create_client

ROOT = os.path.dirname(__file__)
load_dotenv(os.path.join(ROOT, '.env'))

SUPABASE_URL = os.environ.get('SUPABASE_URL')
SUPABASE_KEY = os.environ.get('SUPABASE_KEY')

_client = None

def get_client():
    global _client
    if _client is None:
        if not SUPABASE_URL or not SUPABASE_KEY:
            raise RuntimeError('SUPABASE_URL and SUPABASE_KEY must be set in .env')
        _client = create_client(SUPABASE_URL, SUPABASE_KEY)
    return _client

# Convenience wrappers
def insert(table: str, row: dict):
    client = get_client()
    return client.table(table).insert(row).execute()

def select(
    table: str,
    query: str = '*',
    eq: dict | None = None,
    limit: int | None = None,
    order: str | None = None,
    desc: bool = False
):
    client = get_client()
    q = client.table(table).select(query)
    if eq:
        for k, v in eq.items():
            q = q.eq(k, v)
    if limit:
        q = q.limit(limit)
    if order:
        q = q.order(order, desc=desc)
    return q.execute()

def update(table: str, row: dict, eq: dict | None = None):
    client = get_client()
    q = client.table(table).update(row)
    if eq:
        for k, v in eq.items():
            q = q.eq(k, v)
    return q.execute()

def delete(table: str, eq: dict):
    client = get_client()
    q = client.table(table).delete()
    for k, v in eq.items():
        q = q.eq(k, v)
    return q.execute()
