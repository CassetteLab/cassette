# Audio session: device test procedure

Two open problems, reproducible only on a real device:

- **#49**: playback does not resume after Siri reads a message in CarPlay.
- **Route disconnect**: when a Bluetooth speaker or CarPlay goes away, playback keeps going on the iPhone speaker.

The instrumented build **behaves exactly like the previous one**. It only adds an opt-in log, so what you
reproduce is the real bug. This page is meant to be read on the phone, in the car.

---

## 1. Capture the log

The log is **off by default**. The switches are links; no screen, no setting to find.

1. **Turn it on.** In Safari, type in the address bar and confirm *Open in Cassette*:
   `cassette://diagnostics/audio-session/enable`
   Nothing visible happens. That is expected.
2. **Check it is on.** Open `cassette://diagnostics/audio-session/export`. A share sheet appears with a
   `.log` file. Its first line ends with `logging=on`.
3. **Optional, start clean:** `cassette://diagnostics/audio-session/clear`
4. **Run the tests below.** For each one, write down the **time**, the iOS version, whether it was a
   **track or a radio**, and whether the screen was **locked**.
5. **Send the file:** `cassette://diagnostics/audio-session/export`, then AirDrop, Mail, or attach it to
   the GitHub issue.
6. **Turn it off when done:** `cassette://diagnostics/audio-session/disable`

What the file contains: playback and session states, interruption and route-change reasons, audio port
types (e.g. `BluetoothA2DPOutput`, `CarAudio`), error codes. **No track titles, no server address, no
device names.** It stays on the phone until you share it, and is capped at about 2 MB.

With a Mac at hand you can watch live instead: Console.app → the iPhone → filter
`subsystem:app.cassette.player`. The lines are logged at `notice` level, so they are also kept in a
sysdiagnose.

---

## 2. Reading a log line

| Prefix | Meaning |
|---|---|
| `[RECV #n]` | A system notification, **as received**. `#n` gives the system's order. |
| `[INTERRUPTION #n]` / `[ROUTE #n]` | The **same** notification, as handled by the player. What follows `→` is the decision taken. |
| `[SESSION]` | `setCategory` / `setActive` result, with the error code on failure. |
| `[CMD]` | `pause` / `resume`: **who asked** (`origin=`), the engine state now and **+500ms** later. |
| `[ENGINE]` | Every AudioStreaming state change, end of track, error. |
| `[OBSERVED #n]` | Log-only: media services lost/reset, and on iOS 27 `didBecomeActive`, `didBecomeInactive`, `resumptionRecommendation`. |
| `[APP]` | Process start (environment, session config) and scene phase changes. |

`origin=` values: `ui`, `remote-play`, `remote-pause`, `remote-toggle` (lock screen, CarPlay, Bluetooth
buttons), `intent` (Shortcuts/widget), `interruption`, `route`, `other`.

`interruptionOpen=true` means a `began` was received and its `ended` has not arrived yet.

If `#n` numbers in the `[INTERRUPTION]`/`[ROUTE]` lines come out in a different order than in the
`[RECV]` lines, the player handled notifications out of order.

---

## 3. Scenarios

### T1: Siri, iPhone alone
- **Do:** play a track, lock, hold the side button, ask "what time is it", let Siri finish.
- **Expect:** music resumes.
- **Log:** `began reason=default` → `ended options=shouldResume(1) → resume()` → `[CMD] resume origin=interruption` → `+500ms engine=playing`.
- **Proves:** the interruption path works outside CarPlay. Baseline for T3.

### T2: Siri announcement, AirPods
- **Do:** AirPods in, *Announce Notifications* on, send yourself an SMS from another phone.
- **Expect:** music resumes after the announcement.
- **Proves:** the same path, with a Bluetooth route but no car.

### T3: CarPlay, Siri reads an SMS (issue #49)
- **Do:** wireless CarPlay, play a track, receive an SMS, let Siri read it, answer "No".
- **Expect:** music resumes.
- **Which hypothesis the log confirms:**
  - **S1**: a `began`, then `[ROUTE] … routeConfigurationChange` or `newDeviceAvailable` with `→ setActive(true) ok interruptionOpen=true`, then **no `ended` at all**. Our reactivation ate the interruption end.
  - **S2**: `ended options=none(0) → stay paused: no shouldResume`, or no `ended` **and** no route line. iOS did not ask us to resume.
  - **S3**: `ended … → stay paused: route-disconnect flag`.
  - **S4**: `ended … → resume()`, then `[SESSION] setActive(true) FAILED`, `[ENGINE] unexpected error`, or `+500ms engine=stopped`.
- **Compare with T1/T2:** if those resume and T3 does not, the cause is CarPlay-specific, which points to S1.

### T3b: CarPlay, Siri from the steering wheel
- **Do:** press the voice button, ask something short.
- **Expect:** music resumes.
- **Proves:** whether it is Siri in the car in general, or message reading specifically.

### T4: CarPlay, phone call
- **Do:** one call declined; one call accepted, then hung up.
- **Expect:** music resumes both times.

### T5: user pause must stay paused (critical)
- **Do:** pause **by hand**. Then connect CarPlay or a Bluetooth speaker. Then trigger Siri (T1 or T3).
- **Expect:** music does **not** start.
- **Known risk:** the current code can start playback here by itself.
- **Log if it happens:** `[CMD] pause origin=ui` → `[ROUTE] newDeviceAvailable → setActive(true) ok` → `began … → early return: not playing` → `ended → resume()` → `[CMD] resume origin=interruption`.

### T6: Bluetooth speaker turned off, track
- **Do:** play a track on a Bluetooth speaker, switch the speaker off. Once locked, once unlocked.
- **Expect:** pause, nothing on the iPhone speaker.
- **Note by ear:** does sound **continue without a cut**, or **cut and come back**, and after how long?
- **Log:**
  - **correct:** `[RECV] route reason=oldDeviceUnavailable(2) previous=[BluetoothA2DPOutput]` → `[ROUTE] → pause()` → `[CMD] pause origin=route`.
  - **B2:** no `oldDeviceUnavailable`, or an unexpected `previous=`.
  - **B3:** the pause happens, then `[CMD] resume origin=remote-play`, `remote-toggle` or `interruption`.
  - **B4:** `#n` handled out of order (see §2).
  - **B5:** no `began reason=routeDisconnected(4)` at the disconnect. Since iOS 17 the system interrupts the Now Playing app itself, so its absence means iOS did not treat Cassette as Now Playing.

### T7: Bluetooth speaker turned off, radio
- **Do:** as T6, with an internet radio.
- **Expect:** pause.
- **Known defect (B1):** `[ROUTE] → no pause: no active track track=false radio=true`.

### T8: CarPlay disconnect
- **Do:** play in CarPlay, turn the car off, or unplug for wired CarPlay.
- **Expect:** pause.
- **Log:** the reason and `previous=[CarAudio]`. Then read it like T6.

### T9: AirPods into the case (regression, issue #14)
- **Do:** play with AirPods, put both in the case.
- **Expect:** pause.
- **Log:** `began reason=routeDisconnected(4)`, `oldDeviceUnavailable previous=[BluetoothA2DPOutput]`, `pause()`.

### T10: end of queue, then Siri
- **Do:** let a short queue finish with repeat off, then trigger Siri.
- **Expect:** nothing restarts.
- **Log:** `[CMD] resume path=end-of-queue` must **not** appear.

### T11: Smart Shuffle during an interruption
- **Do:** start Smart Shuffle, look at *Up Next*, trigger Siri (T1).
- **Expect:** music resumes, *Up Next* unchanged.

### T12: AirPods reconnect, play from the lock screen (regression)
- **Do:** AirPods out of and back in the ears, or reconnected. Press play on the lock screen.
- **Expect:** playback starts.
- **Log:** `[CMD] resume origin=remote-play` → `[SESSION] setActive(true) ok` → `+500ms engine=playing`.

### T13: rapid taps, haptics
- **Do:** tap play/pause quickly several times in the full player and the mini player.
- **Expect:** normal behavior.
- **Log:** write down every `code=-50`, and **which call** failed:
  - `[SESSION] setCategory FAILED` versus `setActive(true) FAILED origin=ui`;
  - then `-50 retry setActive(true) ok` or `FAILED`.

---

## 4. Short version for the #49 reporter

1. Install the TestFlight build linked in the issue.
2. In Safari, open `cassette://diagnostics/audio-session/enable` and confirm *Open in Cassette*.
3. In the car, play music in Cassette. Let Siri read a message, answer "No". Note the time.
4. In Safari, open `cassette://diagnostics/audio-session/export` and share the `.log` file, attached to
   the issue or by email.
5. Optional: `cassette://diagnostics/audio-session/disable`.
