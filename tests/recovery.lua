-- Regression tests: stale station flags must not strand an idle turtle.
-- Runs under Lua 5.2; no Minecraft server or extra libraries required.
local state, blocks, processCalls, recovered, dug

local function fixture(phase,processing,owns)
  blocks={front='minecraft:furnace',bottom='minecraft:chest'}
  processCalls,recovered,dug=0,0,0
  state={
    data={
      station={phase=phase,kind='iron',
        ownedChest=owns,ownedFurnace=owns},
      processing=processing,
    },
    save=function() end,
    assertSafe=function() end,
  }
  package.loaded.state=state
  package.loaded.log={event=function() end}
  package.loaded.factory={
    collect=function() error('Chest is empty; should not collect') end,
    craftStep=function() error('Must not craft when equipment exists') end,
  }
  package.loaded.process={
    resume=function()
      recovered=recovered+1
      state.data.processing=nil
      return true
    end,
    run=function(kind)
      assert(kind=='iron')
      processCalls=processCalls+1
    end,
  }
  turtle={
    inspect=function()
      return blocks.front~=nil,blocks.front and {name=blocks.front} or 'No block'
    end,
    inspectDown=function()
      return blocks.bottom~=nil,blocks.bottom and {name=blocks.bottom} or 'No block'
    end,
    getItemDetail=function() return nil end,
    getSelectedSlot=function() return 1 end,
    select=function() return true end,
    dig=function()
      assert(blocks.front=='minecraft:furnace')
      blocks.front=nil
      dug=dug+1
      return true
    end,
    digDown=function()
      assert(blocks.bottom=='minecraft:chest')
      blocks.bottom=nil
      dug=dug+1
      return true
    end,
  }
  peripheral={
    wrap=function()
      return {list=function() return {} end}
    end,
  }
  return dofile('tg/station.lua')
end

-- This is the exact screenshot scenario: smelting done, empty blocks, stale state.
local station=fixture('processing_iron',nil,true)
assert(station.run('iron')==true)
assert(state.data.station==nil,'stale station flag not cleared')
assert(dug==2,'owned empty equipment must be packed')
assert(processCalls==0,'must not smelt a second time')

-- An interrupted smelt should resume itself, then pack its workstation.
station=fixture('processing_iron',{kind='iron'},true)
assert(station.run('iron')==true)
assert(recovered==1,'saved furnace operation was not recovered')
assert(state.data.processing==nil and state.data.station==nil)

-- An interrupted setup uses already-present, unowned blocks and continues.
station=fixture('starting',nil,false)
assert(station.recover()==true)
assert(processCalls==1,'unfinished setup was not resumed')
assert(dug==0,'must not break pre-existing equipment')
assert(state.data.station==nil)

-- Completing an already-placed chest recovers it even if the state wasn't saved.
station=fixture('placing_chest',nil,false)
assert(station.recover()==true)
assert(dug==1,'chest placed immediately before interruption must be reclaimed')
assert(state.data.station==nil)

-- The processing subsystem should clear an already completed smelt.
package.loaded.state={
  data={processing={kind='iron',input='minecraft:raw_iron',
    amount=64,stage='smelting'}},
  save=function()end,
  assertSafe=function()end,
}
package.loaded.log={event=function()end}
turtle={
  inspect=function()return true,{name='minecraft:furnace'}end,
  inspectDown=function()return true,{name='minecraft:chest'}end,
}
local furnace={
  size=function()return 3 end,
  getItemDetail=function()return nil end,
  list=function()return {} end,
  pushItems=function()return 0 end,
}
local chest={list=function()return {} end,pushItems=function()return 0 end}
peripheral={wrap=function(side)
  return side=='front' and furnace or chest
end}
if not os.epoch then os.epoch=function() return 0 end end
local processor=dofile('tg/process.lua')
assert(processor.resume()==true)
assert(package.loaded.state.data.processing==nil,
  'finished processing should clear its own state')

print('PASS: 5 workstation and furnace recovery scenarios')
