# Turtle Genesis

Minecraft 1.20.1 Forge • CC: Tweaked • Advanced Peripherals • Turtlematic

**Experimental v0.2.1**: persistent turtle state, fuel safeguards, limited mining survey and a lab reproduction test. Not autonomous or verified in Minecraft yet.

## One-command installation (inside a turtle)

```sh
wget run https://raw.githubusercontent.com/ztawfik523-lgtm/self-replicating-turtles/main/install.lua
```

After installation, run `tg/main.lua status`. No reboot is needed to use updated commands.

The installer resolves the current GitHub commit, downloads and syntax-checks all files from that immutable revision before replacing any. It retains existing `/tg/state.dat`, `/tg/seed.dat`, and logs. It preserves an existing `/startup.lua` as `/startup.lua.genesis-backup` the first time it runs.

**Important:** running `wget run` downloads and executes Lua from this public GitHub repository. Review `install.lua` before running if desired, and ensure CC: Tweaked HTTP access is enabled.

## Development

`tg/main.lua survey 4` attempts a short, destructive mining survey. Run only where digging is safe. `tg/main.lua install front` and `tg/main.lua replicate` are *untested Minecraft integration experiments*, not proven reproduction.

The source code is intentionally small and independent of client-only mods. This repository contains Lua software; it does not install Minecraft mods.

## Next test: lab reproduction

1. Place an **empty disk drive directly in front** of the parent turtle; leave the block immediately **behind** the parent empty (with safe ground beneath it).
2. Put exactly **one spare Mining Turtle item** and at least **4 coal/charcoal** in the parent's inventory. The parent must already have fuel.
3. Run `tg/main.lua replicate`.
4. A successful test programs the child in the disk drive, retrieves it, places it behind the parent, transfers fuel, and powers it on. Check the child terminal for generation=1.

The entire sequence has **not yet been tested in Minecraft**. It deliberately halts on an interrupted or partially completed replication rather than blindly duplicating the attempt. On failure report the printed `Replication:` stage; do not run `replicate` again without checking the world and state.

## Fresh turtle initialization and interrupted drive insertion

A new uninitialized turtle item has no mounted filesystem. v0.1.4 tries to extract it from the drive, temporarily place and power it on to assign an ID, dig it back into inventory, return it to the drive and install the source files. The Mining Turtle must have an unobstructed air block behind it, directly opposite the drive. This physical sequence still requires an in-game test.

If v0.1.3 failed at the **inserted** stage, leave the item in the disk drive and run `tg/main.lua resume` after updating. The resume command is only allowed at the precise inserted stage. If it fails later, report the stage; do not retry blindly.

## Placement-stage diagnostics (v0.1.5)

When an initial turtle has been placed but is not detected as a peripheral, leave it in place. Run `tg/main.lua diagnose` to inspect the front block and peripheral type. If the replication stage is `init_placed`, `tg/main.lua resume` rechecks the placed turtle and continues only when the expected block and computer methods are available. This avoids blindly creating another child.

## Autonomous mining v0.2

The miner descends 24 blocks from its starting location, then explores four compass directions with tunnel radius 8, 16, 24, and 32. It descends another 16 blocks and repeats, up to seven levels. It checks for ore ahead, overhead, and below, refuels from coal/charcoal in its inventory, preserves navigation progress and discards excess common stone/dirt once the inventory fills.

In a **disposable survival/creative test world**, move the parent away from the disk drive to safe ordinary terrain, put coal in the turtle, and run:

```sh
tg/main.lua auto 4
```

This runs four tunnel passes unattended and then pauses. To run until planned areas are exhausted or fuel/terrain prevents further progress, use `tg/main.lua auto`. Existing programs are loaded directly; **no reboot is required after installation**.

`tg/main.lua status` displays mining state. Terminate a live program with Ctrl+T; then `tg/main.lua stop` disables automatic restart. A saved physical `pending` action still requires manual inspection before auto-resuming, to avoid a guessed position after a power loss.

This is **not** yet fully self-sustaining or self-replicating. It cannot automatically craft furnaces, compute all turtle recipe dependencies or build storage; it may stop if it finds insufficient coal or a liquid/unbreakable obstacle. Extensive chunk loading away from players also requires an installed and configured turtle upgrade or other chunk-loading mechanism.

When a later offspring is created from a parent that has enabled autonomy, the offspring inherits the auto-start setting (not the parent's map and inventory).

## v0.2.1: recovery and safe interruption

The v0.2.0 miner can preserve `pending=back` if Ctrl+T kills a turtle movement before its result is recorded. The engine cannot determine whether the move physically happened. **Do not blindly delete the pending flag or assume a position.** When already stopped underground, `tg/main.lua rebase` backs up the original state, discards the old route, and treats the turtle's current block as a new local origin; this does not move the turtle or remove its inventory. Subsequent `tg/main.lua auto 4` first moves 16 blocks deeper to avoid re-mining the old tunnel network, then starts four new tunnels. Only use rebase on a stationary turtle with no active reproduction or separate survey.

When mining normally, open the turtle terminal and **press S** (without Enter) to request a graceful stop. It finishes returning to its tunnel entrance first, then stops. Do not use Ctrl+T to stop ordinary mining; it can interrupt physical commands. The `stop` command remains available to disable autostart while idle.
