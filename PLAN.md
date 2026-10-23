# Turtle Genesis: Unattended Self-Replication Plan

Status: design plan, not an implementation claim. Last reviewed 2026-10-23.
Target: Minecraft 1.20.1 Forge, CC: Tweaked, existing established addons (Advanced Peripherals, Turtlematic and other appropriate pre-existing tools).
Constraint: **No Minecraft mod, fork, or special API written specifically for Turtle Genesis.** External software/controllers are allowed when they provide a measurable advantage.

## 0. Objective and contract

A single starting Mining + Crafting Turtle, with Genesis software and a reasonable initial fuel supply, is placed in a normal survival world. It must operate without further commands or manually positioned chests, furnaces, drives, ores or offspring. Success is:

1. Construct necessary infrastructure from materials it harvests or mines.
2. Gather and process its own reproduction inputs in survival.
3. Craft, initialize, program, fuel, place and start a child.
4. Observe the child carrying out the same lifecycle independently.
5. Continue while resources, world generation, and server conditions permit.

Continuous means *the software maintains a goal-directed loop whenever the turtle is running*, not that an unloaded chunk or stopped Minecraft server magically executes Lua. Long-term unattended operation requires a verified existing chunk-loading method.

**Two explicit test modes:** (A) integration mode starts with raw ingredients in inventory but *no prebuilt facilities*; (B) autonomy mode starts with only the equipped parent and initial fuel. Passing (A) is not evidence of passing (B). Do not repeatedly request player setup after the initial placement.

Do not promise indefinite population growth in a finite world. Trees can support renewable fuel; iron, diamonds and redstone require access to new finite deposits unless existing mods supply a legitimate renewable source. The attainable objective is continuing expansion under sufficient available world resources.

## 1. What actually works (ground truth)

**In-game verified:**
- One turtle manufactured an offspring from supplied components via `produce`.
- Child item initialization, disk-drive filesystem inheritance, placement, boot and generation increment.
- Furnace smelting of iron and transferring the output back through the chest.

**Not yet established:** a single autonomous lifecycle, first chest from gathered logs, furnace/drive built and placed automatically, autonomous ore/fuel acquisition, navigation from surface to deep ore layers, reliable reboot/chunk-load recovery, child reproducing independently, and colony management.

**Immediate defects/debt:** `startup.lua` currently dispatches a boot command, but independent tasks are not joined into one reproduction planner. Old mining follows an inefficient preselected pattern. `state.assertSafe` and old station guards can lock out a physically recoverable system. Crafting relies on staging to a chest. Child seed auto currently triggers the older mining path, not a complete lifecycle. Preserve the verified recipes and cloning mechanics; rewrite the glue.

## 2. Design: one agent, physical observations, minimal persistent intent

```text
startup
  -> initialize/restore agent
  -> repeat while running
       observe: inventory + adjacent blocks + fuel + local map + optional scan
       reconcile unfinished action with the world
       update needs for reproduction and survival
       choose highest-value achievable subgoal
       perform one/bounded batch of physical actions
       verify effects; update map and progress; yield
     end
```

Suggested modules:
- `agent.lua`: main loop and priority choice
- `needs.lua`: recipe/dependency graph and material accounting (inventory **plus** local storage)
- `world.lua`: bounded local map, discovered resource sites, path and home/worksite location
- `navigate.lua`: planning, safe motion, obstruction handling, return/home strategy
- `gather.lua`: wood, fuel, stone, sand and ores (one policy, different tasks)
- `industry.lua`: existing smelting, crafting and workstation actions, driven by goals
- `reproduce.lua`: existing manufacture/clone/deploy methods as reusable actions
- `journal.lua`: small, durable intent records for actions whose partial completion matters
- `comms.lua` (optional): monitoring/coordination; no dependency in early milestones

These are *conceptual responsibilities*, not an instruction to create ten large modules immediately. Start small and refactor only where necessary. Prefer continuous replanning over a long scripted sequence that collapses on the first unexpected block.

Priority policy: imminent loss of movement/fuel > safe inventory management > recover interrupted action > satisfy a reproduction material deficit > manufacture/clone/deploy > explore new resource locations. If an action is blocked, record why, switch to another feasible task, or relocate. Avoid unbounded repeated failures. Do not discard blocks that are needed in the bill of materials.

**Persistent memory:** generation/parent, local or world pose when justified, home/worksite coordinates, durable discoveries, limited action intent (e.g. child in drive, craft whose output may already exist). Recover by inspecting blocks/inventories first. No phase flag should act as an unconditional manual-reset lock. Interrupted movements genuinely can be ambiguous without external positioning; use GPS if available, a consistent route/landmark scheme otherwise, and bounded local reconciliation instead of pretending ambiguity does not exist.

**Inventory discipline:** reserve enough free space for tools/collected drops; support material stacks split over chest and turtle; first storage chest is special and must be bootstrapped before the turtle clutters all 16 slots. No action should require the player to empty 16 slots.

## 3. Critical material and infrastructure dependency chain

A practical full reproduction budget extends beyond the current `factory.needs()`, which only checks the offspring recipe *after* facilities exist.

| Goal | Base ingredients to plan for | Notes |
| --- | --- | --- |
| Child turtle + diamond mining/crafting upgrades | 14 same-type planks, 7 iron ingots, 7 stone, 1 redstone, 1 glass pane, 3 diamonds, 4 coal/charcoal for child | Verified manufacturing recipe; fuel also needed for parent |
| First reusable work chest | 8 additional planks | Bootstrap using logs -> planks -> chest while inventory is sparse |
| Furnace | 8 cobblestone | Reuse in established worksite; do not repeatedly pack |
| Disk drive | 7 stone + 2 redstone | Reusable across births; this is missing from the factory's displayed material requirements |
| Glass pane | 6 sand -> 6 glass -> 16 panes | Produces spare panes for subsequent children |
| Stone inputs | 14 stone total for computer + disk drive | Smelt cobblestone without silk touch: requires 14 further cobblestone, additional smelting fuel |
| Ongoing fuel | Logs/planks -> charcoal; coal where available | Avoid bootstrap deadlock: a furnace can burn wood/planks before any coal is found |
| Subsequent births | Offspring inputs and starter resources | Parent does not need to rebuild reusable infrastructure for every child |

Therefore, a first-generation worksite needs about **22 cobblestone** for an eight-cobble furnace and fourteen smelted-stone inputs (plus optional extra), at least **3 redstone** across turtle+drive, **7 iron ingots**, **3 diamonds**, **6 sand** for glass panes, wood for chest/offspring/charcoal, and sufficient movement/smelting/offspring fuel. These are planning quantities, not a promise that the initial mining setup supplies everything. A child or colony may share inherited manufacturing facilities rather than create a new disk drive per birth.

## 4. Milestones and gates (in order)

### M0 — Stop regressions, establish an executable baseline

- Keep verified recipes and cloning code unchanged unless a concrete test fails.
- Remove/disable unrelated unfinished workstation commands and the old automatic blind-mining path for the new agent.
- Automated CI: compile *every* Lua file, run physics/inventory mocks, test installer/clone manifests and version pins, prohibit release on red CI.
- Build a deterministic fake-world harness that models turtle movement, inventories, placement, smelting, chunk unloading and restart.
- Core regression: if smelting finished but the state says otherwise, the agent collects/continues without human `process-reset`.

**Gate:** clean deployment, successful test suite, and a startup that does not return to an obsolete miner by default.

### M1 — Closed-loop reproduction with supplied *raw* resources (no placed facilities)

- Single `genesis start` agent entrypoint.
- Automatic selection/placement/reuse of chest, furnace and disk drive; craft the missing infrastructure from *carried* primitive materials.
- Smelt iron and stone, make glass and pane, manufacture offspring, initialize/program/fuel/place/boot child.
- Do not manually invoke `process`, `station`, `make`, `produce` in between.
- Parent remains active after the child is born; child uses the *same* new startup agent.
- Use bounded action batches and inspect resulting physical inventories so rebooting cannot duplicate production.

**Gate:** a single command, no manually positioned machinery, actual in-game birth and boot; then independently confirm the child performs the agent's next meaningful work step. This gate tests integration, **not autonomous gathering**.

### M2 — Wood, basic building material and renewable fuel

- From logs: planks, first chest, replenish wood, charcoal; reserve saplings for planting when appropriate.
- Harvest trees using reachable trunks, collect dropped logs/saplings, avoid orphaned floating items; replant and periodically revisit. Seed location or terrain can affect success; do not claim guaranteed forestry in every biome.
- Mine accessible cobblestone/stone and sand, build a stationary reusable furnace/chest; clear storage by organizing materials instead of discarding them.
- Smelter should support planks/logs and charcoal, not just supplied coal.
- Establish a known home/worksite and bounded exploration.

**Gate:** start with fueled turtle near normal forest/stone terrain; make first chest/furnace and maintain a positive fuel budget without the player.

### M3 — Useful mining and full material acquisition

- Target deficits, not arbitrary tunnel distance. Coal/wood for fuel, iron for turtle body, redstone for computer/drive, diamonds for pickaxe, sand for pane.
- Search terrains by likely resource layer and observed block/ore information. Develop safe paths between home, mine and surface.
- Implement bounded surveying, cave-risk handling, inventory return, ore pickup validation, low-fuel return threshold. Never intentionally mine own storage or infrastructure.
- Evaluate an **existing** Advanced Peripherals Geo Scanner/geoscanning upgrade only if the actual installed version, energy requirements, upgrade-slot swapping, and acquisition path are compatible. It is an optimization, not a magically free starting sensor.
- Distinguish resource not found yet from resource mechanically unreachable; relocate worksite if exhausted.

**Gate:** turtle obtains **all** of one reproduction's ores/materials from generated terrain, processes them, and returns them to its workshop. Test separate seeds/biomes and deep-layer navigation. No preloaded ores.

### M4 — Repeat reproduction autonomously

- Agent checks a complete dependency bill, accumulates resources, reuses infrastructure, runs proven manufacturing+child initialization+clone+boot sequence.
- Offspring starts automatically and receives enough fuel/software to begin gathering; parent continues.
- Avoid collision: designate distinct mining zones/worksites or lightweight claims, and keep spawn/deployment cells clear.
- Recover interrupted manufacturing/drive insert/deployment based on physical evidence; count births exactly once.

**Gate:** begin from **one** turtle with only starter fuel; parent produces a child, then a child autonomously produces a grandchild, with no player assistance.

### M5 — Colony robustness and scaling

- Ensure appropriate chunks stay ticking when player moves away. Test the exact installed chunk-loader addon and whether its turtle upgrade conflicts with mining/crafting upgrades. Confirm reboot behavior explicitly.
- Optional external supervisor (Python/CC computer/WebSockets/HTTP): monitor logs, plan exploration, assign non-overlapping territories, share maps. It is allowed. Decide after measuring whether it improves exploration/collisions/reliability enough to justify continuous service and communication/upgrade overhead.
- Add fuel budgeting, stalled-agent watchdog, task backoff, aging/abandoned worksites, resource storage and redistribution, throughput metrics.
- Test unloaded/reloaded chunks, server reboot, death/obstruction, missing peripherals, limited fuel, full inventory, and two turtles competing for resources.

**Gate:** unattended multi-generation population on several world seeds, with logs showing which turtles gathered what, where the resources went, why any failed, and whether reproduction continues after restarts.

## 5. Technical constraints worth testing early

- **Only two turtle upgrade slots:** mining and crafting already occupy both. A geo scanner, modem or chunk-loader upgrade cannot be assumed simultaneously equipped. Use temporary swaps, external peripheral placement, a separate specialised turtle, or another established mod mechanism **after testing**.
- **Scanner energy and cooldown:** Advanced Peripherals Geo Scanner has a scan cost/FE and cooldown. Confirm access and power; do not make the whole system depend on it without a bootstrap path.
- **Chunk loading:** test the actual installed Turtlematic/Advanced Peripherals behavior in MC 1.20.1 Forge, including moving across chunk boundaries, reboot, and starting offspring. A controller does not make unloaded turtles run.
- **GPS:** CC GPS requires loaded GPS hosts and a modem network. Useful when built, not a free absolute-position API for a lone turtle.
- **Survival world variability:** diamond/redstone acquisition, high-versus-deep ore layers, hostile mobs, caves, lava, sparse trees and fuel exhaustion may cause failure; performance must be measured across seeds.

## 6. Test and release discipline

1. Unit/regression tests for planners, material accounting, crafting slots and recovery.
2. Simulated multi-operation run (interruption between **every** critical place/transfer/craft/boot).
3. CI must pass before any release is recommended. Test syntax and behavior, not just parsing.
4. Immutable pin and manifest consistency: installer and child must copy the same revision, including every new module.
5. One in-game checkpoint per milestone. Report clearly: **verified in Minecraft**, **tested in simulation**, or **implemented but untested**.
6. Collect terminal errors and a compact activity log; avoid turning ordinary blockers into a request for user action.

## 7. Sequence for the next implementation cycle

1. Freeze the currently working source and retain a reproducible test world.
2. Build the simplest `agent.lua` loop over existing `process`, `factory`, and `replicate`, with a real inventory/worksite observer and automatic decisions.
3. Implement complete inventory+storage bill of materials (including furnace/drive and smelting inputs).
4. Make stationary worksite creation/reuse and drive construction operate without manually placed blocks.
5. Prove **M1** end-to-end in Minecraft before changing mining.
6. Add **M2** harvesting/fuel bootstrap.
7. Implement **M3** deficit-driven acquisition, then **M4** recursive offspring autonomy.
8. Add optional scanners, external coordination and robust chunk loading when their measured benefits and mechanical compatibility justify the cost.

**Design principle:** every addition must shorten the distance to the *next unattended birth* or remove a demonstrated cause of failure. Don't add recovery flags, a custom controller, scanner upgrade or portable station simply because they're technically interesting.
