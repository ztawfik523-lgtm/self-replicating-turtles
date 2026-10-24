-- Executes the controller installer with a simulated CC filesystem and HTTP.
-- Covers all-or-nothing staging, copy-failure rollback, and state preservation.
local files,dirs,failFetch,failCopy={}, {}, nil,nil
local function readRepo(p)
 local f=io.open(p,'rb')
 if not f then return nil end
 local s=f:read('*a');f:close()
 return s
end
local function reset()
 files={
  ['/startup.lua']='legacy startup',
  ['/tg/worker.lua']='legacy worker',
  ['/tg/main.lua']='legacy main',
  ['/tg/state.dat']='persistent turtle state',
  ['/tg/worker-config.dat']='ws://previous-host:8765',
 }
 dirs={['/']=true,['/tg']=true}
 failFetch=nil;failCopy=nil
end
fs={}
fs.combine=function(a,b)
 return a:gsub('/$','')..'/'..b:gsub('^/','')
end
fs.getDir=function(p)return p:match('^(.*)/[^/]+$') or '' end
fs.exists=function(p)
 if files[p]~=nil or dirs[p] then return true end
 for name in pairs(files) do
  if name:sub(1,#p+1)==p..'/' then return true end
 end
 return false
end
fs.makeDir=function(p)dirs[p]=true end
fs.delete=function(p)
 files[p]=nil
 dirs[p]=nil
 local prefix=p..'/'
 for name in pairs(files) do
  if name:sub(1,#prefix)==prefix then files[name]=nil end
 end
 for name in pairs(dirs) do
  if name:sub(1,#prefix)==prefix then dirs[name]=nil end
 end
end
fs.copy=function(src,dst)
 assert(files[src]~=nil,'No copy source '..src)
 if dst==failCopy then
  failCopy=nil
  error('Simulated disk write failure for '..dst)
 end
 files[dst]=files[src]
end
fs.open=function(path,mode)
 if mode=='r' then
  local s=files[path]
  if not s then return nil end
  return {readAll=function()return s end,close=function()end}
 end
 local fragments={}
 return {write=function(v)fragments[#fragments+1]=v end,
  close=function()files[path]=table.concat(fragments)end}
end
turtle={}
http={get=function(url)
 local path=url:match('self%-replicating%-turtles/[^/]+/(.+)$')
 assert(path,'Bad raw URL: '..url)
 if path==failFetch then return nil,'Simulated bad HTTP response' end
 local source=readRepo(path)
 if not source then return nil,'No local source' end
 return {readAll=function()return source end,close=function()end}
end}
local launches=0
shell={run=function(path)
 assert(path=='/tg/worker-entry.lua')
 launches=launches+1
 return true
end}
local installer=assert(loadfile('controller/install.lua'))
reset()
failFetch='tg/factory.lua'
local ok=pcall(installer,'ws://controller:8765')
assert(not ok,'Staging failure should abort installation')
assert(files['/startup.lua']=='legacy startup')
assert(files['/tg/state.dat']=='persistent turtle state')
assert(files['/tg/worker-config.dat']=='ws://previous-host:8765')
assert(not fs.exists('/tg-controller-download'))
assert(launches==0)
print('PASS: failed download leaves live turtle untouched')

reset()
failCopy='/tg/worker.lua'
ok=pcall(installer,'ws://controller:8765')
assert(not ok,'Disk failure should abort installation')
assert(files['/startup.lua']=='legacy startup')
assert(files['/tg/worker.lua']=='legacy worker')
assert(files['/tg/main.lua']=='legacy main')
assert(files['/tg/state.dat']=='persistent turtle state')
assert(files['/tg/worker-config.dat']=='ws://previous-host:8765')
assert(not fs.exists('/tg-controller-backup'))
assert(launches==0)
print('PASS: failed replacement restores old startup/worker/config')

reset()
-- A game shutdown after the READY marker but before installing all files
-- must restore the previous generation before doing anything else.
dirs['/tg-controller-backup']=true
files['/tg-controller-backup/READY']='backup complete'
files['/tg-controller-backup/startup.lua']='legacy startup'
files['/tg-controller-backup/tg/worker.lua']='legacy worker'
files['/tg-controller-backup/tg/main.lua']='legacy main'
files['/tg-controller-backup/tg/worker-config.dat']='ws://previous-host:8765'
files['/startup.lua']='interrupted new startup'
files['/tg/worker.lua']='interrupted new worker'
failFetch='tg/factory.lua'
ok=pcall(installer,'ws://controller:8765')
assert(not ok)
assert(files['/startup.lua']=='legacy startup')
assert(files['/tg/worker.lua']=='legacy worker')
assert(files['/tg/main.lua']=='legacy main')
assert(files['/tg/worker-config.dat']=='ws://previous-host:8765')
assert(not fs.exists('/tg-controller-backup'))
print('PASS: interrupted install is automatically rolled back next launch')

reset()
assert(installer('ws://controller:8765')==nil)
assert(files['/startup.lua']==readRepo('startup.lua'))
assert(files['/tg/worker.lua']==readRepo('tg/worker.lua'))
assert(files['/tg/workshop.lua']==readRepo('tg/workshop.lua'))
assert(files['/tg/state.dat']=='persistent turtle state')
assert(files['/tg/worker-config.dat']=='ws://controller:8765')
assert(files['/tg/bootstrap-opt-in.dat']==nil,
 'Upgrading an existing parent must not enable M2 exploration')
assert(files['/tg/bootstrap.lua']==readRepo('tg/bootstrap.lua'))
assert(launches==1)
assert(not fs.exists('/tg-controller-download'))
assert(not fs.exists('/tg-controller-backup'))
print('PASS: first-birth installer stages, installs and starts worker')

reset()
assert(installer('ws://controller:8765','bootstrap')==nil)
assert(files['/tg/bootstrap-opt-in.dat']=='enabled',
 'Explicit M2 opt-in did not reach worker')
assert(files['/tg/bootstrap.lua']==readRepo('tg/bootstrap.lua'))
assert(files['/tg/state.dat']=='persistent turtle state')
assert(launches==2)
print('PASS: only explicit bootstrap install enables M2; existing state preserved')

reset()
failCopy='/tg/bootstrap.lua'
ok=pcall(installer,'ws://controller:8765','bootstrap')
assert(not ok)
assert(files['/tg/bootstrap-opt-in.dat']==nil,
 'Failed M2 install must not leave an exploration flag')
assert(files['/startup.lua']=='legacy startup')
assert(files['/tg/state.dat']=='persistent turtle state')
print('PASS: failed M2 install leaves original turtle safe')
