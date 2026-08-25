# PvZ QoL Mod

A lightweight quality-of-life companion for **Plants vs. Zombies: Game of the
Year Edition (Steam)** on Windows.

It speeds up the whole game, selects seed packets from the keyboard, finds the
shovel automatically, and collects sun and coins without moving the physical
mouse cursor.

Created by [Nicolas Risso](https://github.com/NicolasRisso).

## Features

- **Game-speed control** — switch between 1x, 2x, 3x, and a custom multiplier.
- **Measured speed** — reads PvZ's own update counter to show the effective rate.
- **Keyboard seed selection** — number keys select slots 1 through 10.
- **Automatic shovel position** — reads the active SeedBank slot count from memory.
- **Automatic collection** — collects sun, silver/gold coins, and diamonds.
- **Safe hand detection** — collection pauses while a plant, shovel, or tool is held.
- **Cursor-safe input** — posts clicks to PvZ without moving the physical cursor.
- **Automatic reconnect** — survives game restarts and loading transitions.

## Requirements

- Windows 10 or Windows 11
- Plants vs. Zombies GOTY on Steam, version **1.2.0.1096**
- A legally purchased copy of the game

Other releases, localized executables, GOG builds, and modified game binaries
may have different memory layouts. The tool verifies the supported build and
refuses to write when its fingerprint does not match.

## Download and run

1. Download `pvz-qol-mod.exe` from the
   [latest release](https://github.com/NicolasRisso/PvZ-QoL-Mod/releases/latest).
2. Start Plants vs. Zombies through Steam and enter the game normally.
3. Run `pvz-qol-mod.exe`. The panel connects to the real game process automatically.
4. Return focus to PvZ and use the hotkeys below.

No installation is required. The Roboto UI font and all runtime dependencies are
embedded in the executable.

Closing the panel restores the game to 1x speed.

## Controls

| Input | Action |
|---|---|
| `Alt` | Cycle 1x → 2x → 3x → custom speed |
| `1`–`9` | Select seed slots 1–9 |
| `0` | Select seed slot 10 |
| `X` | Select the shovel |
| `A` | Toggle automatic sun/coin collection |

Hotkeys act only while the PvZ window is focused. A clean Alt tap changes speed;
Alt+Tab is ignored.

The speed presets and auto-collect toggle can also be clicked in the panel. The
custom speed box accepts values from 1x to 100x, though 1x–4x is the practical range.

## How it works

PvZ's Steam launcher starts a separate 32-bit `popcapgame1.exe` process containing
the actual game. PvZ QoL Mod is a normal 64-bit companion application that opens
that process through documented Windows APIs.

### Speed control

The PopCap SexyApp Framework stores a double-precision speed multiplier on the
main application object. The mod resolves and validates that object, then changes
only that multiplier. Animations, cooldowns, zombie movement, and sun production
therefore remain synchronized.

### Seed packets and shovel

Seed keys post `WM_MOUSEMOVE`, `WM_LBUTTONDOWN`, and `WM_LBUTTONUP` directly to
the PvZ window at the appropriate packet center. The game receives an ordinary
click, but Windows never moves the real cursor.

The shovel sits one packet pitch after the final seed slot. The mod reads
`SeedBank::mNumPackets` from the active Board, so its position updates automatically
as adventure levels grant more slots or the player purchases slot upgrades.

### Automatic collection

Sun and money are entries in the same in-memory `DataArray<Coin>`. At 20 Hz the
mod validates the active Board, checks that the hand is empty, and clicks the
center of each live ordinary collectible. It ignores awards, presents, seed
packets, chocolate, and special tools.

Auto-collection stops when PvZ loses focus or when its CursorObject reports a
plant/tool in hand. A short input grace period also prevents queued collection
clicks from cancelling keyboard seed selection.

Detailed reverse-engineering notes and validated offsets are documented in
[`docs/FINDINGS.md`](docs/FINDINGS.md).

## Building from source

Install [Odin](https://odin-lang.org/docs/install/) and run this from the repository
root on Windows:

```powershell
odin check src -vet
odin build src -out:pvz-qol-mod.exe -o:speed -extra-linker-flags:"/FORCE:MULTIPLE"
```

Odin includes the raylib and raygui bindings used by the panel. Roboto is loaded
from `assets/Roboto.ttf` at compile time and embedded in the final executable.

`/FORCE:MULTIPLE` is required because raylib and User32 both export a symbol named
`CloseWindow`. See the explanatory comment in `src/main.odin`.

The public GitHub Actions workflow type-checks and builds every push and pull
request. Tagged releases also include `SHA256SUMS.txt` and a build-provenance
attestation:

```powershell
gh attestation verify pvz-qol-mod.exe --repo NicolasRisso/PvZ-QoL-Mod
```

## Project layout

```text
assets/             Embedded Roboto font and its license
docs/FINDINGS.md    Reverse-engineering and calibration notes
src/game.odin       Process attachment and guarded memory access
src/offsets.odin    Supported-build addresses and field offsets
src/seedbank.odin   Window input, seed selection, and shovel logic
src/autocollect.odin
src/main.odin       Panel, hotkeys, and application loop
```

## Limitations

- Only Steam GOTY 1.2.0.1096 is currently supported.
- Conveyor-belt levels do not have fixed seed slots, so number-key selection is
  not supported there.
- Very high speed multipliers can make PvZ unstable or difficult to control.
- This is intended for the original offline single-player game only.

## Antivirus notice

The mod reads/writes another process and synthesizes window input—the same behavior
used by game trainers. Some antivirus products may therefore classify it as a
HackTool or Riskware even when the executable is built from this source.

For verification, prefer GitHub's public build artifact, compare its SHA-256
checksum, and verify the release attestation. The project never injects a DLL,
patches the executable, modifies game files, or sends gameplay data over a network.

## Legal

This repository contains no Plants vs. Zombies code or assets. It is an independent
fan-made project and is not affiliated with or endorsed by PopCap or Electronic Arts.

## License

PvZ QoL Mod is available under the [MIT License](LICENSE).

Roboto is distributed under the [SIL Open Font License](assets/OFL-Roboto.txt).
