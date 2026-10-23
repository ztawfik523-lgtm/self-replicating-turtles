# Turtle Genesis

Minecraft 1.20.1 Forge • CC: Tweaked • Advanced Peripherals • Turtlematic

**Experimental v0.1.2**: persistent turtle state, fuel safeguards, limited mining survey and a lab reproduction test. Not autonomous or verified in Minecraft yet.

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
