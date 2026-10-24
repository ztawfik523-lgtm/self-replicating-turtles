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
 inspect=function()return false end,inspectDown=function()return false end}
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
