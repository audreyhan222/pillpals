# PillPals (PillPal)

A **Flutter** mobile app for medication routines, with **optional** **FastAPI** backend support, **Firebase** (Firestore & FCM), and on-device **ML Kit** text recognition for pill labels.

---

## What it does

PillPals helps people **remember to take medications on time**, track **daily completion**, and optionally connect **caregivers** to **elderly** users. Users can **scan prescription or bottle labels** with the camera; the app **extracts text locally**, parses key fields, and can call the backend to **refine** structured medication details from the OCR text. **Images are not uploaded** for the scan flow—only **text** is sent to the server when AI analysis is used.

---

## Features (by area)

### Roles & onboarding
- **Landing & role selection** — choose **elderly** vs **caregiver** (and related signup / login flows).
- **Session** — secure storage for tokens and role; routing guards for authenticated vs public screens.

### Elderly experience
- **Dashboard** — daily “Today’s pills” list with scheduled times, tap for details, and **mark as taken** (local completion + optional Firestore sync).
- **Tamagotchi-style pal** — pet expression and **happiness** react to reminders, missed doses, and completed doses.
- **Streaks & status** — streak UI and related Firestore-backed status (e.g. daily completion).
- **Scan medication** — camera capture → **Google ML Kit** OCR → optional **second pass** (label vs handwriting heuristics) → client-side parsing → **analysis screen** with editable name, dosage, instructions, and save to **Firestore** medication catalog (elderly path).
- **Local notifications** — escalating dose reminders (FCM infrastructure for broader push as configured).
- **Device calendar** — optional creation of calendar events when saving certain medication flows (where enabled).
- **OCR label library** — Firestore-backed **corrections** keyed by normalized OCR text so future scans can reuse your edits (not the image).

### Caregiver experience
- **Elderly selection** — pick a linked elderly user.
- **Patient detail** — view patient context and related actions (as implemented in-app).
- **Caregiver nudges** — Firestore-driven nudges surfaced as local notifications to the elderly user’s app (when configured).

### Text extraction & analysis
- **On-device OCR** — `google_mlkit_text_recognition` + image orientation handling; heuristics for **printed label** vs **handwriting** to improve crop/second pass.
- **Client parsing** — `PillDetailsParser` extracts name, dosage, instructions, intervals, and times from raw text.
- **Optional AI pass** — `POST /scan-medication` on the backend accepts **plain text** (not images) and returns structured fields (OpenAI when configured).
- **Label library** — saves **your corrected** name/dosage/instructions tied to a hash of the OCR text for reuse.

### Backend API (FastAPI)
- **Auth** — signup/login for users and caregivers (JWT-style flow as implemented).
- **Users & caregivers** — profiles, linking caregivers to elderly where applicable.
- **Medications & dose logging** — REST resources for medications, dose confirmation, history, insights (see `backend/app/main.py` and Swagger).
- **Push** — device token registration and test push routes.
- **Scan medication** — structured suggestion from OCR text for the app’s analysis step.
- **Firebase Admin** — optional Firestore user sync on signup when service account is configured.

---

## Tech stack

| Layer | Technology |
|--------|------------|
| App | Flutter (Dart 3), **go_router**, **provider**, **dio** |
| Local data / sync | **cloud_firestore**, **flutter_secure_storage** |
| OCR | **google_mlkit_text_recognition**, **image** |
| Push | **firebase_messaging**, **flutter_local_notifications** |
| Backend | **FastAPI**, **Pydantic**, OpenAI (for `/scan-medication` when env set) |
| Config | **flutter_dotenv** (`.env` in project), `API_BASE_URL` / `--dart-define` |

---

## Repository layout (high level)

```
pillpals/
├── lib/                 # Flutter app (screens, state, camera, Firestore, notifications, …)
├── backend/             # FastAPI service (see backend/README.md)
├── ios/, android/       # Platform projects
├── assets/pals/         # Pal sprite assets
├── .env                 # Local API keys / Firebase keys (not committed; use .env.example patterns)
└── pubspec.yaml
```

---

## Running the Flutter app

1. Install [Flutter](https://docs.flutter.dev/get-started/install) and a device or simulator.
2. From the repo root:
   ```bash
   flutter pub get
   ```
3. Configure **`.env`** at the project root (loaded as a Flutter asset per `pubspec.yaml`) with your Firebase and `API_BASE_URL` values as required by `lib/firebase_options.dart` and `lib/config/app_config.dart`.
4. Run:
   ```bash
   flutter run
   ```

---

## Running the backend (optional)

See **`backend/README.md`** for virtualenv, `pip install`, `.env` (including `FIREBASE_SERVICE_ACCOUNT_PATH` / OpenAI keys for scan-medication), and:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Interactive API docs: `http://localhost:8000/docs`.

---

## Privacy note (scan flow)

For the medication **scan** pipeline, **photos stay on the device** for processing; the backend receives **OCR text** when you use server-side analysis, not the image file. Firestore may store **corrected text fields** and metadata for the label library, not image blobs, for that feature set.

---

## License / status

Internal / pre-1.0; update this section when you publish a license or product name.
