## Plan: Add Home Care + Password Fields

Add two new inputs (home care services provider name, and create password) to the Step 2 onboarding UI (HospiceSetupScreen) using the existing styling patterns, and pass the collected values to Step 3 (CareAddressScreen) via constructor params.

**Steps**
1. Update state/controllers in Step 2 (HospiceSetupScreen)
   1. Add `TextEditingController _homeCareController` and `TextEditingController _passwordController` as fields in `_HospiceSetupScreenState`.
   2. Dispose them in `dispose()` alongside `_searchCtrl`.
2. Insert the UI snippet into Step 2 layout
   1. In `build()` inside the main `Column(children: [...])` of the `SingleChildScrollView`, insert the following blocks after the hospice selection/helper-text section and before the trailing spacing:
      - SizedBox spacing
      - Label: “Are you using any home care services?”
      - Container + TextField bound to `_homeCareController` (hint: provider name optional, prefix icon home_work)
      - Spacing
      - Label: “Create Password”
      - Container + TextField bound to `_passwordController` with `obscureText: true` (hint: secure password, prefix icon lock)
   2. Styling decisions to keep design consistent:
      - Use existing constants (`_borderColor`, `_deepPurple`, `_mutedPurple`) for colors.
      - Replace any new hard-coded label color (e.g., `Color(0xFF2E2540)`) with `_deepPurple` (or match the existing black label color used elsewhere on the screen), to avoid introducing new theme tokens.
3. Pass values to Step 3 (CareAddressScreen)
   1. Extend `CareAddressScreen` constructor to accept two new params:
      - `final String homeCareProviderName` (or similar)
      - `final String password`
      Decide whether these are `required` or optional with defaults; since only one call site exists today, `required` is safe.
   2. Update `_goNext()` in HospiceSetupScreen to pass:
      - `homeCareProviderName: _homeCareController.text.trim()`
      - `password: _passwordController.text` (don’t trim passwords)
4. Keep scope tight (no new UX beyond what you pasted)
   1. Do not add toggles, validators, confirm-password, or show/hide password unless explicitly requested.
   2. Do not wire password into Supabase auth yet (you only asked to pass it to the next screen).

**Relevant files**
- `lib/presentation/hospice_setup_screen.dart` — add controllers, dispose, insert Home Care + Password UI, pass values in `_goNext()`.
- `lib/presentation/care_address_screen.dart` — add new constructor fields to receive `homeCareProviderName` and `password` (even if unused for now).

**Verification**
1. Run `flutter analyze` to ensure constructor/field changes compile cleanly.
2. Run the app and navigate Setup (Step 1) → Hospice (Step 2):
   - Confirm both new fields render with the same container styling.
   - Type values, tap Continue.
3. Ensure app still reaches CareAddressScreen (Step 3) without runtime errors.
4. Optional: add a temporary debug print in Step 3 during manual testing only (remove before merge) if you need to confirm values arrived.

**Decisions**
- Home care is an optional text field only (no yes/no toggle).
- Continue forwards values to Step 3 only; no authentication or DB persistence is added in this change.
- Color tokens: prefer existing constants over introducing `Color(0xFF2E2540)`.
