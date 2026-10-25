package.path='tg/?.lua;'..package.path
package.loaded.state={data={pose={x=0,y=0,z=0,dir=0},generation=0},load=function()end}
local files={}
fs={exists=function(p)return files[p]~=nil end,
 delete=function(p)files[p]=nil end,
 move=function(a,b)files[b]=files[a];files[a]=nil end,
 open=function(p,m)
  if m=='r' then return {readAll=function()return files[p]end,close=function()end} end
  return {write=function(s)files[p]=s end,close=function()end}
 end}
textutils={serialize=function(v)_G.saved=v;return 'state' end,
 unserialize=function()return _G.saved end}
turtle={getItemDetail=function()return nil end,
 getFuelLevel=function()return 100 end,
 inspect=function()return false end,
 inspectDown=function()return true,{name='minecraft:chest'} end}
peripheral={wrap=function(side)
 if side=='bottom' then
  return {list=function()return {
   [1]={name='minecraft:sand',count=5},
   [2]={name='minecraft:sand',count=2},
   [3]={name='minecraft:cobblestone',count=8},
  }end}
 end
end}
local w=dofile('tg/worker.lua')
local one=w.handle({id='7:1',action='observe'})
assert(one.ok and one.data.fuel==100)
assert(one.data.storage['minecraft:sand']==7)
assert(one.data.storage_observed==true)
assert(one.data.storage['minecraft:cobblestone']==8)
assert(files['/tg/worker-job.dat'])
assert(w.handle({id='7:1',action='observe'}).ok)
assert(not w.handle({id='7:2',action='unknown'}).ok)
local births=0
package.loaded.workshop={run=function(jobId)
 assert(jobId=='7:3')
 births=births+1
 return true
end}
local job={id='7:3',action='birth',args={}}
local result=w.handle(job)
assert(result.ok and births==1)
assert(w.handle(job).ok and births==1,'Birth was accidentally repeated')
-- Simulate power failure while the birth job is underway.
local paused={id='7:3',status='started',action='birth',args={}}
_G.saved=paused
files['/tg/worker-job.dat']='state'
assert(w.handle(job).ok and births==2,'Interrupted birth was not retried')
assert(files['/tg/worker-job.dat.bak'])
files['/tg/worker-job.dat']=nil
assert(w.handle(job).ok and births==2,
 'Interrupted journal rename replayed a completed birth')
print('PASS: Lua worker snapshot, resume, journal backup fallback')

-- A failed birth must be retryable with the SAME job ID once an upgrade
-- arrives. The previous implementation returned the old failed result.
local attempts=0
package.loaded.state.data.birth={jobId='7:4',stage='craft_furnace'}
package.loaded.workshop={run=function(jobId)
 assert(jobId=='7:4')
 attempts=attempts+1
 if attempts==1 then error('Crafting upgrade missing') end
 package.loaded.state.data.birth=nil
end}
local stalled={id='7:4',action='birth',args={}}
assert(not w.handle(stalled).ok)
assert(w.handle(stalled).ok)
assert(attempts==2,'Previously failed birth must resume, not be deduplicated')
print('PASS: previously failed birth retries after prerequisite correction')

-- A missing peripheral is not the same as an observed empty chest.
peripheral.wrap=function()return nil end
local unavailable=w.handle({id='7:5',action='observe'})
assert(unavailable.ok and unavailable.data.storage==nil)
assert(unavailable.data.storage_observed==false)
peripheral.wrap=function()return {list=function()return {} end} end
local empty=w.handle({id='7:6',action='observe'})
assert(empty.ok and empty.data.storage_observed==true)
assert(type(empty.data.storage)=='table' and next(empty.data.storage)==nil)
print('PASS: empty and inaccessible storage are not conflated')

-- A broken inventory method must not crash the worker or erase its stock.
peripheral.wrap=function()return {list=function() error('peripheral detached') end} end
local detached=w.handle({id='7:7',action='observe'})
assert(detached.ok and detached.data.storage==nil)
assert(detached.data.storage_observed==false)
-- Phantom peripherals are not accepted when no chest exists below.
turtle.inspectDown=function()return false end
peripheral.wrap=function()return {list=function()return {
 [1]={name='minecraft:diamond',count=99}
} end} end
local phantom=w.handle({id='7:8',action='observe'})
assert(phantom.ok and phantom.data.storage==nil)
assert(phantom.data.storage_observed==false)
print('PASS: disconnected and phantom storage cannot fabricate stock')

-- A failed preflight has no persisted birth state. Adding the missing item
-- must still retry under the SAME controller job ID rather than preserve the
-- stale failure forever.
local checks=0
package.loaded.state.data.birth=nil
package.loaded.workshop={run=function(jobId)
 assert(jobId=='7:5')
 checks=checks+1
 if checks==1 then error('Missing crafting upgrade in preflight') end
 return true
end}
local preflight={id='7:5',action='birth',args={}}
local one=w.handle(preflight)
assert(not one.ok and one.data and one.data.snapshot)
local two=w.handle(preflight)
assert(two.ok and checks==2)
assert(w.handle(preflight).ok and checks==2,
 'Completed job ID must never execute a third time')
print('PASS: failed preflight recovers same job ID after material correction')

-- A failed M2 survey must remain paused across reboot. Only the controller
-- may retry its ORIGINAL ID after a relevant new observation.
local autoRuns=0
package.loaded.bootstrap={run=function()autoRuns=autoRuns+1;return true end}
package.loaded.state.data.birth=nil
package.loaded.state.data.bootstrap={jobId='7:6',stage='gather_sand',complete=false}
_G.saved={id='7:6',status='done',action='bootstrap',
          result={id='7:6',ok=false,error='No nearby sand'},args={}}
files['/tg/worker-job.dat']='state'
files['/tg/worker-config.dat']='ws://127.0.0.1:8765'
http={websocket=function()return nil,'controller offline' end}
sleep=function()error('stop mock worker loop')end
local runOk,runError=pcall(w.run)
assert(not runOk and tostring(runError):find('stop mock worker loop'))
assert(autoRuns==0,'Failed job must not resurvey same terrain after reboot')
print('PASS: failed M2 jobs remain paused across restart')

-- The same failed lumber job must retry under its original ID when the
-- controller observes new trees or resources; do not create a new job.
local tries=0
package.loaded.state.data.woodCycle={jobId='7:wood',stage='gather'}
package.loaded.bootstrap={woodCycle=function(id)
 assert(id=='7:wood')
 tries=tries+1
 if tries==1 then error('No reachable trees today') end
 package.loaded.state.data.woodCycle=nil
 return true
end}
local lumber={id='7:wood',action='wood_cycle',args={}}
assert(not w.handle(lumber).ok)
assert(w.handle(lumber).ok and tries==2)
assert(w.handle(lumber).ok and tries==2)
print('PASS: paused lumber job retries once with same persistent ID')

local mineralAttempts=0
package.loaded.state.data.materialCycle={jobId='7:minerals',stage='sand'}
package.loaded.bootstrap={materialCycle=function(id)
 assert(id=='7:minerals')
 mineralAttempts=mineralAttempts+1
 if mineralAttempts==1 then error('No available sand') end
 package.loaded.state.data.materialCycle=nil
end}
local minerals={id='7:minerals',action='material_cycle',args={}}
assert(not w.handle(minerals).ok)
assert(w.handle(minerals).ok and mineralAttempts==2)
assert(w.handle(minerals).ok and mineralAttempts==2)
print('PASS: material-cycle retry is journaled against its original job ID')
