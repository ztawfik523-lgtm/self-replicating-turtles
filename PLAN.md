# Turtle Genesis — Engineering Plan v3
Updated: 2026-10-23
Project: Minecraft 1.20.1 Forge + CC: Tweaked, Advanced Peripherals, Turtlematic and other existing addons as useful
Goal: autonomous, repeatable survival-world reproduction from an initial turtle.
Rule: no Minecraft mod or game-specific API written for this project. An external Python service, existing programs, and modifications to those programs are allowed.

## Executive design decision

**Recommended starting architecture:** one external Python controller + a small Lua turtle runtime + one persistent starter base. Prefer existing controller and turtle libraries over rewriting them. This is a *testable selection*, not a license to rewrite the project before working functionality is preserved.

Python: colony goal scheduling; recipe/resource dependency ledger; persistent map, worksite and task assignment; diagnostics; planning across turtles.
Lua: perform bounded physical jobs; inspect/report blocks and inventories; enforce local fuel/return guard; checkpoint non-idempotent actions; finish/stop safely on network loss; reconnect automatically.
Minecraft: source of truth for physical state. Controller must not assume hidden world data it hasn't received through legitimate turtle/peripheral observations.
Base: known home, reusable chest/storage, furnace, drive for offspring filesystem initialization, safe deployment area, mine and wood access. No unnecessary building or station packing.

The first turtle must be able to do all necessary jobs. Specialization begins only after multiple turtles exist. Newborn turtles receive the same worker code and register with the controller automatically. The controller is allowed to become essential to ongoing planning; reliability on disconnect is a required design goal, not a reason to prohibit external coordination.

### Diagram

```text
                      PYTHON CONTROLLER
           goals / resource ledger / map / scheduler
                              |
                    WebSocket / RPC
                              |
           +------------------+------------------+
           |                  |                  |
     Turtle worker 1    Turtle worker 2    Turtle worker N
     local safety       local safety        local safety
     movement/craft     gathering           expansion
           \                  |                  /
            -------- SHARED BASE / STORAGE -------
                 furnace / disk drive / stock
```

## Starting conditions and target

**Integration test (first):** One equipped mining+crafting turtle with raw materials *in its inventory* (and enough initial fuel) but **no pre-positioned furnace, chest or disk drive**, no human task commands beyond start. Objective: build worksite, process resources, craft/program/place/start a child. The first turtle and controller may still be manually provisioned with starting resources; this only validates automation plumbing.

**True autonomy test (later):** One equipped turtle, modest starting fuel and installed worker, in an ordinary survival world, plus a running controller/server. No player-provided resource piles, existing workshop, GPS network or placed fuel/ore. It must gather what it needs to build a base and reproduce. The child must also gather/reproduce, perhaps using shared or newly built infrastructure.

A server restart or chunk unload means software may stop executing until loaded again. Existing chunk-loading solutions must be tested in the actual modpack before claiming unattended operation. "Continuous" means repeating goals when executable, not infinite Minecraft execution in unloaded chunks.

## Core approach: assemble the system from existing code

| Priority | Source | Potential use | Integration decision |
| --- | --- | --- | --- |
| 1 | https://github.com/neumond/python-computer-craft | Python-side CC API over a Lua bridge; quickest Python-controller experiment | Test one physical move/inspect/inventory/task with reconnection. If robust, reuse rather than writing a bridge. |
| 2 | https://github.com/SPOOKEXE/computercraft-turtle-botnet | Python WebSocket controller, task/behavior framework, serialization, resource/recipe ideas | Review and reuse pieces where better than Pythonized CC; archived and not a demonstrated completed self-replicator. Avoid merging both frameworks blindly. |
| 3 | https://github.com/fnuecke/lama | Local position and movement recovery, including fuel-based reconciliation | Prototype as **single** movement/refueling authority, or choose an alternative. No parallel nav trackers. |
| 4 | https://github.com/helpmyRF24isntworking/computercraft | Mapping, existing advanced miners, home unloading, efficient mining jobs | Its complete system assumes modems and GPS; inspect whether standalone mining/mapping can be reused or adapted. |
| 5 | https://github.com/Equbuxu/mine | Existing local ore vein/mining/fuel/unloading techniques | Consider borrowing algorithmic strategy or replacing the old miner with adapted code. |
| 6 | https://github.com/Tjstretchalot/turtles2 | Restart-friendly movement, tree farming and mining | Focus on forestry/waypoint concepts if compatible; don't graft its entire framework over ours automatically. |
| 7 | https://github.com/egor-oleg/aegis-autocraft | Sophisticated recursive manufacturing using CC storage networks | Defer; may be valuable at scale, but its wired network and staging requirements are far more than a first base needs. |
| Later | Advanced Peripherals Geo Scanner / Turtlematic | Ore scanning, chunk loading, specialized interactions | Validate actual APIs, crafting/FE cost and 2-slot turtle upgrade conflicts before depending on them. |

**Selection rule:** Test a candidate on an isolated turtle/world first. Select ONE command bridge, ONE movement authority, ONE mining executor; compose them behind a small interface, rather than accumulating competing libraries. A script from another project is an interchangeable executor, not necessarily our entire architecture.

### Minimal controller ⇔ turtle protocol

Define these capabilities (not one Lua script per call):
- `snapshot()`: ID, generation, selected upgrades, fuel, inventory, location estimate, nearby observations, worksite/job status.
- `move_to(goal)`: bounded local path, obstacles, remaining fuel and stop/retry reason.
- `gather(resource, budget, region)`: tree/stone/sand/ore collection using tested local programs.
- `deposit(base)`: put gathered materials into assigned storage; retrieve essentials.
- `process(recipe, count)`: furnace job using available fuel and input, return consumed/produced.
- `craft(recipe/count)`: verify inventory and output; safe chest staging.
- `reproduce()`: use existing validated factory + initialized disk-drive cloning + placement + boot.
- `inspect/status`, `cancel/stop`, and `reconnect/resume`.

Prefer **high-level bounded jobs** to network commands for every block. Each job reports `started/progress/succeeded/blocked/failed` and physical changes. Use monotonic job IDs and resumable job state; the controller must not blindly dispatch a duplicate craft or birth after reconnect.

A temporary network outage should leave the turtle finishing its current safe bounded job or waiting/retrying, not wandering indefinitely. A controller restart restores the task queue and reconciles inventory/real-world state.

### State is not a permission lock

Persist: turtle ID/generation, base/route information, map discoveries, active job ID, a minimal journal only around irreversible or ambiguous actions (moving, crafting, placing a turtle, deploying a drive). Reconstruct physical results by inspection after a reboot or reconnect. An empty furnace and completed output are success, not an error state.

Movement is the special case: if a restart occurs during a move, block inspection alone cannot always recover exact pose. Evaluate LAMA's fuel-based approach, GPS if legitimately available, or robust local landmark/home tracking. Test forced restart mid-action, not just normal completion.

## The base design: minimum viable workshop

One known location, simple enough for one turtle to build:
- **Storage** in a chest or barrel, initially one, expanded if useful; resource ledger counts contents plus turtle inventories.
- **Furnace** and renewable fuel loop. Leave installed; rebuild only if necessary.
- **Disk drive** when first reproduction is possible. One drive can serve multiple births.
- **Safe approach/departure, child deployment spot**, and a return route.
- **Optional wood area / mine entrance**, not a required elaborate structure.

Start with the current working geometry where practical: chest below turtle and furnace/drive placed/changed in front. The turtle may need to recover an empty front block to swap from furnace to drive. Do not tear down permanent components unnecessarily. Base locations and inventories must be discoverable and restorable after a reboot.

The initial base is a **hub, not a prison**. Children can contribute from shared storage and later found nearby outposts. Don't implement distributed colony coordination before a second turtle can use the first base.

## Resource dependency engine (single ledger)

Controller computes resource shortages using actual inventory **and storage**, then selects the cheapest feasible action.

Verified offspring craft bill from our repo: 14 same-type planks, 7 stone, 7 iron ingots, 1 redstone, 1 glass pane, 3 diamonds, 4 coal/charcoal delivered to child. These are *not* the complete raw-world prerequisites.

First base additionally needs:
- 8 planks for initial chest (or a separate chest obtained elsewhere).
- 8 cobblestone for furnace.
- 7 extra smelted stone + 2 extra redstone for disk drive, using the recipe actually present in our repo.
- Sand/glass smelting and six-glass-to-sixteen-glass-pane crafting.
- More coal/wood/charcoal for *parent* movement, smelting and repeated offspring, not just four items in the child.
- Wood for an initial crafting table upgrade if not already equipped.

A first worksite thus needs at least roughly 22 cobblestone for furnace and 14 stone inputs, 3 redstone for computer+drive, 7 iron ingots, 3 diamonds, six sand for the first glass-pane batch, planks, and continuing fuel. Verify all crafting recipes in this Minecraft/mod build before assuming the bill is complete. Infrastructure is **reusable**, so later births are cheaper.

Bootstrap order prevents cyclic dependencies:
1. Refuel safely from the original reserve.
2. Gather wood; make plank/crafting capacity and first chest **before** a full miscellaneous inventory.
3. Establish home/storage, gather 8 cobblestone and place furnace.
4. Burn wood/planks initially if coal unavailable; make charcoal, save enough fuel to return from trips.
5. Obtain sand/glass and access to mines.
6. Mine iron/redstone/diamonds by need, store resources in chest; process iron/stone/glass.
7. Make the drive and offspring when the full bill is satisfied; transfer worker code, fuel and boot.
8. Loop, share/replenish materials and expand when resources or space require it.

**Do not waste a complete furnace cycle to test the same component again.** We already verified iron smelting and offspring manufacture/boot individually. Integration is the remaining test.

## Milestones: work and acceptance gates

### P0 — Pick the software foundation
Implementation:
- Snapshot working factory/process/clone version, keep reproducible world.
- Try Pythonized ComputerCraft with ONE turtle: controller starts, retrieves live inventory+fuel/inspect, assigns a bounded task, observes result.
- Force client/controller restart and recover the connection; validate multiple outstanding task protections.
- If it fails reliability requirements, adapt the MIT BotNet worker/WebSocket architecture. Avoid writing a replacement bridge until both are evaluated.
- Validate LAMA separately for navigation across interrupt/refuel; choose one tracker.
- Build automated mock/harness with real example inputs and regression checks; syntax+behavioral CI before releases.

**Gate P0:** one host-to-turtle task completed, retried safely after interruption; launcher repeats startup automatically; no custom Minecraft mod. Mark what was checked in-game versus mocked.

### P1 — One-turtle base and autonomous manufacture (raw resources supplied)
Implementation:
- Controller identifies missing infrastructure and instructs turtle to build the small worksite.
- Inventory/staging manager handles 16 turtle slots, chest, crafting grid and output stacks.
- Use existing furnace + factory + clone rather than rewriting tested recipes.
- Manage furnace/drive swap, full bill and resource accounting without manual commands.
- Newborn registers to same controller via inherited worker bootstrap.
- Release only after passing syntax, scenario/unit tests and a clean installer/child manifest.

**Gate P1:** one startup from raw inventory; NO player-placed furnace/chest/disk drive; automated smelt → craft → initialize → program → fuel → deploy → boot. Parent and child both reach ready state.

### P2 — Self-starting base, wood and fuel loop
Implementation:
- Adapt a tree harvesting/planting executor and return-to-home logic. First chest from harvested wood.
- Gather cobblestone and sand. Build permanent chest+furnace with found resources.
- Use wood as initial furnace fuel; produce charcoal, account for parent's movement reserve.
- When inventory full, return/deposit; no item dumping if needed later.
- Handle missing trees by searching/relocating within fuel bounds.

**Gate P2:** supplied only initial fuel, turtle gathers wood/stone/sand, establishes its own storage and produces a net usable fuel reserve in-game. No raw-material supply by player.

### P3 — Deficit-driven ore mining
Implementation:
- Adapt existing ore/vein mining executors; stop predetermined blind-tunnel "auto" strategy.
- Navigate down to appropriate depths safely, inspect/search and map traversable paths, carry limited loads back to base.
- Mine iron, redstone, diamonds and coal if found; account for smelting, tool slots, drops, lava, caves, gravel and fuel.
- Consider Geo Scanner only when available and affordable in the survival tech tree; Advanced Peripherals geo scanner costs FE/has cooldown and turtle only has two upgrade slots, so it's not a free capability.
- Improve through comparative tests; avoid asserting all seeds are equally easy.

**Gate P3:** on normal generated terrain, gather the COMPLETE bill for an offspring with no injected ores/ingots/diamonds/redstone, process/store them and return to base.

### P4 — The first real autonomous offspring
Implementation:
- Same controller job scheduler autonomously decides when resources are sufficient.
- Manufacture/program/deploy/boot a child through proven mechanisms.
- Child inherits runtime and controller address, has suitable fuel, exits departure lane, gets a new resource task automatically.
- Controller counts a birth exactly once and doesn't duplicate when recovering from disconnection.

**Gate P4:** start from one turtle with initial fuel; it gathers and creates one offspring. **Then the child participates without manual intervention.** Run a second sequence proving a grandchild is made without manually giving materials/commands. Sharing the original base is allowed; lineage must be genuine.

### P5 — Repeatability, additional bases and scaling
Implementation:
- When the first base is crowded or mining becomes uneconomical, turtle establishes a new worksite using a stocked bootstrap kit or locally gathered items.
- Assign mining areas to avoid overlap/collision; maintain shared storage and resource transfers only as complexity makes them necessary.
- Validate existing chunk-loading strategy (including upgrade conflicts) across movement/world save. Test controller/game restart, blocked route, bad biome, no fuel, full storage, child death.
- Add dashboards only for diagnosing actual issues, not as an early dependency.

**Gate P5:** multi-generation unattended growth across several test worlds/seeds, with metrics: births, generations, manual interventions after start, fuel per usable resource, failed/stalled tasks, and successful recovery rate.

## Release/testing discipline

- Only deliver new turtle install command after required CI passes; syntax alone is insufficient.
- Test interrupted operations at each boundary: move, item transfer, chest placement, furnace input/output, craft, child inserted in drive, child boot.
- All installer paths, versions and inherited child files verified against one immutable source commit.
- Existing in-game validated smelting and reproduction remain fixed reference tests.
- A failed activity should report its **observed cause** and be retried/replanned when possible; "old flag set" is not a valid terminal reason.
- Do not merge unrelated features into a release. Use branch/PR or a test gate instead of pushing half-written code onto main.
- Track statuses distinctly: `tested-in-Minecraft`, `mock-tested`, `unverified`.
- Avoid a speculative human-assistance pathway as the default. Manual intervention after initial start counts as a failure at autonomy milestones.

## Work that should happen *next*, in order

1. **Foundation test:** Pythonized ComputerCraft one-turtle task, observe+act+result, reconnect. Evaluate BotNet as fallback.
2. **Navigation selection:** isolated LAMA / alternative tracker with actual move, fuel accounting, forced unload.
3. **Base integration:** fixed geometry, storage accounting, furnace/drive setup and swapping, deterministic resource ledger.
4. **Single command birth:** integrate verified factory/process/clone in Python-led bounded tasks; same runtime boots in child.
5. **Environmental bootstrap:** existing forestry and mining programs added as adapters; wood and fuel first.
6. **Ore acquisition and recursive birth:** full raw-world cycle, then grandchild.
7. **Chunk loading and expansion:** necessary for actual absence of player; test before declaring unattended success.

**No more:** standalone experimental commands marketed as autonomy; repeated manual station resets; blind arbitrary mining patterns; redesigning the entire system every turn; building extra mods; adding controller/colony complexity until an empirical failure warrants it.

## Player testing policy — minimize interruptions

**The user is not the routine test harness.** Stop asking for one-command tests of isolated features after each code change, or repeatedly reinstalling versions following avoidable syntax, state or API mistakes.

**Work I must validate without the player:**
- Lua syntax checks and automated regression tests in CI, including installer/child file manifests.
- Controller/backend unit and integration tests, protocol/task contracts, reconnect/retry, resource accounting, and simulated turtle execution.
- Representative offline test worlds/mocks for inventories, crafting steps, movement, station placement, furnace output, reproduction and crash recovery.
- Review of documented third-party APIs and compatibility assumptions before integration.
- Release only after automated checks pass. Never call mock results an in-game success.
- Automatically capture concise task status, error stage, environment observations and logs so that a failed in-game test gives a useful diagnosis instead of a list of manual troubleshooting commands.

**When an in-game test is worth requesting:** only at a major milestone when the integrated feature is ready, or when an indispensable physical behavior cannot be validated any other way. Tests should have one short setup, one start command, and a visible, meaningful outcome. Prefer letting the turtle execute a multi-step sequence without intervention.

**Proposed player-facing milestones:**
1. **One-turtle controller + base + offspring:** from provided *raw* resources but no manually placed machinery, the turtle builds its own small base, processes materials, creates/programs/boots a child. That single run validates connectivity plus production, not ten individual probes.
2. **Self-established base:** with a starting turtle and fuel, gather wood/cobble/sand, make chest/furnace/fuel, store resources and return home without prompts.
3. **True reproduction:** turtle gathers every material, creates a child, and child participates independently.
4. **Colony continuity:** multiple generations continue after normal restarts and while player is away, with verified chunk loading.

If a milestone fails, use recorded telemetry to diagnose and fix it **before** requesting another in-game run. Only ask for a repeat if the correction specifically addresses the observed failure and passes preflight. Avoid changing the world's setup repeatedly just to accommodate brittle software.

**What cannot be claimed without some in-game validation:** real mod integration, in-world physical placement, Minecraft inventory/peripheral quirks, server/chunk-load behavior. No promise that zero manual in-game tests can guarantee these work.
