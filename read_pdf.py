from PyPDF2 import PdfReader

r = PdfReader('Hospice Symptom Tracking Guide.docx.pdf')
for i, p in enumerate(r.pages):
    print(f'--- Page {i+1} ---')
    print(p.extract_text())
