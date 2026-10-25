"""Small persistent controller for turtle task scheduling and resource accounting."""
from __future__ import annotations
from dataclasses import dataclass, field, asdict
import json
from pathlib import Path
from typing import Any

@dataclass
class Job:
    id: str
    action: str
    args: dict[str, Any] = field(default_factory=dict)
    state: str = "queued"
    result: dict[str, Any] | None = None

    def message(self):
        return {"type": "job", "id": self.id, "action": self.action, "args": self.args}

@dataclass
class TurtleRecord:
    turtle_id: int
    generation: int = 0
    last_snapshot: dict[str, Any] = field(default_factory=dict)
    outstanding: Job | None = None
    history: list[dict[str, Any]] = field(default_factory=list)
    blocked: dict[str, str] = field(default_factory=dict)

class Colony:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.turtles: dict[int, TurtleRecord] = {}
        self.counter = 0
        if self.path.exists():
            self._load()

    def _load(self):
        saved = json.loads(self.path.read_text(encoding="utf-8"))
        self.counter = saved["counter"]
        for raw in saved["turtles"]:
            job = Job(**raw["outstanding"]) if raw["outstanding"] else None
            rec = TurtleRecord(raw["turtle_id"], raw["generation"],
                raw["last_snapshot"], job, raw["history"], raw.get("blocked", {}))
            self.turtles[rec.turtle_id] = rec

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"counter": self.counter,
                   "turtles": [asdict(rec) for rec in self.turtles.values()]}
        temp = self.path.with_suffix(self.path.suffix + ".tmp")
        temp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        temp.replace(self.path)

    def register(self, hello: dict[str, Any]) -> TurtleRecord:
        if hello.get("type") != "hello":
            raise ValueError("Expected hello message")
        ident = hello.get("id")
        if type(ident) is not int or ident < 0:
            raise ValueError("Invalid turtle ID")
        rec = self.turtles.setdefault(ident, TurtleRecord(turtle_id=ident))
        rec.generation = int(hello.get("generation", 0))
        rec.last_snapshot = hello.get("snapshot", {})
        self.save()
        return rec

    def queue(self, ident: int, action: str, args: dict[str, Any] | None = None) -> Job:
        if action not in {"observe", "process", "produce", "birth", "bootstrap", "fuel_cycle", "collect", "station_pack"}:
            raise ValueError("Unsupported turtle task: " + action)
        rec = self.turtles[ident]
        if rec.outstanding:
            raise ValueError("Previous task must be reconciled first")
        self.counter += 1
        job = Job(f"{ident}:{self.counter}", action, args or {})
        rec.outstanding = job
        self.save()
        return job

    def reconcile_hello(self, rec: TurtleRecord, hello: dict[str, Any]) -> str:
        job = rec.outstanding
        if job is None:
            return "idle"
        journal = hello.get("journal") or {}
        if journal.get("id") == job.id and journal.get("status") == "done":
            self.complete(rec.turtle_id, job.id, journal.get("result") or {})
            return "complete"
        # Re-send the SAME ID on reconnect. A sent job might never have
        # arrived; the turtle journal handles duplicates if it did.
        # A resumed birth is journaled locally before hello.
        if journal.get("id") == job.id and journal.get("status") == "started":
            job.state = "queued"
            self.save()
            return "resend_started"
        job.state = "queued"
        self.save()
        return "resend_pending"

    def sent(self, ident: int, job_id: str):
        job = self.turtles[ident].outstanding
        if not job or job.id != job_id:
            raise ValueError("Unknown job")
        job.state = "sent"
        self.save()

    def complete(self, ident: int, job_id: str, result: dict[str, Any]) -> bool:
        rec = self.turtles[ident]
        job = rec.outstanding
        if not job or job.id != job_id:
            return False
        job.state = "done" if result.get("ok") else "failed"
        job.result = result
        # The fresh post-action view MUST replace pre-action inventory before
        # next_job can enqueue more work. Otherwise an old birth-ready
        # snapshot can schedule a duplicate child between result and snapshot.
        view = result.get("data")
        if isinstance(view, dict):
            view = view.get("snapshot")
            if isinstance(view, dict):
                rec.last_snapshot = view
        if not result.get("ok"):
            rec.blocked[job.action] = job.args.get("snapshot_key", "unknown")
        else:
            rec.blocked.pop(job.action, None)
        rec.history.append({"id": job.id, "action": job.action,
                            "state": job.state, "result": result})
        rec.history = rec.history[-50:]
        rec.outstanding = None
        self.save()
        return True

def count_items(snapshot: dict[str, Any]) -> dict[str, int]:
    result = {}
    for slot in snapshot.get("inventory", []):
        if isinstance(slot, dict) and isinstance(slot.get("name"), str):
            item = slot["name"]
            result[item] = result.get(item, 0) + int(slot.get("count", 0))
    return result

CHILD_BILL = {"minecraft:stone": 7, "minecraft:iron_ingot": 7,
              "minecraft:redstone": 1, "minecraft:glass_pane": 1,
              "minecraft:diamond": 3}

def shortages(snapshot: dict[str, Any]) -> dict[str, int]:
    items = count_items(snapshot)
    for name, n in (snapshot.get("storage") or {}).items():
        items[name] = items.get(name, 0) + int(n)
    deficit = {k: v-items.get(k, 0) for k,v in CHILD_BILL.items()
               if items.get(k, 0) < v}
    same_plank = max((n for name,n in items.items()
                      if name.startswith("minecraft:") and name.endswith("_planks")),
                     default=0)
    if same_plank < 14:
        deficit["same_type_planks"] = 14-same_plank
    fuel = items.get("minecraft:coal", 0)+items.get("minecraft:charcoal", 0)
    if fuel < 4:
        deficit["coal_or_charcoal"] = 4-fuel
    return deficit

def starter_kit_missing(view: dict[str, Any]) -> dict[str, int]:
    """Human-readable shortages for the standard first-birth inventory kit.

    This is a diagnostic for the supplied-materials acceptance test, not a
    general recipe resolver. Existing placed machinery or already-processed
    inputs can change the actual requirements in birth_inputs_ready().
    """
    items = count_items(view)
    expected = {
        "minecraft:chest": 1,
        "minecraft:cobblestone": 22,
        "minecraft:raw_iron": 7,
        "minecraft:redstone": 3,
        "minecraft:diamond": 3,
        "minecraft:sand": 6,
    }
    missing = {k: need - items.get(k, 0) for k, need in expected.items()
               if items.get(k, 0) < need}
    planks = max((n for k, n in items.items()
                  if k.startswith("minecraft:") and k.endswith("_planks")),
                 default=0)
    if planks < 14:
        missing["same_type_planks"] = 14 - planks
    fuels = items.get("minecraft:coal", 0) + items.get("minecraft:charcoal", 0)
    if fuels < 8:
        missing["coal_or_charcoal"] = 8 - fuels
    return missing

def birth_inputs_ready(view: dict[str,Any]) -> bool:
    """Minimum materials for experimental starter-chest first birth."""
    items = count_items(view)
    def n(name): return items.get(name, 0)
    below,front = view.get("bottom"),view.get("front")
    has_chest = below in {"minecraft:chest","minecraft:barrel"} or n("minecraft:chest")>0
    has_furnace = front=="minecraft:furnace" or n("minecraft:furnace")>0
    has_drive = front=="computercraft:disk_drive" or n("computercraft:disk_drive")>0
    stone_goal = 7 if has_drive else 14
    missing_stone = max(0,stone_goal-n("minecraft:stone"))
    cobble = missing_stone+(0 if has_furnace or has_drive else 8)
    fuel = 4+((max(0,7-n("minecraft:iron_ingot"))+7)//8)+((missing_stone+7)//8)
    if n("minecraft:glass_pane")==0 and n("minecraft:glass")<6:
        fuel+=1
    wood = any(v>=14 for k,v in items.items()
               if k.startswith("minecraft:") and k.endswith("_planks"))
    glass = n("minecraft:glass_pane")>0 or n("minecraft:glass")>=6 or n("minecraft:sand")>=6
    return (has_chest and wood and glass and n("minecraft:diamond")>=3
        and n("minecraft:redstone")>=(1 if has_drive else 3)
        and n("minecraft:iron_ingot")+n("minecraft:raw_iron")>=7
        and n("minecraft:cobblestone")>=cobble
        and n("minecraft:coal")+n("minecraft:charcoal")>=fuel)

def next_job(rec: TurtleRecord) -> tuple[str,dict[str,Any]] | None:
    """Dispatch only operations already implemented by the Lua turtle.
    New base building and gathering operations will extend this policy.
    """
    view = rec.last_snapshot
    if rec.outstanding:
        return None
    # A visible chest with no working inventory interface is not empty.
    # Do not schedule manufacturing or fuel replenishment against unknown stock.
    if (view.get("bottom") in {"minecraft:chest", "minecraft:barrel"}
            and view.get("storage_observed") is False):
        return None
    if view.get("bootstrap_enabled") and not view.get("bootstrap_done"):
        if any(view.get(k) for k in ("processing","manufacturing","replication","station","birth")):
            return None
        key=json.dumps({"bootstrap_stage":view.get("bootstrap_stage"),
                        "pose":view.get("pose"),"fuel":view.get("fuel")},sort_keys=True)
        if rec.blocked.get("bootstrap") != key:
            return "bootstrap", {"snapshot_key":key}
        return None
    if (view.get("bootstrap_enabled") and view.get("bootstrap_done")
        and view.get("storage_observed")
        and not any(view.get(k) for k in ("processing", "manufacturing",
                       "replication", "station", "birth", "fuel_cycle"))):
        # Only autonomously replenish fuel at a verified M2 chest/furnace.
        if view.get("front")=="minecraft:furnace" and (
              view.get("bottom")=="minecraft:chest"
              or view.get("bottom")=="minecraft:barrel"):
            stock=count_items(view)
            for name,n in (view.get("storage") or {}).items():
                stock[name]=stock.get(name,0)+int(n)
            total=stock.get("minecraft:charcoal",0)+stock.get("minecraft:coal",0)
            travel=view.get("fuel")
            low_movement_fuel=(type(travel) in (int,float) and travel < 120)
            # Charcoal in a chest is not useful if the turtle itself has run
            # out of movement fuel. Dispatch a cycle to refuel before travel.
            if total<3 or low_movement_fuel:
                key=json.dumps({"stock_fuel":total,"movement_fuel":travel,
                                "pose":view.get("pose"),
                                "stage":view.get("bootstrap_stage")},sort_keys=True)
                if rec.blocked.get("fuel_cycle")!=key:
                    return "fuel_cycle",{"snapshot_key":key}
    if any(view.get(k) for k in
           ("processing", "manufacturing", "replication", "station", "birth")):
        return None
    items = count_items(view)
    birth_ready=birth_inputs_ready(view)
    if not birth_ready and view.get("bottom") not in {"minecraft:chest", "minecraft:barrel"}:
        return None
    coal = items.get("minecraft:coal", 0)+items.get("minecraft:charcoal", 0)
    planks = max((n for k,n in items.items() if k.endswith("_planks")), default=0)
    ready = (planks >= 14 and coal >= 4 and
             all(items.get(k, 0) >= n for k,n in CHILD_BILL.items()))
    action, args = None, {}
    if ready and view.get("front") == "computercraft:disk_drive":
        action = "produce"
    elif birth_ready:
        action = "birth"
    elif view.get("front") == "minecraft:furnace" and coal:
        if items.get("minecraft:iron_ingot", 0) < 7 and items.get("minecraft:raw_iron", 0):
            action, args = "process", {"kind": "iron"}
        elif items.get("minecraft:stone", 0) < 7 and items.get("minecraft:cobblestone", 0):
            action, args = "process", {"kind": "stone"}
    if not action:
        return None
    key = json.dumps({"inventory": view.get("inventory", []),
                      "front": view.get("front"), "bottom": view.get("bottom"),
                      "action": action, "args": args}, sort_keys=True)
    if rec.blocked.get(action) == key:
        return None
    return action, dict(args, snapshot_key=key)
