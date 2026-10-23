# Turtle Genesis

Minecraft **1.20.1 Forge**, CC: Tweaked, Advanced Peripherals, Turtlematic.

## Current status — 0.3.0

- **Verified in Minecraft:** autonomous tunnel mining, parent programming and booting a pre-made offspring.
- **Implemented and mock-tested (not yet verified in Minecraft):** crafting a new Mining + Crafting Turtle from ordinary components, with the parent's inventory managed automatically.
- **Not implemented:** automated gathering of every manufacturing resource, raw-ore smelting, charcoal farming, building a self-supplied disk drive, reliable long-range exploration.

This is a fixed-recipe robotics experiment, **not** a general AI or mature unattended survival colony.

## Update (in any installed turtle)

```sh
wget run https://raw.githubusercontent.com/ztawfik523-lgtm/self-replicating-turtles/main/install.lua
```

The installer resolves a single Git commit for every file and checks the download before installation. Updates don't need `reboot`.

## Lab manufacturing — first turtle from components

Use an existing **Mining Turtle** or **Crafty Mining Turtle**. If it has only a pickaxe equipped, supply one extra crafting table in its inventory; the script equips it to the free upgrade slot. The turtle needs:
- **One empty chest or barrel immediately below it**, used as temporary inventory space.
- **One empty disk drive immediately in front** for the combined `produce` test.
- **An empty deployment block immediately behind**, with ground below for the child.
- In its inventory: **14 planks of the same type, 7 stone (not cobblestone), 7 iron ingots, 1 redstone, 1 glass pane, 3 diamonds, 4 coal or charcoal** (and the extra crafting table if needed).
- Make sure the parent has enough fuel and is not on an interrupted/uncertain movement state.

Commands:

```sh
tg/main.lua materials
tg/main.lua make
```

`make` only crafts the offspring into the parent's inventory; it does **not** deploy it. To do both crafting and the previously tested code inheritance/deployment in one command (start with the raw components, not an existing child item), run:

```sh
tg/main.lua produce
```

**Do not run both `make` and `produce` on the same supplied resources.** A successful `make` consumes them. With `produce`, the parent attempts eight crafting operations (sticks, chest, table, pickaxe, computer, turtle and two upgrades), initializes the item in the drive, transfers source files and fuels/boots it.

The script checks the full resource bill before starting, uses the chest below to stage non-recipe items, verifies each crafting recipe with `turtle.craft(0)`, and retrieves staged materials after each craft. A failed step is deliberately **not** restarted automatically. Check inventory and chest before resuming; `tg/main.lua collect` retrieves material in the chest, and `tg/main.lua factory-abort` clears the unfinished crafting flag after retrieval. Consumed materials cannot be recovered by these commands.

All recipes were based on the CC: Tweaked recipe source, including the two upgrade directions. The actual 1.20.1 Forge integration still requires testing in-game.

## Previous commands

- `tg/main.lua status` — inspect generation, navigation and mining state.
- `tg/main.lua auto 4` — older blind mining prototype (**not recommended** as the next development focus).
- `tg/main.lua stop` — disable idle automatic mining.
- `tg/main.lua rebase` — re-anchor after interrupted movement; abandons the old mining route.
- `tg/main.lua replicate` — clone a pre-made, supplied turtle item using a disk drive.
- `tg/main.lua resume` — resume supported partial replication state.

## Inspiration and design notes

- https://github.com/Jumbub/replicating-robots — historical self-replication survival challenge with a simple initial environment.
- https://github.com/SPOOKEXE/computercraft-turtle-botnet — state-persistent self-replication ambitions; unlike that project, Turtle Genesis does not depend on Python/websocket orchestration.
- https://tweaked.cc/module/turtle.html — official crafting and turtle API.
- CC: Tweaked RecipeProvider.java: patterns `###/#R#/#G#` for computer and `###/#C#/#I#` for turtle.

The design goal remains unattended reproduction from one starting turtle. The new manufacturing phase is a component test toward it, not completion of that goal.
