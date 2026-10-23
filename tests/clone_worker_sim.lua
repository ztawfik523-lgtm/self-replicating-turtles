-- Exercise actual clone.install with a virtual CC filesystem and drive.
package.path='tg/?.lua;'..package.path
local hostFiles,media,dirs={}, {}, {}
local function hostRead(p)
 local f=io.open(p:gsub('^/',''),'rb')
 if not f then return nil end
 local v=f:read('*a');f:close();return v
end
local function get(p)
 return media[p] or hostFiles[p] or hostRead(p)
end
fs={
 exists=function(p)return get(p)~=nil or dirs[p] or false end,
 getDir=function(p)return p:match('^(.*)/[^/]+$')or '' end,
 combine=function(a,b)
  return a:gsub('/$','')..'/'..b:gsub('^/','')
 end,
 isReadOnly=function()return false end,
 makeDir=function(p)dirs[p]=true end,
 delete=function(p)media[p]=nil;hostFiles[p]=nil end,
 copy=function(src,dst)assert(get(src),'Missing copy source '..src);media[dst]=get(src)end,
 open=function(p,mode)
  if mode=='r' then
   local contents=get(p)
   if not contents then return nil end
   return {readAll=function()return contents end,close=function()end}
  end
  local parts={}
  return {write=function(v)parts[#parts+1]=v end,
   close=function()media[p]=table.concat(parts)end}
 end,
}
disk={isPresent=function(side)return side=='front'end,
 getMountPath=function()return '/disk'end}
peripheral={getType=function()return 'drive'end}
textutils={serialize=function(v)return 'seed:generation='..v.generation..';auto='..tostring(v.auto)end}
package.loaded.state={data={generation=0,autonomyEnabled=true}}
hostFiles['/tg/worker-config.dat']='ws://127.0.0.1:8765'
local clone=dofile('tg/clone.lua')
assert(clone.install('front')=='/disk')
for _,p in ipairs({'startup.lua','tg/worker.lua',
  'tg/workshop.lua','tg/worker-entry.lua'}) do
 assert(media['/disk/'..p]==hostRead(p),'Child missing '..p)
end
assert(media['/disk/tg/worker-config.dat']==hostFiles['/tg/worker-config.dat'])
assert(media['/disk/tg/seed.dat']:find('generation=1'))
print('PASS: child inherits startup, worker, workshop, controller URL, lineage')

media={}
hostFiles['/tg/worker-config.dat']=nil
clone.install('front')
assert(media['/disk/tg/worker.lua']==nil,
 'Legacy clone must not require experimental worker')
assert(media['/disk/startup.lua']==hostRead('startup.lua'))
print('PASS: legacy clone remains usable without controller configuration')
