import json, re
from PyPDF2 import PdfReader

r = PdfReader('Hospice Symptom Tracking Guide.docx.pdf')
full = ''
for p in r.pages:
    full += p.extract_text()

cleaned = re.sub(r'\s+', ' ', full)

# Extract the JSON block
json_start = cleaned.find('{ "symptoms"')
# Find the matching closing bracket
depth = 0
end = json_start
for i, c in enumerate(cleaned[json_start:]):
    if c == '{': depth += 1
    elif c == '}': depth -= 1
    if depth == 0:
        end = json_start + i + 1
        break

json_text = cleaned[json_start:end]

try:
    data = json.loads(json_text)
    for s in data['symptoms']:
        sid = s.get('id', '?')
        name = s.get('name', '?')
        itype = s.get('input_type', '?')
        dtype = s.get('dropdown_type', '')
        opts = s.get('options', [])
        fields = s.get('fields', [])
        desc = s.get('description', '')
        
        print(f"ID: {sid}")
        print(f"  Name: {name}")
        print(f"  Type: {itype}")
        if dtype: print(f"  Dropdown Type: {dtype}")
        if opts: print(f"  Options: {opts}")
        if desc: print(f"  Description: {desc}")
        if fields:
            for f in fields:
                print(f"  Field: {f}")
        print()
except json.JSONDecodeError as e:
    print(f"JSON parse error: {e}")
    print("JSON text (last 200 chars):", json_text[-200:])
