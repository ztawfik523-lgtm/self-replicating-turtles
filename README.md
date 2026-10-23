# Turtle Genesis

Minecraft 1.20.1 Forge • CC: Tweaked • Advanced Peripherals • Turtlematic

**Experimental v0.1.4**: persistent turtle state, fuel safeguards, limited mining survey and a lab reproduction test. Not autonomous or verified in Minecraft yet.

## One-command installation (inside a turtle)

```sh
wget run https://raw.githubusercontent.com/ztawfik523-lgtm/self-replicating-turtles/main/install.lua
```

After installation, type `reboot`, then `tg/main.lua probe` and `tg/main.lua status`.

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

If v0.1.3 failed at the **inserted** stage, leave the item in the disk drive and run `tg/main.lua resume` after updating/rebooting. The resume command is only allowed at the precise inserted stage. If it fails later, report the stage; do not retry blindly.
