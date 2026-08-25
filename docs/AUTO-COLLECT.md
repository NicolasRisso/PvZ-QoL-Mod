# Planned: auto-collect (sun and coins)

Not implemented. This records where the investigation got to so it can be picked
up without repeating the dead ends.

## Goal

Toggle with **A**. While on, sun and coins are collected automatically by
posting a click at each one's position - the same mechanism plant selection
already uses, so the physical cursor never moves.

## Why memory and not screen scraping

Screen scraping was considered and rejected:

- `PrintWindow` returns blank in-level (the game draws to a hardware surface),
  so it would need real screen capture, which only works while the game is
  unoccluded and on top.
- It costs a capture plus a blob scan several times a second.
- **Colour cannot distinguish a sun from a sunflower's face.** Measured: in a
  level with sunflowers, nearly every yellow blob on screen is a plant, and over
  1.6s of sampling essentially nothing moved.

Memory also gets **coins for free**. In this engine sun and coins are the same
kind of object (a "coin" with a type field), so locating one array yields both.
That is the single strongest argument for this route.

## What is already known

- App object: `[0x00731C50]` (see FINDINGS.md).
- `app+0x03A0` -> an object that contains the sun-count value. This is the best
  Board candidate so far, but the evidence is weak: it was chosen only because
  it was the one pointer-reachable object containing the displayed sun total.
  **Sampling it at 10 Hz for 6s found no moving values in it**, so either it is
  not the Board or the coins live in a separate allocation it points to.

## Techniques tried, and why each failed

| Approach | Outcome |
|---|---|
| Motion signature (y descends, x fixed) over all memory | Full snapshots take ~0.5s each, so temporal resolution is far too coarse. 8115 hits when loose, 0 when tightened. |
| Pointer walk from the app object to find the Board | Found the candidate above; no falling values inside it. |
| Churn funnel - diff regions, sample the busiest at 10 Hz | 13 hits, all in one buffer with identical trajectories. Audio or particle data. |
| Freeze + screen correlation | Mechanically fine, but matches landed in sprite/render buffers (`0x094…`, `0x095…`) that mirror screen coordinates rather than game objects. |

### The freeze trick is worth keeping

Because the speed multiplier is already under our control, the game can be set
to ~0.02x to **nearly stop it**, so a screen capture and a memory scan describe
the same instant. That makes screen-to-memory correlation exact instead of
approximate. Restore the multiplier afterwards.

### The mistake to avoid

Sampling positions *sequentially* aliases animation cycles into what looks like
position-dependent data - this already produced one completely bogus set of
"packet boundaries" (see FINDINGS.md). Interleave, always.

## What the next attempt needs

The blocker was never the technique, it was the lack of a clean signal: during
every sampling window, nothing was actually falling.

Set up a level where **a sun is unambiguously falling and nothing else yellow is
moving**:

1. Ideally a level with no sunflowers planted yet, so sky sun is the only mover.
2. Let a sun fall and sit uncollected for ~20s.
3. Game unpaused, focused, on top.

Then:

1. Freeze the game (multiplier 0.02).
2. Capture the screen, locate the sun blob.
3. Full-memory scan for an adjacent float pair matching the blob position within
   a few pixels - with the game frozen the tolerance can be tight.
4. Filter the hits by re-testing after the sun has moved: the real object tracks
   it, render buffers get rebuilt and will not match consistently.
5. Once one coin object is found, recover the array base and stride by looking
   for sibling structures with the same shape.

## Fields still needed

- array base and stride
- per-entry: x, y, active/alive flag, type (sun vs coin vs diamond)
- collected/claimed state, so already-taken items are not clicked again

An active flag matters more than it looks: sun spawns and despawns constantly,
so without it the tool would click stale coordinates.

## Runtime design once the array is known

```
every ~50 ms while enabled:
    for entry in coin array:
        if entry.active and entry.type in (sun, coin):
            post click at scaled(entry.x, entry.y)
    restore the game's mouse position afterwards
```

Coordinates scale from the 800x600 design space exactly like the seed packets.

Note the speed multiplier interacts: at high speed items fall faster, so the
poll interval should probably scale with it.
