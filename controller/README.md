# Turtle Genesis controller track — 0.4.0-dev

**Status (2026-10-24): First real Minecraft end-to-end birth succeeded.**
The parent turtle, computer **10**, built the starter workshop from supplied
items, processed inputs, produced/programmed/fueled/booted child computer **11**.
Both parent and child connected to the Python controller. The run initially
encountered a missing crafting upgrade; after a targeted repair it resumed the
same birth and finished. This is **Milestone 1**, not autonomous material gathering.
The stable pinned v0.3.5 root `install.lua` remains separate.

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

The turtle **places** its first chest from a supplied chest ITEM. No chest,
furnace or disk drive needs to be pre-positioned in the world. CC:Tweaked
requires all unrelated inventory slots empty for turtle.craft, including slots
outside the 3x3 grid, so crafting that initial chest from a mixed kit is not
supported. During autonomous gathering the turtle will make its first chest
*before* filling its inventory with other resources.

## Offline first-birth material budget

One Mining + Crafting Turtle with both upgrades already equipped and starting
movement fuel. In inventory:

- **1 chest ITEM** for the initial storage bootstrap;
- **14 same-type planks** for offspring;
- **22 cobblestone**: 8 for the furnace, 14 to smelt for disk drive + computer;
- **7 raw iron**;
- **3 redstone**, **3 diamonds**, and **6 sand**;
- **8 coal or charcoal**: 4 for furnace work, 4 for child start.

The turtle needs diggable terrain below, a
workstation cell ahead, and an empty child deployment cell behind it. The
workflow handles these in a bounded way but does not yet search for better base
locations.

This starter-material workflow has **now been verified end-to-end in Minecraft**
with a crafting-upgrade repair during the run. Recoverability from every
possible interruption has not been proven.

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
Lua worker state, source-level worksite execution, first-chest item setup and
rejection of invalid chestless mixed inventory, offspring inheritance, repeated-job protection.

`tests/controller_installer_sim.lua`: full install, network failure before
changes, copying failure rollback, interrupted-install recovery.

CI compiles all Lua source files and runs existing recovery regression tests.

## Known technical gaps

- The opt-in M2 runtime **does** gather wood, sand, cobblestone and
  charcoal in bounded simulated landscapes, but has **not** yet been run
  end-to-end in a real Minecraft survival world.
- Autonomous acquisition of iron, redstone and diamonds for a new offspring
  is still missing, as is a sustainable, replenished sapling farm.
- Intermediate `factory.make()` interruption recovery and arbitrary
  `replicate.resume()` stages are not yet fully generalized.
- Chunk loading and multiplayer colony territory management are still future
  work; the Python service cannot tick unloaded Minecraft chunks.
- Controller URLs must be reachable from the Minecraft JVM. Real-game
  peripheral, crafting, disk-drive and placement behavior still needs the
  **single, worthwhile** Minecraft milestone test.

## Milestone 1 acceptance evidence — 2026-10-24

- Parent ID 10: screen reported `Replication: child_booted`,
  `Replication (lab test) complete`, `Birth: complete`, and
  `Birth sequence complete; worksite remains installed`.
- Child initialized as computer ID 11 and subsequently connected to the controller.
- Python controller: `Turtle 11 connected, recovery=idle` followed by
  `Turtle 10 connected, recovery=idle` after a reboot/reconnect.
- A `websockets.exceptions.ConnectionClosedError` traceback occurred while the
  turtle rebooted, but the Python service continued accepting connections.
  The controller now treats these disconnects as expected informational events.
- The test used stocked materials rather than autonomous wood/ore acquisition.

**Next human-visible acceptance test:** one startup that harvests wood, makes its
first chest before inventory fills, gathers stone and sand and establishes a
fuel-producing starter base. No intermediate player tests per operation.

## Milestone 2 — new opt-in starter-base runtime (v0.5.0-dev)

The new `tg/bootstrap.lua` does not use supplied wood, sand, coal, or
cobblestone. It requires a fresh Mining + Crafting Turtle with an empty item
inventory, at least **140 loaded movement fuel**, and a wooded surface site
with reachable sand and shallow stone. It cuts vertical tree logs, crafts its
first chest before its inventory fills, establishes an offset stone shaft,
makes a furnace and uses a wood plank to ignite the initial charcoal batch.

**This stage is still simulated only.** Four cardinal search rays with a
12-block radius are a practical initial bound, not a guarantee of useful
trees/sand anywhere in a seed. Sapling planting is opportunistic and does not
yet establish a perpetual tree farm.

`controller/install.lua` accepts an explicit second argument
`bootstrap` for this milestone. Without that argument the new worker stays
in normal/controller mode and **will not** bootstrap automatically. Thus
upgrading turtles 10/11 cannot cause unwanted wandering.

Do not request another user micro-test. Wait for all milestone code and
manifest tests to pass, then only ask for one complete, substantial
wood/stone/sand-to-furnace-and-charcoal run.

The main M1 controller and its already-installed copies remain unaffected;
the new runtime is not automatically delivered to them.

## Repeatable fuel production

After M2 reports a completed base, the controller compares charcoal/coal in
the turtle **and observed storage**. If fewer than three pieces remain,
it assigns one bounded `fuel_cycle` to the same turtle. The Lua routine
takes items from storage, harvests reachable logs, uses wood planks as a
fuel source when coal and charcoal are exhausted, smelts more charcoal,
and returns other inventory to its original chest. A persistent job ID
avoids running an already-finished fuel batch twice.

Offline tests now cover draining the original output, a second harvest,
storage retention, same-job replay protection, and controller scheduling.
No indefinite sapling supply has been proved; the process requires
reachable natural trees until sapling farming is implemented.

## Reliability audit: staging chest and fuel-job completion

A repeated fuel job treats an unfinished furnace batch as a separate
transaction: its `tg/process.lua` state and staging chest are reconciled
**before** retrieving general-purpose chest contents. The turtle checks that
its empty slots can conservatively hold the occupied chest slots *before*
starting inventory transfer. If the chest contains more stacks than the turtle
can accommodate, the job pauses without partially emptying storage.

The `fuel_cycle` ID is recorded as complete **only after** surplus inventory
was deposited successfully. A full or unavailable chest leaves the same job ID
pending, rather than falsely reporting a successful fuel run. An offline mock
explicitly simulates a furnace power cut, a failed final deposit, replay of the
same job ID, and an over-capacity chest. These are safeguards, not proof of
unattended survival in every Minecraft environment.

**Still unsupported:** guaranteed movement reconciliation after a power loss
mid-step, general obstacle bypass, arbitrary terrain and renewable forestry.
No extra player micro-tests are requested for these incomplete features.

## Engineering audit — 2026-10-25

The previous M1 test is still the only in-game verification. The M2 tree/sand/
stone/base/charcoal implementation is retained but explicitly unverified in
Minecraft. The following gaps were found and addressed offline:

- **Duplicate TCP/WebSocket turtle ID:** Reject an already-connected ID
  *before* persisting its hello snapshot. A rejected connection no longer
  unlocks an active turtle's session. Tested using concurrent WebSockets.
- **Movement fuel versus stored fuel:** M2 now checks whether the turtle can
  safely complete travel by consuming earned charcoal when required. The
  controller can schedule a refill even if the chest has enough charcoal but
  the turtle's own movement gauge is low.
- **Interrupted furnace manufacture:** If the eight cobblestone were already
  staged into the initial chest when a crash occurred, M2 retrieves those
  ingredients before deciding to mine new stone, then resumes the same job.
- **Offline test coverage:** Live-connection duplication, low movement fuel,
  the real `fuel.ensure` logic, crash during first furnace recipe, and
  repeat charcoal-batch behavior.

The first real M2 milestone remains one **complete**, player-visible run in
suitable terrain, not dozens of tiny manual probes. No existing turtle is
automatically switched to M2; that remains explicit opt-in.
