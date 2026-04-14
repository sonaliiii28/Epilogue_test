import requests
import json

url = 'http://127.0.0.1:8000/api/care-teams'
body = {
    "patient_first_name": "TestPatient",
    "primary_caregiver_name": "Alice",
    "primary_caregiver_email": "alice@example.com"
}
try:
    r = requests.post(url, json=body, timeout=10)
    print('status', r.status_code)
    print(r.text)
except Exception as e:
    print('error', e)
