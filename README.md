# Turtle Genesis

## v0.5.0-dev experimental self-sufficient base

Milestone 1 (parent turtle 10 creating child turtle 11) was verified in-game.
Milestone 2 is now implemented and passing **offline integration scenarios**,
but has **not** been verified in-game. Existing turtles 10 and 11 are
unchanged and won't be sent exploring: base bootstrap requires a fresh turtle
installed with an explicit `bootstrap` opt-in. The stage combines wood
harvesting, a chest crafted from logs, sand/stone collection, a furnace,
initial plank-fired charcoal, storage deposits, return-to-home checks,
and recurring charcoal replenishment when the existing base runs low.

See [Milestone 2 development plan](PLAN.md) and
[controller documentation](controller/README.md) for restrictions and tests.


Minecraft **1.20.1 Forge**, CC: Tweaked, Advanced Peripherals, Turtlematic.

## Current status — v0.4.0-dev first birth succeeded in Minecraft; v0.3.5 remains the pinned legacy installer

**New experimental track:** `0.4.0-dev` provides a Python controller and Lua worker in `controller/`, `tg/worker.lua` and `tg/workshop.lua`, with a **separate** installer `controller/install.lua`. The stable root installer still downloads the pinned v0.3.5 version. **Milestone 1 verified in Minecraft on 2026-10-24:** parent turtle **ID 10** autonomously placed its workstation, processed supplied materials, built, initialized, programmed and booted child **ID 11**. Both joined the Python controller. This required a carried chest item, a crafting table upgrade and supplied reproduction materials; it is **not yet** autonomous gathering. See [PLAN.md](PLAN.md) and [controller/README.md](controller/README.md).

- **Verified in Minecraft:** mining, manufactured offspring from supplied components, parent programming and booting an offspring.
- **Implemented and mock-tested (not yet verified in Minecraft):** furnace processing of raw iron, gold, cobblestone, sand and logs using temporary inventory storage.
- **Not implemented:** automated gathering of every manufacturing resource, harvesting/replanting trees, assembling infrastructure without supplied blocks, reliable long-range exploration.

This is a fixed-recipe robotics experiment, **not** a general AI or mature unattended survival colony.

## Update (in any installed turtle)

```sh
wget run https://raw.githubusercontent.com/ztawfik523-lgtm/self-replicating-turtles/main/install.lua
```

The installer downloads all runtime files from a **pinned Git commit**, syntax-checks them before installation, and does not call `api.github.com` (which may be unavailable from Minecraft). The pin is updated for each new release. Updates don't need `reboot`.

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

## Furnace processing (experimental v0.3.1)

This is another small building block toward using naturally mined/harvested materials rather than receiving finished ingots and blocks.

**Setup:** an empty furnace directly in front of the turtle and an **empty chest or barrel directly below**. Give the turtle one of the supported raw inputs and at least one coal or charcoal. Use the same Mining + Crafting Turtle already tested for manufacturing. No movement or reboot is necessary.

```sh
tg/main.lua furnace-check
tg/main.lua process iron
```

Available processing types: `iron` (raw iron → ingots), `gold`, `stone` (cobblestone → stone), `glass` (sand → glass) and `charcoal` (ordinary logs → charcoal). Each call processes at most one stack using available coal/charcoal, transfers materials through the chest and furnace inventory peripherals, waits for outputs, then retrieves them. It leaves the furnace and chest empty on success.

**Not yet verified in Minecraft:** even though CC: Tweaked documents adjacent generic inventory APIs, the furnace-to-chest item transfer may depend on Forge's inventory exposure. `furnace-check` checks the availability of methods, not actual item-transfer behavior. If `process` stops, read the saved stage from `tg/main.lua status` and inspect the furnace/chest before moving anything. Do not retry automatically. If the furnace and chest are manually emptied and contents accounted for, `tg/main.lua process-reset` clears the interrupted flag. Previous inventory is not deleted.

The furnace, chest, coal, and raw inputs must currently be supplied or acquired separately. The next goal is to make harvesting/mining feed this fixed processing-and-manufacturing chain automatically.

## Portable furnace station (v0.3.2 — experimental)

A useful autonomous primitive: the turtle can deploy a chest below itself, manufacture a furnace from eight cobblestone, place it in front, smelt raw materials, collect the processed goods, then pick up the now-empty furnace and chest. It does **not** need either block pre-positioned.

**Supplies in the turtle inventory:** 1 chest item, 8 cobblestone (or an already-crafted furnace), some raw iron, coal/charcoal and a **crafting upgrade** alongside the pickaxe if you want to craft the furnace. Alternatively, a carried furnace works without crafting. Keep the parent on ordinary terrain, not above machinery or lava; its front and below blocks must be air or simple ground (dirt, stone, etc.). It will dig away one ground block where needed to create a chest space.

```sh
tg/main.lua station iron
```

Other supported jobs: `gold`, `stone`, `glass`, `charcoal`. The program uses the verified furnace processing subsystem. **In-game station deployment and packing are unverified.** Reuses an existing chest/furnace if one is already installed but won't dig those up unless it placed them itself.

On failure the station state is retained: `tg/main.lua status` displays the current phase. Do not start a new station in the same location. After checking and safely removing any materials in the furnace/chest, `tg/main.lua station-pack` tries to reclaim only the equipment it placed. If a processing operation is still marked interrupted, empty/reconcile inventories before using `tg/main.lua process-reset` and then `station-pack`. Do not break a filled furnace/chest: you may lose materials.

**Limitations:** Still requires carrying a chest item and fuel. The next dependencies are making a chest from harvested planks and acquiring the cobblestone/fuel without player assistance. No need to build permanent stations or route back to them.

## v0.3.4: release repair

The previous station module was corrupted by an incomplete edit and could not be compiled. This release restores the earlier small portable-furnace station and removes unfinished `station-chest` and `station-drive` commands until they are implemented and tested. A GitHub Actions Lua syntax check now runs on subsequent pushes.

The `station iron` experiment requires a chest item and eight cobblestone (or a ready furnace) in the turtle's inventory, along with raw iron and coal. It places and packs its own blocks; it is still **untested in Minecraft**. Smelting with a manually positioned furnace/chest was successfully tested by the user.

## v0.3.5 recovery behavior

An interrupted station job now reconciles saved progress with the actual chest and furnace, tries to recover any unfinished smelt, and reclaims empty equipment placed by the program. Normal recovery should not require deleting any flag or giving manually prepared materials. This is still a narrowly scoped recovery patch; it does not implement the future continuously running production/replication lifecycle. Do not consider it verified in Minecraft until the integration test passes.
