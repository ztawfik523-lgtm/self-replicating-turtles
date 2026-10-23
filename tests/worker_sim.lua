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
local w=dofile('tg/worker.lua')
local one=w.handle({id='7:1',action='observe'})
assert(one.ok and one.data.fuel==100)
assert(files['/tg/worker-job.dat'])
assert(w.handle({id='7:1',action='observe'}).ok)
assert(not w.handle({id='7:2',action='unknown'}).ok)
print('PASS: Lua worker deduplication and inventory snapshot')
