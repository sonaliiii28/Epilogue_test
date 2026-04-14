**Epilogue — Architecture & Developer Notes**

Overview
- **Purpose:** Lightweight care-team app (frontend React + backend FastAPI + Postgres/Supabase).
- **Repo layout:** Frontend in `frontend/`, backend in `backend/`, tests and tooling at project root.

API / Backend
- **Framework:** FastAPI (backend/server.py)
- **Auth:** Magic-link tokens + optional access PINs + JWT access tokens.
  - Magic link flow: `/auth/magic-link` accepts a magic token (and optional `pin`).
  - `create_access_token` produces JWTs; `get_current_member` is the dependency used to authenticate routes.
  - PINs are hashed (bcrypt-style) via `hash_pin`/`verify_pin` helpers; legacy hash upgrade performed on verification.
- **DB client:** Supabase wrapper functions: `sb_select`, `sb_insert`, `sb_update`, `sb_delete` (in backend codebase).

Key endpoints (non-exhaustive)
- Onboarding & auth: POST `/care-teams` (create team + primary member), POST `/auth/magic-link`, POST `/auth/set-pin`
- Members: POST `/members/invite`, POST `/admin/members`, GET `/members`, DELETE `/members/{member_id}`
- Medications: POST `/medications`, GET `/medications`
- Dose logs: POST `/dose-logs`, GET `/dose-logs` (optional medication_id query)
- Symptom events & triage: POST `/symptom-events`, GET `/symptom-events`, POST `/nurse-contact`
- Observations: POST `/observations`, GET `/observations`
- Moments: POST `/moments`, GET `/moments` (visibility varies by role)
- Care plan: GET `/care-plan`, PUT `/care-plan`
- Calendar: POST `/calendar-events`, GET `/calendar-events`

Database (summary)
- **Engine:** Postgres (Supabase)
- **Primary tables:**
  - `care_teams` — id, patient_first_name, hospice_org_id, nurse_line_number, created_at
  - `members` — id, care_team_id, name, email, role, is_admin, magic_link_token, access_pin, joined_at, last_active
  - `care_plans` — care_team_id, content fields, updated_at, updated_by_member_id
  - `medications` — id, care_team_id, name, dosing metadata, prn tags, created_at, created_by_member_id
  - `dose_logs` — id, care_team_id, medication_id, medication_name, dose_time, amount_given, who_gave, note, logged_by_member_id, editable_until
  - `symptom_events` — id, care_team_id, severity, symptoms[], event_time, created_by_member_id, editable_until
  - `nurse_contacts` — id, care_team_id, symptom_event_id, contact_method, status, attempted_at, attempted_by_member_id
  - `observations` — id, care_team_id, structured fields, created_at, created_by_member_id
  - `moments` — id, care_team_id, category, notes, visibility, created_at, created_by_member_id
  - `calendar_events` — id, care_team_id, date, title, notes, created_by_member_id
  - `check_ins`, `shift_notes`, `analytics_events` — operational/analytics tables

Frontend
- **Framework:** React (frontend/src)
- **Routing:** React Router via `useNavigate()` and conventional route filenames in `src/pages/`.
- **Primary pages/components modified or of interest:**
  - `src/pages/Landing.js` — public landing and onboarding entry; `Start Your Care Team` navigates to `/setup`.
  - `src/pages/Setup.js` — two-step onboarding: patient + caregiver info, then hospice selection (nurse line, contact cards).
  - `src/pages/Dashboard.js` — main app view; notification badges are red; emergency call card present.
  - `src/pages/Medications.js` — medication list and add-medication form with mobile-first layout.
  - UI atoms: many `src/components/ui/*` helpers (buttons, inputs, cards) used across pages.

UI tokens, fonts & styles
- **Fonts observed:** Cormorant Garamond / Lora / Playfair Display for headings; Inter / Lexend for UI/text.
- **Color notes:** Notification / emergency indicators use red (e.g. `#FF0000` used for badges/emergency states).
- **Breakpoints:** Mobile-first with rules observed for ~600px and ~960px in modified pages.
- **Styling approach:** Mix of inline styles in pages and Tailwind-inspired utility classes in original HTML designs converted to JSX inline/CSS blocks.

Dev / Run instructions
- Backend (local):
  - Ensure Python 3.10+ and venv active.
  - Install: `cd backend && pip install -r requirements.txt`
  - Required env vars (examples):
    - `SUPABASE_URL`, `SUPABASE_KEY` (for Supabase client),
    - `JWT_SECRET` (used to sign access tokens),
    - `FRONTEND_URL` (used when generating magic links)
  - Run server: `cd backend && uvicorn server:app --reload --port 8001`
- Frontend (local):
  - Node 16+ recommended.
  - `cd frontend && npm install`
  - `npm start` (runs dev server, typically on port 3000)
- Project helper scripts (Windows PowerShell present): `run-backend.ps1`, `run-frontend.ps1`, `run-all.ps1` at repo root.

Example requests
- Create care team (onboard primary caregiver):
  - curl -X POST http://127.0.0.1:8001/care-teams -H "Content-Type: application/json" -d '{"patient_first_name":"Sam","primary_caregiver_name":"Alex","primary_caregiver_email":"alex@example.com","nurse_line_number":"555-555-1212"}'
- Exchange magic token for access token:
  - curl -X POST "http://127.0.0.1:8001/auth/magic-link?token=<MAGIC_TOKEN>"

Testing & notes
- Unit/integration tests: see `backend/test_*.py` files and `tests/` folder. The repo also contains `backend_test.py` at root for scripted checks.
- Analytics: `track_analytics_event` writes to `analytics_events` without PII.
- Security: Magic links are single-token entries in `members.magic_link_token`; PINs are optional and stored hashed.

Next steps (suggested)
- Commit documentation and run the full stack locally to validate end-to-end flows.
- Add a short `ARCHITECTURE.md` section linking to `backend/supabase_schema.sql` for verbatim schema.
- Expand API reference with request/response examples for each endpoint if desired.

Contact
- For changes to onboarding flows or DB schema, update both `backend/supabase_schema.sql` and `backend/server.py` (models/endpoints).

---
Generated by the project assistant on the workspace snapshot.
