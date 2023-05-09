FLN_PORT = 66 -- port for FLN communication
UPDATE_TIME_S = 1.0 -- time between updating the network

-- freight platforms do not follow usual rules
FREIGHT_PLATFORM_FLUID_MAX = 2400.0
FREIGHT_PLATFORM_FLUID_DIV = 1000.0

-- get the position an element would be inserted into a list
-- optinal function to determine ordering of the element
function GetPosition(l, elt, f)
  if not f then f = function (x) return x end end
  local val = f(elt)
  for i, v in ipairs(l) do
    if val < f(v) then return i end
  end
  return #l + 1
end

-- Get table, with multiple accessors, and create tables if necessary
function GetTable(t, ...)
  for i, v in ipairs({...}) do
    if not t[v] then t[v] = {} end
    t = t[v]
  end
  return t
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

-- print a network message
local seq
function PrintMessage(src, data)
  print("----- Message " .. seq .. " from " .. src .. " -----")
  PrintTable(data)
  print("------------------------------------------------------------")
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
    if type(v) == "table" then
      s = s .. tostring(k) .. ":{;" .. ser(v)
    else
      s = s .. tostring(k) .. ":" .. tostring(v) .. ";"
    end
  end
  return s .. "}"
end

-- deserialize a string into a table.  
function des(s)
  local t = {}
  local k, v
  while string.sub(s, 1, 1) ~= "}" do
    _, _, k, v, s = string.find(s, "(.-):(.-);(.*)")
    if v == "{" then v, s = des(s) end
    if tonumber(k) then k = tonumber(k) end
    if tonumber(v) then v = tonumber(v) end
    if v == "true" then v = true elseif v == "false" then v = false end
    t[k] = v
  end
  return t, string.sub(s, 2, -1)
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

-- find a stop on a train network based on hash
function FindStation(hash)
  for _, stop in pairs(station:getTrackGraph():getStations()) do
    if stop.hash == hash then return stop end
  end
  return nil
end


do -- Find Components
-- attached items
  nic = computer.getPCIDevices(findClass("NetworkCard"))[1]
  _, _, nic_addr = string.find(tostring(nic), ".*%s(.*)")

  event.ignoreAll()
  event.clear()
  event.listen(nic)
  nic:open(FLN_PORT)


  resources = {}
  ready = {}
end

nic:broadcast(FLN_PORT, ser({cmd = "set_dispatch"}))
seq = 0
while true do
  evt, src, netsrc, port, netdata = event.pull(UPDATE_TIME_S)
  if src == nic and netsrc ~= nic_addr then
    seq = seq + 1
    local msg = des(netdata)
    -- PrintMessage(netsrc, msg)

    if msg.cmd == "get_dispatch" then
      nic:send(netsrc, FLN_PORT, ser({cmd = "set_dispatch"}))

    elseif msg.cmd == "set_prod_info" then
      local st = {address = netsrc,
                  length = msg.length,
                  item = msg.item,
                  capacity = msg.capacity}
      GetTable(resources, msg.length)[msg.item] = msg.stack
    
    -- request for network item information
    elseif msg.cmd == "get_net_info" then
      nic:send(netsrc, FLN_PORT, ser({cmd = "set_net_info", length = msg.length}), ser(GetTable(resources, msg.length)))
    
    -- register a stop with a ready train
    elseif msg.cmd == "train_ready" then
      GetTable(ready, msg.length, msg.item)[netsrc] = msg.qty
      
    -- train request, see if any available can fulfill
    elseif msg.cmd == "train_request" then
      for netaddr, qty in pairs(GetTable(ready, msg.length, msg.item)) do
        if qty < msg.capacity then
          print("Dispatch " .. qty .. " from " .. netaddr .. " to  " .. netsrc)
          nic:send(netaddr, FLN_PORT, ser(
              {cmd = "send_train",
               stop = msg.stop,
               nic = netsrc}))
          GetTable(ready, msg.length, msg.item)[netaddr] = nil
          break
        end
      end
    end -- messages
  end
end