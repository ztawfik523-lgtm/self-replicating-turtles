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

## Implementation status — 2026-10-24

**Milestone 1 has an offline-integrated release candidate; it has NOT passed a
real Minecraft end-to-end run.** The player has not been asked to debug or
run intermediate checks.

Implemented:
- Controller WebSocket job scheduler, persistent job IDs, and snapshot-based
  resource accounting. Results update the controller's inventory immediately,
  avoiding stale repeated births.
- One `birth` job from **inventory inputs (including one chest item)**: the turtle **places a carried chest item** without player-positioned storage;
  crafts a furnace and
  disk drive; smelts iron, stone, and glass; manufactures/programs/boots a child.
- Controller worker and configuration inherited into offspring. Legacy
  v0.3.5 turtles still use their old startup if not controller-enabled.
- Persistent worker job journal with backup; a completed birth records its
  job ID in persistent state, avoiding duplicates when the final response
  is lost.
- Dedicated experimental `controller/install.lua`, keeping the stable root
  `install.lua` pinned to v0.3.5. Simulated download/install/rollback/restart
  recovery passes automated checks.

**Milestone 1 in-game acceptance passed (2026-10-24):** parent **ID 10**
completed the starter worksite and one child, computer **ID 11**, booted and
joined the Python controller. The run used supplied materials and required one
crafting upgrade recovery after an initial missed prerequisite. Some rare
interruptions mid-crafting/child placement still lack full recovery guarantees.

**Future work after that acceptance gate:** wood/charcoal base bootstrap from
terrain, mining and resource acquisition using adapted existing code; then
true self-replication and multiple generations. No repeated player micro-tests.

See [controller/README.md](controller/README.md) for the exact experimental
bill of materials and test status.

**Bootstrap correctness correction (2026-10-24):** CC:Tweaked `turtle.craft`
requires *every* inventory slot outside the recipe to be empty. Therefore
using the seven off-grid slots as a crafting buffer for the first chest with
other materials present was invalid. The Milestone 1 starter kit includes one
**chest item**, which the turtle places itself; no prebuilt chest block or
furnace/drive is required. Milestone 2 makes a chest early from gathered wood
before collecting mixed resources. Regression tests now reject the impossible
chestless mixed-inventory case.

## Current milestone status (2026-10-24)

- **M1 ACCEPTED IN-GAME:** one parent turtle built the small first workshop and
  produced/programmed/booted its first child from supplied inventory items.
  Turtle **10** = parent; turtle **11** = offspring; both reconnected to Python.
- **M2 NEXT:** wood/stone/sand gathering, first chest crafted *before* the turtle
  fills with mixed item types, furnace and charcoal self-supply, home return and
  recovery. Do not ask the player to test individual algorithms.
- **M3–M4 NOT IMPLEMENTED:** independent ore acquisition, recursive children,
  scaling/chunk-loading. The M1 result does not demonstrate either.
- **Controller maintenance:** handle closed WebSockets during turtle reboot
  quietly, rather than emitting an unnecessary traceback.

## Milestone 2 implementation — 0.5.0-dev (2026-10-24)

**Implemented and tested offline; NOT yet verified in Minecraft.** The
M1 parent **10** and offspring **11** have not been upgraded or given
exploration jobs. The M2 controller task is **explicit opt-in only**.

A fresh Mining + Crafting Turtle, with empty item inventory and **at least
140 movement fuel already loaded**, can be assigned one `bootstrap` task by
the Python controller. It uses native CC:Tweaked APIs via these project
modules, not a new Minecraft mod:

- `tg/bootstrap.lua`: bounded four-direction woodland search, vertical
  log harvesting with checked return to the same pose, crafting the first chest
  before collecting unrelated types, sand collection, a **home-offset shallow
  stone shaft** (never drills through the new home chest), furnace construction,
  charcoal from logs using planks as the first fuel, and storage deposit.
- `tg/nav.lua` and `tg/state.lua`: movement/heading journal and local pose.
  When an interrupted physical action cannot be reconciled reliably, stop
  instead of fabricating a location.
- `tg/factory.lua`: existing chest-backed furnace crafting and upgraded
  `turtle.craft` handling.
- `tg/process.lua`: existing furnace inventory transfer and processing with
  **new one-plank-per-log first-charcoal support**; coal/charcoal are preferred
  when available.
- `tg/worker.lua`: explicit M2 flag, controller-visible bootstrap stage,
  child-safe opt-in isolation and a chest inventory report that differentiates
  inaccessible storage from verified empty storage.
- `controller/engine.py`: only schedules a base-establishment job when
  the turtle's installed opt-in flag is present. It will not send existing
  M1 parents or children away by merely updating the controller.
- `controller/install.lua`: M2 installation only when the optional
  `bootstrap` argument is explicitly provided. Copies source files from an
  immutable tested commit and retains recoverable backups.

**Repeatable resource production:** A completed, opted-in M2 base
automatically receives a `fuel_cycle` job when its **observed** combined
turtle-and-chest coal/charcoal stock drops below three. It retrieves the
existing chest inventory, harvests more logs from accessible trees, crafts
planks for first fuel if needed, uses the same furnace to make charcoal,
deposits surplus items back in storage, and records the completed job ID.
Unavailable chest storage is not misreported as empty; existing non-opted-in
M1 turtles are never assigned this job. This is a bounded fuel replenishment
loop while accessible trees remain, **not** a demonstrated perpetual farm.

**Automated acceptance:** `tests/bootstrap_m2_sim.lua` models a landscape
with two trees, sand banks and a stone shaft. It verifies actual navigation
pose matches physical pose, complete base construction and initial charcoal.
It injects interruptions during the log-to-planks and first-chest stages and
checks that the same job resumes without repeated harvesting. Separate checks
exercise the REAL `process.lua` charcoal fuel path, no-tree/low-fuel safe
stops, bootstrap opt-in isolation, installer rollback, clone inheritance and
resource snapshot correctness.

**Honest constraints:** The present search explores four short cardinal
rays (up to 12 blocks each), so it needs a site with reachable logs/sand and
accessible stone above the shallow depth limit. It is **not** yet a general
obstacle-avoiding pathfinder or an indefinite sapling farm; forestry planting
occurs opportunistically only when a suitable sapling is in inventory.
No complete real-game M2 run has taken place. The first *player* test should
be one full environment-to-worksite sequence, after all CI release gates pass.
It should not involve repeatedly testing each craft or movement operation.

**After M2:** gather the iron/redstone/diamond ingredients for M3 and
demonstrate offspring and grandchild created from world-gathered resources.

**Release status:** The opt-in M2 source and local base-to-charcoal and
repeat-fuel simulations are complete. This milestone is still **pending one
Minecraft end-to-end acceptance run** in suitable terrain. No live M2 test
has been attempted, and no original turtle installation was changed.

## Audit and next steps — 2026-10-25

Rechecked existing M1 and M2 programs, source pinning, controller protocol,
WebSocket sessions, startup/offspring inheritance, 16-slot first-chest
constraints, movement journal, crafting, fuel, furnace processing, base
scheduling, and automated test coverage.

**Found and fixed:**
1. **Live ID collision:** A duplicate ID could overwrite a legitimate
   turtle's controller snapshot, then release its connection guard. This is
   now rejected without changing the live session.
2. **No self-refueling despite self-produced charcoal:** Bounded M2 travel can
   now consume earned charcoal for movement; a stocked base with low turtle
   fuel triggers a maintenance job too.
3. **Interrupted furnace recipe:** A crash while the first furnace cobblestone
   is staged in the chest now resumes after collecting the staged items.
4. **Regression coverage:** Added multi-socket ID tests, actual coal/charcoal
   refueling tests, and simulated furnace-crafting interruption tests.
5. **Documentation:** Removed outdated claims that gathering and charcoal
   processing have not been implemented at all. They exist as offline-verified
   experimental M2 features, not as in-game-proven autonomy.

**Remaining risks / separate milestones:** M2 still needs one actual
Minecraft environment-to-base run; fuel yield and search results depend on
terrain. Mining iron/redstone/diamonds, reliable recovery after ambiguous
movement crashes, sapling replenishment, chunk ticking and multi-generation
reproduction are separate unmet objectives. Existing parent/child computers
10 and 11 stay unchanged.

**Next code-first focus:** strengthen tree management, resource acquisition
and path planning without expanding player testing frequency.

### Paused-job controller recovery (2026-10-25 follow-up)

The controller previously removed a failed bootstrap/birth/fuel-cycle job,
then treated changed inventory or fuel as justification to create a **new
job ID**. This conflicted with the turtle's persisted partial job ID
and could strand a partly built base. Now:

- Physical task errors include the turtle's fresh observed snapshot.
- These three multi-step jobs are retained as `paused` with their original ID.
- Unchanged periodic snapshots do not retry the job or consume more fuel.
- A changed inventory, observed stock, worksite, or movement-fuel level permits
  the same ID to be re-queued. The turtle handles this via its original
  persistent state; no new child or base job is invented.
- Reboot replays only an actually **interrupted** (`started`) job. A completed
  failure (`done` with `ok=false`) waits for controller reconciliation.
- Non-resumable legacy tasks remain subject to the old explicit error handling.

Python unit tests exercise pause, persistence, reconnect and same-ID resume;
Lua simulations exercise both failed preflight and reboot-without-change.

**Known limitation:** autonomous recovery after a movement logged as
`pending` at a hard crash is still unresolved without a reliable external
position reference. The turtle correctly refuses to invent its coordinates.

## M2 navigation integration: bounded detours and durable return routes

- The M2 survey can bypass a narrow obstacle by testing either side while
  preserving the original survey heading. It refuses to dig unknown terrain,
  cross liquid/unsupported ground, or continue after running out of return fuel.
- Every completed exploratory movement is journaled in the **same state save**
  as the pose change. Once a reboot restores an unambiguous saved pose, the
  turtle retraces the durable inverse route before resuming resource collection.
- A reboot *during* a physical move leaves a pending intent; code deliberately
  halts rather than guessing whether the turtle moved.
- The integrated landscape test includes an intact stone obstacle, a tree
  reachable only by a detour, a simulated reboot with saved route steps, return
  to base, opportunistic sand pickup, and an ambiguous in-flight movement halt.
- The technique handles narrow static obstructions; it is not general path
  planning, waypoint logistics, terrain elevation, long-distance navigation,
  GPS-based uncertain-step recovery, or a permanent renewable tree farm.
- One Minecraft end-to-end check remains the eventual M2 acceptance gate;
  no per-commit user tests.
