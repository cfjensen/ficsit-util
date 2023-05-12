FLN_PORT = 66 -- port for FLN communication
UPDATE_TIME_S = 1.0 -- time between updating the network

-- freight platforms do not follow usual rules
FREIGHT_PLATFORM_FLUID_MAX = 2400.0
FREIGHT_PLATFORM_FLUID_DIV = 1000.0

STD_VAL = {10, 11, 12, 13, 15, 16, 18, 20, 22, 24, 27, 30, 33, 36, 39, 43, 47, 41, 56, 62, 68, 75, 82, 91}
SCREEN_WIDTH = 20
SCREEN_HEIGHT = 4
NO_ITEM = "None"

FW_VERSION = 1.00

function Limit(val, min_val, max_val)
  if min_val and val < min_val then val = min_val end
  if max_val and val > max_val then val = max_val end
  return val
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
local seq = 0
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
    -- elseif ns == "Build_TrainStation_C" then
    --   while node do
    --     if #node:getInventories() ~= 0 then table.insert(storage, node) end
    --     node = node:GetConnectedPlatform()
    --   end

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
  local total = 0
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

-- Get a table of items and total quantity from a list of nodes
-- Also returns the number of empty stacks
function GetItems(nodes)
  local items = {}
  local empty = 0
  for _, node in pairs(nodes) do
    if node.fluidContent and node:getFluidType()then
      items[node:getFluidType().name] = (items[node:getFluidType().name] or 0) + node.fluidContent
    else
      local inv = node:getInventories()[1]
      if not inv then 
        -- no inventory
        
      -- inventory size 1 is always a fluid container
      elseif inv.size == 1 then
        local stack = inv:getStack(0)
        if stack.count ~= 0 then 
          items[stack.item.type.name] = (items[stack.item.type.name] or 0) + stack.count / FREIGHT_PLATFORM_FLUID_DIV
        end
      else      
        for i = 0, inv.size - 1 do
          local stack = inv:getStack(i)
          if stack.count == 0 then
            empty = empty + 1
          else
            items[stack.item.type.name] = (items[stack.item.type.name] or 0) + stack.count
          end
        end
      end
    end
  end
  return items, empty
end

-- find the index of a value in a list
-- returns index or 0 on failure
function FindIndex(list, elt, f)
  if not f then f = function (x) return x end end
  for i, v in ipairs(list) do
    if elt == f(v) then return i end
  end
  return 0
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

-- wrap a string to a character boundary
-- return modified string and number of lines
function WrapStr(s, nchar)
  local i = 1
  local w = 1
  local l = 1
  while s:sub(i, i) ~= "" do
    i = i + 1
    w = w + 1
    if (w >= nchar) then
      while s:sub(i, i) ~= " " do
        i = i - 1
        w = w - 1
      end
      s = s:sub(1, i - 1) .. "\n" .. s:sub(i + 1)
      w = 1
      l = l + 1
    end
  end
  return s, l
end


-- Consumer specific functions

-- find source of an event
function FindSource(s)
  for slot, ctrl in ipairs(item_slots) do
    for k, v in pairs(ctrl) do
      if s.hash == v.hash then return slot, k end
    end
  end
  return nil
end

-- get quantity and total capacity of an item in a node
-- assumes only one type of item is stored per node
function GetQty(node, slot)
  -- only one type of fluid in a network ever
  local inv = node:getInventories()[1]
  if node.fluidContent then
    return node.fluidContent, node.maxFluidContent
  -- size 1 inventory is always a fluid
  elseif inv.size == 1 then
    return inv:getStack(0).count / FREIGHT_PLATFORM_FLUID_DIV, FREIGHT_PLATFORM_FLUID_MAX
  end
  
  local item_type = inv:getStack(0).item.type
  local capacity = inv.size * request[slot].stack
  -- nothing in the container, could be used for storage
  if not item_type then
    return 0, capacity
    
  -- currently storing this type of item, return count an capacity
  elseif item_type.name == request[slot].item then
    return inv.itemCount, capacity
  end
  
  -- storing another item
  return 0, 0 
end

-- get quantity and total capacity of an item in a node
-- can be multiple types of items in a node
function GetQtyMixed(node, slot)
  -- only one type of fluid in a network ever
  local inv = node:getInventories()[1]
  if node.fluidContent then
    return node.fluidContent, node.maxFluidContent
  -- size 1 inventory is always a fluid
  elseif inv.size == 1 then
    return inv:getStack(0).count / FREIGHT_PLATFORM_FLUID_DIV, FREIGHT_PLATFORM_FLUID_MAX
  end
  
  -- sold inventory, need to iterate over all slots
  local qty = 0
  local cap = 0
  for i = 0, inv.size - 1 do
    local stack = inv:getStack(i)
    if stack.count > 0 then
      if stack.item.type.name == request[slot].item then
        qty = qty + stack.count
        cap = cap + request[slot].stack
      end
    else
      cap = cap + request[slot].stack
    end
  end
  
  return qty, cap
end

function UpdateText(slot, item, qty, pri)
  if slot == 1 and qty == 0 then qty = "Full" end
  local s, l = WrapStr(item, SCREEN_WIDTH)
  s = s .. string.rep("\n", SCREEN_HEIGHT - l) .. qty
  s = s .. string.rep(" ", SCREEN_WIDTH - #tostring(qty) - 1) .. pri
  item_slots[slot].text.text = s
end


-- UX for the item slots
function InitUX()
  for i, slot in ipairs(item_slots) do
    slot.text.size = 37
    slot.text.monospace = true
    slot.text.text = ""
    slot.gauge.limit = 1.0
  end
  UpdateText(1, "Searching for Dispatch Server", "", "")
  
  lever.state = false
  led_en:setColor(0, 0, 0, 0)
  led_dis:setColor(1, 0, 0, 1)
end

function UpdateUX(e, s, d)
  slot, elt = FindSource(s)
  if not slot then return false end
  if lever.state then return true end
  if slot ~= 1 and request[1].qty == 0 then return true end
  
  -- item change
  if elt == "enc_item" then
    local sel = FindIndex(available, request[slot].item, function(x) return x.item end)
    sel = Limit(sel + d, 1, #available)
    request[slot].item = available[sel].item
    request[slot].stack = available[sel].stack
    UpdateText(slot, request[slot].item, request[slot].qty, request[slot].pri)
    
  -- quantity change
  elseif elt == "enc_qty" then
    local sel = FindIndex(available, request[slot].item, function(x) return x.item end)
    request[slot].qty = Limit(request[slot].qty + d * available[sel].stack, 0, nil)
    UpdateText(slot, request[slot].item, request[slot].qty, request[slot].pri)
    
    -- if slot 1 is requesting a full load, blank out all other requests
    if slot == 1 and request[slot].qty == 0 then
      for i = 2, #request do
        request[i].item = NO_ITEM
        request[i].qty = 0
        request[i].pri = 5
        item_slots[i].text.text = ""
      end
    else
      for i = 2, #request do
        UpdateText(i, request[i].item, request[i].qty, request[i].pri)
      end
    end
    
  -- priority change
  elseif elt == "enc_pri" then
    request[slot].pri = Limit(request[slot].pri + d, 0, 9)
    UpdateText(slot, request[slot].item, request[slot].qty, request[slot].pri)
  end
  
  
  return true
end

-- remove this stop from the train
function RemoveStop(train)
  tt = train:getTimeTable()
  for i, stop in ipairs(tt:getStops()) do
    if stop.station == station then
      rem = i
      break
    end
  end
  if rem then tt:removeStop(rem - 1) end
end

-- find incoming trains
function FindIncomingTrains()
  for _, train in ipairs(station:getTrackGraph():getTrains()) do
    if train.isSelfDriving 
        and train:getTimeTable().numStops == 2
        and train:getTimeTable():getStop(1).station == station then
      for item, qty in pairs(GetItems(train:getVehicles())) do
        incoming_trains[train.hash] = {item = item, qty = qty}
        print("Incoming Train " .. train.hash .. " " .. item .. ": " .. qty)
      end
    end
  end
end


do -- Register Devices
  -- find the station and length
  station = component.findComponent(findClass("Build_TrainStation_C"))[1]
  if not station then computer.panic("No Station Found") end
  station = component.proxy(station)
  station_len = TrainStationLength(station, 0)
  freight_platforms = {}
  local plat = station:getConnectedPlatform(0)
  while plat do
    table.insert(freight_platforms, plat)
    plat = plat:getConnectedPlatform(0)
  end
  
  nodes = component.proxy(component.findComponent(""))
  stores = FindStorage(nodes)
  stacks, fluid = GetMaxCapacity(stores)


  -- attached items
  nic = computer.getPCIDevices(findClass("NetworkCard"))[1]
  _, _, nic_addr = string.find(tostring(nic), ".*%s(.*)")
  panel = component.proxy(component.findComponent(findClass("LargeControlPanel"))[1])
  item_slots = {
    {enc_item = panel:getModule(1, 10),
      enc_qty = panel:getModule(1, 9),
      enc_pri = panel:getModule(6, 9),
      text = panel:getModule(2, 10),
      gauge = panel:getModule(7, 10)},
    {enc_item = panel:getModule(1, 7),
      enc_qty = panel:getModule(1, 6),
      enc_pri = panel:getModule(6, 6),
      text = panel:getModule(2, 7),
      gauge = panel:getModule(7, 7)},
    {enc_item = panel:getModule(1, 4),
      enc_qty = panel:getModule(1, 3),
      enc_pri = panel:getModule(6, 3),
      text = panel:getModule(2, 4),
      gauge = panel:getModule(7, 4)},
    {enc_item = panel:getModule(1, 1),
      enc_qty = panel:getModule(1, 0),
      enc_pri = panel:getModule(6, 0),
      text = panel:getModule(2, 1),
      gauge = panel:getModule(7, 1)}}
  
  led_en = panel:getModule(9, 10)
  led_dis = panel:getModule(9, 9)
  lever = panel:getModule(10, 10)
  
  dispatch = nil
  fluid = false
  if station:getConnectedPlatform(0):getInventories()[1].size == 1 then
    fluid = true
  end
  incoming_trains = {}
  docked_train = nil
  last_train = nil
  available = {{item = NO_ITEM, stack = 0}}

  event.ignoreAll()
  event.clear()
  event.listen(lever)
  event.listen(nic)
  for _, slot in ipairs(item_slots) do
    event.listen(slot.enc_item)
    event.listen(slot.enc_qty)
    event.listen(slot.enc_pri)
  end
  nic:open(FLN_PORT)
end

-- Initalize to default values
function Init()
  InitUX()
  
  request = {}
  for i = 1, #item_slots do
    table.insert(request, {item = NO_ITEM, qty = 0, stack = 0, pri = 5})
  end
end

function Save()
  panel.nick = ser({request = request})
end

function Restore()
  local sdata = des(panel.nick)
  request = sdata.request
  FindIncomingTrains()
end

if lever.state then
  Restore()
else
  Init()
end


t = computer.millis()
while true do
  evt, src, netsrc, port, netdata, optdata = event.pull(UPDATE_TIME_S)
  
  -- check for a new docked train
  if station:getDockedLocomotive() then
    docked_train = station:getDockedLocomotive():getTrain()
  else
    docked_train = nil
  end
  if last_train and not docked_train then
    for hash, _ in pairs(incoming_trains) do
      if last_train.hash == hash then incoming_trains[hash] = nil end
    end
    RemoveStop(last_train)
  end
  last_train = docked_train

  -- button press to get network info
  if evt and UpdateUX(evt, src, netsrc) then
    -- UX update

  -- lever to turn on and off
  elseif src == lever then
    if lever.state and request[1] ~= NO_ITEM then
      Save()
      led_en:setColor(0, 1, 0, 1)
      led_dis:setColor(0, 0, 0, 0)
    else
      lever.state = false
      led_en:setColor(0, 0, 0, 0)
      led_dis:setColor(1, 0, 0, 1)
    end
  
  elseif src == nic and netsrc == nic_addr then
    -- broadcast message from self
  elseif src == nic then
    msg = des(netdata)
    seq = seq + 1
    print("----- Message " .. seq .. " from " .. netsrc .. " -----")
    PrintTable(msg)
    print("------------------------------------------------------------")

    -- register with dispatcher
    if msg.cmd == "set_dispatch" then
      dispatch = netsrc
      print("Registered " .. dispatch .. " as dispatch")
      UpdateText(1, request[1].item, request[1].qty, request[1].pri)
      nic:send(dispatch, FLN_PORT, ser({cmd = "get_net_info", length = station_len}))
      
    -- set available materials
    elseif msg.cmd == "set_net_info" then
      available = {}
      for k, v in pairs(des(optdata)) do
        -- insert solids if this station accepts solids, fluids otherwise
        -- fluids are indicated with a stack size of 0
        if (v > 0) ~= fluid then
          table.insert(available, {item = k, stack = v})
        end
      end
      
      table.sort(available, function (a, b) return a.item < b.item end)
      table.insert(available, 1, {item = NO_ITEM, stack = 0})
      

    -- train incoming, add to stock
    elseif msg.cmd == "incoming_train" then
      incoming_trains[msg.train] = {item = msg.item, qty = msg.qty}
      
    -- device firmware upgrade
    elseif msg.cmd == "dfu_cons" then
      computer.setEEPROM(optdata)
      computer.reset()
    
    end -- NIC messages
  end -- events

  -- periodic updates
  if computer.millis() - t > UPDATE_TIME_S * 1000 then
    t = computer.millis()
    
    -- find dispatch server
    if not dispatch then
      nic:broadcast(FLN_PORT, ser({cmd = "get_dispatch"}))
      
    -- station is not enabled, update available items
    elseif not lever.state then
      nic:send(dispatch, FLN_PORT, ser({cmd = "get_net_info", length = station_len}))
      
    -- station is enabled, check current stock, request train if low
    elseif lever.state then
      for i, req in ipairs(request) do
      
        local stock = 0
        local capacity = 0
        local full_load = (i == 1 and req.qty == 0)
        
        -- trying to keep train station full.  all inventories, including the station
        -- will be used for storage
        if full_load then
          for _, store in ipairs(stores) do
            local s, c = GetQty(store, i)
            stock = stock + s
            capacity = capacity + c
          end
          local plat = station:getConnectedPlatform(0)
          while plat do
            local s, c = GetQty(plat, i)
            stock = stock + s
            capacity = capacity + c
            plat = plat:getConnectedPlatform(0)
          end
          
          for _, incoming in pairs(incoming_trains) do
            if incoming.item == req.item then stock = stock + incoming.qty end
          end
          
        -- allow for differences in unloading
        capacity = capacity * 0.9
        
        -- non-zero request quantity, check appropriate stores
        elseif req.qty > 0 then
          for _, store in ipairs(stores) do
            local s, c = GetQty(store, i)
            stock = stock + s
            -- only count capacity from stores currently stocking the relevant item
            if s > 0 then capacity = capacity + c end
          end
          
          -- count inventory from station, but not capacity.  The station should not be
          -- used for storage, only unloading
          local plat = station:getConnectedPlatform(0)
          while plat do
            local s, c = GetQtyMixed(plat, i)
            stock = stock + s
            plat = plat:getConnectedPlatform(0)
          end
          
          for _, incoming in pairs(incoming_trains) do
            if incoming.item == req.item then stock = stock + incoming.qty end
          end
          
          capacity = capacity
          
          -- no stock and no inventory, assume the station can at least handle
          -- one train
          if stock == 0 and capacity == 0 then
            capacity = 1000000 -- tonumber(tostring(math.huge)) ~= math.huge
          end
        end
        
        -- update gauge. 50% is the target fill
        item_slots[i].gauge.percent = Limit(stock / (req.qty * 2), 0.0, 1.0)
        
        if full_load or req.qty > stock then
        nic:send(dispatch, FLN_PORT, ser(
            {cmd = "train_request",
             stop = station.hash,
             length = station_len,
             item = req.item,
             qty = req.qty,
             pri = req.pri,
             stock = stock,
             capacity = capacity,
             full = full_load}))
        end
      end
    end
  end
  

end
