from supabase_client import insert
import uuid
from datetime import datetime, timezone

team_id = str(uuid.uuid4())
team_doc = {
    "id": team_id,
    "patient_first_name": "TestPatient",
    "hospice_org_id": None,
    "nurse_line_number": None,
    "created_at": datetime.now(timezone.utc).isoformat()
}
res = insert('care_teams', team_doc)
print('res:', type(res))
try:
    print('data:', res.data)
    print('error:', res.error)
except Exception as e:
    print('exception reading res:', e)
