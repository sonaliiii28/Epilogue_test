import psycopg
conn = psycopg.connect('postgresql://postgres:postgres@127.0.0.1:54322/postgres')
cur = conn.cursor()
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name")
rows = cur.fetchall()
print(f'Tables found: {len(rows)}')
for r in rows:
    print(f'  - {r[0]}')
conn.close()
print('Database is working!')
