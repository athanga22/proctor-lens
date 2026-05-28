# ProctorLens

A native iPadOS app that monitors test integrity in real time using the front camera and Apple's Vision framework — on-device analysis, no external AI services, and no raw video ever leaving the device.

Built as a portfolio project demonstrating the same technical surface as LockDown Browser for iPad: embedded web content, camera monitoring, session integrity, and a security mindset.

---

## What it does

A candidate launches the app, passes a mandatory camera gate, takes a quiz inside an embedded browser, and is monitored throughout. The app detects integrity violations, escalates them, and — if they pile up — ends the exam automatically. A reviewer dashboard then shows what happened, with a thumbnail of each flagged moment.

**Integrity signals detected:**
- **No face** present in frame
- **Multiple faces** present
- **Head turned away** (yaw or pitch beyond a configurable threshold)
- **Left the exam app** (backgrounding via home, app switcher, Control Center, notifications)

---

## App flow

```
  ┌────────────┐      ┌──────────────────┐      ┌──────────────┐
  │ Camera     │ pass │  Quiz (monitored) │ end  │  Dashboard   │
  │ Gate       │─────►│  WKWebView +      │─────►│  (review)    │
  │            │      │  live monitoring  │      │              │
  └────────────┘      └──────────────────┘      └──────────────┘
        │                      │
   deny │                 warn │ → terminate
        ▼                      ▼
  Hard block            Red banner, then
  (no quiz)             auto-end the exam
```

The quiz **never loads** unless the camera is confirmed active (real device) or explicitly in simulator demo mode. Permission denied is a hard block — exactly how a real proctoring system behaves.

---

## Architecture

```
┌──────────────────────────────── iPadOS App ────────────────────────────────┐
│                                                                             │
│  ContentView  (wires everything; owns the Gate → Quiz → Dashboard flow)     │
│      │                                                                      │
│      ├── CameraGateView ........ blocks entry until camera is authorized    │
│      │                                                                      │
│      ├── WebView (WKWebView) ... loads bundled quiz.html via a JS bridge    │
│      │                                                                      │
│      ├── CameraMonitor ......... AVFoundation, 1 frame / 2s, no video kept  │
│      │        │ frame                                                       │
│      │        ▼                                                             │
│      ├── IntegrityAnalyzer ..... Vision: returns the SET of violations seen │
│      │        │ Set<FlagType>     (VNDetectFaceRectanglesRequest, rev 3)    │
│      │        ▼                                                             │
│      ├── FlagCoalescer ......... collapses continuous detections into       │
│      │        │ new events        discrete "event started" flags            │
│      │        ├──────────────► SessionManager .. severity score + escalate  │
│      │        ├──────────────► SnapshotStore ... local-only thumbnail       │
│      │        └──────────────► FlagLogger ...... POST /flags (bearer token) │
│      │                                                                      │
│      │   scenePhase change (app left) ─────────► appBackgrounded flag       │
│      │                                                                      │
│      └── DashboardView ......... grouped flags + thumbnails + termination   │
│                                  banner; GET /sessions/{id}/flags           │
└─────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼  HTTP (local network)
┌──────────────────────── Backend (FastAPI + SQLite) ────────────────────────┐
│  POST /sessions ............ creates a session, issues a write token        │
│  POST /flags ............... ingest one flag (requires bearer token)        │
│  GET  /sessions/{id}/flags . list a session's flags (open, for reviewer)    │
│  GET  /health .............. liveness probe                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Module boundaries

| File | Responsibility |
|---|---|
| `ProctorLensApp.swift` | App entry point; loads RocketSim Connect in DEBUG (simulator camera) |
| `ContentView.swift` | Root view; owns the flow and wires all services |
| `CameraGateView.swift` | Pre-exam gate; blocks entry unless camera is authorized |
| `WebView.swift` | WKWebView wrapper + JS bridge for quiz-submit |
| `CameraMonitor.swift` | AVFoundation session; throttled frame sampling; publishes camera state |
| `IntegrityAnalyzer.swift` | Vision; reports the set of violations present per frame |
| `FlagCoalescer.swift` | Collapses continuous detections into discrete events |
| `SnapshotStore.swift` | Local-only thumbnail of each flagged moment |
| `SessionManager.swift` | Session lifecycle, weighted severity score, warn/terminate escalation |
| `FlagLogger.swift` | Creates an authenticated session; posts flags with a bearer token |
| `DashboardView.swift` | Read-only reviewer UI; thumbnails; termination banner |
| `Flag.swift` | `IntegrityFlag` model + `FlagType` enum (severity, raw values) |
| `quiz.html` | Bundled static quiz form |
| `backend/main.py` | FastAPI: session tokens, flag ingest, retrieval, SQLite persistence |
| `ProctorLensTests/` | XCTest: coalescing, escalation thresholds, flag types (15 tests) |

---

## The integrity model

**Coalescing.** Frames are sampled every 2 seconds, but a single continuous violation (looking away for 10s) should be *one* event, not five. `FlagCoalescer` tracks which violation types are currently active and emits a flag only on the transition from absent → present.

**Severity & escalation.** Each flag carries a weight, and the session accumulates a score:

| Violation | Severity |
|---|---|
| Left the exam app | 3 |
| Multiple faces | 2 |
| No face | 2 |
| Head turned away | 1 |

- At **4 points** → the candidate sees a red warning banner.
- At **8 points** → the exam ends automatically and the dashboard opens with a termination notice.

Thresholds are named constants in `SessionManager`, easy to tune.

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

API: `http://127.0.0.1:8765` · Interactive docs: `http://127.0.0.1:8765/docs`

### 2. Run the iOS app

1. Open `ProctorLens.xcodeproj` in Xcode.
2. Select an iPad simulator (e.g. **iPad Pro 13-inch**).
3. Press **⌘R**.
4. Allow camera access at the gate → take the quiz → submit (or get auto-terminated).
5. Review flags in the dashboard.

> **Real device:** set `backendBaseURL` in `FlagLogger.swift` to your Mac's LAN IP (e.g. `http://192.168.1.x:8765`). The front camera and Vision run natively — no extra setup.

### 3. Camera in the simulator (RocketSim)

The iOS Simulator has **no camera hardware**, and on recent Xcode its built-in camera virtualization (`FigCaptureSourceSimulator`) is unreliable. To get a live camera feed in the simulator, this project uses [RocketSim](https://www.rocketsim.app), which injects a virtual camera via **RocketSim Connect** (loaded in DEBUG from `ProctorLensApp.swift`).

1. Install RocketSim and open it.
2. In RocketSim → **Capture** tab → enable **Simulator Camera** and authorize Mac camera access.
3. Run the app — Vision now analyzes your real Mac camera feed.

**Without RocketSim**, the app falls back to **demo mode**: synthetic flags are generated so the full pipeline (coalescing → escalation → logging → dashboard) is still exercisable. Demo mode is clearly labelled with a `DEMO` badge.

> Vision face detection needs a Neural Engine, which the simulator lacks. The analyzer forces CPU compute (`MLComputeDevice`) so detection runs on the simulator's CPU. Face analysis is most reliable on a real device.

### 4. Tests

```bash
xcodebuild test -scheme ProctorLens \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch'
```

15 unit tests cover the coalescing logic, escalation thresholds, and flag-type contract.

### Regenerating the Xcode project

Source files are managed by [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding files via the CLI:

```bash
brew install xcodegen   # once
xcodegen generate
```

---

## Security

This is a proctoring app applying for a security-focused role, so security is treated as a first-class concern, not an afterthought.

### Authenticated writes

`POST /flags` was the obvious abuse vector — an open write endpoint lets anyone forge or inject flags for any session. The fix:

- `POST /sessions` issues a per-session bearer token.
- `POST /flags` requires `Authorization: Bearer <token>` matching the session, validated with a constant-time comparison (`secrets.compare_digest`).
- A forged flag with no/invalid token returns **401**.

Reads (`GET`) are left open for the demo reviewer; in production they would sit behind reviewer authentication.

### Data minimization

No raw camera frames or video ever leave the device — **only flag metadata** (`session_id`, `flag_type`, `timestamp`) is transmitted. The violation thumbnails shown in the dashboard are stored **locally only**, so the reviewer gets visual context without any imagery crossing the network.

### A deliberate abuse case: photo spoofing

**Scenario:** a candidate holds up a photograph of themselves.

**Why it defeats the current checks:** `VNDetectFaceRectanglesRequest` is a 2D detector. A clear, well-lit photo satisfies "one face present, centred" — yaw and pitch read near zero, so `noFace` and `headTurnedAway` never fire.

**Why this demo doesn't claim to solve it:** defeating photo spoofing requires *liveness* detection — blink detection, depth sensing (TrueDepth), or challenge-response ("turn left"). These are non-trivial and out of scope here. The limitation is documented rather than hidden — which is the point of an honest security writeup.

**How a production system would address it:** combine face detection with a liveness signal (depth where available, or randomized head-movement prompts that a static image can't satisfy).

### What iOS can and can't do

The app **detects** every time the candidate leaves the exam (backgrounding) and flags it. It cannot **prevent** leaving without kiosk mode (Guided Access / MDM Single-App Mode), which is out of scope. Being explicit about that boundary — detection vs. prevention — is itself part of the security mindset.

---

## Head pose vs. eye gaze

Vision's `VNFaceObservation` exposes **yaw** (left/right) and **pitch** (up/down) of the head. These are a practical proxy for "looking away": more than ~20° off-centre and attention is likely elsewhere.

This is **not** eye-gaze tracking — knowing where the eyes point *within* the head is a much harder problem Vision doesn't solve, and it's deliberately out of scope. Head pose is the honest, achievable signal.

---

## Tech stack

| Layer | Choice |
|---|---|
| App | Swift, SwiftUI |
| Embedded web | WKWebView + JS bridge |
| Camera | AVFoundation (no video stored) |
| Analysis | Vision (`VNDetectFaceRectanglesRequest` rev 3), on-device |
| Backend | FastAPI, Python 3.13 |
| Storage | SQLite via aiosqlite |
| Auth | Per-session bearer tokens |
| Tests | XCTest (15 tests) |
| Project gen | XcodeGen |
| Simulator camera | RocketSim Connect (DEBUG only) |
