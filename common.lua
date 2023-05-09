FLN_PORT = 66 -- port for FLN communication
UPDATE_TIME_S = 1.0 -- time between updating the network

-- freight platforms do not follow usual rules
FREIGHT_PLATFORM_FLUID_MAX = 2400.0
FREIGHT_PLATFORM_FLUID_DIV = 1000.0


function InitFS()
  fs = filesystem
  if fs.initFileSystem("/dev") == false then
      computer.panic("Cannot initialize /dev")
  end
  local dsk = nil
  for _, drive in pairs(fs.childs("/dev")) do
    if drive ~= "serial" then dsk = drive end
  end

  fs.mount("/dev/" .. dsk, "/")
end

-- size of a table
function TableSize(t)
  local i = 0
  for _, _ in pairs(t) do
    i = i + 1
  end
  return i
end

-- print a table
function PrintTable(t)
  for k, v in pairs(t) do
    print(tostring(k) .. ": " .. tostring(v))
  end
end

-- Find attached inventories
function FindStorage(nodes)
  local storage = {}
  for _, node in pairs(nodes) do
    local ns = tostring(node)

    -- computers have inventory that's useless
    if ns == "Computer_C" then
      -- ignore

    -- iterate over all train platforms
    elseif ns == "Build_TrainStation_C" then
      while node do
        if #node:getInventories() ~= 0 then table.insert(storage, node) end
        node = node:GetConnectedPlatform()
      end

    -- otherwise, include if it can store solids or fluids
    elseif #node:getInventories() ~= 0 or node.maxFluidContent then
      table.insert(storage, node)
    end
  end

  return storage
end

-- check for total stacks, fluid storage, and any items that may be in the system
function GetMaxCapacity(nodes)
  local stacks = 0
  local fluid = 0
  local items = {}
  for _, node in pairs(nodes) do
    -- check first inventory
    local inv = node:getInventories()[1]
    if inv then
      -- fluid freight platforms do not behave like other fluid storage
      if tostring(node) == "Build_TrainDockingStationLiquid_C" then
        fluid = fluid + FREIGHT_PLATFORM_FLUID_MAX
      else
        stacks = stacks + inv.size
      end
      for i = 0, inv.size - 1 do
        local stk = inv:getStack(i)
        if stk.count > 0 then items[stk.item.type.name] = stk.item.type end
      end
    end

    -- check fluid storage
    if node.maxFluidContent then 
      fluid = fluid + node.maxFluidContent
      if node:getFluidType() then items[node:getFluidType().name] = node:getFluidType() end
    end
  end

  return stacks, fluid, items
end

-- check for current quantity of items in the system
function GetQty(nodes)
  total = 0
  for _, node in pairs(nodes) do
    if node.fluidContent then
      total = total + node.fluidContent
    else
      local inv = node:getInventories()[1]
      if not inv then
        --no inventory
      elseif inv.size == 1 then
        total = total + inv.itemCount / FREIGHT_PLATFORM_FLUID_DIV
      else
        total = total + inv.itemCount
      end
    end
  end
  return total
end

-- serialize a table into a string
function ser(t)
  local s = ""
  for k, v in pairs(t) do
    s = s .. k .. ":" .. v .. ";"
  end
  return s
end

-- deserialize a string into a table.  
function des(s)
  local t = {}
  local k, v
  while s ~= "" do
    _, _, k, v, s = string.find(s, "(.-):(.-);(.*)")
    if tonumber(k) then k = tonumber(k) end
    if tonumber(v) then v = tonumber(v) end
    if v == "true" then v = true elseif v == "false" then v = false end
    t[k] = v
  end
  return t
end

-- print out contents of an object
function PrintInventory(obj)
  print("Inventory for: ", obj)
  local invs = obj:getInventories()
  for i, inv in ipairs(invs) do
    print("Inventory ", i, "Size", inv.size, "Total", inv.itemCount)
    for j = 0, inv.size - 1 do
      local stack = inv:getStack(j)
      if stack.count > 0 then print(stack.item.type.name, stack.count) end
    end
  end
  print("------")
end

-- find the length of the attached train station
function TrainStationLength(station, dir)
  local len = 0;
  while station do
    len = len + 1
    station = station:getConnectedPlatform(dir)
  end
  return len
end

function TrainStationDone(station)
  while station do
    if station.
    
    
  
  end
end