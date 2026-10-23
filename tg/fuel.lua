local M = {}
local allowed = {['minecraft:coal'] = true, ['minecraft:charcoal'] = true}
function M.level()
  local level = turtle.getFuelLevel()
  if level == 'unlimited' then return math.huge end
  return tonumber(level) or 0
end
function M.ensure(required)
  if M.level() >= required then return true end
  local oldSlot = turtle.getSelectedSlot()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and allowed[item.name] then
      turtle.select(slot)
      while turtle.getItemCount(slot) > 0 and M.level() < required do
        local ok = turtle.refuel(1)
        if not ok then break end
      end
    end
    if M.level() >= required then break end
  end
  turtle.select(oldSlot)
  return M.level() >= required
end
function M.findFuelSlot(excluded)
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and allowed[item.name] and slot ~= excluded then return slot end
  end
  return nil
end
return M
