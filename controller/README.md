# Experimental Turtle Genesis Python Controller

The first integrated control-plane slice. It accepts turtle inventory/position snapshots over native CC: Tweaked WebSockets, maintains job IDs and reconnect journals, computes the offspring resource bill, and schedules **existing, already implemented** Lua `process` or `produce` jobs when the needed machinery is present. It does **not** yet construct a base, find ores, or start at turtle boot. Do not install it as a milestone release.

Run from repository root: `python -m pip install -r controller/requirements.txt` then `python -m controller.server`. Defaults to `ws://127.0.0.1:8765`, local-only, with saved state in `controller/colony.json`. A turtle worker would run `require('worker').run('ws://<controller-host>:8765')` after integration into the installer. The current installed turtles are intentionally untouched. Accessing private IPs from Minecraft requires an appropriate CC: Tweaked HTTP allow rule. Controller has **no authentication**; do not bind it to untrusted networks.

Offline tests: `python -m pip install pytest pytest-asyncio websockets` then `python -m pytest -q tests/test_controller.py`; Lua test: `lua5.2 tests/worker_sim.lua`. The real Minecraft bridge remains unverified.

## Experimental single-job birth workshop

The controller now recognizes a complete first-birth kit and queues one `birth`
job, rather than individual network calls for crafting and smelting. The Lua
worker delegates that job to `tg/workshop.lua`, which installs a chest, crafts
a furnace, processes iron/stone/glass, crafts panes and disk drive, and calls
the previously in-game-verified offspring manufacturing and cloning routines.

**This is an offline prototype, not a live-turtle release.** A starter **chest
item** is currently required. This avoids pretending the turtle can craft its
first chest from a full inventory of unrelated materials: CC:Tweaked requires
other crafting slots to be empty. The later wood-bootstrapping phase creates a
chest before resource gathering fills the turtle.

Initial mock kit: 1 chest item; 22 cobblestone; 7 raw iron; 3 redstone; 6 sand;
3 diamonds; 14 matching planks; 8 coal or charcoal; equipped mining+crafting
upgrades. No pre-positioned infrastructure. This is not a self-sustaining build,
and worker inheritance/controller registration is not yet integrated.
