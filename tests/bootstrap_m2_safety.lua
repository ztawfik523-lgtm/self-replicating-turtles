-- M2 failures must not cause unbounded wandering or invent a home position.
package.path='tg/?.lua;'..package.path
local pos={x=0,y=0,z=0,dir=0}
local fuelLevel=1000
local steps=0
turtle={
 getItemDetail=function()return nil end,
 getFuelLevel=function()return fuelLevel end,
 craft=function()return true end,
 getSelectedSlot=function()return 1 end,
 select=function()return true end,
 inspect=function()return false end,
 inspectDown=function()return false end,
 detect=function()return false end,
 forward=function()steps=steps+1;fuelLevel=fuelLevel-1;return true end,
 back=function()steps=steps+1;fuelLevel=fuelLevel-1;return true end,
 turnRight=function()return true end,
 turnLeft=function()return true end,
}
local st={data={pose=pos,moves=0},save=function()end,
 assertSafe=function() assert(not st or true) end}
package.loaded.state=st
package.loaded.fuel={
 level=function()return fuelLevel end,
 ensure=function(n)return fuelLevel>=n end
}
package.loaded.factory={}
package.loaded.process={}
local boot=dofile('tg/bootstrap.lua')
local ok,why=pcall(boot.run,'3:1')
assert(not ok and tostring(why):find('No accessible tree'))
assert(pos.x==0 and pos.y==0 and pos.z==0 and pos.dir==0,
 'No-tree survey failed to return home')
assert(steps<=96,'Survey explored farther than bounded radius')
assert(not st.data.bootstrap.complete)
print('PASS: no-tree environment stops safely after bounded return-to-home search')

pos={x=0,y=0,z=0,dir=0}
fuelLevel=20;steps=0
st.data={pose=pos,moves=0}
ok,why=pcall(boot.run,'4:1')
assert(not ok and tostring(why):find('at least 140'))
assert(st.data.bootstrap==nil and steps==0,
 'Low-fuel bootstrap changed the turtle position')
print('PASS: insufficient initial movement fuel fails before deployment')
