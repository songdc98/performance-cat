# Performance Cat · 性能监测猫猫

> 中文说明见 [README.zh.md](README.zh.md).

A tiny, native **macOS performance dashboard** for Apple Silicon. One always-on
window that shows what your Mac is doing right now — CPU, power, temperature,
fans, memory, network, storage and battery — in a clean, Apple-style dark UI.

It is built with plain **AppKit in a single Swift file**. No Electron, no web
view, no background daemon, no network access, no analytics, no language switcher
inside the app. It only *reads* local system metrics and draws them.

> Footprint: the app idles at roughly **1% CPU** and a flat **~70 MB** of memory
> (the figure Activity Monitor shows); the bundled `macmon` sensor helper adds
> about **1% CPU and ~6 MB**. The dashboard is rendered once per refresh into an
> offscreen bitmap and shown through the view's layer, so memory stays flat
> instead of spiking on every redraw.

## Two language builds

There is no in-app language toggle — instead the project ships **two separate
apps** so the binary stays lean. Download the one you want:

- **English** — `Performance Cat.app`
- **中文** — `性能监测猫猫.app`

Both are identical apart from the on-screen language.

---

## Features

Every value is labeled so you always know what you are looking at.

| Card | Shows |
|------|-------|
| **CPU** | Total load %, user/system/idle split, chip name, CPU temperature, live sparkline |
| **Power** | System power (W), SoC total, and the CPU / GPU / ANE / DRAM breakdown, thermal state |
| **Cooling** | **Real per-fan RPM read from the SMC** (shows `0 RPM` when the fans are off), plus CPU/GPU temperature. Falls back to a thermal panel on fanless Macs |
| **Memory** | Used / total, pressure %, swap, free, **plus the top 3 memory-using apps**. The "used" figure matches Activity Monitor's *Memory Used* (see note below) |
| **Network** | Live up/down throughput and the **top 3 processes by traffic** (per second) |
| **Storage** | Apple-style breakdown of the boot volume: **System / Data / Other / Free**, from `diskutil` |
| **Battery** | Charge %, charge/discharge wattage, adapter wattage, cycle count |
| **AI Tools** | For any running `codex` / `claude` processes: **CPU %, memory, helper-process count, and how long the app has been running** |
| **Top Processes** | The processes currently using the most CPU |

The header strip shows a one-line status (All clear / High CPU load / Thermal
pressure …) with the key vitals (SoC power, CPU/GPU temperature, memory %).

---

## How it works (data sources)

Performance Cat is honest about where each number comes from and never
fabricates data:

- **CPU / memory / network throughput / battery** — Apple system APIs
  (`host_processor_info`, `host_statistics64`, `getifaddrs`, IOKit power sources).
- **Fan RPM** — read directly from the **SMC** via IOKit (`AppleSMC`). Read-only,
  no privileges. When the Mac is cool the fans are genuinely off, so it honestly
  shows `0 RPM`.
- **Power & temperature** — the bundled [`macmon`](https://github.com/vladkens/macmon)
  helper, launched as a child process and parsed from its JSON output.
- **Per-process network** — `nettop`, sampled briefly on a background thread.
- **Storage breakdown** — `diskutil apfs list`, sampled about once every 5 min.

### Which "memory used" number is correct?

Activity Monitor, this app, and tools like Stats often show *different* memory
numbers — because there is no single definition of "used" on macOS:

- **`Total − Free` is misleading.** macOS keeps "free" RAM full of file caches it
  can drop instantly, so that number looks alarmingly high (~40% here) and means
  little.
- The meaningful figure is **App Memory + Wired + Compressed** — memory that is
  actually committed and can't be reclaimed for free. This is exactly what
  Activity Monitor calls **"Memory Used"** and what its memory-pressure graph is
  based on.

Performance Cat reports that same App + Wired + Compressed figure (via `macmon`),
so it lines up with Activity Monitor's "Memory Used". If another tool shows a
different number, it is using a different definition — not a more accurate one.

---

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon.
- **Xcode Command Line Tools** to build from source: `xcode-select --install`.

## Build & run

```bash
git clone <your-repo-url> performance-cat
cd performance-cat
./build.sh                 # builds both language apps into dist/
# or build just one:  ./build.sh en   |   ./build.sh zh

codesign --force --deep --sign - "dist/Performance Cat.app"
open "dist/Performance Cat.app"
```

`build.sh` compiles the single Swift source (twice, once per language), generates
the app icon, and copies the `macmon` helper into each app bundle. The result is a
self-contained `.app` you can move to `/Applications` and keep running.

The ad-hoc `codesign` step lets the app run locally without a paid Developer ID.
The first time you open it, macOS may ask you to confirm an app from an
unidentified developer (right-click → Open).

---

## Permissions & privacy

- The app **only reads** system metrics. It never changes any system setting and
  **never sends any data anywhere** — there is no networking code in it.
- No special entitlements are required. macOS may prompt for ordinary access
  (e.g. to launch the helper tools); grant it if you want the sensor readings.
- Process and app names in the Memory / Network / Top-Process / AI cards come
  from `ps` / `nettop`. No file contents, no conversations, and no personal data
  are read or stored.

---

## Disclaimer

This software is provided **"AS IS", without warranty of any kind**, express or
implied. The fan, power, and temperature readings are best-effort values from the
SMC and the `macmon` helper and **must not be relied upon for any safety-critical
decision**. The authors are not liable for any damage or data loss arising from
its use. Use at your own risk.

This is a free, non-commercial, open-source project. It collects no data, serves
no ads, and is built purely to be a convenient, lightweight performance display.

---

## Third-party

This project bundles **macmon** (MIT, © 2024 vladkens). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[bin/macmon-LICENSE.txt](bin/macmon-LICENSE.txt).

## License

[MIT](LICENSE) © 2026 Dachuan Song.
