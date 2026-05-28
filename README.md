# ProctorLens

A native iPadOS app that monitors test integrity in real time. It loads a quiz in an embedded browser and watches the test-taker through the front camera, detecting integrity violations on-device with Apple's Vision framework. Analysis runs locally, no external AI services are used, and no raw video leaves the device.

## What it does

A candidate launches the app, passes a mandatory camera gate, takes a quiz inside an embedded browser, and is monitored throughout. The app detects integrity violations, escalates them, and ends the exam automatically if they accumulate past a threshold. A reviewer dashboard then shows what happened, including a thumbnail of each flagged moment.

Integrity signals detected:

- No face present in frame
- Multiple faces present
- Head turned away (yaw or pitch beyond a configurable threshold)
- Left the exam app (backgrounding via home, app switcher, Control Center, or a notification)

## App flow

```
  ┌────────────┐  pass  ┌───────────────────┐  end   ┌──────────────┐
  │ Camera     │ ─────► │ Quiz (monitored)  │ ─────► │  Dashboard   │
  │ Gate       │        │ WKWebView +       │        │  (review)    │
  │            │        │ live monitoring   │        │              │
  └────────────┘        └───────────────────┘        └──────────────┘
        │                        │
   deny │                   warn │ then terminate
        ▼                        ▼
   Hard block              Red banner, then
   (no quiz)               auto-end the exam
```

The quiz never loads unless the camera is confirmed active (on a real device) or explicitly in simulator demo mode. Denied permission is a hard block.

## Architecture

```
┌──────────────────────────────── iPadOS App ────────────────────────────────┐
│                                                                             │
│  ContentView (owns the Gate -> Quiz -> Dashboard flow, wires services)      │
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
│      │        ├──────────────► SessionManager .. severity score, escalate   │
│      │        ├──────────────► SnapshotStore ... local-only thumbnail       │
│      │        └──────────────► FlagLogger ...... POST /flags (bearer token) │
│      │                                                                      │
│      │   scenePhase change (app left) ─────────► appBackgrounded flag       │
│      │                                                                      │
│      └── DashboardView ......... grouped flags, thumbnails, termination     │
│                                  banner; GET /sessions/{id}/flags           │
└─────────────────────────────────────────────────────────────────────────────┘
                          │
                          ▼  HTTP (local network)
┌──────────────────────── Backend (FastAPI + SQLite) ────────────────────────┐
│  POST /sessions ............ creates a session, issues a write token        │
│  POST /flags ............... ingest one flag (requires bearer token)        │
│  GET  /sessions/{id}/flags . list a session's flags                         │
│  GET  /health .............. liveness probe                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Module boundaries

| File | Responsibility |
|---|---|
| `ProctorLensApp.swift` | App entry point; loads RocketSim Connect in DEBUG for simulator camera |
| `ContentView.swift` | Root view; owns the flow and wires all services |
| `CameraGateView.swift` | Pre-exam gate; blocks entry unless the camera is authorized |
| `WebView.swift` | WKWebView wrapper and JS bridge for quiz submission |
| `CameraMonitor.swift` | AVFoundation session; throttled frame sampling; publishes camera state |
| `IntegrityAnalyzer.swift` | Vision; reports the set of violations present per frame |
| `FlagCoalescer.swift` | Collapses continuous detections into discrete events |
| `SnapshotStore.swift` | Local-only thumbnail of each flagged moment |
| `SessionManager.swift` | Session lifecycle, weighted severity score, warn and terminate escalation |
| `FlagLogger.swift` | Creates an authenticated session; posts flags with a bearer token |
| `DashboardView.swift` | Read-only reviewer UI; thumbnails; termination banner |
| `Flag.swift` | `IntegrityFlag` model and `FlagType` enum (severity, raw values) |
| `quiz.html` | Bundled static quiz form |
| `backend/main.py` | FastAPI: session tokens, flag ingest, retrieval, SQLite persistence |
| `ProctorLensTests/` | XCTest: coalescing, escalation thresholds, flag types (15 tests) |

## Integrity model

Coalescing. Frames are sampled every 2 seconds, but a single continuous violation (looking away for 10 seconds) should be one event, not five. `FlagCoalescer` tracks which violation types are currently active and emits a flag only on the transition from absent to present.

Severity and escalation. Each flag carries a weight, and the session accumulates a score:

| Violation | Severity |
|---|---|
| Left the exam app | 3 |
| Multiple faces | 2 |
| No face | 2 |
| Head turned away | 1 |

At 4 points the candidate sees a red warning banner. At 8 points the exam ends automatically and the dashboard opens with a termination notice. Thresholds are named constants in `SessionManager` and are easy to tune.

## Running the project

### 1. Start the backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8765 --reload
```

API: `http://127.0.0.1:8765`. Interactive docs: `http://127.0.0.1:8765/docs`.

### 2. Run the iOS app

1. Open `ProctorLens.xcodeproj` in Xcode.
2. Select an iPad simulator (for example, iPad Pro 13-inch).
3. Press Command-R.
4. Allow camera access at the gate, take the quiz, and submit (or get auto-terminated).
5. Review flags in the dashboard.

On a real device, set `backendBaseURL` in `FlagLogger.swift` to your Mac's LAN IP (for example, `http://192.168.1.x:8765`). The front camera and Vision run natively with no extra setup.

### 3. Camera in the simulator (RocketSim)

The iOS Simulator has no camera hardware, and on recent Xcode versions its built-in camera virtualization (`FigCaptureSourceSimulator`) is unreliable. To get a live camera feed in the simulator, this project uses [RocketSim](https://www.rocketsim.app), which injects a virtual camera through RocketSim Connect (loaded in DEBUG from `ProctorLensApp.swift`).

1. Install RocketSim and open it.
2. In RocketSim, go to the Capture tab, enable Simulator Camera, and authorize Mac camera access.
3. Run the app. Vision now analyzes the live Mac camera feed.

Without RocketSim, the app falls back to demo mode: synthetic flags are generated so the full pipeline (coalescing, escalation, logging, dashboard) is still exercisable. Demo mode is labelled with a DEMO badge.

Vision face detection needs a Neural Engine, which the simulator lacks. The analyzer forces CPU compute (`MLComputeDevice`) so detection runs on the simulator's CPU. Face analysis is most reliable on a real device.

### 4. Tests

```bash
xcodebuild test -scheme ProctorLens \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch'
```

15 unit tests cover the coalescing logic, the escalation thresholds, and the flag-type contract.

### Regenerating the Xcode project

Source files are managed by [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding files via the command line:

```bash
brew install xcodegen   # once
xcodegen generate
```

## Security

Security is treated as a first-class concern.

### Authenticated writes

An open write endpoint would let anyone forge or inject flags for any session. To prevent that:

- `POST /sessions` issues a per-session bearer token.
- `POST /flags` requires `Authorization: Bearer <token>` matching the session, validated with a constant-time comparison (`secrets.compare_digest`).
- A forged flag with a missing or invalid token returns 401.

Reads (`GET`) are left open for the local reviewer. In a production deployment they would sit behind reviewer authentication.

### Data minimization

No raw camera frames or video leave the device. Only flag metadata (`session_id`, `flag_type`, `timestamp`) is transmitted. The violation thumbnails shown in the dashboard are stored locally, so the reviewer gets visual context without any imagery crossing the network.

### A deliberate abuse case: photo spoofing

Scenario: a candidate holds up a photograph of themselves.

Why it defeats the current checks: `VNDetectFaceRectanglesRequest` is a 2D detector. A clear, well-lit photo satisfies "one face present, centred", so yaw and pitch read near zero and neither the no-face nor the head-turned-away check fires.

Why this project does not claim to solve it: defeating photo spoofing requires liveness detection such as blink detection, depth sensing (TrueDepth), or challenge-response prompts ("turn left"). These are non-trivial and out of scope here. The limitation is documented rather than hidden.

How a production system would address it: combine face detection with a liveness signal (depth where available, or randomized head-movement prompts that a static image cannot satisfy).

### Detection versus prevention

The app detects every time the candidate leaves the exam (backgrounding) and flags it. It does not prevent leaving, which on iOS requires kiosk mode (Guided Access or MDM Single-App Mode) and is out of scope. The boundary between detection and prevention is explicit by design.

## Head pose versus eye gaze

Vision's `VNFaceObservation` exposes yaw (left and right rotation) and pitch (up and down tilt) of the head. These are a practical proxy for looking away: more than roughly 20 degrees off-centre and attention is likely elsewhere.

This is not eye-gaze tracking. Knowing where the eyes point within the head is a harder problem that Vision does not solve, and it is deliberately out of scope. Head pose is the achievable signal.

## Tech stack

| Layer | Choice |
|---|---|
| App | Swift, SwiftUI |
| Embedded web | WKWebView with a JS bridge |
| Camera | AVFoundation (no video stored) |
| Analysis | Vision (`VNDetectFaceRectanglesRequest` rev 3), on-device |
| Backend | FastAPI, Python 3.13 |
| Storage | SQLite via aiosqlite |
| Auth | Per-session bearer tokens |
| Tests | XCTest (15 tests) |
| Project generation | XcodeGen |
| Simulator camera | RocketSim Connect (DEBUG only) |
