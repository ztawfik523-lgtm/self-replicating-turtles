"""Turtle Genesis control service. Default: local-only, unauthenticated.
Install dependency: pip install 'websockets>=14'
Run from repository root: python -m controller.server
"""
from __future__ import annotations
import asyncio
import json
import logging
import os
from pathlib import Path
from websockets.asyncio.server import serve
from .engine import Colony, shortages, next_job

LOG = logging.getLogger("genesis")

class Host:
    def __init__(self, state_path: str | Path):
        self.colony = Colony(state_path)
        self.connected: set[int] = set()

    async def handle(self, websocket):
        rec = None
        try:
            hello = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15))
            if hello.get("type") != "hello":
                await websocket.close(code=1008, reason="Expected hello")
                return
            rec = self.colony.register(hello)
            if rec.turtle_id in self.connected:
                await websocket.close(code=1008, reason="Duplicate turtle ID")
                return
            self.connected.add(rec.turtle_id)
            recovery = self.colony.reconcile_hello(rec, hello)
            LOG.info("Turtle %d connected, recovery=%s", rec.turtle_id, recovery)
            await websocket.send(json.dumps({"type": "welcome", "recovery": recovery,
                                             "shortages": shortages(rec.last_snapshot)}))
            while True:
                if rec.outstanding is None:
                    selection = next_job(rec)
                    if selection:
                        self.colony.queue(rec.turtle_id, *selection)
                job = rec.outstanding
                if job and job.state == "queued":
                    await websocket.send(json.dumps(job.message()))
                    self.colony.sent(rec.turtle_id, job.id)
                msg = json.loads(await asyncio.wait_for(websocket.recv(), timeout=1200))
                if msg.get("type") == "snapshot":
                    rec.last_snapshot = msg.get("snapshot") or {}
                    self.colony.save()
                    await websocket.send(json.dumps({"type": "ack",
                                                     "shortages": shortages(rec.last_snapshot)}))
                elif msg.get("type") == "result":
                    applied = self.colony.complete(rec.turtle_id, str(msg.get("id")), msg)
                    await websocket.send(json.dumps({"type": "ack", "accepted": applied}))
                elif msg.get("type") == "ping":
                    await websocket.send('{"type":"pong"}')
                else:
                    await websocket.send('{"type":"error","reason":"Unsupported message"}')
        except (EOFError, ConnectionError, OSError, TimeoutError, json.JSONDecodeError) as err:
            LOG.info("Turtle %s disconnected: %s", rec.turtle_id if rec else "?", err)
        finally:
            if rec:
                self.connected.discard(rec.turtle_id)

async def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    bind = os.getenv("GENESIS_HOST", "127.0.0.1")
    port = int(os.getenv("GENESIS_PORT", "8765"))
    path = os.getenv("GENESIS_STATE", "controller/colony.json")
    host = Host(path)
    async with serve(host.handle, bind, port, max_size=2_000_000, ping_interval=None):
        LOG.info("Turtle Genesis controller listening on ws://%s:%d", bind, port)
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
