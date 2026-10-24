import json
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
