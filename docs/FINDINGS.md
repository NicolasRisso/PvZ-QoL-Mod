# Reverse engineering notes

How the offsets in [`src/offsets.odin`](../src/offsets.odin) were derived, so
they can be re-derived for another build rather than trusted blindly.

## The target is not the Steam exe

`PlantsVsZombies.exe` in the Steam folder is a **DRM launcher stub**. Observed
live: 0.53s CPU, no main window, 2 threads, and its app object is never
constructed.

The real game is `popcapgame1.exe`, extracted to
`%ProgramData%\PopCap Games\PlantsVsZombies\`, launched, and then **unlinked
from disk while still mapped**. The only copy at runtime is in memory.

They are genuinely different binaries:

| | Steam stub | real game |
|---|---|---|
| `.text` size | 1,186,716 | 2,965,148 |
| image size | 5,296,312 on disk | 4,317,184 mapped |

Analysing the Steam exe produces plausible-looking but completely wrong
addresses. This cost a full analysis pass; check which process you're in first.

### Consequence for version gating

You **cannot** MD5 the game file — it does not exist on disk while running.
Instead the tool fingerprints from memory, comparing the first 8 entries of the
`Sexy::SexyApp` vtable against `KNOWN_VTABLE_HEAD`.

## Binary facts (popcapgame1.exe)

- x86 32-bit, imagebase `0x00400000`
- **ASLR disabled** (`DllCharacteristics = 0x0000`) → absolute addresses stable
- Engine: PopCap SexyApp Framework, MSVC, unoptimised build
- RTTI partially intact — 125 type descriptors, but only framework classes.
  PvZ's own `LawnApp` has no RTTI name, which is why searching for it fails.

| Section | VA | vsize |
|---|---|---|
| `.text` | `0x00001000` | 2,965,148 |
| `.rdata` | `0x002d5000` | 303,058 |
| `.data` | `0x0031f000` | 815,580 |
| `.rsrc` | `0x003e7000` | 221,596 |

## Recovering the app object

RTTI walk (TypeDescriptor → CompleteObjectLocator → vftable):

| Symbol | VA |
|---|---|
| `Sexy::SexyAppBase` vftable (offset 0) | `0x006ff074` |
| `Sexy::SexyAppBase` vftable (offset 4) | `0x006ff204` |
| `Sexy::SexyApp` vftable (offset 0) | `0x0070346c` |
| `Sexy::SexyApp` vftable (offset 4) | `0x00703618` |

Both classes have **two** vtables — `SexyAppBase` is multiply-inherited, so
objects carry vtable pointers at both `+0` and `+4`. That pair is a useful
signature for spotting the object in a memory dump.

The live object is a `LawnApp` with its own vtable pair, so scanning for the
`SexyApp` vtable finds nothing. It was located instead by:

1. Snapshotting writable memory twice, 2s apart.
2. Finding dwords incrementing at ~100/sec (the framework's update rate).
3. Scanning backwards from those counters for two adjacent `.rdata` pointers —
   the multiple-inheritance signature. Object base found at the pair.

Static globals pointing at the object (all four alias the same address):

```
0x00731C50   0x00731CDC   0x00731D08   0x00731DA0
```

These are in `.data` and fixed. The object itself is heap and moves every run.

## Field offsets

| Offset | Type | Meaning |
|---|---|---|
| `+0x4B4` | `i32` | frame time, ms. `10` on stock → 100 updates/sec |
| `+0x4D0` | `u32` | millisecond clock, +1000/sec |
| `+0x4DC` | `u32` | update counter, +100/sec |
| `+0x4E4` | `u32` | update counter, +100/sec |
| `+0x4C8` | `f64` | `1.0`, but **no effect on speed** |
| **`+0x4F0`** | **`f64`** | **the speed multiplier** |

### It's an f64, not an f32

This is the easy mistake. Reading `+0x4CC` as a float gives `1.875`, which looks
like a plausible game value but is meaningless — it's the high dword of
`0x3FF0000000000000`, i.e. the double `1.0`.

**Scanning for a 4-byte float `1.0` finds nothing.** Search for an 8-byte double.

### Verification method

Rather than guessing, each `1.0` double was tested by writing `3.0` and
measuring the game's own update counter at `+0x4E4`:

| Field | rate before | rate after | verdict |
|---|---|---|---|
| `+0x4C8` | 99.9/s | 100.0/s | no effect |
| `+0x4F0` | 99.9/s | **301.3/s** | **confirmed, exactly 3x** |

Restoring `1.0` returned the rate to 100.0/s. The game measures itself, so no
human judgement is involved.

## Safety checks before writing

`resolve_object` refuses to return an address unless all hold:

1. `[GLOBAL_APP_PTR]` is non-null.
2. `obj[0]` points inside the image (it's a vtable pointer).
3. `obj+0x4B4 == 10` (frame time — confirms the pacing block).
4. `obj+0x4F0` is a finite double in `(0, 1000]`.

Plus `verify_build` compares 8 vtable entries. A wrong build fails at step 3 or
at the fingerprint, before any write happens.

## Reproducing on another build

1. Confirm which process is the real game (check CPU time and window title).
2. Dump the image from memory if the file is unlinked.
3. Find ~100/sec counters by diffing two memory snapshots.
4. Locate the object via the adjacent-vtable-pointer signature.
5. Find `f64` fields equal to `1.0` near the counters.
6. Test each by writing and measuring the counter rate.
7. Find static `.data` pointers to the object for the stable path.

## Toolchain

- Ghidra 12.1.3 with a Temurin JDK 21
- Headless analysis + a small decompile-at-address script
- Python `ctypes` for live memory work


---

# Seed bank geometry (plant selection)

Measured against level 1-7, standard 6-packet seed bank, 800x600 client.

| slot | card x range | centre |
|---|---|---|
| 1 | 96-142 | 119 |
| 2 | 155-201 | 178 |
| 3 | 214-260 | 237 |
| 4 | 273-319 | 296 |
| 5 | 332-378 | 355 |
| 6 | 391-437 | 414 |

**Pitch is 59 px, cards are ~47 wide.** Vertical extent y 8-77, centre y 42.

An earlier estimate of 51.5 px was wrong and produced an off-by-one at the far
end of the bank: a click aimed at slot 5 landed in slot 4's hit region. Aim at
the centre, not the edge - the inter-card gap belongs to the preceding slot.

## How it was measured

Eyeballing a screenshot was not accurate enough, and two automated attempts
produced garbage worth recording so they are not repeated:

1. **Brightness thresholding** on the card art - failed, the art varies too much
   between packets.
2. **Sweeping the mouse and diffing memory** - produced a beautiful stepped
   pattern that was entirely an artifact. The "steps" were 41 samples wide at
   50 ms per sample, i.e. a ~2 s animation cycle aliased against the sample
   rate. Sampling positions consecutively makes any time-varying field look
   position-dependent. **Interleave the positions (A B A B) instead**; doing so
   reduced 741 candidate addresses to exactly one - the raw mouse coordinate.

What finally worked: detect the card's bright, desaturated cost strip
(`brightness > 140 && saturation < 0.35` over y 64..74). The strip is broken up
by the dark cost digits, so take the first and last run of each cluster as the
card extent.

## Verification

Post a click at a computed centre, capture the seed bank before and after, and
compute the mean per-slot pixel difference. A correct hit changes exactly one
slot:

```
clicked slot 5 at x=355
   slot 1: 0.00    slot 4: 0.00
   slot 2: 0.00    slot 5: 421.50  <== CHANGED
   slot 3: 0.00    slot 6: 0.00
```

Do this on a *live* board with a short interval between captures - sun changes
grey packets in and out and will otherwise swamp the signal. Also pick an
affordable plant: clicking a packet you cannot afford does nothing, which reads
identically to a missed click.

# Input injection

The game imports `GetCursorPos` + `ScreenToClient` and runs a plain
`PeekMessageA` loop, no DirectInput. It tracks the mouse position at
**app+0x1608**.

Posting `WM_MOUSEMOVE` / `WM_LBUTTONDOWN` / `WM_LBUTTONUP` to the game's HWND
works and requires no cursor movement. Post a final `WM_MOUSEMOVE` back to the
user's real cursor position afterwards so the selected plant follows their
pointer.

**The game ignores UI input while its window is not active** - posted messages
are still received and the coordinate is stored, but no widget reacts. Any
calibration attempt against an unfocused *or paused* game will find nothing.
Check both before concluding the approach does not work.
