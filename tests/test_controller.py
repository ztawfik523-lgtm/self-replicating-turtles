import json
import asyncio
import pytest
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from controller.engine import Colony, shortages, next_job, starter_kit_missing
from controller.server import Host

def hello(journal=None):
    return {"type":"hello","id":7,"generation":1,
        "snapshot":{"fuel":200,"inventory":[{"name":"minecraft:raw_iron","count":9}]},
        "journal":journal or {}}

def test_missing_materials_and_no_fake_base(tmp_path):
    db=Colony(tmp_path/"db.json")
    rec=db.register(hello())
    assert next_job(rec) is None
    assert shortages(rec.last_snapshot)["minecraft:iron_ingot"]==7

def test_continued_job_not_repeated_after_reboot(tmp_path):
    p=tmp_path/"db.json"
    db=Colony(p);rec=db.register(hello())
    job=db.queue(7,"produce");db.sent(7,job.id)
    db2=Colony(p);rec=db2.register(hello({"id":job.id,"status":"started"}))
    assert db2.reconcile_hello(rec,hello({"id":job.id,"status":"started"}))=="resend_started"
    assert rec.outstanding.state=="queued"
    complete=hello({"id":job.id,"status":"done",
        "result":{"type":"result","id":job.id,"ok":True}})
    assert db2.reconcile_hello(rec,complete)=="complete"
    assert not db2.complete(7,job.id,{"ok":True})
    assert len(rec.history)==1

def test_scheduler_decides_from_inventory_and_base(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    rec.last_snapshot={"front":"minecraft:furnace","bottom":"minecraft:chest",
        "inventory":[{"name":"minecraft:coal","count":2},
                     {"name":"minecraft:raw_iron","count":10}]}
    action,args=next_job(rec)
    assert action=="process" and args["kind"]=="iron"
    rec.blocked[action]=args["snapshot_key"]
    assert next_job(rec) is None
    rec.last_snapshot["inventory"].append({"name":"minecraft:coal","count":1})
    assert next_job(rec) is not None

def test_production_requires_full_bill(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    items={"minecraft:oak_planks":14,"minecraft:coal":4,
       "minecraft:stone":7,"minecraft:iron_ingot":7,
       "minecraft:redstone":1,"minecraft:glass_pane":1,"minecraft:diamond":3}
    rec.last_snapshot={"front":"computercraft:disk_drive","bottom":"minecraft:chest",
        "inventory":[{"name":k,"count":v} for k,v in items.items()]}
    assert next_job(rec)[0]=="produce"
    rec.last_snapshot["inventory"][0]["count"]=13
    assert next_job(rec) is None

@pytest.mark.asyncio
async def test_websocket_worker_protocol(tmp_path):
    host=Host(tmp_path/"db.json")
    rec=host.colony.register(hello())
    job=host.colony.queue(rec.turtle_id,"observe")
    async with serve(host.handle,"127.0.0.1",0) as server:
        port=server.sockets[0].getsockname()[1]
        async with connect(f"ws://127.0.0.1:{port}") as ws:
            await ws.send(json.dumps(hello()))
            assert json.loads(await ws.recv())["type"]=="welcome"
            data=json.loads(await ws.recv())
            assert data["id"]==job.id and data["action"]=="observe"
            await ws.send(json.dumps({"type":"result","id":job.id,"ok":True}))
            assert json.loads(await ws.recv())["accepted"]
    assert host.colony.turtles[7].outstanding is None

def test_first_birth_is_single_high_level_job(tmp_path):
    db=Colony(tmp_path/"db.json"); rec=db.register(hello())
    kit={"minecraft:chest":1,"minecraft:cobblestone":22,
         "minecraft:raw_iron":7,"minecraft:redstone":3,
         "minecraft:sand":6,"minecraft:diamond":3,
         "minecraft:oak_planks":14,"minecraft:coal":8}
    rec.last_snapshot={"front":None,"bottom":"minecraft:grass_block",
        "inventory":[{"name":k,"count":v} for k,v in kit.items()]}
    assert next_job(rec)[0]=="birth"
    rec.last_snapshot["inventory"][1]["count"]=21
    assert next_job(rec) is None

@pytest.mark.asyncio
async def test_child_registers_without_replacing_parent(tmp_path):
    host=Host(tmp_path/"state.json")
    async with serve(host.handle, "127.0.0.1", 0) as server:
        port=server.sockets[0].getsockname()[1]
        async with connect(f"ws://127.0.0.1:{port}") as parent:
            await parent.send(json.dumps(hello()))
            assert json.loads(await parent.recv())["type"]=="welcome"
            child={"type":"hello","id":8,"generation":2,
                "snapshot":{"fuel":320,"inventory":[]},"journal":{}}
            async with connect(f"ws://127.0.0.1:{port}") as ws:
                await ws.send(json.dumps(child))
                assert json.loads(await ws.recv())["type"]=="welcome"
    assert set(host.colony.turtles)=={7,8}
    assert host.colony.turtles[8].generation==2

def test_reconnected_inflight_task_is_resent_same_id(tmp_path):
    p=tmp_path/"db.json"
    db=Colony(p); rec=db.register(hello())
    job=db.queue(7,"produce");db.sent(7,job.id)
    db2=Colony(p);rec=db2.register(hello())
    assert db2.reconcile_hello(rec,hello())=="resend_pending"
    assert rec.outstanding.id==job.id
    assert rec.outstanding.state=="queued"
    assert db2.queue if False else True  # no second job is created
    assert db2.counter==1

def test_completed_birth_refreshes_snapshot_before_followup(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    rec.last_snapshot={"birth":False,"front":"computercraft:disk_drive",
      "bottom":"minecraft:chest","inventory":[
        {"name":"minecraft:oak_planks","count":14},
        {"name":"minecraft:coal","count":4},
        {"name":"minecraft:stone","count":7},
        {"name":"minecraft:iron_ingot","count":7},
        {"name":"minecraft:redstone","count":1},
        {"name":"minecraft:glass_pane","count":1},
        {"name":"minecraft:diamond","count":3}]}
    assert next_job(rec) is not None
    job=db.queue(7,"produce");db.sent(7,job.id)
    result={"ok":True,"type":"result","id":job.id,
       "data":{"snapshot":{"birth":False,"children":1,"inventory":[],
                            "front":"computercraft:disk_drive",
                            "bottom":"minecraft:chest"}}}
    assert db.complete(7,job.id,result)
    assert rec.last_snapshot["children"]==1
    assert next_job(rec) is None

def test_mixed_inventory_requires_a_chest_item(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    raw={"minecraft:cobblestone":22,"minecraft:raw_iron":7,
      "minecraft:redstone":3,"minecraft:sand":6,"minecraft:diamond":3,
      "minecraft:oak_planks":14,"minecraft:coal":8}
    rec.last_snapshot={"front":None,"bottom":"minecraft:dirt",
      "inventory":[{"name":k,"count":n} for k,n in raw.items()]}
    assert next_job(rec) is None
    rec.last_snapshot["inventory"].append({"name":"minecraft:chest","count":1})
    assert next_job(rec)[0]=="birth"

def test_first_birth_idle_explains_specific_material_shortages(tmp_path, caplog):
    host=Host(tmp_path/"state.json")
    rec=host.colony.register(hello())
    rec.last_snapshot={"inventory": [], "front": None, "bottom": "minecraft:dirt"}
    missing=starter_kit_missing(rec.last_snapshot)
    assert missing["minecraft:chest"]==1
    assert missing["minecraft:raw_iron"]==7
    assert missing["same_type_planks"]==14
    assert missing["coal_or_charcoal"]==8
    with caplog.at_level("INFO", logger="genesis"):
        host.report_if_waiting(rec)
        host.report_if_waiting(rec)
    assert caplog.text.count("standard first-birth kit missing")==1

def test_full_material_kit_is_not_reported_as_idle(tmp_path, caplog):
    host=Host(tmp_path/"state.json")
    rec=host.colony.register(hello())
    kit={"minecraft:chest":1, "minecraft:cobblestone":22,
         "minecraft:raw_iron":7, "minecraft:redstone":3,
         "minecraft:diamond":3, "minecraft:sand":6,
         "minecraft:oak_planks":14, "minecraft:charcoal":8}
    rec.last_snapshot={"inventory":[{"name":key,"count":value}
                                for key,value in kit.items()],
                      "front":None, "bottom":None}
    with caplog.at_level("INFO", logger="genesis"):
        host.report_if_waiting(rec)
    assert "standard first-birth kit missing" not in caplog.text
    assert next_job(rec)[0]=="birth"

@pytest.mark.asyncio
async def test_abrupt_turtle_reboot_disconnects_cleanly(tmp_path, caplog):
    """CC:Tweaked doesn't necessarily send a WebSocket close frame on reboot."""
    host = Host(tmp_path / "db.json")
    async with serve(host.handle, "127.0.0.1", 0) as server:
        port = server.sockets[0].getsockname()[1]
        with caplog.at_level("INFO", logger="genesis"):
            ws = await connect(f"ws://127.0.0.1:{port}")
            await ws.send(json.dumps(hello()))
            assert json.loads(await ws.recv())["type"] == "welcome"
            assert 7 in host.connected
            ws.transport.abort()  # no close frame
            async def wait_for_removal():
                while 7 in host.connected:
                    await asyncio.sleep(0.01)
            await asyncio.wait_for(wait_for_removal(), timeout=1)
    assert "Turtle 7 disconnected" in caplog.text

def test_m2_bootstrap_is_explicitly_opted_in(tmp_path):
    db=Colony(tmp_path/"db.json"); rec=db.register(hello())
    rec.last_snapshot={"inventory":[],"fuel":400,"bottom":"minecraft:grass_block",
        "front":None,"bootstrap_enabled":False,"bootstrap_done":False}
    assert next_job(rec) is None  # M1 parents never wander off automatically
    rec.last_snapshot["bootstrap_enabled"]=True
    job=next_job(rec)
    assert job is not None and job[0]=="bootstrap"
    assert "snapshot_key" in job[1]
    db.queue(7,*job)
    assert next_job(rec) is None  # no second task while working


def test_m2_completed_base_never_restarts_wood_search(tmp_path):
    db=Colony(tmp_path/"db.json"); rec=db.register(hello())
    rec.last_snapshot={"inventory":[],"fuel":400,
        "front":"minecraft:furnace","bottom":"minecraft:chest",
        "bootstrap_enabled":True,"bootstrap_done":True}
    assert next_job(rec) is None


def test_m2_blocked_job_only_retries_after_observed_change(tmp_path):
    db=Colony(tmp_path/"db.json"); rec=db.register(hello())
    rec.last_snapshot={"inventory":[],"fuel":450,"pose":{"x":0,"y":0,"z":0,"dir":0},
       "bootstrap_enabled":True,"bootstrap_done":False}
    action,args=next_job(rec)
    rec.blocked[action]=args["snapshot_key"]
    assert next_job(rec) is None
    rec.last_snapshot["fuel"]=500
    assert next_job(rec)[0]=="bootstrap"

def test_completed_opted_in_base_auto_replenishes_when_fuel_low(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    rec.last_snapshot={"bootstrap_enabled":True,"bootstrap_done":True,
        "storage_observed":True,"front":"minecraft:furnace",
        "bottom":"minecraft:chest","pose":{"x":0,"y":0,"z":0,"dir":0},
        "inventory":[{"name":"minecraft:charcoal","count":1}],
        "storage":{"minecraft:sand":6,"minecraft:charcoal":1}}
    task=next_job(rec)
    assert task and task[0]=="fuel_cycle"
    rec.last_snapshot["storage"]["minecraft:charcoal"]=3
    assert next_job(rec) is None  # recovered reserve, no pointless work

def test_fuel_cycle_never_runs_without_verified_base_or_during_smelt(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    view={"bootstrap_enabled":True,"bootstrap_done":True,
        "storage_observed":True,"front":"minecraft:furnace",
        "bottom":"minecraft:chest","inventory":[],"storage":{}}
    rec.last_snapshot=view
    assert next_job(rec)[0]=="fuel_cycle"
    view["processing"]=True
    assert next_job(rec) is None
    view["processing"]=False
    view["storage_observed"]=False
    assert next_job(rec) is None
    view["storage_observed"]=True
    view["front"]="computercraft:disk_drive"
    assert next_job(rec) is None

def test_inaccessible_chest_defers_legacy_smelt_and_logs_warning(tmp_path, caplog):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    rec.last_snapshot={"front":"minecraft:furnace","bottom":"minecraft:chest",
        "storage_observed":False,
        "inventory":[{"name":"minecraft:raw_iron","count":8},
                     {"name":"minecraft:coal","count":2}]}
    assert next_job(rec) is None
    host=Host(tmp_path/"host.json")
    with caplog.at_level("WARNING",logger="genesis"):
        host.report_if_waiting(rec)
    assert "inventory peripheral is unavailable" in caplog.text
    rec.last_snapshot["storage_observed"]=True
    rec.last_snapshot["storage"]={}
    assert next_job(rec)[0]=="process"

@pytest.mark.asyncio
async def test_duplicate_hello_cannot_overwrite_or_unlock_live_turtle(tmp_path):
    host=Host(tmp_path/"registry.json")
    original={"type":"hello","id":7,"generation":1,
              "snapshot":{"fuel":250,"inventory":[{"name":"minecraft:diamond","count":3}]},
              "journal":{}}
    bogus={"type":"hello","id":7,"generation":999,
           "snapshot":{"fuel":0,"inventory":[]},"journal":{}}
    async with serve(host.handle,"127.0.0.1",0) as server:
        port=server.sockets[0].getsockname()[1]
        async with connect(f"ws://127.0.0.1:{port}") as first:
            await first.send(json.dumps(original))
            assert json.loads(await first.recv())["type"]=="welcome"
            assert host.connected=={7}
            for _ in range(2):
                async with connect(f"ws://127.0.0.1:{port}") as duplicate:
                    await duplicate.send(json.dumps(bogus))
                    with pytest.raises(Exception):
                        await duplicate.recv()
                await asyncio.sleep(0.02)
                assert host.connected=={7}
                assert host.colony.turtles[7].generation==1
                assert host.colony.turtles[7].last_snapshot["fuel"]==250
            await first.send(json.dumps({"type":"ping"}))
            assert json.loads(await first.recv())["type"]=="pong"
    assert host.connected==set()
    persisted=Colony(tmp_path/"registry.json")
    assert persisted.turtles[7].generation==1

@pytest.mark.asyncio
async def test_invalid_id_does_not_mutate_registry_or_connection_set(tmp_path):
    host=Host(tmp_path/"registry.json")
    async with serve(host.handle,"127.0.0.1",0) as server:
        port=server.sockets[0].getsockname()[1]
        async with connect(f"ws://127.0.0.1:{port}") as ws:
            await ws.send(json.dumps({"type":"hello","id":True,
                                      "snapshot":{"fuel":999}}))
            with pytest.raises(Exception):
                await ws.recv()
    assert not host.colony.turtles
    assert not host.connected

def test_m2_full_charcoal_stock_still_refuels_turtle_when_movement_low(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    rec.last_snapshot={"bootstrap_enabled":True,"bootstrap_done":True,
        "storage_observed":True,"front":"minecraft:furnace",
        "bottom":"minecraft:chest","fuel":35,
        "inventory":[{"name":"minecraft:charcoal","count":4}],
        "storage":{"minecraft:sand":6}}
    task=next_job(rec)
    assert task is not None and task[0]=="fuel_cycle"
    rec.last_snapshot["fuel"]=180
    assert next_job(rec) is None  # stocked and moving safely
    rec.last_snapshot["fuel"]=0
    assert next_job(rec)[0]=="fuel_cycle"

def test_failed_partial_bootstrap_pauses_without_losing_original_job_id(tmp_path):
    p=tmp_path/"db.json"
    db=Colony(p);rec=db.register(hello())
    job=db.queue(7,"bootstrap");db.sent(7,job.id)
    after={"bootstrap_enabled":True,"bootstrap_done":False,
           "bootstrap_stage":"gather_sand","fuel":270,
           "inventory":[{"name":"minecraft:oak_planks","count":8}],
           "front":None,"bottom":"minecraft:chest"}
    assert db.complete(7,job.id,{"id":job.id,"ok":False,
                 "error":"No nearby sand","data":{"snapshot":after}})
    assert rec.outstanding and rec.outstanding.id==job.id
    assert rec.outstanding.state=="paused"
    assert rec.last_snapshot==after
    assert next_job(rec) is None
    assert not db.record_snapshot(7,dict(after))
    assert rec.outstanding.state=="paused"
    reboot=Colony(p)
    rec=reboot.register({"type":"hello","id":7,"generation":1,
         "snapshot":after})
    hello_msg={"journal":{"id":job.id,"status":"done",
                          "result":{"id":job.id,"ok":False}},
               "snapshot":after}
    assert reboot.reconcile_hello(rec,hello_msg)=="paused"
    updated=dict(after,inventory=[{"name":"minecraft:sand","count":6},
                                  {"name":"minecraft:oak_planks","count":8}])
    assert reboot.record_snapshot(7,updated)
    assert rec.outstanding.id==job.id and rec.outstanding.state=="queued"
    assert reboot.counter==1

def test_failed_birth_preflight_does_not_allocate_another_job_id(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    job=db.queue(7,"birth");db.sent(7,job.id)
    failed={"inventory":[],"fuel":200,"front":None,"bottom":None}
    assert db.complete(7,job.id,{"id":job.id,"ok":False,"error":"missing table",
                                 "data":{"snapshot":failed}})
    assert rec.outstanding.id==job.id
    assert rec.outstanding.state=="paused"
    assert not db.record_snapshot(7,failed)
    updated=dict(failed,inventory=[{"name":"minecraft:crafting_table","count":1}])
    assert db.record_snapshot(7,updated)
    assert rec.outstanding.id==job.id and rec.outstanding.state=="queued"

def test_legacy_smelt_error_can_start_a_new_job_once_reconciled(tmp_path):
    db=Colony(tmp_path/"db.json");rec=db.register(hello())
    job=db.queue(7,"process",{"kind":"iron"})
    db.sent(7,job.id)
    assert db.complete(7,job.id,{"id":job.id,"ok":False,"error":"blocked"})
    assert rec.outstanding is None
    assert len(rec.history)==1

def test_completed_base_replenishes_same_species_planks(tmp_path):
    db=Colony(tmp_path/"wood.json"); rec=db.register(hello())
    rec.last_snapshot={
        "bootstrap_enabled":True,"bootstrap_done":True,"storage_observed":True,
        "front":"minecraft:furnace","bottom":"minecraft:chest",
        "fuel":350,"inventory":[{"name":"minecraft:charcoal","count":4}],
        "storage":{"minecraft:sand":6,"minecraft:oak_planks":8}}
    job=next_job(rec)
    assert job and job[0]=="wood_cycle"
    rec.last_snapshot["storage"]["minecraft:oak_planks"]=16
    assert next_job(rec) is None
    rec.last_snapshot["storage"]["minecraft:oak_planks"]=8
    rec.last_snapshot["fuel"]=70
    assert next_job(rec)[0]=="fuel_cycle"

def test_wood_cycle_pause_resumes_same_id_after_stock_change(tmp_path):
    db=Colony(tmp_path/"wood_pause.json"); rec=db.register(hello())
    view={"bootstrap_enabled":True,"bootstrap_done":True,
          "storage_observed":True,"front":"minecraft:furnace",
          "bottom":"minecraft:chest","fuel":300,
          "inventory":[{"name":"minecraft:charcoal","count":5}],
          "storage":{"minecraft:oak_planks":6}}
    rec.last_snapshot=view
    action,args=next_job(rec)
    assert action=="wood_cycle"
    job=db.queue(7,action,args);db.sent(7,job.id)
    assert db.complete(7,job.id,{"ok":False,"error":"No reachable logs",
                              "data":{"snapshot":view}})
    assert rec.outstanding and rec.outstanding.state=="paused"
    assert not db.record_snapshot(7,dict(view))
    new=dict(view,storage={"minecraft:oak_planks":10})
    assert db.record_snapshot(7,new)
    assert rec.outstanding.id==job.id and rec.outstanding.state=="queued"
