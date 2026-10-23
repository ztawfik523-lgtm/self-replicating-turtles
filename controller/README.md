# Turtle Genesis controller track — 0.4.0-dev

**Status:** Experimental Python/Lua integrated first-birth build. Offline test suite
passes; full Minecraft implementation **has not been verified in-game**. Do not
confuse this with the stable v0.3.5 `install.lua` path.

## Architecture

The Python controller stores turtle identities, inventory snapshots, resource
requirements and durable jobs. Lua workers use CC: Tweaked's built-in WebSocket
API, execute bounded operations and reconnect after interruption. Workers inherit
the controller address and runtime when a child turtle is programmed.

The first-birth worker includes `tg/workshop.lua`, which takes one `birth` job:
craft/place a chest; craft/place a furnace; smelt raw iron, cobblestone and sand;
craft panes and a disk drive; use the in-game-verified factory/clone/reproduction
routines to program and start a child. An existing furnace is reclaimed when the
disk drive must occupy the same front block. This is a small *starter workstation*,
not a complete persistent colony infrastructure.

The first chest is crafted from raw planks using the 16 inventory slots. There is
**no pre-positioned chest, furnace, disk drive or supplied chest item**.

## Offline first-birth material budget

One Mining + Crafting Turtle with both upgrades already equipped and starting
movement fuel. In inventory:

- **22 same-type planks**: 8 for the first chest, 14 for offspring;
- **22 cobblestone**: 8 for the furnace, 14 to smelt for disk drive + computer;
- **7 raw iron**;
- **3 redstone**, **3 diamonds**, and **6 sand**;
- **8 coal or charcoal**: 4 for furnace work, 4 for child start.

Starting materials occupy seven item-stack types, leaving room for chest crafting
without an existing storage chest. The turtle needs diggable terrain below, a
workstation cell ahead, and an empty child deployment cell behind it. The
workflow handles these in a bounded way but does not yet search for better base
locations.

This budget and physical arrangement are **simulated**, not confirmed end-to-end
in a real Minecraft world.

## Running the prototype once a Minecraft milestone test is warranted

Controller (in the repository on the computer hosting Python):

```sh
python -m pip install -r controller/requirements.txt
python -m controller.server
```

Defaults: `GENESIS_HOST=127.0.0.1`, `GENESIS_PORT=8765`,
`GENESIS_STATE=controller/colony.json`. Override via environment variables
when the Minecraft JVM/server runs elsewhere.

Experimental turtle install entry: `controller/install.lua` downloads an
immutable tested revision of the 18 runtime sources, validates Lua syntax,
retains turtle state, rolls back failed installs, saves the controller address,
and starts the worker. It is **not** the stable installer. CC: Tweaked's HTTP
rules must permit the exact controller address; local/private addresses are
restricted by default. The server is unauthenticated: bind only to a trusted
local interface/network.

No user installation or player testing is needed merely because this code
exists. Request one meaningful full base-to-child test when the integration is
ready, not per commit.

## Automated quality gates

`tests/test_controller.py`: WebSocket real loopback, jobs, interruptions,
registry, child connection, controller inventory updates, material accounting.

`tests/worker_sim.lua`, `tests/workshop_sim.lua`,
`tests/bootstrap_chest_sim.lua`, `tests/clone_worker_sim.lua`:
Lua worker state, source-level worksite execution, realistic 16-slot chest
bootstrap, offspring inheritance, repeated-job protection.

`tests/controller_installer_sim.lua`: full install, network failure before
changes, copying failure rollback, interrupted-install recovery.

CI compiles all Lua source files and runs existing recovery regression tests.

## Known technical gaps

- This does **not** acquire wood, sand, ore, diamonds or fuel from terrain.
- Intermediate `factory.make()` interruption recovery and arbitrary
  `replicate.resume()` stages are not yet fully generalized.
- Chunk loading and multiplayer colony territory management are still future
  work; the Python service cannot tick unloaded Minecraft chunks.
- Controller URLs must be reachable from the Minecraft JVM. Real-game
  peripheral, crafting, disk-drive and placement behavior still needs the
  **single, worthwhile** Minecraft milestone test.
