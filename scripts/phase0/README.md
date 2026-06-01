# Phase 0 — Dedicated Server Feasibility (Windows)

Automated checks for environment, network, lobby API, mod logs, and performance while the game runs.

**Platform:** run on **Windows** (Heim-PC or Hetzner VPS). Scripts are not useful on macOS/Linux for game-path tests.

## Quick start

```powershell
cd scripts\phase0
Copy-Item phase0.config.example.json phase0.config.json
# Edit phase0.config.json — set DvInstallDir at minimum

# 1) Baseline (no game running)
.\Invoke-Phase0Tests.ps1 -HostProfile HomePC

# 2) Optional: smoke-start game (batchmode) — tests mod load only
.\Invoke-Phase0Tests.ps1 -HostProfile HomePC -LaunchSmoke

# 3) Manual: host Career in Derail Valley, then monitor 10 min
.\Invoke-Phase0Tests.ps1 -HostProfile HomePC -SessionMonitor

# 4) From second PC (set RemoteServerHost in config to server IP/DNS)
.\Invoke-Phase0Tests.ps1 -HostProfile Client -ClientOnly
```

Reports are written to `reports/phase0-<Profile>-<timestamp>.json`.

## What is automated vs manual

| Check | Automated | Manual |
|-------|-----------|--------|
| DV + Mod + AssetBundle installed | Yes | |
| RAM / GPU hints | Yes | |
| Lobby REST `/list_game_servers` | Yes | |
| Public IP, firewall hints | Yes | Open UDP port in router/Hetzner |
| Mod load via `multiplayer.log` | Yes (smoke or session) | Enable log file in mod advanced settings |
| UDP port listening while hosted | Yes (`-SessionMonitor`) | Start host in game first |
| RAM/CPU during session | Yes (`-SessionMonitor`) | Play or idle with clients |
| Career save loads on host | | Host Career in UI |
| Second player joins (IP) | Partial (DNS/UDP probe) | Join in game |
| Steam lobby join | | Second player via Steam |
| 30 min stability / trains / save | | Playtest checklist below |

## Manual checklist (fill after automation)

Copy into your report notes or a ticket:

- [ ] Career world hosted on server machine
- [ ] Client 2 joined via **direct IP** (same mod version)
- [ ] Client 2 joined via **Steam lobby**
- [ ] Sandbox quick test (optional)
- [ ] Ran 30+ minutes without disconnect
- [ ] Save / weather / jobs behaved normally
- [ ] Hetzner: tested without physical GPU (if applicable)

## Config highlights

| Key | Purpose |
|-----|---------|
| `DvInstallDir` | Steam DV install folder |
| `LaunchSmokeTest` | Auto-start `DerailValley.exe` with `LaunchArgs` |
| `SessionMonitor.Enabled` | Or use `-SessionMonitor` switch |
| `RemoteServerHost` | Server IP/hostname for client-side `-ClientOnly` |
| `LogSuccessPatterns` / `LogFailurePatterns` | Regex matched against `multiplayer.log` |

Enable file logging in-game: Multiplayer mod → Advanced → **Enable Log File**.

## Go / No-Go

| `goNoGo` in report | Meaning |
|--------------------|---------|
| `Go` | No failures; proceed to Phase 1 mod work |
| `ConditionalGo` | Warnings only (e.g. no GPU, no UDP yet) |
| `NoGo` | Fix failures before Phase 1 |

## Hetzner tips

- Use **Windows Server** with Desktop Experience for first test.
- RDP in, install Steam + DV + UMM + mod like a normal PC.
- If `-LaunchSmoke` with `-batchmode` fails, retry without batchmode (minimized window).
- Set `RemoteServerHost` on your home PC to the VPS public IP when running `-ClientOnly`.

## CI

These scripts are **not** run in GitHub Actions (game + Windows required).
