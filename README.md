# PvZ GOTY — Speed Up Mod

A tiny speed control for **Plants vs. Zombies: Game of the Year Edition** (Steam).
Press **ALT** to cycle 1x → 2x → 3x → Custom, and **1**–**9**/**0** to pick a plant.

Written in [Odin](https://odin-lang.org/). No injection, no modified game files.

A small always-on-top panel: pick a speed preset with the mouse or cycle it
with ALT, and watch the **measured** rate the game reports back.


## Usage

1. Start Plants vs. Zombies.
2. Run `pvz-speed.exe`. It connects on its own and stays on top.
3. Click a preset, or press **ALT** to cycle. The hotkey works while the game
   is focused — you do not need to alt-tab back to the panel.
4. Press **1**–**9** or **0** in game to pick that seed packet.
5. Press **X** for the shovel. Set **level has N plants** in the panel so the
   tool knows where the shovel sits (it is one slot past your last packet).

Type into the **custom** box for any multiplier from 1x to 100x. Closing the
window restores the game to 1x.

Hotkeys are polled globally, so they work with the game focused. Plant
selection additionally requires the game to be the foreground window — see
Caveats.

The **measured** line reads the game's own update counter, so it shows the rate
the game is actually running at, not merely what was requested. If you ask for
3x and it says 3.00x, the change really took effect.

## How it works

**Speed** — the game is the PopCap SexyApp Framework, whose update loop is paced
by a speed multiplier field on the main app object. The tool resolves that object
through a static global and writes one 8-byte `f64`.

**Plant selection** — the tool posts `WM_MOUSEMOVE` + `WM_LBUTTONDOWN` +
`WM_LBUTTONUP` directly to the game's window handle at the packet's coordinates,
then posts a final move back to where your real cursor is. **Your mouse never
moves.** Because the messages are addressed to a window rather than to a screen
position, they cannot reach any other application, and it does not matter what is
stacked on top of the game.

Neither half modifies a game file, injects a DLL, or patches any code. The speed
control writes a single number the engine already reads every frame; plant
selection sends the same window messages a real click would.

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

- **ALT cycles speed only while the game is the foreground window**, and only on
  a clean tap — holding Alt and pressing another key (Alt+Tab) is ignored.
  SPACE is deliberately not used: it pauses the game.
- The tool ignores ALT for the first few seconds after launch. GLFW synthesises
  an ALT keypress when it tries to focus its own window, and without the settle
  window that would cycle the speed before you touched anything.
- **Plant selection requires the game to be the foreground window**, so typing
  digits in another application cannot change your selection.
- **Conveyor-belt levels are not supported.** Those levels have no fixed seed
  bank — packets slide along a belt — so the number keys will hit whatever
  happens to be at that position, or nothing.
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
