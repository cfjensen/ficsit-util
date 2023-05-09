Ficsit Logistics Network readme

General information:
 - FLN allows you to dynamically send trains from producers to consumers based on need.
 - FLN supports both fluids and solids.
 - Producer stations can only provide one type of item.
 - Trains can only carry one type of item.
 - Consumer stations requesting solids can request multiple types of items.  Fluid stations can only request one type of fluid.
 - FLN supports multiple train station lengths, however, trains will only be sent between stations of the same length.
 - You can send full or partial trains.

Before launching the game
 - Install ficsit networks (https://ficsit.app/mod/FicsItNetworks) 
 - Place the blueprints (.sbp and .sbpcfg in AppData/FactoryGame/Saved/Savegames/blueprints/<your_save_name>
 
Ficsit Networks Overview
 - Ficsit networks creates an in game buildable computer that can run lua code.  It can control buildings that are attached to it with network cable.
 - Network cable is a new item that functions similar to power cables.  It can be attached to individual devices, and multiple network cables can be joined at a network pole.
 - Computers require code to run.  Currently there's a bug with Ficsit networks where you can't blueprint code in a computer, so you will have to load it manually.
 - To load code, craft an EEPROM at the craft bench, then place it in the computer.  Copy-paste the code from a file into the computer, and hit the power button to run it.
 - Multiple computers can communicate with each other through a network router (similar to a power switch).  This allows a computer to control its local network (directly connected via network cables) while receiving data from other computers.
 
Example:
Train staion <-> computer <-> network router <-> computer <-> train station

The computer on the left controls the train station on the left, while the computer on the right controls the station on the right.

For short distances, you can connect network routers to other network routers with network cable.  For longer distances, you can use a wireless router, but it must be attached to a radar tower.



Setting up the dispatch server.

The dispatch server determines what trains go where.  There must be one and only one dispatcher on the network.

1. Place the FLN Dispatch blueprint
2. Craft an EEPROM and place it in the computer
3. Copy the code in "dispatch.lua" into the computer
4. Hit the power switch

Setting up producers

The network only knows about what items it can request based on what items are being produced.  At least one producer must be set up before a consumer will be able to request that item.

1.  Place the FLN Producer blueprint
2.  Craft an EEPROM and place it in the computer
3.  Copy the code in "prod.lua" into the computer
4.  Use network cable to attach the train station to the network cable junction at the base of the control panel
5.  (optionally) Use network cable to attach any relevant storage containers to the network cable junction at the base of the control panel.
6.  Use network cable to attach the router to the main network (either via a wireless network or connected cables)
7.  Hit the power switch

The station should auto-detect what item it is providing.  It can only provide one item, and will not allow you to enable the station unless there is one and only one type of item present.
8.  Select the minimum load for trains this station will send.  The default is to only send full trains.
9.  Enable the station with the lever.
10. Send at least one train to this station.  
  a. Set a train to have this station as its only stop
  b. Edit the stop settings and hit save.  You don't need to change anything.  IF YOU DON'T DO THIS THE GAME WILL CRASH (ficsit networks bug)
  c. Enable self driving
  

Setting up consumers

1. Place the FLN Consumer blueprint
2. Craft an EEPROM and place it in the computer
3. Copy the code in "cons.lua" into the computer.
4. Use network cable to attach the train station to the network cable junction at the base of the control panel
5. (optionally) Use network cable to attach any relevant storage containers to the network cable junction at the base of the control panel.
6. Use network cable to attach the router to the main network (either via a wireless network or connected cables)
7. Hit the power switch

The station should auto-detect what items the network is producing.  It can request multiple items, but only if the first item isn't set to "Full"
8. Set the requested items and quantities (you can set priority but it's not implemented yet)
9. Enable the station with the lever
