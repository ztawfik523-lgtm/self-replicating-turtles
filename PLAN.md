# Turtle Genesis — Productive Development Milestones

Updated 2026-10-23. No custom Minecraft mod; established CC: Tweaked mods, Lua programs, publicly available projects and external Python controllers are allowed.

## One objective

A single Mining + Crafting Turtle starts with an initial fuel supply in an ordinary survival world. The system builds a reusable base, obtains materials, makes and activates a child, and repeats. A working child must eventually help produce a grandchild. Reusing a parent's workshop is allowed.

## Architecture chosen for implementation

- **Python controller:** Colony resource ledger, task planning, job allocation, common map, persistence and reconnect handling.
- **Lua workers:** Physical movement, mining, tree harvesting, inventory operations, smelting, crafting and offspring initialization; use existing working scripts rather than replacing them.
- **Minimal fixed base:** First chest, reusable furnace, eventual disk drive and a safe deployment cell. Infrastructure is maintained rather than repeatedly packed and unpacked.
- **Borrow first:** Consider LAMA for movement, existing mining/forestry software for field operations, existing Python/WebSocket frameworks for controller needs. Only integrate a library if it is demonstrably simpler than an adapter; do not combine incompatible trackers or entire operating systems without reason.
- **Physical reality wins:** A state flag describes what was intended; item/block inspection determines what actually happened. Non-repeatable activities (crafting a child, movement at restart) need small journals, not permanent manual-reset gates.
- **Practical constraint:** Minecraft server and relevant chunks must be ticking. Investigate existing chunk loaders before claiming fully unattended persistence.

## Four player-visible milestones — no micro-tests

### Milestone 1 — One launch, one complete child

**Input:** One equipped turtle with the necessary raw materials and starter fuel in its inventory, but **no pre-positioned base equipment**. External Python service may be running.

**Turtle/controller work:** Establish the chest/furnace, smelt raw iron and stone, prepare glass panes, craft a disk drive, manufacture the turtle, initialize its filesystem, copy worker and Genesis software, fuel and deploy the child. Child registers with the controller. Parent remains available.

**Player test:** Start the system once; watch an entire first birth. No intermediary commands.

**Before we ask for that test:** All source syntax checked; controller simulation; real WebSocket loopback integration; inventory/crafting/furnace simulation; staged action recovery; verification of the installer and child manifests. This is currently **in development**, not ready for a player run.

### Milestone 2 — Base bootstraps itself and produces fuel

**Input:** One turtle with starter fuel, in normal terrain suitable for wood/stone/sand gathering.

**Work:** Find/harvest trees, craft planks and first chest, construct/place an enduring furnace, mine cobble, gather sand, store material, burn wood to bootstrap charcoal, keep a safe reserve, return home.

**Player test:** Start once; the turtle creates a usable base and fuel stock without a resource handout.

**Before test:** Offline simulated tree/fuel/route/storage runs and restart scenarios.

### Milestone 3 — First true autonomous reproduction

**Input:** One turtle and initial fuel, ordinary generated terrain.

**Work:** Deficit-driven gathering of iron, redstone, diamonds and remaining supplies using adapted existing mining code; route home, smelt, use the hub to produce, program and boot a child. No supplied ores, equipment or manual task commands.

**Player test:** One complete autonomous resource-to-child run.

**Before test:** Simulated ore searches, full inventory recovery, fuel budgeting, obstruction/cave handling, resource bill verification, and controller crash scenarios.

### Milestone 4 — Self-replicating colony, not just a robot factory

**Work:** Child automatically joins the workforce, helps gather and/or uses the base, participates in building a grandchild. Expand to additional bases when returns to the first base are uneconomical. Use established chunk-loading tools and collision-free work allocation.

**Player test:** One longer unattended run covering parent → child → grandchild, shutdown/reload, and absence of the player.

**Before test:** Simulation with multiple turtles, task leases, infrastructure access, storage, and chunk loading constraints.

## Immediate development sprint (starts now)

1. [x] Add a standalone Python controller + Lua worker with observed inventory snapshots, job IDs, state persistence and automatic selection of *existing* smelt/manufacture operations when their physical prerequisites are already satisfied.
2. [x] Build Python WebSocket loopback tests and simulated Lua worker tests. **No in-game check yet**.
3. [ ] Select and integrate one navigation and base-placement strategy while retaining the verified legacy factory, clone and smelter.
4. [ ] Build fixed worksite construction and the complete first-birth material plan, including chest, furnace, glass panes and disk drive.
5. [ ] Join all actions into a full automatic birth and child registration, then run end-to-end simulator.
6. [ ] Only when the above passes request the **first worthwhile Minecraft test**.

**Important:** The controller worker is presently an experimental repository module, **not** shipped by the current turtle installer, and is **not** active on boot. Its existence does not establish autonomous reproduction.

## Release and testing discipline

- **No player involvement per commit.** Automated CI runs at every code push; that's not a request for human testing.
- Keep known working in-game routines stable until their replacements pass full integration.
- Don't ask for pre-positioned furnaces, disk drives, repeated installs, state resets or screenshots of trivial primitives.
- Each player test must validate an entire milestone and produce meaningful visible behavior and machine-readable diagnostics.
- Distinguish **in-game verified**, **mock-tested**, **implemented but untested**, and **not yet implemented**.
- If a milestone fails, use logs to identify cause and fix it before considering another user run.
- No custom mod. External controllers, third-party scripts, software adaptations and standard mod addons are all allowed.
