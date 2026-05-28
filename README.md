# ProctorLens

A native iPadOS app that monitors test integrity in real time using the front camera and Apple's Vision framework — no external AI services, no raw video leaving the device.

Built as a portfolio project demonstrating the same technical surface as LockDown Browser for iPad: embedded web content, camera monitoring, session integrity, and a security mindset.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                     iPadOS App                      │
│                                                     │
│  ContentView                                        │
│     │                                               │
│     ├── WebView (WKWebView)                         │
│     │      └── quiz.html (bundled static quiz)      │
│     │                                               │
│     ├── CameraMonitor (AVFoundation)                │
│     │      └── samples 1 frame / 2 s (no storage)  │
│     │                                               │
│     ├── IntegrityAnalyzer (Vision framework)        │
│     │      ├── VNDetectFaceLandmarksRequest         │
│     │      ├── Check 1: no face present             │
│     │      ├── Check 2: multiple faces              │
│     │      └── Check 3: yaw/pitch > 0.35 rad        │
│     │                                               │
│     ├── FlagLogger (URLSession)                     │
│     │      └── POST /flags  →  backend              │
│     │                                               │
│     └── DashboardView                               │
│            └── GET /sessions/{id}/flags  →  backend │
└─────────────────────────────────────────────────────┘
                          │
                          ▼ HTTP (local network)
┌─────────────────────────────────────────────────────┐
│               Backend (FastAPI + SQLite)             │
│                                                     │
│  POST /flags               — ingest one flag        │
│  GET  /sessions/{id}/flags — list session flags     │
│  GET  /health              — liveness probe         │
└─────────────────────────────────────────────────────┘
```

### Module boundaries

| File | Responsibility |
|---|---|
| `ProctorLensApp.swift` | App entry point |
| `ContentView.swift` | Root view; wires all services together |
| `WebView.swift` | WKWebView wrapper + JS bridge for quiz-submit events |
| `CameraMonitor.swift` | AVFoundation session; throttled frame sampling |
| `IntegrityAnalyzer.swift` | Vision requests; three integrity checks |
| `FlagLogger.swift` | Fire-and-forget POST to the backend |
| `SessionManager.swift` | Session ID, start/stop, in-memory flag list |
| `DashboardView.swift` | Read-only reviewer UI; fetches from backend |
| `Flag.swift` | `IntegrityFlag` model + `FlagType` enum |
| `quiz.html` | Bundled static quiz form |
| `backend/main.py` | FastAPI app with two endpoints and SQLite persistence |

---

## Running the project

### 1. Start the backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8765 --reload
```

The API will be live at `http://127.0.0.1:8765`.  
Interactive docs: `http://127.0.0.1:8765/docs`

### 2. Run the iOS app in Xcode

1. Open `ProctorLens.xcodeproj` in Xcode.
2. Select the **iPad Pro 13-inch (M5)** simulator (or any iPad simulator).
3. Press **⌘R** to build and run.
4. The quiz loads automatically. Answer the questions and tap **Submit**.
5. The dashboard appears and shows any flags captured during the session.

> **Real device**: change `backendBaseURL` in `FlagLogger.swift` from `127.0.0.1` to your Mac's LAN IP (e.g. `192.168.1.x`).

### 3. Regenerating the Xcode project (optional)

If you add new Swift files via the CLI, re-run:

```bash
brew install xcodegen   # once
xcodegen generate
```

---

## Head pose vs. eye gaze

Vision's `VNFaceObservation` exposes **yaw** (left/right rotation) and **pitch** (up/down tilt) of the head. These are a practical proxy for "looking away": if the head turns more than ~20° off-centre, attention is likely elsewhere.

What this is **not**: eye-gaze tracking. True gaze requires knowing where the eyeballs point *within* the head — a significantly harder problem that Vision does not solve and that is explicitly out of scope for v1.

---

## Security note — one deliberate abuse case

**Scenario**: a test-taker holds up a photograph of themselves in front of the camera.

**Why it would fool the current v1**: `VNDetectFaceLandmarksRequest` is a 2D detector. A high-quality, well-lit photo of a face satisfies the "one face present, centred" check. Yaw and pitch read near zero. The `noFace` and `headTurnedAway` checks never fire.

**Why v1 does not claim to solve it**: defeating photo spoofing requires liveness detection — blink detection, depth sensing, or challenge-response (e.g. "turn left"). These are non-trivial and explicitly listed as out of scope in the PRD. The limitation is acknowledged here rather than hidden.

**How a production system would address it**: combine face landmarks with a liveness model (Apple's `VNDetectFaceRectanglesRequest` + depth via TrueDepth where available), or require periodic head-movement prompts that are hard to spoof with a static image.

---

## Tech stack

| Layer | Choice |
|---|---|
| App | Swift 5.9, SwiftUI |
| Embedded web | WKWebView + JS bridge |
| Camera | AVFoundation (no video stored) |
| Analysis | Vision framework, on-device |
| Backend | FastAPI 0.115, Python 3.13 |
| Storage | SQLite via aiosqlite |
| Project gen | XcodeGen 2.x |
