import json, re
from PyPDF2 import PdfReader

r = PdfReader('Hospice Symptom Tracking Guide.docx.pdf')
full = ''
for p in r.pages:
    full += p.extract_text()

# Try to extract the JSON schema portion
json_start = full.find('"symptoms"')
if json_start >= 0:
    # backtrack to find the opening brace
    brace = full.rfind('{', 0, json_start)
    rest = full[brace:]
    # Fix spacing issues from PDF extraction
    # The PDF puts spaces between characters
    cleaned = re.sub(r'\s+', ' ', rest)
    print("=== Cleaned JSON-ish text (first 500 chars) ===")
    print(cleaned[:500])
    print("\n\n")

# Just extract all symptom names from the "Complete Symptom List" section
# Look for patterns like: "name": "Symptom Name"
names = re.findall(r'"name"\s*:\s*"([^"]+)"', re.sub(r'\s+', ' ', full))
print(f"Found {len(names)} symptom names:")
for n in sorted(names):
    print(f"  - {n}")

# Also extract id, input_type, dropdown_type, options for each
ids = re.findall(r'"id"\s*:\s*"([^"]+)"', re.sub(r'\s+', ' ', full))
print(f"\nFound {len(ids)} symptom IDs:")
for sid in sorted(ids):
    print(f"  - {sid}")
