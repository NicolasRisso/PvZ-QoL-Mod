# PvZ GOTY — Speed Up Mod

A tiny speed control for **Plants vs. Zombies: Game of the Year Edition** (Steam).
Press **SPACE** to cycle 1x → 2x → 3x → Custom.

Written in [Odin](https://odin-lang.org/). No injection, no modified game files.

A small always-on-top panel: pick a speed preset with the mouse or cycle it
with SPACE, and watch the **measured** rate the game reports back.


## Usage

1. Start Plants vs. Zombies.
2. Run `pvz-speed.exe`. It connects on its own and stays on top.
3. Click a preset, or press **SPACE** to cycle. The hotkey works while the game
   is focused — you do not need to alt-tab back to the panel.
4. Press **1**–**9** or **0** in game to pick that seed packet.

Type into the **custom** box for any multiplier from 1x to 100x. Closing the
window restores the game to 1x.

Hotkeys are polled globally, so they work with the game focused. Plant
selection additionally requires the game to be the foreground window — see
Caveats.

The **measured** line reads the game's own update counter, so it shows the rate
the game is actually running at, not merely what was requested. If you ask for
3x and it says 3.00x, the change really took effect.

## How it works

The game is the PopCap SexyApp Framework, whose update loop is paced by a speed
multiplier field on the main app object. The tool resolves that object through a
static global and writes one 8-byte `f64`.

That's the entire mod. It does not modify any game file, inject any DLL, or
patch any code — it writes a single number the engine already reads every frame.

Because it only sets a value the engine uses natively, everything stays in sync:
plant cooldowns, zombie movement, sun production, and animations all scale
together.

## Compatibility

Built against **PvZ GOTY (Steam), version 1.2.0.1096**.

The tool verifies the build before writing anything. If it doesn't recognise
the game, it refuses to write and says so rather than guessing. See
[docs/FINDINGS.md](docs/FINDINGS.md) for how the offsets were derived and how to
re-derive them for another build.

> **Note on the target process.** The `PlantsVsZombies.exe` in your Steam folder
> is only a DRM launcher. It extracts the real game to
> `%ProgramData%\PopCap Games\PlantsVsZombies\popcapgame1.exe`, starts it, and
> deletes it from disk. This tool attaches to that child process.

## Building

Requires [Odin](https://odin-lang.org/docs/install/) (targets `windows_amd64`).
raylib and raygui ship with Odin and link statically, so the result is a single
self-contained exe with no DLLs to distribute.

```
odin build src -out:pvz-speed.exe -o:speed -extra-linker-flags:"/FORCE:MULTIPLE"
```

`/FORCE:MULTIPLE` is required: raylib and user32 both export a symbol named
`CloseWindow`, so linking raylib alongside the Win32 API is otherwise a
duplicate-symbol error. See the note in `src/main.odin`.

The tool is a normal 64-bit program that reads and writes the memory of the
32-bit game process. Nothing runs inside the game.

## Caveats

- **SPACE is polled globally.** The hotkey fires no matter which window is
  focused, which is what makes it usable mid-game — but it also means pressing
  space in another application will cycle the speed.
- Very high multipliers may make the game unstable or unplayable. 1x–4x is the
  comfortable range.
- Single-player only. This is an offline game; there is nothing to cheat against
  but yourself.
- Because it writes to another process's memory, some antivirus software may
  flag it. The full source is here.

## Legal

This project contains no game code or assets — only memory offsets derived by
analysis. You need your own legally purchased copy. Not affiliated with PopCap
or Electronic Arts.

## License

MIT
