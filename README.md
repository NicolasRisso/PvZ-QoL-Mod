# PvZ GOTY — Speed Up Mod

A tiny speed control for **Plants vs. Zombies: Game of the Year Edition** (Steam).
Press **SPACE** to cycle 1x → 2x → 3x → Custom.

Written in [Odin](https://odin-lang.org/). No injection, no modified game files.

```
  PvZ GOTY - Speed Up Mod
  ------------------------------------

 > 1x       1.00x
   2x       2.00x
   3x       3.00x
   Custom   5.00x

  connected  pid 18692
  measured: 100 updates/sec  (1.00x)

  ------------------------------------
  SPACE  cycle speed
  C      set custom value
  Q      quit (restores 1x)
```

## Usage

1. Start Plants vs. Zombies.
2. Run `pvz-speed.exe`.
3. Press **SPACE** to cycle speeds. It works while the game is focused — you do
   not need to alt-tab back to the console.

`C` sets the custom multiplier (0.1–100). `Q` or `Esc` quits and restores 1x.

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

```
odin build src -out:pvz-speed.exe -o:speed
```

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
