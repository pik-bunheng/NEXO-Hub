local source=[==========[local core=[========[-- NEXO: live-data quest farming. Starts OFF; direct attacks target quest NPC enemies only.
local Players=game:GetService('Players')
local TweenService=game:GetService('TweenService')
local Input=game:GetService('UserInputService')
local player=Players.LocalPlayer
local env=type(getgenv)=='function' and getgenv() or _G
local host=player:WaitForChild('PlayerGui')
-- Complete the native arrival sequence before requiring controllers or restoring jobs.
do
 local ticket={};env.NexoStartupTicket=ticket
 local arrival=env.NexoTeleportBoot==true
 local deadline=os.clock()+180;local stableSince;local warned=false
 local nextTeam=0
 local selectedTeam='Marines'
 pcall(function()
  local saved=game:GetService('HttpService'):JSONDecode(readfile('Nexo/settings-'..player.UserId..'.json'))
  if saved.autoLoadTeam=='Pirates' then selectedTeam='Pirates' end
 end)
 -- Use the native team button handlers; never synthesize mouse input or send SetTeam.
 env.NexoSelectTeamUI=function(team)
  if player.Team then return true end
  local main=host:FindFirstChild('Main') or host:FindFirstChild('Main (minimal)')
  local chooser=main and main:FindFirstChild('ChooseTeam')
  local container=chooser and chooser:FindFirstChild('Container');local card=container and container:FindFirstChild(team=='Pirates' and 'Pirates' or 'Marines')
  local frame=card and card:FindFirstChild('Frame');local button=frame and frame:FindFirstChildWhichIsA('GuiButton')
  local selection=host:FindFirstChild('TeamSelection')
  if selection and selection.Enabled then
   local root=selection:FindFirstChild('ROOT');local window=root and root:FindFirstChild('Frame')
   local content=window and window:FindFirstChild('content')
   local name=team=='Pirates' and 'pirate' or 'marine'
   local tile=content and content:FindFirstChild(name..'Frame')
   local current=tile and tile:FindFirstChild(name)
   if current and current:IsA('GuiButton') then button=current end
  end
  if not button then return false end
  local node=button
  while node and node~=host do
   if node:IsA('GuiObject') and not node.Visible then return false end
   if node:IsA('ScreenGui') and not node.Enabled then return false end
   node=node.Parent
  end
  if not button.Active or button.AbsoluteSize.X<=0 or button.AbsoluteSize.Y<=0 then return false end
  if type(getconnections)~='function' then return false end
  for _,name in ipairs({'Activated','MouseButton1Click','MouseButton1Down'}) do
   local ok,connections=pcall(getconnections,button[name])
   if ok then
    local handlers={}
    for _,connection in ipairs(connections) do
     if connection.Enabled~=false and type(connection.Function)=='function' then handlers[#handlers+1]=connection end
    end
    if #handlers>0 then
     for _,connection in ipairs(handlers) do
      task.spawn(function()
       local x=button.AbsolutePosition.X+button.AbsoluteSize.X/2
       local y=button.AbsolutePosition.Y+button.AbsoluteSize.Y/2
       local ok,err=pcall(connection.Function,x,y)
       if not ok then env.NexoTeamUIError=tostring(err) end
      end)
     end
     return true
    end
   end
  end
  return false
 end
 env.NexoStartupState='Waiting for native game loading'
 while env.NexoStartupTicket==ticket do
  local data=player:FindFirstChild('Data');local main=host:FindFirstChild('Main')
  local craft=host:FindFirstChild('Craft');local window=craft and craft:FindFirstChild('Window')
  local baseReady=game:IsLoaded() and player:GetAttribute('LoadComplete')==true
   and data and data:FindFirstChild('Level') and main
  local nativeReady=baseReady and window and window:FindFirstChild('Main')
  local ready=nativeReady
  if not player.Team and game:IsLoaded() and os.clock()>=nextTeam then
   env.NexoStartupState='Waiting for '..selectedTeam..' team button'
   if env.NexoSelectTeamUI(selectedTeam) then nextTeam=os.clock()+5 end
  end
  if arrival and baseReady then
   env.NexoStartupState='Waiting for character and NPCs'
   local char=player.Character;local h=char and char:FindFirstChildOfClass('Humanoid')
   local npcs=workspace:FindFirstChild('NPCs');local npcReady=false
   if npcs then for _,npc in ipairs(npcs:GetChildren()) do
    if npc:IsA('Model') and npc:FindFirstChildWhichIsA('BasePart',true) then npcReady=true;break end
   end end
   ready=nativeReady and player.Team and char and char:IsDescendantOf(workspace) and h and h.Health>0 and char:FindFirstChild('HumanoidRootPart') and npcReady
  end
  if ready then
   stableSince=stableSince or os.clock()
   if os.clock()-stableSince>=(arrival and 6 or 2) then env.NexoStartupState='Ready';break end
  else stableSince=nil end
  if not warned and os.clock()>deadline-165 then
   warned=true
   pcall(function()game:GetService('StarterGui'):SetCore('SendNotification',{Title='Nexo',Text='Waiting for game, character and NPC loading.',Duration=6})end)
  end
  if os.clock()>=deadline then
   env.NexoStartupState='Paused: game or NPC loading incomplete'
   warn('Nexo auto-load paused: native game loading did not complete; no jobs started.')
   return
  end
  task.wait(.25)
 end
 if env.NexoStartupTicket~=ticket then return end
end
local runId=game:GetService('HttpService'):GenerateGUID(false)
env.NexoReplacing=true
host:SetAttribute('NexoFarmRunId',runId)
if env.NexoFarmUI then pcall(env.NexoFarmUI.Destroy) end
for _,oldGui in ipairs(host:GetChildren()) do
 if oldGui.Name=='NexoFarmUI' then
  local shutdown=oldGui:FindFirstChild('NexoShutdown')
  if shutdown and shutdown:IsA('BindableEvent') then shutdown:Fire() else oldGui:Destroy() end
 end
end
env.NexoReplacing=false
game:GetService('RunService').Heartbeat:Wait()
if host:GetAttribute('NexoFarmRunId')~=runId then return end
for _,oldGui in ipairs(host:GetChildren()) do if oldGui.Name=='NexoFarmUI' then oldGui:Destroy() end end
local alive,busy,opened=true,false,false
local introRunning=true
local connections,tweens={},{}
local bindingSignals,bindingObjects,bindingHandlers={},{},{}
local bindingPicker
local capturePicker=false
local function connect(signal,fn)
 bindingSignals[signal]=bindingSignals[signal] or {};table.insert(bindingSignals[signal],fn)
 local c=signal:Connect(fn);table.insert(connections,c);return c
end
local function bindControl(node,event,fn)
 bindingHandlers[node]=bindingHandlers[node] or {}
 local events=bindingHandlers[node];events[event]=events[event] or {};table.insert(events[event],fn)
 return connect(node[event],fn)
end
local function make(class,parent,props)
 local o=Instance.new(class);for k,v in pairs(props) do o[k]=v end;o.Parent=parent
 if o:IsA('GuiObject') then
  local r={object=o,parent=parent,text=props.Text or '',x=o.Position.X.Offset,y=o.Position.Y.Offset,h=o.Size.Y.Offset}
  if o:IsA('GuiButton') or o:IsA('TextBox') then
   local left=math.huge
   for label,m in pairs(bindingObjects)do
    if label:IsA('TextLabel') and label.Parent==parent and label.Visible and m.text~='' and label.Position.X.Offset<r.x and math.abs(label.Position.Y.Offset+label.Size.Y.Offset/2-r.y-r.h/2)<14 then
     local x=label.Position.X.Offset
     if x<left or (x==left and (m.seq or 0)>(r.titleSeq or 0)) then left=x;r.title=m.text;r.titleSeq=m.seq end
    end
   end
  end
  bindingSignals.sequence=(bindingSignals.sequence or 0)+1;r.seq=bindingSignals.sequence;bindingObjects[o]=r
 end
 return o
end
local brass=Color3.fromRGB(155,50,255)
local pale=Color3.fromRGB(242,241,246)
local gui=make('ScreenGui',player:WaitForChild('PlayerGui'),{Name='NexoFarmUI',Enabled=false,ResetOnSpawn=false,DisplayOrder=5100,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local root=make('Frame',gui,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(80,220),Size=UDim2.fromOffset(770,620),BackgroundTransparency=1})
root.Visible=false
local scale=make('UIScale',root,{Scale=1})
local menuHeight=520
local mobileLayout
local function fit()
 local v=gui.AbsoluteSize
 scale.Scale=math.max(.1,math.min(v.X/1280,v.Y/720));menuHeight=460
end
connect(gui:GetPropertyChangedSignal('AbsoluteSize'),fit);fit()
local carrier=make('Frame',root,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ZIndex=5})
local logoScale=make('UIScale',carrier,{Scale=1})
carrier.AnchorPoint=Vector2.new(.5,.5);carrier.Position=UDim2.fromScale(.5,.5)
local function half(upper)
 local b=make('TextButton',carrier,{Name=upper and 'LogoTop' or 'LogoBottom',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.5,0,.5,upper and -20 or 20),Size=UDim2.fromOffset(80,40),BackgroundTransparency=1,Text='',ClipsDescendants=true,AutoButtonColor=false,ZIndex=5})
 make('ImageLabel',b,{BackgroundTransparency=1,Size=UDim2.fromOffset(80,80),Position=UDim2.fromOffset(0,upper and 0 or -40),Image='rbxassetid://140686261014577',ZIndex=5})
 return b
end
local top,bottom=half(true),half(false)
local dock=make('TextButton',root,{Name='LogoButton',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(86,86),BackgroundTransparency=1,Text='',ZIndex=6})
local menu=make('CanvasGroup',root,{Name='Menu',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(740,0),BackgroundColor3=Color3.fromRGB(20,22,24),BackgroundTransparency=.35,ClipsDescendants=true,Visible=false,ZIndex=2})
make('UICorner',menu,{CornerRadius=UDim.new(0,14)})
make('UIStroke',menu,{Color=brass,Thickness=1,Transparency=.25})
local content=make('Frame',menu,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(740,520),BackgroundTransparency=1,ZIndex=3})
local shading=make('Frame',menu,{Name='BackgroundShading',Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=.45,BorderSizePixel=0,ZIndex=2})
make('UICorner',shading,{CornerRadius=UDim.new(0,14)})
make('UIGradient',shading,{Color=ColorSequence.new(Color3.fromRGB(33,35,37),Color3.fromRGB(18,20,23)),Rotation=90})
local function label(parent,value,x,y,w,h,size,color)
 return make('TextLabel',parent,{Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,ZIndex=4,TextColor3=color or pale,TextSize=size,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left})
end
local title=label(content,'NEXO',220,16,300,36,25);title.Font=Enum.Font.GothamBold;title.TextXAlignment=Enum.TextXAlignment.Center
-- Farming and Player tabs.
local header=make('TextButton',content,{Position=UDim2.fromOffset(0,0),Size=UDim2.fromOffset(740,54),BackgroundTransparency=1,Text='',AutoButtonColor=false})
make('Frame',content,{Position=UDim2.fromOffset(28,60),Size=UDim2.fromOffset(684,1),BackgroundColor3=brass,BackgroundTransparency=.65,BorderSizePixel=0})
-- Small mechanical fasteners, keeping the decoration restrained.
for _,p in ipairs({{12,12},{722,12},{12,502},{722,502}}) do
 local rivet=make('Frame',content,{Position=UDim2.fromOffset(p[1],p[2]),Size=UDim2.fromOffset(6,6),BackgroundColor3=brass,BorderSizePixel=0})
 make('UICorner',rivet,{CornerRadius=UDim.new(1,0)})
end
local card=make('ScrollingFrame',content,{CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollingDirection=Enum.ScrollingDirection.Y,Position=UDim2.fromOffset(202,106),Size=UDim2.fromOffset(514,126),BackgroundColor3=Color3.fromRGB(29,31,33),BackgroundTransparency=.3,BorderSizePixel=0,ZIndex=3})
make('UICorner',card,{CornerRadius=UDim.new(0,10)})
make('UIStroke',card,{Color=brass,Transparency=.82,Thickness=1})
label(card,'Farm Level',22,24,310,30,16,Color3.fromRGB(250,247,239))
local state=label(card,'Ready',22,61,465,44,13,Color3.fromRGB(224,226,225))
state.TextWrapped=true;state.TextYAlignment=Enum.TextYAlignment.Top;state.Visible=false
local toggle=make('TextButton',card,{Name='FarmLevel',Position=UDim2.fromOffset(410,26),Size=UDim2.fromOffset(80,30),Text='OFF',TextSize=12,Font=Enum.Font.GothamBold,TextColor3=Color3.fromRGB(245,237,221),BackgroundColor3=Color3.fromRGB(65,58,46),BorderSizePixel=0,AutoButtonColor=false,ZIndex=4})
make('UICorner',toggle,{CornerRadius=UDim.new(0,8)})
-- Uses live quest definitions and the current sea's NPC registry.
local function createFarm(onStatus)
 local RS=game:GetService('ReplicatedStorage')
 local RunService=game:GetService('RunService')
 local farm={enabled=false,seaActive=false,stackEvents={elite=false,factory=false,raid=false,ripindra=false,darkbeard=false,doughking=false,reaper=false},generation=0,message='Ready',completed=0,events={},bringMobs=true,mobLimit=2,gathered=0,maxGathered=0,weapon="Melee",tweenSpeed=200,autoClick=false,stackFruit=false,stackMessage="Off",recoveries=0,mode="level",material="Angel Wings",materialKills=0}
 farm.skillUse={}
 for _,kind in ipairs({'Fruit','Sword','Gun','Melee'}) do
  farm.skillUse[kind]={Z=true,X=true,C=true,V=true,F=true}
 end
 local function fishingTool(tool)
  if not tool or not tool:IsA('Tool') then return false end
  local kind=tool:GetAttribute('WeaponType') or tool.ToolTip
  return tool:FindFirstChild('FishingRodData')~=nil or kind=='Fishing Rod' or kind=='FishingRod' or tool.Name:lower():find('fishing rod',1,true)~=nil
 end
 function farm.SkillCategory(tool)
  if fishingTool(tool) then return end
  local kind=tool.ToolTip
  if kind=='' then kind=tool:GetAttribute('WeaponType') end
  if kind=='Demon Fruit' or kind=='Blox Fruit' then return 'Fruit' end
  if farm.skillUse[kind] then return kind end
 end
 function farm.SkillAllowed(tool,key)
  local kind=farm.SkillCategory(tool)
  return kind and farm.skillUse[kind][key]==true or false
 end
 function farm.SkillQueue(tools)
  table.sort(tools,function(a,b) return a.Name<b.Name end)
  local queue={}
  for _,tool in ipairs(tools) do
   for _,key in ipairs({'Z','X','C','V','F'}) do
    if farm.SkillAllowed(tool,key) then table.insert(queue,{tool=tool,key=Enum.KeyCode[key]}) end
   end
  end
  return queue
 end
 local questDefs,guide,guideData,combatUtil,attackRemote,sendHits
 local activeTween,flight,attachment,collisionConnection,travelRotation,travelHumanoid,travelAutoRotate
 local collisionSaved={}
 local stopHover=function() end
 local hoverHeight=24
 local hoverSide=2
 local stopStabilize=function() end
 local lastSpawns={}
 local avoided=setmetatable({},{__mode="k"})
 local scanFruit,collectFruit,scanStackEvent
 local currentMode="idle"
 local function status(message)
  farm.message=message
  if farm.events[#farm.events]~=message then
   table.insert(farm.events,message);if #farm.events>30 then table.remove(farm.events,1) end
  end
  onStatus(message,farm.enabled)
 end
 local function body()
  local char=player.Character
  local h=char and char:FindFirstChildOfClass('Humanoid')
  local rootPart=char and char:FindFirstChild('HumanoidRootPart')
  if h and h.Health>0 and rootPart then return char,h,rootPart end
 end
 local function stopNoclip()
  if collisionConnection then collisionConnection:Disconnect();collisionConnection=nil end
  for part,value in pairs(collisionSaved) do pcall(function() if part.Parent then part.CanCollide=value end end) end
  collisionSaved={}
 end
 local function startNoclip(char)
  stopNoclip()
  local parts={};local scanAt=0
  local function apply()
   if not char.Parent or player.Character~=char then stopNoclip();return end
   local now=os.clock()
   if now>=scanAt then
    scanAt=now+.5
    local current={};parts={}
    for _,part in ipairs(char:GetDescendants()) do
     if part:IsA('BasePart') then
      current[part]=true;parts[#parts+1]=part
      if collisionSaved[part]==nil then collisionSaved[part]=part.CanCollide end
     end
    end
    for part,value in pairs(collisionSaved) do
     if not current[part] then
      pcall(function() if part.Parent then part.CanCollide=value end end)
      collisionSaved[part]=nil
     end
    end
   end
   for _,part in ipairs(parts) do if part.Parent and part.CanCollide then part.CanCollide=false end end
  end
  apply();collisionConnection=RunService.PreSimulation:Connect(apply)
 end
 local function releaseMovement()
  if activeTween then activeTween:Cancel();activeTween=nil end
  if flight then flight:Destroy();flight=nil end
  if travelRotation then travelRotation:Destroy();travelRotation=nil end
  if travelHumanoid then pcall(function() travelHumanoid.AutoRotate=travelAutoRotate end);travelHumanoid=nil end
  if attachment then attachment:Destroy();attachment=nil end
  stopNoclip()
 end
 local function anyStackEvent() return farm.stackEvents.elite or farm.stackEvents.factory or farm.stackEvents.raid or farm.stackEvents.ripindra or farm.stackEvents.darkbeard or farm.stackEvents.doughking or farm.stackEvents.reaper end
 local function running(token) return alive and (farm.enabled or farm.stackFruit or farm.seaActive or anyStackEvent()) and farm.generation==token end
 local function pause(token,seconds)
  local untilTime=os.clock()+seconds
  repeat task.wait(.02) until not running(token) or os.clock()>=untilTime
  return running(token)
 end
 local cannonRequestAt=0;local cannonPending=false
 local function skyCannonFallback(tools,token,forceCannon)
  local alternatives={}
  for _,tool in ipairs(tools) do
   if tool.Name=='Cannon' then return tool,true end
   if tool.Name~='Combat' then table.insert(alternatives,tool) end
  end
  if not forceCannon and #farm.SkillQueue(alternatives)>0 then return nil,false end
  if cannonPending or os.clock()<cannonRequestAt then status('Waiting for Cannon availability');return nil,true end
  cannonRequestAt=os.clock()+30;cannonPending=true
  local finished=false;local result
  local function cannonTool()
   for _,container in pairs({player.Character,player:FindFirstChild('Backpack')}) do
    local tool=container:FindFirstChild('Cannon');if tool and tool:IsA('Tool') then return tool end
   end
  end
  task.spawn(function()
   local ok,err=pcall(function()
    -- Loading first avoids buying again when the gun is already in inventory.
    RS.Remotes.CommF_:InvokeServer('LoadItem','Cannon')
    local deadline=os.clock()+1
    repeat task.wait(.1) until cannonTool() or not running(token) or os.clock()>deadline
    if not running(token) or cannonTool() then return end
    result=RS.Remotes.CommF_:InvokeServer('BuyItem','Cannon')
    if not running(token) then return end
    if result==1 or result==2 then RS.Remotes.CommF_:InvokeServer('LoadItem','Cannon') end
   end)
   if not ok then result=tostring(err) end
   cannonPending=false;finished=true
  end)
  status('Preparing Cannon for Sky cloud')
  local deadline=os.clock()+8
  while running(token) and not cannonTool() and (not finished or result==1 or result==2) and os.clock()<deadline do task.wait(.1) end
  if not running(token) then return nil,true end
  local tool=cannonTool()
  if not tool then status(result==0 and 'Not enough money for Cannon' or result==3 and 'Cannon purchase level requirement not met' or 'Cannon not available yet; will retry') end
  return tool,true
 end
 local entranceBusy=false;local entranceAt=0
 local skyDirectRetryAt=0
 local skySkillToken;local skySkillAttempts=0;local skyRetryAt=0
 local function entranceRoute(fromPosition,destination)
  local map=workspace:FindFirstChild('Map');if not map then return nil end
  local routes={}
  if game.PlaceId==7449423635 or game.PlaceId==100117331123089 then
   local dock=Vector3.new(11520.8,-2154.99,9829.51)
   if destination.Y < -1000 and (destination-dock).Magnitude<6000 and fromPosition.Y > -1000 then
    return {name='Submerged Island',entry=Vector3.new(-16269.408,26,1376.662),exit=dock,submarine=true}
   end
  end
  local function add(name,source,target)
   if source and target and source:IsA('BasePart') and target:IsA('BasePart') then
    table.insert(routes,{name=name,entry=source.Position,exit=target.Position})
   end
  end
  local water=map:FindFirstChild('TeleportSpawn')
  if water then
   add('Underwater City',water:FindFirstChild('Entrance'),water:FindFirstChild('EntrancePoint'))
   add('Underwater exit',water:FindFirstChild('Exit'),water:FindFirstChild('ExitPoint'))
  end
  local sky=map:FindFirstChild('Sky');local upper=map:FindFirstChild('SkyArea2')
  if sky and upper then
   add('Upper Skylands',sky:FindFirstChild('Entrance'),upper:FindFirstChild('EntrancePoint'))
   add('Skylands exit',upper:FindFirstChild('Exit'),sky:FindFirstChild('ExitPoint'))
  end
  if (game.PlaceId==4442272183 or game.PlaceId==79091703265657) then
   local ship=map:FindFirstChild('GhostShip');local interior=map:FindFirstChild('GhostShipInterior')
   if ship and interior then
    add('Cursed Ship',ship:FindFirstChild('Teleport'),interior:FindFirstChild('TeleportSpawn'))
    add('Cursed Ship exit',interior:FindFirstChild('Teleport'),ship:FindFirstChild('TeleportSpawn'))
   end
   local hasEntry,hasExit=false,false
   for _,route in ipairs(routes) do hasEntry=hasEntry or route.name=='Cursed Ship';hasExit=hasExit or route.name=='Cursed Ship exit' end
   if not hasEntry then table.insert(routes,{name='Cursed Ship',entry=Vector3.new(-6496.898,89.035,-116.509),exit=Vector3.new(923.213,126.976,32852.832)}) end
   if not hasExit then table.insert(routes,{name='Cursed Ship exit',entry=Vector3.new(920.478,154.901,32838.965),exit=Vector3.new(-6508.558,89.035,-132.84)}) end
   -- The interior is a separate distant area, not an island to fly directly to.
   for _,route in ipairs(routes) do
    if route.name=='Cursed Ship' and destination.Z>20000 and fromPosition.Z<20000 then return route end
    if route.name=='Cursed Ship exit' and fromPosition.Z>20000 and destination.Z<20000 then return route end
   end
   if destination.Z>20000 and fromPosition.Z<20000 and not ship then
    return {name='Cursed Ship entrance loading',entry=Vector3.new(-6497,94,-117),staging=true}
   elseif fromPosition.Z>20000 and destination.Z<20000 and not interior then
    return {name='Cursed Ship exit loading',entry=Vector3.new(920,155,32839),staging=true}
   end
  end
  -- Crossing Sky regions must use their gate, even if direct flight looks shorter.
  for _,route in ipairs(routes) do
   if route.name=='Upper Skylands' and destination.Y>4000 and fromPosition.Y<4000 then return route end
   if route.name=='Skylands exit' and fromPosition.Y>4000 and destination.Y<4000 then return route end
  end
  local best;local bestCost=(destination-fromPosition).Magnitude-500
  for _,route in ipairs(routes) do
   local cost=(route.entry-fromPosition).Magnitude+(route.exit-destination).Magnitude+80
   if cost<bestCost and (route.exit-fromPosition).Magnitude>200 then best=route;bestCost=cost end
  end
  if best then return best end
  -- Sky geometry loads only when approaching the island. Stage nearby first.
  if water and (not sky or not upper) then
   local goingUp=destination.Y>4000 and fromPosition.Y<4000
   local goingDown=fromPosition.Y>4000 and destination.Y<4000
   if goingUp or goingDown then
    local ok,definition=pcall(function()
     local sea=RS.Definitions.Map.DEFINITIONS.LIBRARY.Sea1
     return require(goingUp and sea.Sky or sea.SkyArea2)
    end)
    local point=ok and definition.World and definition.World.Position
    if typeof(point)=='Vector3' then
     return {name='Skylands entrance loading',entry=point+Vector3.new(0,100,0),staging=true}
    end
   end
  end
  return nil
 end
 local moveTo
 local function jumpOutOfSeat(h)
  if h and h.Health>0 and (h.Sit or h.SeatPart) then
   h.Sit=false;h.Jump=true
   h:ChangeState(Enum.HumanoidStateType.Jumping)
   return true
  end
  return false
 end
 moveTo=function(position,token,skipEntrance,retryCount,keepMoving)
  local char,h,hr=body();if not hr or not running(token) then return false end
  stopHover();stopStabilize();releaseMovement()
  if jumpOutOfSeat(h) then
   if not pause(token,.2) then return false end
  end
  if not skipEntrance then
   local route=entranceRoute(hr.Position,position)
   if route then
    if route.submarine then
     if entranceBusy or os.clock()<entranceAt then pause(token,.5);return false end
     status('Travelling to Tiki submarine')
     if not moveTo(route.entry,token,true) then return false end
     if not running(token) then return false end
     entranceBusy=true;entranceAt=os.clock()+10
     local completed=false;local accepted=false
     task.spawn(function()
      local controller
      local ok=pcall(function()
       controller=require(RS.Controllers.MapServices.SubmergedIslandController)
       controller:LockState();controller:LoadMap();task.wait(.5)
       if running(token) then
        accepted=RS.Modules.Net:FindFirstChild('RF/SubmarineWorkerSpeak'):InvokeServer('TravelToSubmergedIsland')==true
       end
      end)
      if controller then pcall(function() controller:UnlockState() end) end
      accepted=ok and accepted;completed=true;entranceBusy=false
     end)
     local deadline=os.clock()+12
     while running(token) and not completed and os.clock()<deadline do task.wait(.1) end
     if not running(token) then return false end
     if not completed or not accepted then status('Submarine trip not accepted; waiting to retry');return false end
     if not pause(token,.5) then return false end
     local _,_,root=body()
     if not root or (root.Position-route.exit).Magnitude>1500 or root.Position.Y > -1000 then
      status('Waiting for Submerged Island arrival');return false
     end
     return moveTo(position,token,false)
    end
    if route.staging then
     status('Approaching Skylands entrance')
     if moveTo(route.entry,token,true) then status('Waiting for sky entrance to load');pause(token,1) end
     return false
    end
    if entranceBusy or os.clock()<entranceAt then status('Waiting for entrance');pause(token,.5);return false end
    status('Travelling via '..route.name)
    local function requestEntrance()
     if not running(token) or entranceBusy then return false end
     entranceBusy=true;entranceAt=os.clock()+8
     local finished=false
     task.spawn(function()
      local ok,result=pcall(function() return RS.Remotes.CommF_:InvokeServer('requestEntrance',route.exit) end)
      if ok and typeof(result)=='Vector3' and running(token) and player.Character==char and hr.Parent then
       hr.CFrame=CFrame.new(result)
      end
      entranceBusy=false;finished=true
     end)
     local deadline=os.clock()+8
     while running(token) and not finished and os.clock()<deadline do task.wait(.1) end
     if not running(token) or not finished then return false end
     pause(token,.35)
     return player.Character==char and hr.Parent and (hr.Position-route.exit).Magnitude<180
    end
    -- Use the physical portal; a remote request alone is not proof of arrival.
    local arrived=(hr.Position-route.exit).Magnitude<180
    if not arrived and route.name=='Upper Skylands' and os.clock()>=skyDirectRetryAt then
     skyDirectRetryAt=os.clock()+60
     status('Trying direct Upper Sky entrance')
     arrived=requestEntrance()
     if not running(token) then return false end
     if not arrived and not entranceBusy then
      entranceAt=0
      status('Direct entrance unavailable; using cloud entrance')
     end
    end
    if not arrived then
     if not running(token) or entranceBusy then return false end
     status('Approaching '..route.name..' entrance')
     if route.name=='Upper Skylands' then
      if skySkillToken~=token then skySkillToken=token;skySkillAttempts=0;skyRetryAt=0 end
      if os.clock()<skyRetryAt then status('Waiting to retry Sky cloud skills');pause(token,.5);return false end
      if not moveTo(route.entry+Vector3.new(0,10,12),token,true) then return false end
      local tools={}
      local function usable(t)
       if not t:IsA('Tool') or fishingTool(t) then return false end
       local kind=t:GetAttribute('WeaponType') or t.ToolTip
       return kind=='Melee' or kind=='Sword' or kind=='Blox Fruit' or kind=='Demon Fruit' or kind=='Gun'
      end
      for _,container in pairs({char,player:FindFirstChild('Backpack')}) do
       for _,candidate in ipairs(container:GetChildren()) do if usable(candidate) then table.insert(tools,candidate) end end
      end
      table.sort(tools,function(a,b) return a.Name<b.Name end)
      local cannon,useCannon=skyCannonFallback(tools,token)
      if not running(token) then return false end
      if useCannon and not cannon then pause(token,1);return false end
      local queue=farm.SkillQueue(tools)
      if not useCannon and #queue==0 then status('Enable a skill in Settings > Skill Use');pause(token,1);return false end
      local entry=not useCannon and queue[skySkillAttempts%#queue+1]
      local tool=useCannon and cannon or entry.tool;local skillKey=entry and entry.key
      if tool.Parent~=char then h:EquipTool(tool);if not pause(token,.2) then return false end end
      if player.Character~=char or not running(token) then return false end
      skySkillAttempts=skySkillAttempts+1
      if not useCannon and skySkillAttempts%#queue==0 then skyRetryAt=os.clock()+2 end
      status('Opening Sky cloud: '..tool.Name..' '..(useCannon and 'M1' or skillKey.Name))
      local camera=workspace.CurrentCamera;local savedCamera=camera.CFrame
      local savedType=camera.CameraType;local savedFocus=camera.Focus
      local aimPoint=route.entry-Vector3.new(0,2,0)
      local mousePosition=tool:FindFirstChild('MousePos')
      local savedMouse=mousePosition and mousePosition:IsA('Vector3Value') and mousePosition.Value
      local input=game:GetService('VirtualInputManager')
      local function sendInput(method,...)
       local setIdentity=setthreadidentity or setidentity
       local getIdentity=getthreadidentity or getidentity
       local previous=getIdentity and getIdentity() or 2
       if setIdentity then setIdentity(8) end
       local ok,err=pcall(input[method],input,...)
       if setIdentity then setIdentity(previous) end
       if not ok then error(tostring(err),0) end
      end
      local function aimDown()
       if not camera.Parent or not hr.Parent then return end
       camera.CameraType=Enum.CameraType.Scriptable
       camera.CFrame=CFrame.lookAt(hr.Position+Vector3.new(0,12,8),aimPoint)
       camera.Focus=CFrame.new(aimPoint)
       if savedMouse then mousePosition.Value=aimPoint end
       local projected=camera:WorldToViewportPoint(aimPoint)
       local inset=game:GetService('GuiService'):GetGuiInset()
       sendInput('SendMouseMoveEvent',projected.X+inset.X,projected.Y+inset.Y,game)
      end
      local aimConnection=RunService.RenderStepped:Connect(function() pcall(aimDown) end)
      local pressed,inputError=pcall(function()
       if not useCannon and not farm.SkillAllowed(tool,skillKey.Name) then return end
       aimDown()
       if useCannon then
        local p=camera:WorldToViewportPoint(aimPoint);local inset=game:GetService('GuiService'):GetGuiInset()
        sendInput('SendMouseButtonEvent',p.X+inset.X,p.Y+inset.Y,0,true,game,0)
       else sendInput('SendKeyEvent',true,skillKey,false,game) end
       pause(token,useCannon and .12 or .35)
      end)
      pcall(function()
       if useCannon then
        local p=camera:WorldToViewportPoint(aimPoint);local inset=game:GetService('GuiService'):GetGuiInset()
        sendInput('SendMouseButtonEvent',p.X+inset.X,p.Y+inset.Y,0,false,game,0)
       else sendInput('SendKeyEvent',false,skillKey,false,game) end
      end)
      if running(token) then pause(token,useCannon and .9 or .2) end
      aimConnection:Disconnect()
      pcall(function() camera.CameraType=savedType;camera.CFrame=savedCamera;camera.Focus=savedFocus;if savedMouse then mousePosition.Value=savedMouse end end)
      if not pressed then status('Cloud input failed: '..tostring(inputError));return false end
      if not running(token) then return false end
      if player.Character~=char or not hr.Parent then return false end
      if (hr.Position-route.exit).Magnitude<180 then
       skySkillAttempts=0;skyRetryAt=0
       return moveTo(position,token,false)
      end
     end
     if not moveTo(route.entry+Vector3.new(0,5,0),token,true) then
      -- Touching the physical entrance can teleport during movement.
      if not running(token) or player.Character~=char or not hr.Parent or (hr.Position-route.exit).Magnitude>=180 then return false end
     end
     arrived=(hr.Position-route.exit).Magnitude<180
     if not arrived then
      while running(token) and os.clock()<entranceAt do task.wait(.1) end
      -- Cloud skills should not wait for a remote entrance request after each cast.
      if route.name~='Upper Skylands' then arrived=requestEntrance() end
     end
    end
    if not arrived then status('Entrance not confirmed; retrying');return false end
    if not pause(token,.35) then return false end
    return moveTo(position,token,false)
   end
  end
  local distance=(hr.Position-position).Magnitude
  if distance<2 then return true end
  attachment=Instance.new('Attachment');attachment.Name='NexoTravel';attachment.Parent=hr
  travelHumanoid=h;travelAutoRotate=h.AutoRotate;h.AutoRotate=false
  flight=Instance.new('AlignPosition');flight.Name='NexoTravelHold';flight.Attachment0=attachment
  flight.Mode=Enum.PositionAlignmentMode.OneAttachment;flight.ApplyAtCenterOfMass=true
  flight.MaxForce=1000000;flight.MaxVelocity=farm.tweenSpeed;flight.Responsiveness=35
  flight.Position=hr.Position;flight.Parent=hr
  travelRotation=Instance.new('AlignOrientation');travelRotation.Name='NexoTravelFacing';travelRotation.Attachment0=attachment
  travelRotation.Mode=Enum.OrientationAlignmentMode.OneAttachment;travelRotation.MaxTorque=1000000;travelRotation.Responsiveness=30
  travelRotation.CFrame=hr.CFrame.Rotation;travelRotation.Parent=hr
  startNoclip(char)
  local duration=math.max(.15,distance/farm.tweenSpeed)
  activeTween=TweenService:Create(flight,TweenInfo.new(duration,Enum.EasingStyle.Linear),{Position=position})
  local movement=activeTween;movement:Play()
  local deadline=os.clock()+duration+3
  local lastTravelPosition=hr.Position
  local bestDistance=distance;local progressAt=os.clock();local stalled=false
  local seatJumpAt=0
  while running(token) and (not keepMoving or keepMoving()) and hr.Parent and h.Health>0 and os.clock()<deadline and (movement.PlaybackState==Enum.PlaybackState.Playing or (hr.Position-position).Magnitude>3) do
   if os.clock()>=seatJumpAt and jumpOutOfSeat(h) then
    seatJumpAt=os.clock()+.5;progressAt=os.clock()
   end
   if (hr.Position-lastTravelPosition).Magnitude>180 then movement:Cancel();break end
   lastTravelPosition=hr.Position
   local remaining=(hr.Position-position).Magnitude
   if remaining<bestDistance-1 then bestDistance=remaining;progressAt=os.clock() end
   if remaining>10 and os.clock()-progressAt>2 then stalled=true;movement:Cancel();break end
   if not farm.priorityOnly and currentMode~="fruit" and farm.stackFruit and scanFruit and scanFruit() then break end
   task.wait(.08)
  end
  local arrived=running(token) and (not keepMoving or keepMoving()) and hr.Parent and h.Health>0 and (hr.Position-position).Magnitude<10
  if activeTween==movement then releaseMovement() end
  if stalled and running(token) and (not keepMoving or keepMoving()) and (retryCount or 0)<2 then
   farm.movementRecoveries=(farm.movementRecoveries or 0)+1
   status('Repositioning around obstacle')
   if pause(token,.2) then return moveTo(position,token,skipEntrance,(retryCount or 0)+1,keepMoving) end
  end
  return arrived
 end
 local function startHover(enemyRoot,steady,followBoss)
  steady=true
  stopHover();stopStabilize()
  local char,h,hr=body();if not hr then return false end
  startNoclip(char);farm.hoverStuck=false
  local savedRotation=h.AutoRotate;h.AutoRotate=false
  local att=Instance.new('Attachment');att.Name='NexoHover';att.Parent=hr
  local position=Instance.new('AlignPosition');position.Name='NexoHoverPosition'
  position.Mode=Enum.PositionAlignmentMode.OneAttachment;position.Attachment0=att
  position.MaxForce=1000000;position.MaxVelocity=160;position.Responsiveness=45;position.ApplyAtCenterOfMass=true
  position.Position=enemyRoot.Position+Vector3.new(0,hoverHeight,hoverSide);position.Parent=hr
  local rotation=Instance.new('AlignOrientation');rotation.Name='NexoHoverFacing'
  rotation.Mode=Enum.OrientationAlignmentMode.OneAttachment;rotation.Attachment0=att
  rotation.MaxTorque=1000000;rotation.Responsiveness=35
  local direction=hr.CFrame.LookVector*Vector3.new(1,0,1)
  if direction.Magnitude<.01 then direction=Vector3.new(0,0,-1) end
  local fixedFacing=CFrame.lookAt(Vector3.zero,direction.Unit)
  local function facing()
   local aim=type(enemyRoot)=='table' and rawget(enemyRoot,'nexoAim')
   if aim then local delta=(aim-hr.Position)*Vector3.new(1,0,1);if delta.Magnitude>.01 then return CFrame.lookAt(Vector3.zero,delta.Unit) end end
   return fixedFacing
  end
  rotation.CFrame=steady and facing() or CFrame.lookAt(hr.Position,enemyRoot.Position);rotation.Parent=hr
  local lastHoverPosition=hr.Position;local hoverProgressAt=os.clock()
  local step=RunService.PreSimulation:Connect(function(dt)
   if hr.Parent and enemyRoot.Parent and player.Character==char then
    local wanted=enemyRoot.Position+Vector3.new(0,hoverHeight,hoverSide)
    if followBoss then
     local lead=enemyRoot.AssemblyLinearVelocity*.08
     if lead.Magnitude>6 then lead=lead.Unit*6 end
     wanted=wanted+lead
    end
    position.Position=position.Position:Lerp(wanted,1-math.exp(-(followBoss and 24 or 12)*dt))
    rotation.CFrame=steady and facing() or CFrame.lookAt(hr.Position,enemyRoot.Position)
    if steady then hr.AssemblyAngularVelocity=Vector3.zero end
    if (hr.Position-lastHoverPosition).Magnitude>.5 or (hr.Position-position.Position).Magnitude<12 then
     lastHoverPosition=hr.Position;hoverProgressAt=os.clock()
    elseif os.clock()-hoverProgressAt>2 then farm.hoverStuck=true end
   end
  end)
  local stopped=false
  stopHover=function()
   if stopped then return end;stopped=true;step:Disconnect();stopNoclip();farm.hoverStuck=false
   position:Destroy();rotation:Destroy();att:Destroy()
   pcall(function() h.AutoRotate=savedRotation end)
  end
  return true
 end
 local function quest()
  local data=guideData and guideData.Data
  return data and type(data.QuestData)=='table' and data.QuestData or nil
 end
 local function canonical(name)
  return tostring(name):gsub('%s*%[.-%]',''):lower():gsub('^%s+',''):gsub('%s+$','')
 end
 local materials={
  {name="Angel Wings",enemies={"God's Guard","Shanda","Royal Squad","Royal Soldier"}},
  {name="Leather",enemies={"Pirate","Brute","Mercenary","Marine Captain","Forest Pirate"}},
  {name="Magma Ore",enemies={"Military Soldier","Military Spy","Magma Ninja","Lava Pirate"}},
  {name="Scrap Metal",enemies={"Pirate","Brute","Mercenary","Swan Pirate","Jungle Pirate"}},
  {name="Yeti Fur",enemies={"Yeti"}},
  {name="Bones",enemies={"Reborn Skeleton","Living Zombie","Demonic Soul","Posessed Mummy","Possessed Mummy"}},
  {name="Ectoplasm",enemies={"Ship Deckhand","Ship Engineer","Ship Steward","Ship Officer"}},
  {name="Fish Tail",enemies={"Fishman Warrior","Fishman Commando","Fishman Raider","Fishman Captain"}},
  {name="Gunpowder",enemies={"Pistol Billionaire"}},
  {name="Mini Tusk",enemies={"Mythological Pirate"}},
  {name="Mystic Droplet",enemies={"Sea Soldier","Water Fighter"}},
  {name="Radioactive Material",enemies={"Factory Staff"}},
  {name="Vampire Fang",enemies={"Vampire"}},
  {name="Conjured Cocoa",enemies={"Cocoa Warrior","Chocolate Bar Battler"}},
  {name="Demonic Wisp",enemies={"Demonic Soul"}},
  {name="Dragon Scale",enemies={"Dragon Crew Warrior","Dragon Crew Archer"}},
 }
 farm.Materials=materials
 local function materialTarget()
  local _,_,hr=body();if not hr then return nil end
  local selected
  for _,entry in ipairs(materials) do if entry.name==farm.material then selected=entry end end
  if not selected then return nil end
  local allowed={};for _,name in ipairs(selected.enemies) do allowed[canonical(name)]=true end
  local best,score
  local function candidate(name,position,live)
   if not allowed[canonical(name)] then return end
   local distance=(position-hr.Position).Magnitude+(live and 0 or 100000)
   if not score or distance<score then best={enemy=name,material=farm.material,position=position,amount=0};score=distance end
  end
  local enemies=workspace:FindFirstChild('Enemies')
  if enemies then for _,enemy in ipairs(enemies:GetChildren()) do
   local h=enemy:FindFirstChildOfClass('Humanoid');local r=enemy:FindFirstChild('HumanoidRootPart')
   if h and h.Health>0 and r and (avoided[enemy] or 0)<os.clock() then candidate(enemy.Name,r.Position,true) end
  end end
  local origin=workspace:FindFirstChild('_WorldOrigin');local spawns=origin and origin:FindFirstChild('EnemySpawns')
  if spawns then for _,spawn in ipairs(spawns:GetChildren()) do if spawn:IsA('BasePart') then candidate(spawn.Name,spawn.Position,false) end end end
  return best
 end
 local function questNPCs()
  local entries={}
  for _,npc in pairs(guide.Data.NPCList or {})do entries[#entries+1]=npc end
  if #entries>0 then return entries end
  -- Some clients relocate NPC models into ReplicatedStorage, leaving Guide empty.
  local registry={
   ["Cupid Valentine Quest Giver"]="Cupid_ValentineDailyQuests",
   ["Pirate Adventurer"]="BuggyQuest1",
   ["Bandit Quest Giver"]="BanditQuest1",
   ["Adventurer"]="JungleQuest",
   ["Desert Adventurer"]="DesertQuest",
   ["Villager"]="SnowQuest",
   ["Marine Leader"]="MarineQuest",
   ["Sky Adventurer"]="SkyQuest",
   ["Marine"]="MarineQuest2",
   ["Colosseum Quest Giver"]="ColosseumQuest",
   ["Jail Keeper"]="PrisonerQuest",
   ["Head Jailer"]="ImpelQuest",
   ["The Mayor"]="MagmaQuest",
   ["King Neptune"]="FishmanQuest",
   ["Mole"]="SkyExp1Quest",
   ["Sky Quest Giver 2"]="SkyExp2Quest",
   ["Freezeburg Quest Giver"]="FountainQuest",
   ["Bartilo"]="Bartilo",
   ["Citizen"]="Citizen",
   ["Horned Man"]="HornedMan",
   ["Arena Trainer"]="ArenaTrainer",
   ["Valentines Delivery"]="StartValentinesDelivery",
   ["Area 1 Quest Giver"]="Area1Quest",
   ["Area 2 Quest Giver"]="Area2Quest",
   ["Marine Quest Giver"]="MarineQuest3",
   ["Graveyard Quest Giver"]="ZombieQuest",
   ["Snow Quest Giver"]="SnowMountainQuest",
   ["Ice Quest Giver"]="IceSideQuest",
   ["Fire Quest Giver"]="FireSideQuest",
   ["Rear Crew Quest Giver"]="ShipQuest1",
   ["Front Crew Quest Giver"]="ShipQuest2",
   ["Frost Quest Giver"]="FrostQuest",
   ["Forgotten Quest Giver"]="ForgottenQuest",
   ["Pirate Port Quest Giver"]="PiratePortQuest",
   ["Dragon Crew Quest Giver"]="DragonCrewQuest",
   ["Hydra Town Quest Giver"]="VenomCrewQuest",
   ["Marine Tree Quest Giver"]="MarineTreeIsland",
   ["Deep Forest Quest Giver"]="DeepForestIsland",
   ["Deep Forest Area 2 Quest Giver"]="DeepForestIsland2",
   ["Turtle Adventure Quest Giver"]="DeepForestIsland3",
   ["Haunted Castle Quest Giver 1"]="HauntedQuest1",
   ["Haunted Castle Quest Giver 2"]="HauntedQuest2",
   ["Peanut Quest Giver"]="NutsIslandQuest",
   ["Ice Cream Quest Giver"]="IceCreamIslandQuest",
   ["Cake Quest Giver 1"]="CakeQuest1",
   ["Cake Quest Giver 2"]="CakeQuest2",
   ["Chocolate Quest Giver 1"]="ChocQuest1",
   ["Chocolate Quest Giver 2"]="ChocQuest2",
   ["Candy Cane Quest Giver"]="CandyQuest1",
   ["Tiki Quest Giver 1"]="TikiQuest1",
   ["Tiki Quest Giver 2"]="TikiQuest2",
   ["Tiki Quest Giver 3"]="TikiQuest3",
   ["Submerged Quest Giver 1"]="SubmergedQuest1",
   ["Submerged Quest Giver 2"]="SubmergedQuest2",
   ["Submerged Quest Giver 3"]="SubmergedQuest3",
   ["Frozen Watcher"]="LeviathanGate",
   ["Tournament Master"]="FishTournamentNpc",
   ["Red Army Recruiter"]="RedRecruiter",
   ["Secret Santa"]="SecretSanta",
  }
  for _,container in ipairs({RS,workspace})do
   local folders={container}
   local npcs=container:FindFirstChild('NPCs');if npcs then folders[#folders+1]=npcs end
   for _,folder in ipairs(folders)do for _,model in ipairs(folder:GetChildren())do
    local questId=registry[model.Name]
    if questId and model:IsA('Model') then
     entries[#entries+1]={NPCName=model.Name,InternalQuestName=questId,Position=model:GetPivot().Position}
    end
   end end
  end
  return entries
 end
 local function selectQuest()
  local data=player:FindFirstChild('Data');local lv=data and data:FindFirstChild('Level')
  if not lv then return nil end
  local _,_,hr=body();local best
  for _,npc in ipairs(questNPCs()) do
   local variants=questDefs[npc.InternalQuestName]
   if type(variants)=='table' and typeof(npc.Position)=='Vector3' then
    for index,definition in pairs(variants) do
     local required=tonumber(definition.LevelReq)
     local taskName,amount,taskCount=nil,nil,0
     for name,count in pairs(definition.Task or {}) do taskName=name;amount=count;taskCount=taskCount+1 end
     -- Ordinary multi-enemy quests only. Boss/special quests are not a level loop.
     if required and required<=lv.Value and tonumber(index) and taskCount==1 and type(amount)=='number' and amount>1 and amount<=12 then
      local preferred=player.Team and player.Team.Name=='Marines' and 'MarineQuest' or 'BanditQuest1'
      local score=required*100+(npc.InternalQuestName==preferred and 1 or 0)
      local distance=hr and (hr.Position-npc.Position).Magnitude or 0
      if not best or score>best.score or (score==best.score and distance<best.distance) then
       best={id=npc.InternalQuestName,index=tonumber(index),enemy=taskName,amount=amount,level=required,npc=npc.NPCName,position=npc.Position,score=score,distance=distance}
      end
     end
    end
   end
  end
  return best
 end
 local function matches(q,target)
  return q and q.InternalQuestName==target.id and q.Info and q.Info.Task and q.Info.Task[target.enemy]~=nil
 end
 local function done(q)
  if not q or not q.Info or not q.Info.Task then return false end
  for name,count in pairs(q.Info.Task) do if (tonumber(q.Progress and q.Progress[name]) or 0)<count then return false end end
  return true
 end
 local requestBusy=false
 local function requestQuest(token,...)
  if requestBusy then error('Quest request still pending. Toggle off and retry later.') end
  local remotes=RS:FindFirstChild('Remotes');local remote=remotes and remotes:FindFirstChild('CommF_')
  if not remote then error('Quest remote unavailable') end
  requestBusy=true
  local args=table.pack(...);local finished,ok,result=false,false,nil
  task.spawn(function()
   ok,result=pcall(function() return remote:InvokeServer(table.unpack(args,1,args.n)) end)
   requestBusy=false;finished=true
  end)
  local deadline=os.clock()+6
  while running(token) and not finished and os.clock()<deadline do task.wait(.1) end
  if not running(token) then return false end
  if not finished then error('Quest request timed out') end
  if not ok then error('Quest request failed: '..tostring(result)) end
  return true,result
 end
 local function findEnemy(name)
  local _,_,hr=body();local container=workspace:FindFirstChild('Enemies');if not hr or not container then return nil end
  local best,distance
  for _,enemy in ipairs(container:GetChildren()) do
   if canonical(enemy.Name)==canonical(name) then
    local h=enemy:FindFirstChildOfClass('Humanoid');local rootPart=enemy:FindFirstChild('HumanoidRootPart')
    if h and h.Health>0 and rootPart and (avoided[enemy] or 0)<os.clock() then
     lastSpawns[canonical(name)]=rootPart.Position
     local d=(rootPart.Position-hr.Position).Magnitude
     if not distance or d<distance then best=enemy;distance=d end
    end
   end
  end
  return best
 end
 local spawnCursor={}
 local function spawnPosition(target)
  local origin=workspace:FindFirstChild('_WorldOrigin');local spawns=origin and origin:FindFirstChild('EnemySpawns')
  local candidates={};local key=canonical(target.enemy)
  if spawns then
   for _,spawn in ipairs(spawns:GetChildren()) do
    if spawn:IsA('BasePart') and (canonical(spawn.Name)==key or canonical(spawn:GetAttribute('DisplayName') or '')==key) then
     table.insert(candidates,spawn.Position)
    end
   end
  end
  if #candidates>0 then
   spawnCursor[key]=(spawnCursor[key] or 0)%#candidates+1
   return candidates[spawnCursor[key]]
  end
  return lastSpawns[key]
 end
 local function waitAtSpawn(target,token)
  local spawn=spawnPosition(target)
  if not spawn then
   status('Waiting for enemy spawn data')
   local _,_,hr=body()
   if hr then startHover({Position=hr.Position-Vector3.new(0,hoverHeight,hoverSide),Parent=true}) end
   pause(token,2);return
  end
  status('Waiting above '..target.enemy)
  hoverHeight=24;hoverSide=2
  if moveTo(spawn+Vector3.new(0,hoverHeight,hoverSide),token) then
   startHover({Position=spawn,Parent=true})
   local deadline=os.clock()+5
   repeat
    if findEnemy(target.enemy) or (not target.material and (not matches(quest(),target) or done(quest()))) or (farm.stackFruit and scanFruit()) then break end
    pause(token,.25)
   until not running(token) or os.clock()>deadline
  end
 end
 local function equip()
  local char,h=body();if not char then return nil end
  local backpack=player:FindFirstChildOfClass('Backpack')
  for _,container in ipairs({char,backpack}) do
   if container then for _,tool in ipairs(container:GetChildren()) do
    if tool:IsA('Tool') and not fishingTool(tool) and (not farm.serviceTool or tool.Name==farm.serviceTool) and (tool.ToolTip==farm.weapon or (farm.weapon=='Demon Fruit' and tool.ToolTip=='Blox Fruit') or tool:GetAttribute('WeaponType')==farm.weapon) then
     if tool.Parent~=char then h:EquipTool(tool) end
     return tool
    end
   end end
  end
  return nil
 end
 local gathered={}
 local function owned(part)
  if type(isnetworkowner)~='function' then return false end
  local ok,result=pcall(isnetworkowner,part);return ok and result==true
 end
 local function releaseMob(enemy)
  local saved=gathered[enemy];if not saved then return end
  gathered[enemy]=nil
  pcall(function()
   saved.h.WalkSpeed=saved.walk;saved.h.JumpPower=saved.jump;saved.h.AutoRotate=saved.rotate
   for part,value in pairs(saved.collisions) do if part.Parent then part.CanCollide=value end end
   if saved.root.Parent and saved.h.Health>0 and owned(saved.root) then saved.root.CFrame=saved.origin end
  end)
 end
 local function releaseMobs()
  local list={};for enemy in pairs(gathered) do table.insert(list,enemy) end
  for _,enemy in ipairs(list) do releaseMob(enemy) end
  farm.gathered=0
 end
 local function gather(primary,target)
  if not farm.bringMobs then releaseMobs();return {} end
  local anchor=primary:FindFirstChild('HumanoidRootPart')
  local _,_,hr=body();if not anchor or not hr then return {} end
  local container=workspace:FindFirstChild('Enemies');if not container then return {} end
  local list={}
  for _,enemy in ipairs(container:GetChildren()) do
   local h=enemy:FindFirstChildOfClass('Humanoid');local rootPart=enemy:FindFirstChild('HumanoidRootPart')
   if enemy~=primary and (target.enemyNames and target.enemyNames[canonical(enemy.Name)] or not target.enemyNames and canonical(enemy.Name)==canonical(target.enemy)) and h and h.Health>0 and rootPart and not rootPart.Anchored and (not target.region or target.region(rootPart.Position)) and (rootPart.Position-hr.Position).Magnitude<=180 and owned(rootPart) then
    table.insert(list,{enemy=enemy,h=h,root=rootPart,distance=(rootPart.Position-anchor.Position).Magnitude})
   end
  end
  table.sort(list,function(a,b) if a.distance==b.distance then return a.enemy:GetFullName()<b.enemy:GetFullName() end;return a.distance<b.distance end)
  local keep,extras={},{}
  local limit=math.min(farm.mobLimit-1,#list)
  for i=1,limit do
   local v=list[i];keep[v.enemy]=true
   if not gathered[v.enemy] then
    local collisions={};for _,part in ipairs(v.enemy:GetDescendants()) do if part:IsA('BasePart') then collisions[part]=part.CanCollide end end
    gathered[v.enemy]={h=v.h,root=v.root,walk=v.h.WalkSpeed,jump=v.h.JumpPower,rotate=v.h.AutoRotate,origin=v.root.CFrame,collisions=collisions}
   end
   v.h.WalkSpeed=0;v.h.JumpPower=0;v.h.AutoRotate=false
   for part in pairs(gathered[v.enemy].collisions) do if part.Parent then part.CanCollide=false end end
   local angle=(i-1)*math.pi*2/math.max(1,limit)
   v.root.CFrame=CFrame.new(anchor.Position+Vector3.new(math.cos(angle)*2,0,math.sin(angle)*2))
   v.root.AssemblyLinearVelocity=Vector3.zero;v.root.AssemblyAngularVelocity=Vector3.zero
   local part=v.enemy:FindFirstChild('Head') or v.root
   if (part.Position-hr.Position).Magnitude<=28 then table.insert(extras,{v.enemy,part}) end
  end
  local expired={};for enemy in pairs(gathered) do if not keep[enemy] then table.insert(expired,enemy) end end
  for _,enemy in ipairs(expired) do releaseMob(enemy) end
  farm.gathered=1+#extras;farm.maxGathered=math.max(farm.maxGathered,farm.gathered)
  return extras
 end
 function farm.SetBringMobs(value) farm.bringMobs=value==true;if not farm.bringMobs then releaseMobs() end;status(farm.message) end
 function farm.SetMobLimit(value) farm.mobLimit=math.clamp(math.floor(tonumber(value) or 4),2,6);releaseMobs();status(farm.message) end
 local auraAt=0;local auraBusy=false;local auraCharacter
 local function aura()
  local char=player.Character
  if char~=auraCharacter then auraCharacter=char;auraAt=0 end
  if farm.autoAura==false or not char or char:FindFirstChild('HasBuso') or auraBusy or os.clock()<auraAt then return end
  auraAt=os.clock()+15;auraBusy=true
  task.spawn(function()
   pcall(function() RS.Remotes.CommF_:InvokeServer('Buso') end)
   auraBusy=false
  end)
 end
 function farm.EnsureAura() aura() end
 local function isSeaBeast(model)
  if not model then return false end
  return model.Parent==workspace:FindFirstChild('SeaBeasts') or model.Name:lower():gsub('[%s%-_]',''):match('^seabeast%d*$')~=nil
 end
 local function isFruitTool(tool)
  return tool and (tool.Name=='Dragon-Dragon' or tool.ToolTip=='Blox Fruit' or tool.ToolTip=='Demon Fruit' or tool:GetAttribute('WeaponType')=='Demon Fruit')
 end
 local attackAt=0;local combo=0;local lastAttackTool
 local function gunType(tool)
  local n=tool and tool.Name:lower():gsub('[%s%-_]','')
  return n=='dragonstorm' and 'dragon' or n=='dualflintlock' and 'dual' or nil
 end
 local function attackRange(tool) return gunType(tool)=='dual' and 500 or gunType(tool) and 400 or 28 end
 local gunShootFunction;local gunController
 local function dragonstorm(tool,hit,extras)
  if type(debug.getupvalues)~='function' or type(debug.setupvalue)~='function' then farm.attackMessage='Gun: executor inspection unavailable';return false end
  local controller=require(RS.Controllers.CombatController)
  if gunController~=controller or not gunShootFunction then
   gunController=controller;gunShootFunction=nil
   for _,value in pairs(debug.getupvalues(controller.Attack)) do
    if type(value)=='function' and debug.info(value,'n')=='shootGun' then gunShootFunction=value;break end
   end
  end
  if not gunShootFunction then farm.attackMessage='Gun: gun controller changed';return false end
  local u=debug.getupvalues(gunShootFunction)
  -- Match the inspected controller before touching its shared shot sequence.
  for i=13,19 do if type(u[i])~='number' then farm.attackMessage='Gun: unsupported shot sequence';return false end end
  if u[18]~=1099511627776 or u[17]<=0 then farm.attackMessage='Gun: unsupported shot sequence';return false end
  local char,h,root=body()
  if not root or tool.Parent~=char or not hit.Parent then return false end
  local busy=char:FindFirstChild('Busy');local stun=char:FindFirstChild('Stun')
  if h.Sit or (busy and busy.Value) or (stun and stun.Value>0) then return false end
  local shots=RS.Modules.Net:FindFirstChild('RE/ShootGunEvent')
  local validator=RS.Remotes:FindFirstChild('Validator2')
  if not shots or not validator then return false end
  local parts={hit}
  local low=(u[15]*u[14]+u[13]*u[16])%u[17]
  local value=(low*u[17]+u[13]*u[14])%u[18]
  local high=math.floor(value/u[17]);local count=u[19]+1
  debug.setupvalue(gunShootFunction,15,high)
  debug.setupvalue(gunShootFunction,13,value-high*u[17])
  debug.setupvalue(gunShootFunction,19,count)
  validator:FireServer(math.floor(value/u[18]*16777215),count)
  shots:FireServer(hit.Position,parts)
  farm.attacks=(farm.attacks or 0)+1;farm.attackMessage='Gun auto attack'
  return true
 end
 local function attack(tool,enemy,extras,token,targetPart)
  if fishingTool(tool) then return end
  local char,h,hr=body();if not alive or farm.generation~=token or not hr or not tool or tool.Parent~=char or os.clock()<attackAt then return end
  local enemyH=enemy and enemy:FindFirstChildOfClass('Humanoid')
  local enemyHealth=enemyH and enemyH.Health
  if not enemyH and enemy and (farm.seaActive or isSeaBeast(enemy)) then
   local hp=enemy:FindFirstChild('Health') or enemy:FindFirstChild('Humanoid')
   local value=hp and hp:IsA('ValueBase') and tonumber(hp.Value) or tonumber(enemy:GetAttribute('Health'))
   enemyHealth=value or 1
  end
  local hit=targetPart or enemy and (enemy:FindFirstChild('Head') or enemy:FindFirstChild('HumanoidRootPart') or ((farm.seaActive or isSeaBeast(enemy)) and (enemy:FindFirstChild('RootPart') or enemy:FindFirstChild('Engine') or enemy:FindFirstChild('VehicleSeat') or enemy.PrimaryPart)))
  if not hit or not hit:IsA('BasePart') or not enemyHealth or enemyHealth<=0 then return end
  local deltaToHit=hit.Position-hr.Position
  local seaFruit=isSeaBeast(enemy) and isFruitTool(tool)
  local hitDistance=seaFruit and Vector3.new(deltaToHit.X,0,deltaToHit.Z).Magnitude or deltaToHit.Magnitude
  if hitDistance>(attackRange(tool)) then farm.m1State='Out of range';return end
  if lastAttackTool~=tool then combo=0;lastAttackTool=tool end
  farm.attackMessage=nil
  local kind=tool:GetAttribute('WeaponType') or tool.ToolTip
  if kind=='Blox Fruit' or isFruitTool(tool) then kind='Demon Fruit' end
  if kind=='Gun' and gunType(tool) then
   attackAt=os.clock()+(gunType(tool)=='dual' and .18 or .08)
   if dragonstorm(tool,hit,extras) and gunType(tool)=='dual' then
    task.delay(1/12,function()
     local c,hum=body()
     if alive and farm.generation==token and tool.Parent==c and hum and hum.Health>0 and hit.Parent and (farm.enabled or farm.seaActive or farm.autoClick) then
      RS.Modules.Net['RE/ShootGunEvent']:FireServer(hit.Position,{hit});farm.attacks=(farm.attacks or 0)+1
     end
    end)
   end
   return
  end
  if kind=='Demon Fruit' then
   local busy=char:FindFirstChild('Busy');local stun=char:FindFirstChild('Stun');local holding=tool:FindFirstChild('Holding')
   local bossFight=enemy:GetAttribute('IsBoss')==true or enemy:GetAttribute('RaidBoss')==true
   -- Keep requesting bounded M1s through boss hit-stun; the server decides
   -- whether an attack is allowed. Do not change either character's stun value.
   if h.Sit or (busy and busy.Value) or (stun and stun.Value>0 and not farm.seaActive and not bossFight) or (holding and holding.Value) then
    farm.m1State=h.Sit and 'Seated' or (busy and busy.Value) and 'Skill busy' or (holding and holding.Value) and 'Holding skill' or 'Stunned';return
   end
   farm.m1State='Requesting M1'
   local remote=tool:FindFirstChild('LeftClickRemote')
   if tool.Name=='Dragon-Dragon' and remote and remote:IsA('RemoteEvent') and not char:FindFirstChild('EasternBloxfruitsDragon') and not char:FindFirstChild('WesternDragonRig') then
    local d=hit.Position-hr.Position;local flat=Vector3.new(d.X,0,d.Z)
    if flat.Magnitude<.01 then return end
    local mousePos=tool:FindFirstChild('MousePos');if mousePos and mousePos:IsA('Vector3Value') then mousePos.Value=hit.Position end
    aura();remote:FireServer(flat.Unit,1);attackAt=os.clock()+.08
    farm.attacks=(farm.attacks or 0)+1;return
   end
   -- T-Rex ClientRuntime.onTap observed on the live client: direction + four-hit combo.
   if tool.Name=='T-Rex-T-Rex' and remote and remote:IsA('RemoteEvent') then
    if stun and stun.Value>0 and not farm.seaActive and not bossFight then return end
    local flat=Vector3.new(deltaToHit.X,0,deltaToHit.Z)
    if flat.Magnitude<.01 then return end
    local rig=tool:FindFirstChild('TransformedRigObject')
    local transformed=rig and rig:IsA('ObjectValue') and rig.Value~=nil
    local steady=farm.enabled or farm.seaActive or farm.autoClick
    combo=steady and 1 or combo%4+1
    local mousePos=tool:FindFirstChild('MousePos')
    if mousePos and mousePos:IsA('Vector3Value') then mousePos.Value=hit.Position end
    local scale=1
    pcall(function() scale=require(RS.Modules.FruitM1Speed).getCooldownScale(char) end)
    scale=math.clamp(tonumber(scale) or 1,.05,3)
    remote:FireServer(flat.Unit,combo)
    local interval=(combo<4 and .3 or transformed and 1.5 or .75)*scale
    if farm.seaActive then interval=math.min(interval,.08) end
    attackAt=os.clock()+interval
    farm.attacks=(farm.attacks or 0)+1;farm.attackMessage=steady and 'T-Rex steady M1' or 'T-Rex M1';return
   end
   -- Control's observed ClientRuntime.onM1: flat aim, four-hit combo, grounded flag.
   if tool.Name=='Control-Control' and remote and remote:IsA('RemoteEvent') then
    if stun and stun.Value>0 then return end
    local room=char:FindFirstChild('RoomActiveProxy') or tool:FindFirstChild('RoomActive')
    local mode=char:FindFirstChild('ControlModeProxy')
    if room and room.Value and mode and mode.Value=='Fist' then
     farm.attackMessage='Control: select Dagger mode for M1';attackAt=os.clock()+.25;return
    end
    local flat=Vector3.new(deltaToHit.X,0,deltaToHit.Z)
    if flat.Magnitude<.01 then return end
    local now=os.clock();local state=farm.controlM1State
    if not state or state.tool~=tool or state.character~=char or now-state.last>=1 then
     state={tool=tool,character=char,last=now,index=0};farm.controlM1State=state
    end
    local steady=farm.enabled or farm.seaActive or farm.autoClick
    state.index=steady and 1 or state.index%4+1;state.last=now
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={char,enemy}
    local grounded=workspace:Raycast(hr.Position,Vector3.new(0,-(h.HipHeight+hr.Size.Y*.5+4),0),params)~=nil
    local scale=1
    pcall(function() scale=require(RS.Modules.FruitM1Speed).getCooldownScale(char) end)
    scale=math.clamp(tonumber(scale) or 1,.05,3)
    local mousePos=tool:FindFirstChild('MousePos')
    if mousePos and mousePos:IsA('Vector3Value') then mousePos.Value=hit.Position end
    aura();remote:FireServer(flat.Unit,state.index,grounded)
    attackAt=now+(state.index<4 and .25 or .75)*scale
    farm.attacks=(farm.attacks or 0)+1;farm.attackMessage=steady and 'Control steady M1' or ('Control M1 '..state.index..'/4');return
   end
   -- Kitsune ClientRuntime.hostInit: flat aim, five-hit combo and grounded flag.
   if tool.Name=='Kitsune-Kitsune' and remote and remote:IsA('RemoteEvent') then
    local flat=Vector3.new(deltaToHit.X,0,deltaToHit.Z)
    if flat.Magnitude<.01 then return end
    local steady=farm.enabled or farm.seaActive or farm.autoClick
    combo=steady and 1 or combo%5+1
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={char,enemy}
    local grounded=workspace:Raycast(hr.Position,Vector3.new(0,-(h.HipHeight+hr.Size.Y*.5+4),0),params)~=nil
    local mousePos=tool:FindFirstChild('MousePos');if mousePos and mousePos:IsA('Vector3Value') then mousePos.Value=hit.Position end
    local scale=1
    pcall(function()scale=require(RS.Modules.FruitM1Speed).getCooldownScale(char)end)
    scale=math.clamp(tonumber(scale) or 1,.05,3)
    aura();remote:FireServer(flat.Unit,combo,grounded)
    attackAt=os.clock()+(steady and math.min(.1,.3*scale) or (combo<5 and .3 or 1)*scale)
    farm.attacks=(farm.attacks or 0)+1;farm.attackMessage=steady and 'Kitsune steady M1' or 'Kitsune M1';return
   end
   local known=tool.Name=='Pain-Pain' or tool.Name=='Gas-Gas'
   if known and remote and remote:IsA('RemoteEvent') then
    local delta=hit.Position-hr.Position;local flat=Vector3.new(delta.X,0,delta.Z)
    if flat.Magnitude<.01 then return end
    aura()
    if tool.Name=='Pain-Pain' then
     local steady=farm.seaActive or farm.enabled or farm.autoClick
     combo=steady and 1 or combo%4+1
     local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={char,enemy}
     local grounded=workspace:Raycast(hr.Position,Vector3.new(0,-(h.HipHeight+hr.Size.Y*.5+4),0),params)~=nil
     remote:FireServer(flat.Unit,combo,grounded)
     local scale=math.clamp(1-(tonumber(char:GetAttribute('FruitTAPCooldown')) or 0),.05,1)
     local interval=(combo<4 and .3 or 1)*scale
     -- Bounded sea-fight cadence; the server still decides which hits apply.
     if steady then
      -- Experimental normal-Pain cadence for Terrorshark only; no stat or ability changes.
      local terror=farm.seaActive and string.find(string.lower(enemy.Name or ''),'terrorshark',1,true)
      interval=terror and .03 or .06
     end
     attackAt=os.clock()+interval
    else
     -- Gas ClientRuntime: reset after one second, scaled cooldown, .8s finisher.
     if stun and stun.Value>0 and not farm.seaActive and not bossFight then return end
     local now=os.clock();local state=farm.gasM1State
     if not state or state.tool~=tool or state.character~=char or now-state.last>=1 then
      state={tool=tool,character=char,last=now,index=0};farm.gasM1State=state
     end
     local steady=farm.enabled or farm.seaActive or farm.autoClick
     state.index=steady and 1 or state.index%5+1;state.last=now
     local transformed=char:FindFirstChild('GasRig')~=nil
     local delays=transformed and {.3,.3,.3,.3,.8} or {.2,.2,.35,.6,.8}
     local scale=1
     pcall(function() scale=require(RS.Modules.FruitM1Speed).getCooldownScale(char) end)
     scale=math.clamp(tonumber(scale) or 1,.05,3)
     local mousePos=tool:FindFirstChild('MousePos')
     if mousePos and mousePos:IsA('Vector3Value') then mousePos.Value=hit.Position end
     remote:FireServer(flat.Unit,state.index)
     local interval=delays[state.index]*scale
     if farm.seaActive then interval=math.min(interval,.08) end
     attackAt=now+interval
     farm.attackMessage=steady and 'Gas steady M1' or ('Gas M1 '..state.index..'/5') 
    end
    farm.attacks=(farm.attacks or 0)+1
    return
   end
   -- Other fruit handlers use their own Tool activation until a protocol is verified.
   if remote then
    local mousePos=tool:FindFirstChild('MousePos')
    if mousePos and mousePos:IsA('Vector3Value') then mousePos.Value=hit.Position end
    attackAt=os.clock()+(farm.raidCombatToken==token and .1 or .3);tool:Activate()
    task.delay(.05,function() if tool.Parent then pcall(function() tool:Deactivate() end) end end)
    farm.attackMessage='Using fruit M1 handler';return
   end
  end
  if not combatUtil then
   combatUtil=require(RS.Modules.CombatUtil)
   attackRemote=require(RS.Modules.Net):RemoteEvent('RegisterAttack')
   sendHits=require(RS.Global).SendHitsToServer
  end
  local ok,weaponData=pcall(function() return combatUtil:GetWeaponData(combatUtil:GetWeaponName(tool)) end)
  local basic=ok and weaponData and weaponData.Moveset and weaponData.Moveset.Basic
  if type(basic)~='table' or #basic==0 then farm.attackMessage='No supported M1 on '..tool.Name;attackAt=os.clock()+1;return end
  kind=weaponData.WeaponType
  if kind~='Melee' and kind~='Sword' and kind~='Demon Fruit' then return end
  if not combatUtil:CanAttack(char,kind) then return end
  attackAt=os.clock()+.1;aura();combo=combo%#basic+1
  attackRemote:FireServer(.1,combo)
  task.wait(.02)
  if not alive or farm.generation~=token or tool.Parent~=char or not hit.Parent or not enemyH or not enemyH.Parent or enemyH.Health<=0 then return end
  local valid={}
  for _,pair in ipairs(extras or {}) do
   local eh=pair[1]:FindFirstChildOfClass('Humanoid')
   if eh and eh.Health>0 and pair[2].Parent and (pair[2].Position-hr.Position).Magnitude<=28 then table.insert(valid,pair) end
  end
  sendHits(hit,valid);farm.attacks=(farm.attacks or 0)+1
 end
 -- Auto Click operates only on an equipped M1 weapon, and never moves the player.
 task.spawn(function()
  local setIdentity=setthreadidentity or setidentity
  if setIdentity then setIdentity(2) end
  while alive do
   if farm.autoClick and not farm.enabled and not farm.seaActive and currentMode~='fruit' then
    pcall(function()
     local char,h,hr=body();local tool=char and char:FindFirstChildOfClass('Tool')
     if not hr or not tool then return end
     local targets={}
     local function add(model)
      if not model or model==char then return end
      local humanoid=model:FindFirstChildOfClass('Humanoid')
      local beast=isSeaBeast(model)
      local part=model:FindFirstChild('Head') or model:FindFirstChild('HumanoidRootPart') or (beast and (model:FindFirstChild('RootPart') or model.PrimaryPart))
      local health=humanoid and humanoid.Health
      if not health and beast then
       local value=model:FindFirstChild('Health') or model:FindFirstChild('Humanoid')
       health=value and value:IsA('ValueBase') and tonumber(value.Value) or tonumber(model:GetAttribute('Health')) or 1
      end
      if health and health>0 and part and part:IsA('BasePart') then
       local gap=part.Position-hr.Position
       local distance=beast and isFruitTool(tool) and Vector3.new(gap.X,0,gap.Z).Magnitude or gap.Magnitude
       if distance<=attackRange(tool) then table.insert(targets,{model,part}) end
      end
     end
     local enemies=workspace:FindFirstChild('Enemies')
     if enemies then for _,enemy in ipairs(enemies:GetChildren()) do add(enemy) end end
     if gunType(tool) or isFruitTool(tool) then
      local beasts=workspace:FindFirstChild('SeaBeasts')
      if beasts then for _,beast in ipairs(beasts:GetChildren()) do if beast:IsA('Model') then add(beast) end end end
     end
     for _,other in ipairs(Players:GetPlayers()) do if other~=player then add(other.Character) end end
     table.sort(targets,function(a,b) return (a[2].Position-hr.Position).Magnitude<(b[2].Position-hr.Position).Magnitude end)
     if #targets>0 then local first=table.remove(targets,1);attack(tool,first[1],targets,farm.generation) end
    end)
   end
   task.wait(.04)
  end
 end)
 local fruitSeen=setmetatable({},{__mode='k'})
 local storageRetry=setmetatable({},{__mode='k'});local nextScan=0;local cachedFruit
 local storageBusy=false
 local function fruitInfo(tool)
  if not tool or not (tool:IsA('Tool') or tool:IsA('Model')) then return end
  if tool:IsA('Model') and tool.Name~='Fruit' and not tool.Name:match(' Fruit$') then return end
  local handle=tool:FindFirstChild('Handle',true)
  if not handle or not handle:IsA('BasePart') then return end
  local original=tool:GetAttribute('OriginalName')
  local physical=tool.Name:match(' Fruit$') or tool.Name=='Fruit' or tool:FindFirstChild('EatRemote',true)
  if not physical then return end -- Never mistake an equipped ability for a pickup.
  if type(original)=='string' and original~='' then return original,handle end
  local base=tool.Name:gsub(' Fruit$','')
  if base=='Fruit' then
   local named=tool:FindFirstChild('FruitName')
   base=type(tool:GetAttribute('FruitName'))=='string' and tool:GetAttribute('FruitName') or named and named:IsA('StringValue') and named.Value or ''
  end
  if base=='' then return end
  local key=base:find('-',1,true) and base or base..'-'..base
  local ok,info=pcall(function()return require(RS.FruitInfo).tryGet(key)end)
  if ok and info then return key,handle end
  -- A named physical Tool with an eating remote is still collectable if metadata is late.
  if tool:IsA('Tool') and tool:FindFirstChild('EatRemote',true) and tool.Name:match(' Fruit$') then return key,handle end
 end
 local function isLoose(tool)
  if not tool or not tool:IsDescendantOf(workspace) then return false end
  for _,p in ipairs(Players:GetPlayers()) do if p.Character and tool:IsDescendantOf(p.Character) then return false end end
  local ancestor=tool.Parent
  while ancestor and ancestor~=workspace do
   if ancestor:IsA('Model') and ancestor:FindFirstChildOfClass('Humanoid') then return false end
   ancestor=ancestor.Parent
  end
  return true
 end
 -- Keep a small live pickup index instead of rescanning every map model.
 local fruitCandidates=setmetatable({},{__mode='k'})
 local function indexFruit(v)
  if v:IsA('Tool') or (v:IsA('Model') and (v.Name=='Fruit' or v.Name:match(' Fruit$'))) then fruitCandidates[v]=true end
 end
 connect(workspace.DescendantAdded,indexFruit)
 connect(workspace.DescendantRemoving,function(v)fruitCandidates[v]=nil end)
 task.spawn(function()
  local initial=workspace:GetDescendants()
  for i,v in ipairs(initial) do
   if not alive then return end
   if v:IsDescendantOf(workspace) then indexFruit(v) end
   if i%300==0 then task.wait() end
  end
 end)
 scanFruit=function()
  if not farm.stackFruit or storageBusy then return nil end
  if os.clock()<nextScan then return cachedFruit and isLoose(cachedFruit) and cachedFruit or nil end
  nextScan=os.clock()+2;cachedFruit=nil
  local _,_,hr=body();if not hr then return end
  local distance
  for tool in pairs(fruitCandidates) do
   if (tool:IsA('Tool') or tool:IsA('Model')) and (fruitSeen[tool] or 0)<=os.clock() and isLoose(tool) then
    local name,handle=fruitInfo(tool)
    if name then
     local d=(handle.Position-hr.Position).Magnitude
     if not distance or d<distance then distance=d;cachedFruit=tool end
    end
   end
  end
  return cachedFruit
 end
 local fruitDisplayAt=0;local fruitDisplay={}
 function farm.FruitNames()
  if os.clock()<fruitDisplayAt then return fruitDisplay end
  fruitDisplayAt=os.clock()+3;fruitDisplay={};local names={}
  for tool in pairs(fruitCandidates) do
   if (tool:IsA('Tool') or tool:IsA('Model')) and isLoose(tool) then
    local name=fruitInfo(tool)
    if name and not names[name] then names[name]=true;table.insert(fruitDisplay,tool.Name) end
   end
  end
  table.sort(fruitDisplay);return fruitDisplay
 end
 collectFruit=function(tool,token)
  local name,handle=fruitInfo(tool)
  if not name or not isLoose(tool) then return end
  fruitSeen[tool]=os.clock()+5;cachedFruit=nil;nextScan=0
  farm.stackMessage='Collecting '..tool.Name;status(farm.stackMessage)
  local backpack=player:FindFirstChildOfClass('Backpack');local before={}
  if backpack then for _,v in ipairs(backpack:GetChildren()) do before[v]=true end end
  if player.Character then for _,v in ipairs(player.Character:GetChildren()) do before[v]=true end end
  if not moveTo(handle.Position+Vector3.new(0,24,0),token) or not isLoose(tool) then return end
  if not handle.Parent or not moveTo(handle.Position+Vector3.new(0,1,0),token) then return end
  local function collected()
   if tool.Parent==backpack or tool.Parent==player.Character then return tool end
   for _,root in pairs({backpack,player.Character}) do
    for _,v in ipairs(root:GetChildren()) do
     if not before[v] and v:IsA('Tool') and fruitInfo(v)==name then return v end
    end
   end
  end
  local deadline=os.clock()+4;local owned
  repeat
   owned=collected();if owned then break end
   if not isLoose(tool) or not handle.Parent then break end
   local _,_,root=body()
   if root and type(firetouchinterest)=='function' then
    pcall(firetouchinterest,root,handle,0);pause(token,.1)
    pcall(firetouchinterest,root,handle,1)
   end
   pause(token,.15)
  until not running(token) or os.clock()>deadline
  owned=owned or collected()
  if not running(token) then return end
  if not owned then
   fruitSeen[tool]=os.clock()+8;farm.stackMessage='Pickup not confirmed; will retry';return
  end
  fruitSeen[tool]=nil;farm.stackMessage='Collected '..owned.Name
  farm.StoreOwnedFruit(owned)
 end
 function farm.StoreOwnedFruit(tool)
  if not farm.autoStore or storageBusy or not alive or (storageRetry[tool] or 0)>os.clock() then return false end
  local name=fruitInfo(tool);local backpack=player:FindFirstChildOfClass('Backpack')
  if not name or (tool.Parent~=backpack and tool.Parent~=player.Character) then return false end
  if farm.trevorFruitReservation or farm.raidFruitReservation then return false end
  storageBusy=true;storageRetry[tool]=os.clock()+60
  local finished=false
  task.spawn(function()
   local attempted=false
   local ok=pcall(function() if farm.autoStore and alive and not farm.raidFruitReservation and not farm.trevorFruitReservation then attempted=true;RS.Remotes.CommF_:InvokeServer('StoreFruit',name,tool) end end)
   task.wait(.4)
   local stillOwned=tool.Parent==backpack or tool.Parent==player.Character
   if attempted and ok and not stillOwned then
    storageRetry[tool]=nil;farm.stackMessage='Stored '..name
   elseif attempted and ok then
    -- A completed request left this physical fruit in the bag (for example full storage).
    -- Skip only this instance. A newly received fruit always gets its own attempt.
    storageRetry[tool]=math.huge
    farm.stackMessage='Could not store '..name..'; kept in backpack; no repeat attempts'
   elseif not attempted then storageRetry[tool]=nil
   else
    farm.stackMessage='Storage request failed; retrying later'
   end
   storageBusy=false;finished=true
  end)
  local deadline=os.clock()+7
  while alive and not finished and os.clock()<deadline do task.wait(.1) end
  return finished
 end
 task.spawn(function()
  while alive do
   if farm.autoStore and not storageBusy and not farm.trevorFruitReservation and not farm.raidFruitReservation then
    for _,container in pairs({player:FindFirstChildOfClass('Backpack'),player.Character}) do
     for _,tool in ipairs(container:GetChildren()) do
      if not alive or not farm.autoStore then break end
      if fruitInfo(tool) then farm.StoreOwnedFruit(tool) end
     end
    end
   end
   task.wait(2)
  end
 end)

 local function stabilizeTarget(enemy,token)
  stopStabilize()
  if farm.weapon~='Demon Fruit' then return end
  local rootPart=enemy:FindFirstChild('HumanoidRootPart');local humanoid=enemy:FindFirstChildOfClass('Humanoid')
  if not rootPart or not humanoid then return end
  local anchor=rootPart.CFrame
  local character=player.Character;local equipped=character and character:FindFirstChildOfClass('Tool')
  local fixedControl=equipped and equipped.Name=='Control-Control'
  local connection=RunService.PreSimulation:Connect(function()
   if not running(token) or not enemy.Parent or humanoid.Health<=0 then return end
   if owned(rootPart) then
    local displaced=(rootPart.Position-anchor.Position).Magnitude
    local speed=rootPart.AssemblyLinearVelocity.Magnitude
    if displaced>2 or speed>25 then
     rootPart.AssemblyLinearVelocity=Vector3.zero
     rootPart.AssemblyAngularVelocity=Vector3.zero
     rootPart.CFrame=anchor
     farm.stabilized=(farm.stabilized or 0)+1
    end
   else
    -- Only correct naturally owned targets. Keep Control's hold point through brief ownership changes.
    if not fixedControl then anchor=rootPart.CFrame end
   end
  end)
  stopStabilize=function() connection:Disconnect() end
 end
 local function enterCakePortal(enemy,token)
  local name=canonical(enemy.Name)
  if name~='cake prince' and name~='dough king' then return true end
  local _,_,root=body();local target=enemy:FindFirstChild('HumanoidRootPart')
  if not root or not target then return false end
  -- Already in the boss arena: leave the current combat route alone.
  if (root.Position-target.Position).Magnitude<3000 then return true end
  local cake=Vector3.new(-2091,70,-12142)
  local function portal()
   local map=workspace:FindFirstChild('Map');if not map then return end
   local best,distance
   for _,v in ipairs(map:GetDescendants()) do
    local n=v.Name:lower():gsub('[^%a]','')
    if n=='bigmirror' or n=='cakemirror' or n=='cakeportal' or n=='mirror' then
     local part=v:IsA('BasePart') and v or v:FindFirstChild('Hitbox',true) or v:FindFirstChildWhichIsA('BasePart',true)
     if part and part:IsA('BasePart') then
      local d=(part.Position-cake).Magnitude
      if d<1500 and (not distance or d<distance) then best=part;distance=d end
     end
    end
   end
   return best
  end
  status('Using Cake Land portal for '..enemy.Name)
  local gate=portal()
  if not gate then
   if not moveTo(cake+Vector3.new(0,10,0),token) then return false end
   if not pause(token,.4) then return false end
   gate=portal()
  end
  if not gate then status('Waiting for Cake Land portal to load');pause(token,1);return false end
  if not moveTo(gate.Position,token) then return false end
  local _,_,hr=body();if not hr or not running(token) then return false end
  stopHover();stopStabilize()
  if type(firetouchinterest)=='function' then
   pcall(firetouchinterest,hr,gate,0);pause(token,.1);pcall(firetouchinterest,hr,gate,1)
  end
  local deadline=os.clock()+4
  repeat
   if not pause(token,.15) then return false end
   local _,_,r=body()
   if r and target.Parent and (r.Position-target.Position).Magnitude<3000 then return true end
  until os.clock()>deadline
  status('Portal entry not confirmed; waiting for it to open');return false
 end
 local tyrantScanAt=0;local tyrantLive
 local function liveTyrant()
  local folder=workspace:FindFirstChild('Enemies')
  if tyrantLive and tyrantLive.Parent==folder then
   local h=tyrantLive:FindFirstChildOfClass('Humanoid')
   if h and h.Health>0 and tyrantLive:FindFirstChild('HumanoidRootPart') then return tyrantLive end
  end
  tyrantLive=nil
  if os.clock()<tyrantScanAt then return end
  tyrantScanAt=os.clock()+.15
  if folder then for _,e in ipairs(folder:GetChildren()) do
   if e:IsA('Model') and canonical(e.Name)=='tyrant of the skies' then
    local h=e:FindFirstChildOfClass('Humanoid')
    if h and h.Health>0 and e:FindFirstChild('HumanoidRootPart') then tyrantLive=e;return e end
   end
  end end
 end
 local function fight(enemy,target,token)
  if not enterCakePortal(enemy,token) then return end
  local enemyH=enemy:FindFirstChildOfClass('Humanoid');local enemyRoot=enemy:FindFirstChild('HumanoidRootPart')
  if not enemyH or not enemyRoot then return end
  hoverHeight=farm.weapon=='Demon Fruit' and 3 or 24;hoverSide=farm.weapon=='Demon Fruit' and 10 or 2
  status('Moving to '..target.enemy)
  local destination=enemyRoot.Position+Vector3.new(0,hoverHeight,hoverSide)
  local function approachValid()
   if not enemyRoot.Parent or enemyH.Health<=0 then return false end
   if target.tyrant then return (enemyRoot.Position+Vector3.new(0,hoverHeight,hoverSide)-destination).Magnitude<24 end
   return not (farm.mode=='tyrant' and not target.special and liveTyrant())
  end
  if not moveTo(destination,token,target.tyrant==true,nil,approachValid) then return end
  local tool=equip();if not tool then status('Equip or obtain '..farm.weapon);pause(token,2);return end
  -- Direct hit registration does not start a local swing animation.
  local followBoss=target.tyrant or farm.weapon=='Demon Fruit' and (enemy:GetAttribute('IsBoss')==true or enemy:GetAttribute('RaidBoss')==true)
  if not startHover(enemyRoot,farm.enabled and farm.mode=='tyrant',followBoss) then return end
  stabilizeTarget(enemy,token)
  pause(token,.3)
  local lastHealth=enemyH.Health;local damageAt=os.clock()
  local combo=0
  local extras={};local lastGather=0
  while running(token) and enemy.Parent and enemyRoot.Parent and enemyH.Health>0 do
   if farm.mode=='tyrant' and not target.special and liveTyrant() then return end
   if not farm.priorityOnly and farm.stackFruit and scanFruit() then return end
   if not target.special and scanStackEvent and scanStackEvent() then return end
   local char,h,hr=body();if not hr then return end
   if farm.hoverStuck then
    farm.movementRecoveries=(farm.movementRecoveries or 0)+1
    status('Repositioning around obstacle')
    if not moveTo(enemyRoot.Position+Vector3.new(0,hoverHeight,hoverSide),token) then return end
    if not startHover(enemyRoot,farm.enabled and farm.mode=='tyrant',followBoss) then return end
    stabilizeTarget(enemy,token)
   end
   if target.region and not target.region(enemyRoot.Position) then return end
   aura()
   local q=quest();if not target.material and not target.prison and not target.special and (not matches(q,target) or done(q)) then return end
   if tool.Parent~=char or (tool.ToolTip~=farm.weapon and tool:GetAttribute('WeaponType')~=farm.weapon) then tool=equip();if not tool then return end end
   if not target.prison and not target.special and os.clock()-lastGather>.35 then extras=gather(enemy,target);lastGather=os.clock() end
   local distance=(hr.Position-enemyRoot.Position).Magnitude
   if distance<=(attackRange(tool)) then attack(tool,enemy,extras,token) end
   if not running(token) then return end
   local count=tonumber(q and q.Progress and q.Progress[target.enemy]) or 0
   status(farm.attackMessage or target.progressText or (target.special and ('Fighting '..target.enemy) or target.prison and 'Defeating escaped prisoner' or target.material and ('Farming '..target.material..' Â· '..farm.materialKills..' defeats') or string.format('%s  %d / %d',target.enemy,count,target.amount)))
   if enemyH.Health<lastHealth then damageAt=os.clock();lastHealth=enemyH.Health end
   if os.clock()-damageAt>(farm.weapon=='Demon Fruit' and 8 or 5) then
    if farm.weapon~='Demon Fruit' and hoverHeight>20 then hoverHeight=20;damageAt=os.clock()
    elseif farm.weapon~='Demon Fruit' and hoverHeight>18 then hoverHeight=18;damageAt=os.clock()
    else
     farm.recoveries=farm.recoveries+1;avoided[enemy]=os.clock()+8
     status('Rechecking target and weapon');h:UnequipTools();pause(token,.5);return
    end
   end
   if not pause(token,.04) then return end
  end
 end
 local function prisonPreparation(token)
  if (game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId)~=2753915549 then return false end
  local data=player:FindFirstChild('Data');local level=data and data:FindFirstChild('Level')
  if not level or level.Value<190 then return false end
  local controller=require(RS.Controllers.BonusMomentsController)
  local moment=controller:GetLoadedMoments()['Escape from Alcatraz']
  if not moment or moment.Completed or not moment.Active then return false end
  local prisoners=moment.MiscData and moment.MiscData.Prisoners
  if not prisoners or not next(prisoners) then return false end
  local dialogue=require(RS.DialogueController)
  -- These records identify the special prisoners even though their models are named Prisoner.
  for _,key in ipairs({'Digger','Puncher','Raft'}) do
   if not running(token) then return true end
   local entry=prisoners[key];local model=entry and entry.Model
   local root=model and (model.PrimaryPart or model:FindFirstChild('HumanoidRootPart'))
   local hum=model and model:FindFirstChildOfClass('Humanoid')
   if model and model.Parent and root and hum and hum.Health>0 and (not entry.Confronted or dialogue.Active) then
    stopHover();stopStabilize();releaseMobs()
    status('Speaking to escaped prisoner: '..key)
    if not moveTo(root.Position+Vector3.new(0,0,6),token) then return true end
    local deadline=os.clock()+8;local selected=false
    repeat
     if not pause(token,.2) then return true end
     local activeDialogue=dialogue.getActiveDialogue()
     local page=activeDialogue and activeDialogue:getCurrent()
     for _,option in ipairs(page and page._options or {}) do
      if type(option._text)=='table' and option._text[1]=='Not this time!' then
       dialogue.select(option);selected=true;break
      end
     end
    until selected or not running(token) or os.clock()>deadline
    if not selected then status('Waiting for escaped-prisoner dialogue');pause(token,1);return true end
    if not pause(token,.5) then return true end
   end
  end
  for _,key in ipairs({'Digger','Puncher','Raft'}) do
   if not running(token) then return true end
   local entry=prisoners[key];local model=entry and entry.Model
   local hum=model and model:FindFirstChildOfClass('Humanoid')
   if model and model.Parent and hum and hum.Health>0 then
    fight(model,{enemy=model.Name,prison=true},token)
    if farm.generation==token then stopHover();stopStabilize();releaseMobs() end
   end
  end
  status('Checking Prison preparation completion');pause(token,.5)
  return true
 end
 local eventRetry={};local castlePosition
 local function castleCenter()
  if castlePosition then return castlePosition end
  local folder=RS.Definitions.Map.DEFINITIONS.LIBRARY:FindFirstChild('Sea3')
  if folder then for _,module in ipairs(folder:GetChildren()) do
   if module:IsA('ModuleScript') then
    local ok,d=pcall(require,module)
    if ok and d.Display and tostring(d.Display.Name):lower():find('castle',1,true) then castlePosition=d.World and d.World.Position;return castlePosition end
   end
  end end
  local origin=workspace:FindFirstChild('_WorldOrigin')
  local locations=origin and origin:FindFirstChild('Locations')
  local castle=locations and locations:FindFirstChild('Castle on the Sea')
  if castle and castle:IsA('BasePart') then castlePosition=castle.Position;return castlePosition end
 end
 scanStackEvent=function()
  if not anyStackEvent() then return end
  local container=workspace:FindFirstChild('Enemies');if not container then return end
  local _,_,hr=body();if not hr then return end
  local best,kind,distance
  local candidates=container:GetChildren()
  if (game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId)==7449423635 and (farm.stackEvents.elite or farm.stackEvents.ripindra or farm.stackEvents.doughking or farm.stackEvents.reaper) or (game.PlaceId==4442272183 or game.PlaceId==79091703265657) and farm.stackEvents.darkbeard then
   for _,enemy in ipairs(RS:GetChildren()) do
    local n=canonical(enemy.Name)
    if enemy:IsA('Model') and (n=='diablo' or n=='deandre' or n=='urban' or n=='rip_indra' or n=='rip_indra true form' or n=='darkbeard' or n=='dough king' or n=='soul reaper') then table.insert(candidates,enemy) end
   end
  end
  for _,enemy in ipairs(candidates) do
   local hum=enemy:FindFirstChildOfClass('Humanoid');local rootPart=enemy:FindFirstChild('HumanoidRootPart')
   if hum and hum.Health>0 and rootPart and (avoided[enemy] or 0)<os.clock() then
    local n=canonical(enemy.Name);local k
    if (game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId)==7449423635 and farm.stackEvents.elite and (n=='diablo' or n=='deandre' or n=='urban') then k='elite'
    elseif (game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId)==7449423635 and farm.stackEvents.ripindra and not farm.blockIndraForTushita and (n=='rip_indra' or n=='rip_indra true form') then k='ripindra'
    elseif workspace:GetAttribute('MAP')=='Sea3' and farm.stackEvents.doughking and n=='dough king' then k='doughking'
    elseif workspace:GetAttribute('MAP')=='Sea3' and farm.stackEvents.reaper and n=='soul reaper' then k='reaper'
    elseif (game.PlaceId==4442272183 or game.PlaceId==79091703265657) and farm.stackEvents.darkbeard and n=='darkbeard' then k='darkbeard'
    elseif (game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId)==4442272183 and farm.stackEvents.factory and n=='core' then k='factory'
    elseif (game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId)==7449423635 and farm.stackEvents.raid and (n=='pirate millionaire' or n=='pistol billionaire' or n=='forest pirate' or n=='captain') then
     local center=castleCenter();if center and (rootPart.Position-center).Magnitude<1200 then k='raid' end
    end
    local priority=k=='doughking' or k=='reaper'
    if farm.priorityOnly and not priority then k=nil end
    local gap=(rootPart.Position-hr.Position).Magnitude-(priority and 1000000 or 0)
    if k and (eventRetry[k] or 0)<os.clock() and (not distance or gap<distance) then best=enemy;kind=k;distance=gap end
   end
  end
  return best,kind
 end
 local function runStackEvent(token)
  local enemy,kind=scanStackEvent();if not enemy then return false end
  stopHover();stopStabilize();releaseMobs()
  if kind=='elite' then
   local function assigned()
    local q=quest();local tasks=q and q.Info and q.Info.Task
    if type(tasks)=='table' then for name in pairs(tasks) do if canonical(name)==canonical(enemy.Name) then return true end end end
    local progress=q and q.Progress
    if type(progress)=='table' then for name in pairs(progress) do if canonical(name)==canonical(enemy.Name) then return true end end end
    return false
   end
   if not assigned() then
    status('Accepting Elite Hunter quest')
    if quest() then requestQuest(token,'AbandonQuest');if not pause(token,.3) then return true end end
    requestQuest(token,'EliteHunter')
    local deadline=os.clock()+5
    repeat if not pause(token,.25) then return true end until assigned() or os.clock()>deadline
    if not assigned() then
     status('Visiting Elite Hunter to confirm quest')
     local npcs=workspace:FindFirstChild('NPCs')
     local hunter=npcs and npcs:FindFirstChild('Elite Hunter')
     local hunterPosition=hunter and hunter:GetPivot().Position or Vector3.new(-5417.664,313.064,-2822.914)
     if not moveTo(hunterPosition+Vector3.new(0,0,5),token) then eventRetry.elite=os.clock()+5;return true end
     requestQuest(token,'EliteHunter')
     deadline=os.clock()+5
     repeat if not pause(token,.25) then return true end until assigned() or os.clock()>deadline
    end
    if not assigned() then eventRetry.elite=os.clock()+30;status('Elite Hunter quest not confirmed');return true end
   end
  end
  if running(token) and not enterCakePortal(enemy,token) then return true end
  if running(token) and enemy.Parent==RS then
   local name=canonical(enemy.Name)
   status('Travelling to '..enemy.Name)
   if not moveTo(enemy:GetPivot().Position+Vector3.new(0,35,0),token) then return true end
   local loaded;local deadline=os.clock()+12
   repeat
    local container=workspace:FindFirstChild('Enemies')
    if container then for _,candidate in ipairs(container:GetChildren()) do
     local h=candidate:FindFirstChildOfClass('Humanoid')
     if canonical(candidate.Name)==name and h and h.Health>0 and candidate:FindFirstChild('HumanoidRootPart') then loaded=candidate;break end
    end end
    if loaded then break end
    if not pause(token,.25) then return true end
   until os.clock()>deadline
   if not loaded then eventRetry[kind]=os.clock()+5;status('Waiting for elite to load');return true end
   enemy=loaded
  end
  if running(token) then fight(enemy,{enemy=enemy.Name,special=true},token) end
  if farm.generation==token then stopHover();stopStabilize();releaseMobs() end
  return true
 end
 local sea2CheckAt=0;local detectiveStage;local sea2TravelAt=0
 local function firstSeaProgression(token)
  if game.PlaceId~=2753915549 and game.PlaceId~=85211729168715 then return false end
  local data=player:FindFirstChild('Data');local level=data and data:FindFirstChild('Level')
  if not level or level.Value<700 then return false end
  if os.clock()<sea2CheckAt then pause(token,.5);return true end
  sea2CheckAt=os.clock()+3
  local ok,ready=requestQuest(token,'DressrosaQuestProgress','Dressrosa')
  if not ok then return true end
  if ready==0 then
   if os.clock()>=sea2TravelAt then
    status('Travelling to Second Sea');sea2TravelAt=os.clock()+15
    requestQuest(token,'TravelDressrosa')
   end
   pause(token,1);return true
  end
  local char,h=body();if not char then return true end
  local function npcPosition(names,fallback)
   local folder=workspace:FindFirstChild('NPCs')
   if folder then for _,npc in ipairs(folder:GetChildren()) do
    if names[npc.Name] and npc:IsA('Model') then return npc:GetPivot().Position end
   end end
   return fallback
  end
  local backpack=player:FindFirstChild('Backpack')
  local key=char:FindFirstChild('Key') or (backpack and backpack:FindFirstChild('Key'))
  if not key and detectiveStage~=1 then
   status('Level 700: meeting Military Detective')
   local point=npcPosition({['Military Detective']=true,Detective=true},Vector3.new(4851,6,719))
   if not moveTo(point+Vector3.new(0,0,5),token) then return true end
   local accepted,result=requestQuest(token,'DressrosaQuestProgress','Detective')
   if not accepted then return true end
   detectiveStage=result
   if result==2 then
    requestQuest(token,'DressrosaQuestProgress','Dressrosa');return true
   end
   pause(token,.5);key=char:FindFirstChild('Key') or (backpack and backpack:FindFirstChild('Key'))
   if not key and result~=1 then status('Waiting for Detective key');return true end
  end
  status('Opening Ice Admiral entrance')
  -- Move to the Frozen Village cave so the door and boss can stream in.
  if not moveTo(Vector3.new(1348,37,-1329),token) then return true end
  local ice=workspace.Map:FindFirstChild('Ice')
  local door=ice and ice:FindFirstChild('Door',true)
  if door and door:IsA('BasePart') and door.CanCollide then
   if not key then detectiveStage=nil;status('Ice door locked: getting another key');return true end
   h:EquipTool(key);pause(token,.25)
   if not moveTo(door.Position,token) then return true end
   local deadline=os.clock()+3
   repeat if not pause(token,.2) then return true end until not door.Parent or not door.CanCollide or os.clock()>deadline
   if door.Parent and door.CanCollide then detectiveStage=nil;status('Ice door has not opened yet');return true end
  end
  -- The key is consumed by the door; keep fighting instead of fetching it again.
  if door and door:IsA('BasePart') and not door.CanCollide then detectiveStage=1 end
  local enemy=findEnemy('Ice Admiral')
  if not enemy then
   moveTo(Vector3.new(1266,60,-1399),token)
   status('Waiting for Ice Admiral');return true
  end
  status('Defeating Ice Admiral')
  local enemyHumanoid=enemy:FindFirstChildOfClass('Humanoid')
  fight(enemy,{enemy=enemy.Name,special=true},token)
  if running(token) and enemyHumanoid and enemyHumanoid.Health<=0 then
   stopHover();stopStabilize();releaseMobs();detectiveStage=nil
   status('Reporting Ice Admiral defeat')
   requestQuest(token,'DressrosaQuestProgress','Detective')
  end
  return true
 end
 local thirdCheckAt=0;local thirdTravelAt=0
 local function secondSeaProgression(token)
  if game.PlaceId~=4442272183 and game.PlaceId~=79091703265657 then return false end
  local data=player:FindFirstChild('Data');local level=data and data:FindFirstChild('Level')
  if not level or level.Value<1500 then return false end
  if os.clock()<thirdCheckAt then pause(token,.3);return true end
  thirdCheckAt=os.clock()+2
  local function battle(name,point,ordinary)
   local target={enemy=name,special=not ordinary,id='BartiloQuest',amount=50,index=1}
   local enemy=findEnemy(name)
   if not enemy then
    status('Third Sea: waiting for '..name)
    moveTo(point+Vector3.new(0,25,0),token);pause(token,1)
   else fight(enemy,target,token) end
   if running(token) then stopHover();stopStabilize();releaseMobs() end
  end
  local ok,ready=requestQuest(token,'ZQuestProgress','Zou')
  if not ok then return true end
  if ready==0 then
   if os.clock()>=thirdTravelAt then
    thirdTravelAt=os.clock()+15;status('Travelling to Third Sea');requestQuest(token,'TravelZou')
   end
   return true
  end
  local checked,stage=requestQuest(token,'BartiloQuestProgress','Bartilo')
  if not checked then return true end
  if stage==0 then
   local q=quest()
   if not q or q.InternalQuestName~='BartiloQuest' then
    status('Third Sea: accepting Bartilo quest')
    local point=Vector3.new(-461.533,72.348,300.311)
    local npcs=workspace:FindFirstChild('NPCs');local npc=npcs and npcs:FindFirstChild('Bartilo')
    if npc and npc:IsA('Model') then point=npc:GetPivot().Position end
    local _,_,hr=body();if not hr then return true end
    if (hr.Position-point).Magnitude>45 then
     -- Stop outside the furniture instead of requiring an exact point inside it.
     moveTo(point+Vector3.new(0,3,-22),token)
     _,_,hr=body()
     if not running(token) or not hr or (hr.Position-point).Magnitude>45 then return true end
    end
    if q then requestQuest(token,'AbandonQuest');if not pause(token,.3) then return true end end
    local accepted,result=requestQuest(token,'StartQuest','BartiloQuest',1)
    if not accepted or result~=0 then status('Bartilo quest not accepted: '..tostring(result));pause(token,1);return true end
    local deadline=os.clock()+3
    repeat
     if not pause(token,.2) then return true end
     q=quest()
    until (q and q.InternalQuestName=='BartiloQuest') or os.clock()>=deadline
    if not q or q.InternalQuestName~='BartiloQuest' then status('Waiting for Bartilo quest confirmation') end
    return true
   end
   battle('Swan Pirate',Vector3.new(970,137,1217),true);return true
  elseif stage==1 then
   battle('Jeremy',Vector3.new(2006,449,853));return true
  elseif stage==2 then
   status('Third Sea: freeing the gladiators')
   local _,_,hr=body();if not hr then return true end
   local centre=Vector3.new(-1837,15,1724)
   if (hr.Position-centre).Magnitude>150 then
    if not moveTo(centre+Vector3.new(0,5,0),token) then return true end
   end
   local map=workspace:FindFirstChild('Map');local dress=map and map:FindFirstChild('Dressrosa')
   local plates=dress and dress:FindFirstChild('BartiloPlates')
   if not plates then status('Waiting for puzzle plates to load');pause(token,1);return true end
   -- Release flight before touching plates; never tween across other symbols.
   stopHover();stopStabilize();releaseMovement()
   for i=1,8 do
    local plate=plates:FindFirstChild('Plate'..i)
    local char,h,root=body()
    if not char or not root or not plate or not plate:IsA('BasePart') or not running(token) then return true end
    jumpOutOfSeat(h)
    status('Third Sea: puzzle plate '..i..' / 8')
    root.AssemblyLinearVelocity=Vector3.new(0,0,0)
    root.AssemblyAngularVelocity=Vector3.new(0,0,0)
    root.CFrame=CFrame.new(plate.Position)
    if not pause(token,.15) then return true end
    if player.Character~=char or not root.Parent then return true end
    if type(firetouchinterest)=='function' then
     pcall(function() firetouchinterest(root,plate,0) end)
     if not pause(token,.15) then return true end
     pcall(function() firetouchinterest(root,plate,1) end)
    end
    if not pause(token,.25) then return true end
    local checked,progress=requestQuest(token,'BartiloQuestProgress','Bartilo')
    if checked and progress==3 then status('Gladiators freed; continuing to Third Sea');return true end
   end
   status('Waiting for puzzle completion; will retry if needed');pause(token,2)
   return true
  elseif stage~=3 then
   status('Third Sea: waiting for Bartilo progress');return true
  end
  local _,king=requestQuest(token,'ZQuestProgress','Check')
  if king==0 then
   local enemy=findEnemy('rip_indra')
   if enemy then battle('rip_indra',enemy:GetPivot().Position)
   else
    status('Third Sea: meeting King Red Head')
    if moveTo(Vector3.new(-1926,13,1738),token) then requestQuest(token,'ZQuestProgress','Begin');pause(token,2) end
   end
   return true
  elseif king==1 then status('Third Sea: waiting for Captain access');pause(token,2);return true end
  local _,trevor=requestQuest(token,'TalkTrevor','1')
  if trevor~=0 then
   local char,h=body();if not char then return true end
   local physical={}
   for _,container in pairs({char,player:FindFirstChild('Backpack')}) do
    for _,tool in ipairs(container:GetChildren()) do
     if tool:IsA('Tool') and tool.Name:match(' Fruit$') then table.insert(physical,tool) end
    end
   end
   if #physical==0 then
    local candidate
    local scanned,scanError=pcall(function()
     local rep=require(RS.ItemReplicationService)
     local itemConfig=require(RS.ItemConfig)
     if not rep.IsInitialized then return end
     for _,item in pairs(rep:GetItems(rep.KEYS.QUANTITY) or {}) do
      if type(item.Value)=='number' and item.Value>0 then
       local result=itemConfig.match(item.ItemId)
       if result:isOk() then
        local info=result:unwrap();local quality=info.Quality
        if info.State and info.State.EquipMethod=='LoadFruit' and quality and quality.Rarity=='Legendary' and type(quality.MoneyPrice)=='number' and quality.MoneyPrice>=1000000 then
         if not candidate or quality.MoneyPrice<candidate.price then
          candidate={key=info.Index.StorageKey,price=quality.MoneyPrice}
         end
        end
       end
      end
     end
    end)
    if not scanned then status('Trevor: could not read storage; retrying');pause(token,2);return true end
    if not candidate then status('Trevor: no eligible Legendary fruit in storage');pause(token,2);return true end
    status('Trevor: withdrawing '..candidate.key)
    farm.trevorFruitReservation=true
    requestQuest(token,'LoadFruit',candidate.key)
    -- Re-read backpack and re-check rarity on the next pass before offering.
    pause(token,2);return true
   end
   -- Trevor's server chooses the offered fruit: only proceed with one physical fruit.
   if #physical~=1 then status('Trevor: carry exactly one Legendary fruit to offer');pause(token,2);return true end
   local tool=physical[1];local base=tool.Name:gsub(' Fruit$','')
   local info=require(RS.FruitInfo).tryGet(base..'-'..base)
   if not info or not info.Rarity or info.Rarity.Name~='Legendary' then
    status('Trevor: this fruit is not Legendary; keeping it');pause(token,2);return true
   end
   status('Trevor: offering '..tool.Name)
   if not moveTo(Vector3.new(-339,332,643),token) then return true end
   h:EquipTool(tool);pause(token,.3)
   requestQuest(token,'TalkTrevor','2')
   local _,offer=requestQuest(token,'TalkTrevor','1')
   if offer==2 and running(token) and tool.Parent==char then requestQuest(token,'TalkTrevor','3') end
   return true
  end
  farm.trevorFruitReservation=false
  battle('Don Swan',Vector3.new(2289,15,863));return true
 end

 local function initialize(token)
  local ready,failed=false,nil
  task.spawn(function()
   local ok,err=pcall(function()
    questDefs=require(RS:WaitForChild('Quests',5))
    guide=require(RS:WaitForChild('GuideModule',5))
    guideData=require(RS.GuideModule:WaitForChild('GuideData',5))
    combatUtil=require(RS.Modules:WaitForChild('CombatUtil',5))
    local net=require(RS.Modules.Net)
    attackRemote=net:RemoteEvent('RegisterAttack')
    local global=require(RS.Global)
    sendHits=global.SendHitsToServer
    assert(type(sendHits)=='function','Current hit-registration API unavailable')
   end)
   failed=not ok and tostring(err) or nil;ready=true
  end)
  local deadline=os.clock()+12
  while running(token) and not ready and os.clock()<deadline do task.wait(.1) end
  if not running(token) then return false end
  if not ready then error('Quest data did not load') end
  if failed then error(failed) end
  return true
 end
 -- Summon farming reads the server's progress; it never invents a kill counter.
 local summonPollAt=0;local cakeReply;local summonAt=0;local summonPatrol=0
 local tikiCenter=Vector3.new(-16342.5,164.525,1397)
 local cakeCenter=Vector3.new(-2091,70,-12142)
 local function spawnedBoss(names)
  for _,container in pairs({workspace:FindFirstChild('Enemies'),RS}) do
   for _,enemy in ipairs(container:GetChildren()) do
    if names[canonical(enemy.Name)] and enemy:IsA('Model') then
     local h=enemy:FindFirstChildOfClass('Humanoid');local r=enemy:FindFirstChild('HumanoidRootPart')
     if h and h.Health>0 and r then return enemy end
    end
   end
  end
 end
 local function fightSummoned(enemy,token)
  if canonical(enemy.Name)=='tyrant of the skies' then
   local boss=liveTyrant();if not boss then return end
   stopStabilize();releaseMobs()
   fight(boss,{enemy=boss.Name,special=true,tyrant=true},token)
   return
  end
  if not enterCakePortal(enemy,token) then return end
  if enemy.Parent==RS then
   status('Travelling to '..enemy.Name)
   moveTo(enemy:GetPivot().Position+Vector3.new(0,30,0),token)
   pause(token,.5);return
  end
  fight(enemy,{enemy=enemy.Name,special=true},token)
  if farm.generation==token then stopHover();stopStabilize();releaseMobs() end
 end
 local function summonMobs(names,center,title,token)
  local _,_,hr=body();if not hr then return end
  local best,distance
  for _,name in ipairs(names) do
   local enemy=findEnemy(name);local rootPart=enemy and enemy:FindFirstChild('HumanoidRootPart')
   if rootPart then local d=(rootPart.Position-hr.Position).Magnitude
    if not distance or d<distance then best=enemy;distance=d end
   end
  end
  if best then
   fight(best,{enemy=best.Name,material=title},token)
   if running(token) then
    local _,_,root=body()
    stopStabilize();releaseMobs()
    if root then
     local position=root.Position
     hoverHeight=0;hoverSide=0
     startHover({Position=position,Parent=workspace})
     root.AssemblyLinearVelocity=Vector3.zero
    end
   end
  else
   summonPatrol=summonPatrol%#names+1
   local position=spawnPosition({enemy=names[summonPatrol]}) or center
   status(title..': finding enemies')
   if moveTo(position+Vector3.new(0,28,0),token,true,nil,function()return not liveTyrant()end) then
    hoverHeight=28;hoverSide=0;startHover({Position=position,Parent=true});pause(token,1)
   end
  end
 end
 farm.SummonMobs=summonMobs
 local function sweetChalice()
  for _,container in pairs({player.Character,player:FindFirstChild('Backpack')}) do
   for _,tool in ipairs(container:GetChildren()) do
    if tool:IsA('Tool') and canonical(tool.Name)=='sweet chalice' then return true end
   end
  end
  return false
 end
 local function cakeStage(reply)
  if type(reply)~='string' then return 'unknown' end
  reply=reply:gsub('<[^>]*>',''):lower()
  local remaining=tonumber(reply:match('(%d+)%s+more') or reply:match('(%d+)%s+enemies'))
  if reply:find('open the portal now',1,true) then return 'ready',0 end
  if remaining then return remaining>0 and 'farm' or 'ready',remaining end
  return 'unknown'
 end
 local function farmCake(token)
  local boss=spawnedBoss({['cake prince']=true})
  if boss then fightSummoned(boss,token);return end
  if os.clock()>=summonPollAt then
   summonPollAt=os.clock()+5
   local ok,reply=requestQuest(token,'CakePrinceSpawner',true)
   if not running(token) then return end
   cakeReply=ok and reply or nil
  end
  local stage,remaining=cakeStage(cakeReply)
  if stage=='ready' then
   if sweetChalice() then status('Put away Sweet Chalice before summoning Cake Prince');pause(token,1);return end
   status('Summoning Cake Prince')
   if os.clock()>=summonAt then
    summonAt=os.clock()+10;requestQuest(token,'CakePrinceSpawner');cakeReply=nil;summonPollAt=0
   end
   pause(token,1)
  elseif stage=='farm' then
   summonMobs({'Cookie Crafter','Cake Guard','Baking Staff','Head Baker'},cakeCenter,'Cake Prince: '..remaining..' remaining',token)
  else
   status('Checking Cake Prince summon progress');pause(token,1)
  end
 end
 local function tikiEyes()
  local map=workspace:FindFirstChild('Map');local tiki=map and map:FindFirstChild('TikiOutpost')
  if not tiki then return 0,0 end
  local found,ready={},{}
  for _,part in ipairs(tiki:GetDescendants()) do
   if part:IsA('BasePart') and part.Name:match('^Eye[1-4]$') then
    found[part.Name]=true
    if part.Transparency<.5 and part.Color.R>part.Color.G*1.5 then ready[part.Name]=true end
   end
  end
  local total,count=0,0;for _ in pairs(found) do total=total+1 end;for _ in pairs(ready) do count=count+1 end
  return count,total
 end
 local potVisits={}
 local function potVisitAt(position)
  local visited=0
  for _,entry in ipairs(potVisits) do if (entry.position-position).Magnitude<24 then visited=math.max(visited,entry.at) end end
  return visited
 end
 local function markPotVisit(position)
  for _,entry in ipairs(potVisits) do if (entry.position-position).Magnitude<24 then entry.at=os.clock();return end end
  table.insert(potVisits,{position=position,at=os.clock()})
 end
 local function potModel(part)
  local v=part
  while v and v~=workspace do
   if v:GetAttribute('TikiUrn') then return v end
   v=v.Parent
  end
 end
 local activePot
 local function summonPot()
  local best,distance,oldest;local _,_,hr=body();if not hr then return end
  local tiki=workspace:FindFirstChild('Map') and workspace.Map:FindFirstChild('TikiOutpost')
  if not tiki then return end
  for _,model in ipairs(tiki:GetDescendants()) do
   if model:IsA('Model') and model:GetAttribute('TikiUrn') and not model:GetAttribute('AlreadyDestroyedClient') then
    local part,volume
    for _,v in ipairs(model:GetDescendants()) do
     if v:IsA('BasePart') and v.Transparency<.95 then
      local size=v.Size;local area=size.X*size.Y*size.Z
      if not volume or area>volume then part=v;volume=area end
     end
    end
    if part then
     if model==activePot then return part end
     local d=(part.Position-hr.Position).Magnitude;local visited=potVisitAt(part.Position)
     if not oldest or visited<oldest or (visited==oldest and d<distance) then best=part;distance=d;oldest=visited end
    end
   end
  end
  activePot=best and potModel(best) or nil
  return best
 end
 local potGunLoadAt=0
 local potGunShotAt=0
 local function potGunM1(part,model,token)
  if liveTyrant() then return false end
  local char,h,hr=body();if not char or not h or not hr or not running(token) then return false end
  local tool
  for _,name in ipairs({'Soul Guitar','Cannon'}) do
   for _,container in pairs({char,player:FindFirstChild('Backpack')}) do
    local candidate=container:FindFirstChild(name)
    if candidate and candidate:IsA('Tool') then tool=candidate;break end
   end
   if tool then break end
  end
  if not tool then
   if os.clock()>=potGunLoadAt then
    potGunLoadAt=os.clock()+60
    task.spawn(function()
     for _,name in ipairs({'Soul Guitar','Cannon'}) do
      if not running(token) then return end
      local owned=false
      pcall(function()
       local id=require(RS.Economy.ItemId).getId(name,'Moveset'):asNullable()
       owned=id and require(RS.Util.ItemReplication).IsOwned.readClient(id)==true
      end)
      if owned then pcall(function()RS.Remotes.CommF_:InvokeServer('LoadItem',name)end);return end
     end
    end)
   end
   return false
  end
  -- Use the gun's normal M1, retaining its own cooldown and hit handling.
  if os.clock()<potGunShotAt then return false end
  local busy=char:FindFirstChild('Busy');local stun=char:FindFirstChild('Stun')
  if (busy and busy.Value) or (stun and stun.Value>0) then return false end
  if tool.Parent~=char then h:EquipTool(tool);if not pause(token,.15) then return false end end
  if liveTyrant() or not part.Parent or not model.Parent or model:GetAttribute('AlreadyDestroyedClient') then return false end
  local camera=workspace.CurrentCamera;if not camera then return false end
  local savedType,savedCF,savedFocus=camera.CameraType,camera.CFrame,camera.Focus
  local mouse=tool:FindFirstChild('MousePos');local savedMouse=mouse and mouse:IsA('Vector3Value') and mouse.Value
  local input=game:GetService('VirtualInputManager');local pressed=false;local x,y=0,0
  local function click(down)
   local setID=setthreadidentity or setidentity;local getID=getthreadidentity or getidentity
   local identity=getID and getID() or 2;if setID then setID(8) end
   local ok,err=pcall(input.SendMouseButtonEvent,input,x,y,0,down,game,0)
   if setID then setID(identity) end
   if not ok then error(err,0) end
  end
  local ok=pcall(function()
   camera.CameraType=Enum.CameraType.Scriptable
   camera.CFrame=CFrame.lookAt(hr.Position+Vector3.new(0,3,0),part.Position);camera.Focus=CFrame.new(part.Position)
   if savedMouse then mouse.Value=part.Position end
   local screen=camera:WorldToViewportPoint(part.Position);local inset=game:GetService('GuiService'):GetGuiInset()
   x,y=screen.X+inset.X,screen.Y+inset.Y
   pressed=true;click(true);status('Breaking pot: '..tool.Name..' M1');pause(token,.12)
  end)
  if pressed then pcall(click,false) end
  pcall(function()
   camera.CameraType=savedType;camera.CFrame=savedCF;camera.Focus=savedFocus
   if savedMouse and mouse.Parent then mouse.Value=savedMouse end
  end)
  potGunShotAt=os.clock()+1.5
  return ok
 end
 local potCastState={}
 local function breakSummonPot(part,token)
  if liveTyrant() then return end
  local model=potModel(part)
  if not model or model:GetAttribute('AlreadyDestroyedClient') then return end
  local point=part.Position;local char,h,hr=body();if not hr then return end
  if (hr.Position-point).Magnitude>35 then
   stopHover();stopStabilize();releaseMobs()
   if not moveTo(point+Vector3.new(0,10,12),token,true,nil,function()return not liveTyrant() and model.Parent and not model:GetAttribute('AlreadyDestroyedClient')end) then return end
  end
  if liveTyrant() then return end
  hoverHeight=10;hoverSide=12;startHover({Position=point,Parent=model},true)
  if potGunM1(part,model,token) then markPotVisit(point);return end
  local used,why=farm.CastSkillCycle(potCastState,function()
   if liveTyrant() or not part.Parent or not model.Parent or model:GetAttribute('AlreadyDestroyedClient') then return end
   return part.Position
  end,token)
  if used then markPotVisit(point) else status(why or 'Waiting for a ready summon skill');pause(token,.1) end
 end
 -- Bounds cover the observed Serpent Hunter / Skull Slayer platforms.
 local function tyrantSide(position)
  return position.X>=-17200 and position.X<=-16100 and position.Z>=1200 and position.Z<=1950 and position.Y>=0 and position.Y<=450
 end
 local tyrantNames={['serpent hunter']=true,['skull slayer']=true,['isle champion']=true,['sun-kissed warrior']=true,['isle outlaw']=true,['island boy']=true}
 local tyrantPatrol={Vector3.new(-16536,106,1347),Vector3.new(-16521,106,1489),Vector3.new(-16443,71,1693),Vector3.new(-16813,71,1757),Vector3.new(-16949,192,1644),Vector3.new(-16855,121,1478)}
 local tyrantCursor=0
 local function tyrantMobs(ready,token)
  local _,_,hr=body();if not hr then return end
  local enemies=workspace:FindFirstChild('Enemies');local best,distance
  for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
   local rootPart=enemy:FindFirstChild('HumanoidRootPart');local h=enemy:FindFirstChildOfClass('Humanoid')
   if rootPart and h and h.Health>0 and tyrantNames[canonical(enemy.Name)] and tyrantSide(rootPart.Position) and (avoided[enemy] or 0)<os.clock() then
    local d=(rootPart.Position-hr.Position).Magnitude
    if not distance or d<distance then best=enemy;distance=d end
   end
  end
  if best then
   fight(best,{enemy=best.Name,material='Tyrant',region=tyrantSide,enemyNames=tyrantNames,progressText='Tyrant: '..ready..'/4 eyes'},token)
   if farm.generation==token then stopHover();stopStabilize();releaseMobs() end
  else
   tyrantCursor=tyrantCursor%#tyrantPatrol+1
   local position=tyrantPatrol[tyrantCursor]
   status('Tyrant side: checking enemy spawns')
   if moveTo(position+Vector3.new(0,28,0),token) then
    hoverHeight=28;hoverSide=0;startHover({Position=position,Parent=true});pause(token,.75)
   end
  end
 end
 local function farmTyrant(token)
  local boss=liveTyrant()
  if boss then fightSummoned(boss,token);return end
  local ready,total=tikiEyes()
  if total<4 then
   status('Loading Tiki summon area');moveTo(tikiCenter+Vector3.new(0,35,0),token);pause(token,1);return
  end
  if ready==4 then
   local pot=summonPot()
   if pot then breakSummonPot(pot,token)
   else status('Tyrant: four eyes ready, waiting for summon objects');moveTo(tikiCenter+Vector3.new(0,12,0),token);pause(token,1) end
  else
   tyrantMobs(ready,token)
  end
 end
 local function summonFarm(token)
  if workspace:GetAttribute('MAP')~='Sea3' then status('This boss is in Sea 3');pause(token,2);return end
  if farm.mode=='tyrant' then farmTyrant(token) else farmCake(token) end
 end

 local function loop(token)
  status('Reading quests...');if not initialize(token) then return end
  while running(token) do
   local fruit=not farm.priorityOnly and farm.stackFruit and scanFruit()
   if not body() then
    releaseMovement();stopHover();stopStabilize();releaseMobs()
    status('Waiting for respawn');pause(token,.5)
   elseif farm.enabled and farm.mode=='tyrant' and liveTyrant() then currentMode='farm';farmTyrant(token)
   elseif fruit then currentMode='fruit';stopHover();stopStabilize();releaseMobs();collectFruit(fruit,token);currentMode='farm'
   elseif body() and runStackEvent(token) then currentMode='farm'
   elseif farm.priorityOnly then pause(token,.2)
   elseif not farm.enabled then currentMode='idle';pause(token,.5)
   elseif farm.mode=='level' and firstSeaProgression(token) then
    currentMode='farm'
   elseif farm.mode=='level' and secondSeaProgression(token) then
    currentMode='farm'
   elseif farm.mode=='level' and prisonPreparation(token) then
    currentMode='farm'
   else
    currentMode='farm'
    if farm.mode=='tyrant' or farm.mode=='cake' then summonFarm(token)
    elseif farm.mode=='material' then
     local target=materialTarget()
     if not target then status(farm.material..': no source in this sea');pause(token,2)
     else
      farm.target=target.enemy;farm.questId=nil
      local enemy=findEnemy(target.enemy)
      if enemy then
       local h=enemy:FindFirstChildOfClass('Humanoid')
       fight(enemy,target,token)
       if h and h.Health<=0 then farm.materialKills=farm.materialKills+1 end
       if farm.generation==token then stopHover();stopStabilize();releaseMobs() end
      else waitAtSpawn(target,token) end
     end
    else
    local target=selectQuest();if not target then error('No eligible quest found in this sea') end
    farm.target=target.enemy;farm.questId=target.id
    local q=quest()
    -- Finish an existing eligible ordinary quest before switching on a level-up.
    if q and q.Info and not done(q) then
     for _,npc in ipairs(questNPCs()) do
      if npc.InternalQuestName==q.InternalQuestName then
       for index,definition in pairs(questDefs[q.InternalQuestName] or {}) do
        if definition.Name==q.Info.Name then
         local name,count=next(definition.Task or {})
         if name and type(count)=='number' and count>1 and count<=12 then
          target={id=q.InternalQuestName,index=tonumber(index),enemy=name,amount=count,npc=npc.NPCName,position=npc.Position}
         end
        end
       end
      end
     end
    end
    if not matches(q,target) then
     if q then error('Finish or abandon the current special quest before farming') end
     status('Moving to '..tostring(target.npc))
     if moveTo(target.position+Vector3.new(0,0,4),token) and pause(token,.4) then
      status('Accepting '..target.enemy)
      if requestQuest(token,'StartQuest',target.id,target.index) then
       local deadline=os.clock()+5
       repeat pause(token,.2);q=quest() until not running(token) or matches(q,target) or os.clock()>deadline
       if running(token) and not matches(q,target) then error('Quest acceptance was not confirmed') end
      end
     end
    elseif done(q) then
     status('Waiting for quest reward');pause(token,1)
    else
     local before=q.UID
     local enemy=findEnemy(target.enemy)
     if enemy then fight(enemy,target,token);if farm.generation==token then stopHover();stopStabilize();releaseMobs() end else
      waitAtSpawn(target,token)
     end
     local after=quest()
     if running(token) and before and (not after or after.UID~=before) then farm.completed=farm.completed+1 end
    end
    end
    pause(token,.15)
   end
   -- All priority/early-return paths must yield, including death and moving targets.
   task.wait(.03)
  end
 end
 local function restart()
  farm.seaActive=false
  farm.generation=farm.generation+1;releaseMovement();stopHover();stopStabilize();releaseMobs()
  if not farm.enabled and not farm.stackFruit and not anyStackEvent() then status('Stopped');return end
  local token=farm.generation
  task.spawn(function()
   local setIdentity=setthreadidentity or setidentity
   local getIdentity=getthreadidentity or getidentity
   local previousIdentity=getIdentity and getIdentity() or nil
   if setIdentity then setIdentity(2) end
   while running(token) do
    local ok,err=pcall(loop,token)
    if not running(token) then break end
    releaseMovement();stopHover();stopStabilize();releaseMobs()
    farm.recoveries=farm.recoveries+1
    status(ok and 'Rechecking farm' or ('Retrying: '..tostring(err):gsub('^.-:%d+: ','')))
    pause(token,3)
   end
   if setIdentity and previousIdentity then pcall(setIdentity,previousIdentity) end
  end)
 end
 function farm.SetMode(mode,enabled)
  if mode~='level' and mode~='material' and mode~='tyrant' and mode~='cake' then return end
  farm.mode=mode;farm.enabled=enabled==true;restart()
 end
 function farm.SelectMaterial(name)
  for _,entry in ipairs(materials) do
   if entry.name==name then
    farm.material=name;farm.materialKills=0
    if farm.mode=='material' and farm.enabled then restart() else status(farm.message) end
    return true
   end
  end
  return false
 end
 function farm.SetEnabled(value)
  value=value==true;if value==farm.enabled then return end
  farm.enabled=value;restart()
 end
 function farm.SetStackFruit(value)
  value=value==true;if value==farm.stackFruit then return end
  farm.stackFruit=value;farm.stackMessage=value and 'Watching for fruits' or 'Off';restart()
 end
 function farm.PriorityBoss()
  if workspace:GetAttribute('MAP')~='Sea3' then return end
  if farm.stackEvents.doughking then local boss=spawnedBoss({['dough king']=true});if boss then return boss end end
  if farm.stackEvents.reaper then return spawnedBoss({['soul reaper']=true}) end
 end
 function farm.HasStackTarget() return scanStackEvent and scanStackEvent()~=nil end
 function farm.HasLooseFruit() return scanFruit and scanFruit()~=nil end
 function farm.SetStackEvent(key,value)
  if farm.stackEvents[key]==nil then return end
  farm.stackEvents[key]=value==true;restart()
 end
 function farm.SetWeapon(value)
  if value=='Melee' or value=='Sword' or value=='Demon Fruit' or value=='Gun' then farm.weapon=value;status(farm.message) end
 end
 function farm.SetTweenSpeed(value) farm.tweenSpeed=math.clamp(tonumber(value) or 200,40,350);status(farm.message) end
 function farm.SetAutoClick(value) farm.autoClick=value==true;status(farm.message) end

 local seaHoverRoot,seaStabilizedTarget,seaHoverClearance,seaHoverEvade
 function farm.RaceFightEnemy(enemy,token)
  if not farm.SeaActive(token) then return false end
  fight(enemy,{enemy=enemy.Name,special=true},token)
  if farm.SeaActive(token) then stopHover();stopStabilize();releaseMobs() end
  return farm.SeaActive(token)
 end
 function farm.RaceDonSwan(token)
  local function battle(name,point)
   local enemy=findEnemy(name)
   if enemy then fight(enemy,{enemy=name,special=true},token)
   else status('Waiting for '..name);moveTo(point+Vector3.new(0,25,0),token);pause(token,1) end
   if running(token) then stopHover();stopStabilize();releaseMobs() end
  end
  local _,trevor=requestQuest(token,'TalkTrevor','1')
  if trevor~=0 then
   local char,h=body();if not char then return true end
   local physical={}
   for _,container in pairs({char,player:FindFirstChild('Backpack')}) do
    for _,tool in ipairs(container:GetChildren()) do
     if tool:IsA('Tool') and tool.Name:match(' Fruit$') then table.insert(physical,tool) end
    end
   end
   if #physical==0 then
    local candidate
    local scanned,scanError=pcall(function()
     local rep=require(RS.ItemReplicationService)
     local itemConfig=require(RS.ItemConfig)
     if not rep.IsInitialized then return end
     for _,item in pairs(rep:GetItems(rep.KEYS.QUANTITY) or {}) do
      if type(item.Value)=='number' and item.Value>0 then
       local result=itemConfig.match(item.ItemId)
       if result:isOk() then
        local info=result:unwrap();local quality=info.Quality
        if info.State and info.State.EquipMethod=='LoadFruit' and quality and quality.Rarity=='Legendary' and type(quality.MoneyPrice)=='number' and quality.MoneyPrice>=1000000 then
         if not candidate or quality.MoneyPrice<candidate.price then
          candidate={key=info.Index.StorageKey,price=quality.MoneyPrice}
         end
        end
       end
      end
     end
    end)
    if not scanned then status('Trevor: could not read storage; retrying');pause(token,2);return true end
    if not candidate then status('Trevor: no eligible Legendary fruit in storage');pause(token,2);return true end
    status('Trevor: withdrawing '..candidate.key)
    farm.trevorFruitReservation=true
    requestQuest(token,'LoadFruit',candidate.key)
    -- Re-read backpack and re-check rarity on the next pass before offering.
    pause(token,2);return true
   end
   -- Trevor's server chooses the offered fruit: only proceed with one physical fruit.
   if #physical~=1 then status('Trevor: carry exactly one Legendary fruit to offer');pause(token,2);return true end
   local tool=physical[1];local base=tool.Name:gsub(' Fruit$','')
   local info=require(RS.FruitInfo).tryGet(base..'-'..base)
   if not info or not info.Rarity or info.Rarity.Name~='Legendary' then
    status('Trevor: this fruit is not Legendary; keeping it');pause(token,2);return true
   end
   status('Trevor: offering '..tool.Name)
   if not moveTo(Vector3.new(-339,332,643),token) then return true end
   h:EquipTool(tool);pause(token,.3)
   requestQuest(token,'TalkTrevor','2')
   local _,offer=requestQuest(token,'TalkTrevor','1')
   if offer==2 and running(token) and tool.Parent==char then requestQuest(token,'TalkTrevor','3') end
   return true
  end
  farm.trevorFruitReservation=false
  battle('Don Swan',Vector3.new(2289,15,863));return true
 end
 function farm.RaceBartilo(token)
  local function battle(name,point,ordinary)
   local enemy=findEnemy(name)
   if enemy then fight(enemy,{enemy=name,special=not ordinary,id='BartiloQuest',amount=50,index=1},token)
   else moveTo(point+Vector3.new(0,25,0),token);pause(token,1) end
   if running(token) then stopHover();stopStabilize();releaseMobs() end
  end
  local checked,stage=requestQuest(token,'BartiloQuestProgress','Bartilo')
  if not checked then return true end
  if stage==0 then
   local q=quest()
   if not q or q.InternalQuestName~='BartiloQuest' then
    status('Race V2: accepting Bartilo quest')
    local point=Vector3.new(-461.533,72.348,300.311)
    local npcs=workspace:FindFirstChild('NPCs');local npc=npcs and npcs:FindFirstChild('Bartilo')
    if npc and npc:IsA('Model') then point=npc:GetPivot().Position end
    local _,_,hr=body();if not hr then return true end
    if (hr.Position-point).Magnitude>45 then
     -- Stop outside the furniture instead of requiring an exact point inside it.
     moveTo(point+Vector3.new(0,3,-22),token)
     _,_,hr=body()
     if not running(token) or not hr or (hr.Position-point).Magnitude>45 then return true end
    end
    if q then requestQuest(token,'AbandonQuest');if not pause(token,.3) then return true end end
    local accepted,result=requestQuest(token,'StartQuest','BartiloQuest',1)
    if not accepted or result~=0 then status('Bartilo quest not accepted: '..tostring(result));pause(token,1);return true end
    local deadline=os.clock()+3
    repeat
     if not pause(token,.2) then return true end
     q=quest()
    until (q and q.InternalQuestName=='BartiloQuest') or os.clock()>=deadline
    if not q or q.InternalQuestName~='BartiloQuest' then status('Waiting for Bartilo quest confirmation') end
    return true
   end
   battle('Swan Pirate',Vector3.new(970,137,1217),true);return true
  elseif stage==1 then
   battle('Jeremy',Vector3.new(2006,449,853));return true
  elseif stage==2 then
   status('Race V2: freeing the gladiators')
   local _,_,hr=body();if not hr then return true end
   local centre=Vector3.new(-1837,15,1724)
   if (hr.Position-centre).Magnitude>150 then
    if not moveTo(centre+Vector3.new(0,5,0),token) then return true end
   end
   local map=workspace:FindFirstChild('Map');local dress=map and map:FindFirstChild('Dressrosa')
   local plates=dress and dress:FindFirstChild('BartiloPlates')
   if not plates then status('Waiting for puzzle plates to load');pause(token,1);return true end
   -- Release flight before touching plates; never tween across other symbols.
   stopHover();stopStabilize();releaseMovement()
   for i=1,8 do
    local plate=plates:FindFirstChild('Plate'..i)
    local char,h,root=body()
    if not char or not root or not plate or not plate:IsA('BasePart') or not running(token) then return true end
    jumpOutOfSeat(h)
    status('Race V2: puzzle plate '..i..' / 8')
    root.AssemblyLinearVelocity=Vector3.new(0,0,0)
    root.AssemblyAngularVelocity=Vector3.new(0,0,0)
    root.CFrame=CFrame.new(plate.Position)
    if not pause(token,.15) then return true end
    if player.Character~=char or not root.Parent then return true end
    if type(firetouchinterest)=='function' then
     pcall(function() firetouchinterest(root,plate,0) end)
     if not pause(token,.15) then return true end
     pcall(function() firetouchinterest(root,plate,1) end)
    end
    if not pause(token,.25) then return true end
    local checked,progress=requestQuest(token,'BartiloQuestProgress','Bartilo')
    if checked and progress==3 then status('Gladiators freed');return true end
   end
   status('Waiting for puzzle completion; will retry if needed');pause(token,2)
   return true
  elseif stage~=3 then
   status('Race V2: waiting for Bartilo progress');return true
  end
  return false
 end
 function farm.SeaBegin()
  farm.enabled=false;farm.stackFruit=false;farm.autoClick=false
  farm.generation=farm.generation+1;releaseMovement();stopHover();stopStabilize();releaseMobs()
  farm.seaActive=true;currentMode='sea';return farm.generation
 end
 function farm.SeaActive(token) return farm.seaActive and running(token) end
 function farm.SeaGather(primary,token)
  if not farm.SeaActive(token) or not primary or not primary.Parent then return 0 end
  gather(primary,{enemy='Living Zombie'})
  return farm.gathered
 end
 function farm.SeaRelease(token)
  if farm.generation~=token then return end
  releaseMovement();stopHover();stopStabilize();seaHoverRoot=nil;seaStabilizedTarget=nil
 end
 function farm.SeaEnd(token)
  if farm.generation~=token then return end
  farm.SeaRelease(token);farm.seaActive=false;farm.generation=farm.generation+1;currentMode='idle'
 end
 function farm.SeaMove(position,token,keepMoving)
  if not farm.SeaActive(token) then return false end
  local _,h=body()
  if h and h.SeatPart then h.Sit=false;h.Jump=true;task.wait(.3) end
  seaHoverRoot=nil;return moveTo(position,token,keepMoving~=nil,nil,keepMoving)
 end
 function farm.SeaHold(position,token,aim)
  if not farm.SeaActive(token) then return end
  if type(seaHoverRoot)=='table' and seaHoverRoot.nexoFixed and not farm.hoverStuck then seaHoverRoot.Position=position;seaHoverRoot.nexoAim=aim;return end
  local proxy={Parent=workspace,Position=position,nexoFixed=true,nexoAim=aim}
  hoverHeight=0;hoverSide=0;startHover(proxy);seaHoverRoot=proxy;seaStabilizedTarget=nil;seaHoverClearance=nil;seaHoverEvade=nil
 end
 function farm.SeaHover(root,token,clearance,evade)
  if not farm.SeaActive(token) or (seaHoverRoot==root and seaHoverClearance==clearance and seaHoverEvade==evade and not farm.hoverStuck) then return end
  local waterHeight
  pcall(function() waterHeight=require(RS.Util.GetWaterHeightAtLocation) end)
  local orbitStart=os.clock();local lastHealth;local evadeUntil=0
  local proxy=setmetatable({}, {__index=function(_,key)
   if key=='Parent' then return root.Parent end
   if key=='Position' then
    local p=root.Position;local surface=0
    if waterHeight then local ok,y=pcall(waterHeight,p);if ok and type(y)=='number' then surface=y end end
    local raidFruit=farm.raidCombatToken==token and farm.weapon=='Demon Fruit'
    local height=math.max(p.Y+(raidFruit and 3 or farm.weapon=='Gun' and (clearance or 30) or 12),surface+(raidFruit and 3 or clearance or 12))
    if evade and farm.weapon=='Gun' then
     local c=player.Character;local hum=c and c:FindFirstChildOfClass('Humanoid')
     local now=os.clock()
     if hum then
      if lastHealth and hum.Health<lastHealth then evadeUntil=now+3 end
      lastHealth=hum.Health
     end
     local escaping=now<evadeUntil
     local radius=escaping and 72 or 48
     local angle=(now-orbitStart)*.9
     return Vector3.new(p.X+math.cos(angle)*radius,height+(escaping and 40 or 0),p.Z+math.sin(angle)*radius)
    end
    return Vector3.new(p.X,height,p.Z)
   end
  end})
  hoverHeight=0;hoverSide=6;startHover(proxy);seaHoverRoot=root;seaHoverClearance=clearance;seaHoverEvade=evade;seaStabilizedTarget=nil
 end

 local function cloudSkillReady(tool,key)
  local gui=player:FindFirstChild('PlayerGui')
  local main=gui and gui:FindFirstChild('Main')
  local skills=main and main:FindFirstChild('Skills')
  local panel=skills and skills:FindFirstChild(tool.Name)
  local row=panel and panel:FindFirstChild(key.Name)
  if panel and not row then return false end
  if row then
   local cooldown=row:FindFirstChild('Cooldown')
   if cooldown and cooldown:IsA('GuiObject') and (cooldown.Size.X.Scale>.001 or cooldown.Size.X.Offset>1) then return false end
   local requirement=row:FindFirstChild('Level')
   local mastery=tool:FindFirstChild('Level')
   local needed=requirement and requirement:IsA('TextLabel') and tonumber(requirement.Text:match('%d+'))
   if needed and mastery and mastery.Value<needed then return false end
  end
  return true
 end
 farm.SkillReady=cloudSkillReady
 -- Persistent cursor over a stable, tool-grouped queue. Cooldowns never block other tools.
 function farm.CastSkillCycle(state,targetPosition,token)
  local char,h,hr=body()
  if not hr or not running(token) then return false,'Stopped' end
  local busy=char:FindFirstChild('Busy');local stun=char:FindFirstChild('Stun')
  if (busy and busy.Value) or (stun and stun.Value>0) then return false,'Finishing current skill' end
  local tools={}
  for _,container in pairs({char,player:FindFirstChild('Backpack')}) do
   for _,tool in ipairs(container:GetChildren()) do if tool:IsA('Tool') and farm.SkillCategory(tool) and (not state.categories or state.categories[farm.SkillCategory(tool)]) then table.insert(tools,tool) end end
  end
  local queue=farm.SkillQueue(tools)
  if #queue==0 then return false,'Enable skills in Settings > Skill Use' end
  state.used=state.used or {};state.cursor=state.cursor or 0
  local entry
  for _=1,#queue do
   state.cursor=state.cursor%#queue+1
   local candidate=queue[state.cursor];local tool,key=candidate.tool,candidate.key
   local kind=farm.SkillCategory(tool)
   local cooldown=tonumber(char:GetAttribute(kind..key.Name..'Cooldown')) or 0
   if cooldown<=0 and os.clock()>=(state.used[tool.Name..key.Name] or 0) then
    if tool.Parent~=char then h:EquipTool(tool);if not pause(token,.1) then return false,'Stopped' end end
    if cloudSkillReady(tool,key) and farm.SkillAllowed(tool,key.Name) then entry=candidate;break end
   end
  end
  if not entry then return false,'Waiting for skill cooldowns' end
  local tool,key=entry.tool,entry.key
  local point=targetPosition();if not point or not running(token) then return false,'Target finished' end
  local camera=workspace.CurrentCamera;if not camera then return false,'Camera unavailable' end
  local savedType,savedCF,savedFocus=camera.CameraType,camera.CFrame,camera.Focus
  local mouse=tool:FindFirstChild('MousePos');local oldMouse=mouse and mouse:IsA('Vector3Value') and mouse.Value
  local input=game:GetService('VirtualInputManager')
  local function send(method,...)
   local setID=setthreadidentity or setidentity;local getID=getthreadidentity or getidentity
   local old=getID and getID() or 2;if setID then setID(8) end
   local ok,err=pcall(input[method],input,...);if setID then setID(old) end
   if not ok then error(err,0) end
  end
  local function aim()
   local target=targetPosition();if not target or not running(token) then return false end
   camera.CameraType=Enum.CameraType.Scriptable
   camera.CFrame=CFrame.lookAt(hr.Position+Vector3.new(0,8,6),target);camera.Focus=CFrame.new(target)
   if oldMouse and mouse.Parent then mouse.Value=target end
   local p=camera:WorldToViewportPoint(target);local inset=game:GetService('GuiService'):GetGuiInset()
   send('SendMouseMoveEvent',p.X+inset.X,p.Y+inset.Y,game)
   return true
  end
  local pressed=false;local canceled=false
  local connection=RunService.RenderStepped:Connect(function()
   if not running(token) or not targetPosition() then
    canceled=true
    if pressed then pcall(send,'SendKeyEvent',false,key,false,game) end
    return
   end
   pcall(aim)
  end)
  local ok,err=pcall(function()
   if canceled or not targetPosition() or not farm.SkillAllowed(tool,key.Name) or not running(token) then return end
   aura();if not aim() then return end;send('SendKeyEvent',true,key,false,game);pressed=true
   state.used[tool.Name..key.Name]=os.clock()+1
   status('Using '..tool.Name..' '..key.Name);pause(token,.2)
  end)
  pcall(send,'SendKeyEvent',false,key,false,game)
  if pressed and running(token) then
   pause(token,.15)
   local deadline=os.clock()+4
   while running(token) and targetPosition() and busy and busy.Value and os.clock()<deadline do pause(token,.05) end
  end
  if pressed and state.confirmSeconds then
   local confirmUntil=os.clock()+state.confirmSeconds
   while running(token) and targetPosition() and os.clock()<confirmUntil do pause(token,.05) end
  end
  connection:Disconnect()
  pcall(function() camera.CameraType=savedType;camera.CFrame=savedCF;camera.Focus=savedFocus;if oldMouse and mouse.Parent then mouse.Value=oldMouse end end)
  return ok and pressed,ok and ('Used '..tool.Name..' '..key.Name) or tostring(err)
 end

 local cloudSkillAttempts=0;local attemptedCloud=nil;local cloudAttemptStarted=0;local cannonReadyAt=0;local cloudSkillUsed={}
 function farm.HoverCloud(cloud,token)
  if not running(token) or not cloud or not cloud.Parent then return end
  local proxy={Parent=cloud.Parent,Position=cloud.Position+Vector3.new(0,cloud.Size.Y*.5+12,0)}
  hoverHeight=0;hoverSide=0;startHover(proxy)
 end
 function farm.BreakCloud(cloud,token)
  local char,h,hr=body()
  if not hr or not running(token) or not cloud or not cloud.Parent then return false end
  if attemptedCloud~=cloud then attemptedCloud=cloud;cloudSkillAttempts=0;cloudAttemptStarted=os.clock() end
      local tools={}
      local function usable(t)
       if not t:IsA('Tool') or fishingTool(t) then return false end
       local kind=t:GetAttribute('WeaponType') or t.ToolTip
       return kind=='Melee' or kind=='Sword' or kind=='Blox Fruit' or kind=='Demon Fruit' or kind=='Gun'
      end
      for _,container in pairs({char,player:FindFirstChild('Backpack')}) do
       for _,candidate in ipairs(container:GetChildren()) do if usable(candidate) then table.insert(tools,candidate) end end
      end
      table.sort(tools,function(a,b) return a.Name<b.Name end)
      local cannon,useCannon=skyCannonFallback(tools,token,cloudSkillAttempts>=6 or os.clock()-cloudAttemptStarted>=12)
      if not running(token) then return false end
      if useCannon and not cannon then pause(token,.05);return false end
      useCannon=cannon~=nil and os.clock()>=cannonReadyAt
      local queue={}
      for _,candidate in ipairs(farm.SkillQueue(tools)) do if cloudSkillReady(candidate.tool,candidate.key) and os.clock()>=(cloudSkillUsed[candidate.tool.Name..candidate.key.Name] or 0) then table.insert(queue,candidate) end end
      if not useCannon and #queue==0 then status('Switching to a ready cloud attack');pause(token,.05);return false end
      local entry=not useCannon and queue[cloudSkillAttempts%#queue+1]
      local tool=useCannon and cannon or entry.tool;local skillKey=entry and entry.key
      if tool.Parent~=char then h:EquipTool(tool);if not pause(token,.08) then return false end end
      if player.Character~=char or not running(token) then return false end
      cloudSkillAttempts=cloudSkillAttempts+1
      status('Breaking charged cloud: '..tool.Name..' '..(useCannon and 'M1' or skillKey.Name))
      local camera=workspace.CurrentCamera;local savedCamera=camera.CFrame
      local savedType=camera.CameraType;local savedFocus=camera.Focus
      local aimPoint=cloud.Position
      local mousePosition=tool:FindFirstChild('MousePos')
      local savedMouse=mousePosition and mousePosition:IsA('Vector3Value') and mousePosition.Value
      local input=game:GetService('VirtualInputManager')
      local function sendInput(method,...)
       local setIdentity=setthreadidentity or setidentity
       local getIdentity=getthreadidentity or getidentity
       local previous=getIdentity and getIdentity() or 2
       if setIdentity then setIdentity(8) end
       local ok,err=pcall(input[method],input,...)
       if setIdentity then setIdentity(previous) end
       if not ok then error(tostring(err),0) end
      end
      local function aimDown()
       if not camera.Parent or not hr.Parent then return end
       camera.CameraType=Enum.CameraType.Scriptable
       camera.CFrame=CFrame.lookAt(hr.Position+Vector3.new(0,12,8),aimPoint)
       camera.Focus=CFrame.new(aimPoint)
       if savedMouse then mousePosition.Value=aimPoint end
       local projected=camera:WorldToViewportPoint(aimPoint)
       local inset=game:GetService('GuiService'):GetGuiInset()
       sendInput('SendMouseMoveEvent',projected.X+inset.X,projected.Y+inset.Y,game)
      end
      local aimConnection=RunService.RenderStepped:Connect(function() pcall(aimDown) end)
      local pressed,inputError=pcall(function()
       if not useCannon and not farm.SkillAllowed(tool,skillKey.Name) then return end
       aimDown()
       if useCannon then
        local cooldown=tool:FindFirstChild('Cooldown')
        local shotDelay=cooldown and cooldown:IsA('NumberValue') and tonumber(cooldown.Value) or 1.5
        shotDelay=math.clamp(shotDelay+.15,.5,5)
        cannonReadyAt=os.clock()+shotDelay
        local p=camera:WorldToViewportPoint(aimPoint);local inset=game:GetService('GuiService'):GetGuiInset()
        sendInput('SendMouseButtonEvent',p.X+inset.X,p.Y+inset.Y,0,true,game,0)
        pause(token,.12)
        sendInput('SendMouseButtonEvent',p.X+inset.X,p.Y+inset.Y,0,false,game,0)
       else
        cloudSkillUsed[tool.Name..skillKey.Name]=os.clock()+.6
        sendInput('SendKeyEvent',true,skillKey,false,game)
        pause(token,.1)
       end
      end)
      pcall(function()
       if useCannon then
        local p=camera:WorldToViewportPoint(aimPoint);local inset=game:GetService('GuiService'):GetGuiInset()
        sendInput('SendMouseButtonEvent',p.X+inset.X,p.Y+inset.Y,0,false,game,0)
       else sendInput('SendKeyEvent',false,skillKey,false,game) end
      end)
      if running(token) then pause(token,.05) end
      aimConnection:Disconnect()
      pcall(function() camera.CameraType=savedType;camera.CFrame=savedCamera;camera.Focus=savedFocus;if savedMouse then mousePosition.Value=savedMouse end end)
      if not pressed then status('Cloud input failed: '..tostring(inputError));return false end
      if not running(token) then return false end
      if player.Character~=char or not hr.Parent then return false end

  return true
 end
 function farm.SeaAttackPart(model,part,token)
  if not farm.SeaActive(token) or not model or not model.Parent or not part or not part.Parent then return false end
  local tool=equip();if not tool then return false end
  aura();attack(tool,model,{},token,part);return true
 end
 function farm.SeaAttack(enemy,token)
  if not farm.SeaActive(token) then return false,'Stopped' end
  local tool=equip();if not tool then return false,'Obtain or select '..farm.weapon end
  if farm.weapon=='Demon Fruit' then
   if seaStabilizedTarget~=enemy then stabilizeTarget(enemy,token);seaStabilizedTarget=enemy end
  elseif seaStabilizedTarget then stopStabilize();seaStabilizedTarget=nil end
  aura();attack(tool,enemy,{},token)
  return farm.attackMessage==nil or farm.attackMessage=='Gun auto attack',farm.attackMessage
 end
 function farm.Destroy()
  farm.seaActive=false;farm.enabled=false;farm.stackFruit=false;farm.autoClick=false;farm.generation=farm.generation+1
  releaseMovement();stopHover();stopStabilize();releaseMobs()
 end
 function farm.Snapshot()
  local _,h,hr=body();local q=quest()
  return {m1State=farm.m1State,movementRecoveries=farm.movementRecoveries or 0,mode=farm.mode,material=farm.material,materialKills=farm.materialKills,stabilized=farm.stabilized or 0,attacks=farm.attacks or 0,attackMessage=farm.attackMessage,weapon=farm.weapon,tweenSpeed=farm.tweenSpeed,autoClick=farm.autoClick,stackFruit=farm.stackFruit,stackMessage=farm.stackMessage,recoveries=farm.recoveries,bringMobs=farm.bringMobs,mobLimit=farm.mobLimit,gathered=farm.gathered,maxGathered=farm.maxGathered,hoverHeight=hoverHeight,enabled=farm.enabled,message=farm.message,completed=farm.completed,target=farm.target,questId=farm.questId,quest=q,health=h and h.Health,position=hr and {hr.Position.X,hr.Position.Y,hr.Position.Z},events=table.clone(farm.events)}
 end
 return farm
end

local function createAutoStats(onUpdate)
 local manager={selected={},message='Select stats to spend points',allocated={}}
 local keys={'Melee','Defense','Sword','Gun','Demon Fruit'}
 local display={['Demon Fruit']='Fruit'}
 local stopped=false
 local changedAt=0
 local cursor=0
 local blocked={}
 local pending=false
 local batchRemaining={};local batchAmount=0
 local function values(key)
  local data=player:FindFirstChild('Data')
  local points=data and data:FindFirstChild('Points')
  local stats=data and data:FindFirstChild('Stats')
  local stat=stats and stats:FindFirstChild(key)
  local level=stat and stat:FindFirstChild('Level')
  return points and points.Value or 0,level and level.Value or nil
 end
 local function update(message)
  manager.message=message
  if alive and not stopped then onUpdate(message,manager.selected,values('Melee')) end
 end
 local function nextKey()
  for step=1,#keys do
   local index=(cursor+step-1)%#keys+1
   local key=keys[index]
   if manager.selected[key] and not blocked[key] then return key,index end
  end
 end
 function manager.Select(key,value)
  if not table.find(keys,key) then return end
  manager.selected[key]=value==true;blocked[key]=nil;changedAt=os.clock();batchRemaining={}
  update('Updating selection...')
 end
 function manager.Snapshot()
  return {selected=table.clone(manager.selected),points=values('Melee'),message=manager.message,allocated=table.clone(manager.allocated),pending=pending}
 end
 function manager.Destroy() stopped=true end
 task.spawn(function()
  while alive and not stopped do
   task.wait(.35)
   if not alive or stopped then break end
   local key,index=nextKey()
   local points,beforeLevel=values(key or 'Melee')
   if os.clock()-changedAt<1 then
    -- A short debounce lets the player tick several boxes before spending starts.
   elseif not key then
    local any=false;for _,v in pairs(manager.selected) do if v then any=true end end
    update(any and 'Selected stats unavailable; retick to retry' or 'Select stats to spend points')
   elseif points<1 then update('Waiting for new points')
   elseif pending then update('Waiting for stat confirmation')
   elseif beforeLevel==nil then blocked[key]=true;update('Stat data unavailable')
   else
    local remotes=game.ReplicatedStorage:FindFirstChild('Remotes')
    local remote=remotes and remotes:FindFirstChild('CommF_')
    if not remote then update('Stat request unavailable') else
     pending=true;local finished,ok,reply=false,false,nil
     if not next(batchRemaining) then
      local selectedCount=0
      for _,k in ipairs(keys)do if manager.selected[k] and not blocked[k]then batchRemaining[k]=true;selectedCount=selectedCount+1 end end
      batchAmount=math.max(1,math.floor(points/math.max(1,selectedCount)))
     end
     local amount=math.min(math.floor(points),batchAmount)
     batchRemaining[key]=nil
     update('Adding to '..(display[key] or key))
     task.spawn(function()
      ok,reply=pcall(function() return remote:InvokeServer('AddPoint',key,amount) end)
      finished=true
     end)
     local deadline=os.clock()+6
     while alive and not stopped and not finished and os.clock()<deadline do task.wait(.1) end
     if not finished then
      update('Stat request delayed; waiting before spending more')
      while alive and not stopped and not finished do task.wait(.5) end
     end
     if not alive or stopped then break end
     if finished then
      pending=false
      local confirmation=os.clock()+2
      local _,afterLevel=values(key)
      while alive and not stopped and ok and afterLevel==beforeLevel and os.clock()<confirmation do
       task.wait(.1);_,afterLevel=values(key)
      end
      if afterLevel and afterLevel>beforeLevel then
       cursor=index;manager.allocated[key]=(manager.allocated[key] or 0)+(afterLevel-beforeLevel)
       update('Points shared between checked stats')
      else
       blocked[key]=true;update((display[key] or key)..': capped or request not accepted')
      end
     else
      update('Stat request timed out; auto stats paused')
      break -- Never overlap a possibly pending investment with another one.
     end
    end
   end
  end
 end)
 return manager
end

-- Sea-event coordinator. Uses the existing character mover/combat, one owner at a time.
local function createSeaEvent(farm,onStatus)
 local RS=game:GetService('ReplicatedStorage')
 local sea={enabled=false,zone=nil,selected={},boat='Guardian',boatSpeed=120,continuous=false,resetDistance=false,message='Off',phase='idle',distanceKm=0,kills=0}
 sea.group={enabled=false,count=2,owner=player.UserId,role='Driver',members={}}
 local function grouped() return sea.group.enabled and not sea.searchIsland end
 local function passenger() return grouped() and sea.group.role=='Passenger' end
 local generation=0;local token;local boat;local seat;local steering;local origin
 local rememberedBoat;local rememberedPosition;local rememberedOwner;local rememberedCharacter;local resumeBoat=false
 local sailingCollisions={}
 local collisionScanAt=0;local collisionBoat
 local resetPending=false;local forceNewBoat=false;local spawnReady=false;local currentTarget;local lastCharacter
 local TIKI=Vector3.new(-16928.9277,7.766,434.62)
 local function report(message) sea.message=message;onStatus(sea) end
 local function active(g) return alive and sea.enabled and g==generation and farm.SeaActive(token) end
 local function body()
  local c=player.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
  if h and h.Health>0 and r then return c,h,r end
 end
 local function flat(v) return Vector3.new(v.X,0,v.Z) end
 local function boatAlive(b)
  if not b or not b.Parent then return false end
  local hp=b:FindFirstChild('Humanoid')
  return not hp or (hp:IsA('Humanoid') and hp.Health>0) or (hp:IsA('ValueBase') and tonumber(hp.Value) and hp.Value>0)
 end
 local function stopDrive()
  if steering then steering:Disconnect();steering=nil end
  if not passenger() and seat and seat.Parent then seat.ThrottleFloat=0;seat.SteerFloat=0 end
  for part,value in pairs(sailingCollisions) do if part.Parent then part.CanCollide=value end end
  sailingCollisions={};collisionScanAt=0;collisionBoat=nil
 end
 -- Run before physics on every participating client, including passengers.
 connect(game:GetService('RunService').PreSimulation,function()
  local _,hum=body()
  local riding=sea.enabled and boatAlive(boat) and hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(boat)
  local now=os.clock()
  if riding and boat==collisionBoat and now<collisionScanAt then
   for part in pairs(sailingCollisions) do if part.Parent then if part.CanCollide then part.CanCollide=false end else sailingCollisions[part]=nil end end
   return
  end
  if not riding and next(sailingCollisions)==nil then return end
  collisionBoat=riding and boat or nil;collisionScanAt=now+.5
  local keep={}
  if riding then
   local containers={boat}
   for _,p in ipairs(game:GetService('Players'):GetPlayers()) do
    local ch=p.Character;local h=ch and ch:FindFirstChildOfClass('Humanoid')
    if h and h.SeatPart and h.SeatPart:IsDescendantOf(boat) then table.insert(containers,ch) end
   end
   for _,container in ipairs(containers) do for _,part in ipairs(container:GetDescendants()) do
    if part:IsA('BasePart') then
     keep[part]=true
     if sailingCollisions[part]==nil then sailingCollisions[part]=part.CanCollide end
     part.CanCollide=false
    end
   end end
  end
  for part,value in pairs(sailingCollisions) do
   if not keep[part] then if part.Parent then part.CanCollide=value end;sailingCollisions[part]=nil end
  end
 end)
 local function ownedBoat(nearPosition,maxDistance,excluded)
  local folder=workspace:FindFirstChild('Boats');if not folder then return end
  local ownerId=grouped() and sea.group.owner or player.UserId
  local ownerPlayer=game:GetService('Players'):GetPlayerByUserId(ownerId)
  local ch=ownerPlayer and ownerPlayer.Character
  local hum=ch and ch:FindFirstChildOfClass('Humanoid')
  local root=ch and ch:FindFirstChild('HumanoidRootPart')
  local reference=nearPosition or (root and root.Position)
  local best,bestDistance
  for _,b in ipairs(folder:GetChildren()) do
   local owner=b:FindFirstChild('Owner');local bs=b:FindFirstChild('VehicleSeat')
   if not (excluded and excluded[b]) and owner and owner:IsA('ObjectValue') and owner.Value and owner.Value.UserId==ownerId and boatAlive(b) and bs then
    local d=reference and (bs.Position-reference).Magnitude or 0
    if not nearPosition or d<=(maxDistance or 1000) then
     if hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(b) then return b end
     if not bestDistance or d<bestDistance then best=b;bestDistance=d end
    end
   end
  end
  return best
 end
 local function call(g,...)
  local args=table.pack(...);local finished=false;local ok,result
  task.spawn(function() ok,result=pcall(function() return RS.Remotes.CommF_:InvokeServer(table.unpack(args,1,args.n)) end);finished=true end)
  local deadline=os.clock()+10
  repeat task.wait(.1) until finished or not active(g) or os.clock()>deadline
  if not active(g) then return false,'Canceled' end
  if not finished then error('Server request timed out; stopped to avoid duplicate purchases') end
  return ok,result
 end
 local function dealer()
  local npcs=workspace:FindFirstChild('NPCs');local best,d
  if npcs then for _,v in ipairs(npcs:GetChildren()) do
   if v.Name=='Boat Dealer' and v:IsA('Model') then local p=v:GetPivot().Position;local n=(p-TIKI).Magnitude
    if n<2000 and (not d or n<d) then best=p;d=n end
   end
  end end
  return best or TIKI
 end
 local function acquire(g)
  if resumeBoat and not forceNewBoat then
   local ownerId=grouped() and sea.group.owner or player.UserId
   if rememberedOwner==ownerId and rememberedCharacter==player.Character then
    if boatAlive(rememberedBoat) then boat=rememberedBoat
    elseif rememberedPosition then
     report('Returning to previous boat')
     if not farm.SeaMove(rememberedPosition+Vector3.new(0,5,0),token) or not active(g) then return false end
     boat=ownedBoat(rememberedPosition,1500)
    end
    if boat then seat=boat:FindFirstChild('VehicleSeat') or boat:FindFirstChildWhichIsA('VehicleSeat',true);if seat then resumeBoat=false;return true end end
   end
   resumeBoat=false
  end
  if grouped() then
   local _,_,root=body()
   if not forceNewBoat then boat=passenger() and ownedBoat() or (root and ownedBoat(root.Position,1000)) end
   if boat then seat=boat:FindFirstChild('VehicleSeat');return true end
   if passenger() or sea.group.owner~=player.UserId then sea.phase='waiting';report('Waiting for the selected owner to provide a boat');task.wait(.5);return false end
  end
  sea.phase='buying';report('Travelling to Tiki')
  if not farm.SeaMove(dealer()+Vector3.new(0,4,0),token) or not active(g) then return false end
  origin=dealer()
  if not spawnReady then
   local ok,result=call(g,'SetSpawnPoint')
   spawnReady=ok and result~=nil and result~=0 and result~=-1
  end
  boat=not forceNewBoat and ownedBoat(origin,1000) or nil
  if not boat then
   report('Buying '..sea.boat)
   local id=sea.boat=='Beast Hunter' and 'Beast Hunter' or sea.boat=='Brigade' and (player.Team and player.Team.Name=='Marines' and 'MarineBrigade' or 'PirateBrigade') or 'Guardian'
   local previous={};local folder=workspace:FindFirstChild('Boats');if folder then for _,b in ipairs(folder:GetChildren()) do previous[b]=true end end
   local ok,result=call(g,'BuyBoat',id)
   if not ok or result~=1 then
    local messages={[0]='Not enough money',[2]='Boat spawn blocked',[3]='Boat unavailable',[4]='Boat locked'}
    error(messages[result] or ('Boat purchase failed: '..tostring(result)))
   end
   local untilTime=os.clock()+8
   repeat boat=ownedBoat(origin,1000,previous);if boat then break end;boat=nil;task.wait(.2) until not active(g) or os.clock()>untilTime
  end
  if not boat then error('Purchased boat did not appear') end
  seat=boat:FindFirstChild('VehicleSeat')
  if not seat then error('Boat steering seat unavailable') end
  resetPending=false;forceNewBoat=false
  return true
 end
 local function board(g)
  sea.phase='boarding';report('Boarding '..boat.Name)
  farm.SeaRelease(token)
  local _,h=body();if not h or not boatAlive(boat) then return false end
  local targetSeat=seat
  if passenger() then
   if h.SeatPart and h.SeatPart~=seat and h.SeatPart:IsDescendantOf(boat) then return true end
   local seats={}
   for _,v in ipairs(boat:GetDescendants()) do if (v:IsA('Seat') or v:IsA('VehicleSeat')) and v~=seat and not v.Occupant then table.insert(seats,v) end end
   table.sort(seats,function(a,b) return a:GetFullName()<b:GetFullName() end)
   targetSeat=#seats>0 and seats[player.UserId%#seats+1] or nil
   if not targetSeat then report('Waiting for a free passenger seat');task.wait(.5);return false end
  end
  h.Sit=false
  if not farm.SeaMove(targetSeat.Position+Vector3.new(0,3,0),token) then return false end
  for _=1,12 do
   if not active(g) or not boatAlive(boat) then return false end
   local _,hum=body();if not hum then return false end
   if targetSeat.Occupant and targetSeat.Occupant~=hum then return false end
   targetSeat:Sit(hum);task.wait(.25)
   if hum.SeatPart==targetSeat then return true end
  end
  error('Could not board the boat')
 end
 local function groupReady()
  if not grouped() then return true end
  local aboard=0
  for key,value in pairs(sea.group.members) do if value then
   local p=game:GetService('Players'):GetPlayerByUserId(tonumber(key) or 0)
   local h=p and p.Character and p.Character:FindFirstChildOfClass('Humanoid')
   if h and h.Health>0 and h.SeatPart and h.SeatPart:IsDescendantOf(boat) then aboard=aboard+1 end
  end end
  sea.group.aboard=aboard
  return aboard>=sea.group.count
 end
 local names={terrorshark='Terrorshark',shark='Shark',seabeast='Sea Beast',piranha='Piranha'}
 local function eventKind(model)
  local owner=model:FindFirstChild('Owner')
  if model==boat or (owner and owner:IsA('ObjectValue') and owner.Value~=nil) then return nil end
  local boatName=model.Name:lower():gsub('[%s%-_]','')
  if boatName=='piratebasic' or boatName=='piratebrigade' or boatName=='fishboat' or boatName=='pirateboat' then return 'Kill Boats' end
  local n=model.Name:lower():gsub('%[.-%]',''):gsub('[%s%-_]','')
  return names[n] or (n:match('^seabeast%d*$') and 'Sea Beast')
 end
 local function health(model)
  local h=model:FindFirstChildOfClass('Humanoid');if h then return h.Health end
  local v=model:FindFirstChild('Health') or model:FindFirstChild('Humanoid')
  if v and v:IsA('ValueBase') then return tonumber(v.Value) end
  return tonumber(model:GetAttribute('Health'))
 end
 local function targetRoot(model)
  return model:FindFirstChild('Head') or model:FindFirstChild('HumanoidRootPart') or model:FindFirstChild('RootPart') or model:FindFirstChild('Engine') or model:FindFirstChild('VehicleSeat') or model.PrimaryPart
 end
 local function scan()
  local _,_,r=body();if not r then return end
  local best,kind,distance
  for _,folderName in ipairs({'Enemies','SeaBeasts','Boats'}) do
   local folder=workspace:FindFirstChild(folderName)
   if folder then for _,m in ipairs(folder:GetChildren()) do
    if m:IsA('Model') then local k=eventKind(m);local hp=health(m);local root=targetRoot(m)
     if k and sea.selected[k] and root and root:IsA('BasePart') and (not hp or hp>0) then
      local d=(root.Position-(grouped() and seat and seat.Parent and seat.Position or r.Position)).Magnitude
      if d<1800 and (not distance or d<distance) then best=m;kind=k;distance=d end
     end
    end
   end end
  end
  return best,kind
 end
 local islandNames={['Mirage Island']={mirageisland=true,mysticisland=true},['Kitsune Island']={kitsuneisland=true},['Prehistoric Island']={prehistoricisland=true}}
 local function islandPresent()
  local aliases=islandNames[sea.searchIsland];if not aliases then return end
  local originFolder=workspace:FindFirstChild('_WorldOrigin')
  for _,folder in pairs({workspace:FindFirstChild('Map'),workspace,originFolder and originFolder:FindFirstChild('Locations')}) do
   for _,object in ipairs(folder:GetChildren()) do
    local name=object.Name:lower():gsub('[^%a]','')
    if aliases[name] and (object:IsA('Model') or object:IsA('BasePart')) then return object end
   end
  end
 end
 local function islandBounds(island)
  if island:IsA('Model') then local cf,size=island:GetBoundingBox();return cf.Position,size end
  return island.Position,island.Size
 end
 local function solidLanding(island,highest)
  local center,size=islandBounds(island)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={island};params.RespectCanCollide=true
  local top=center.Y+size.Y*.5+100;local depth=size.Y+300
  local best
  local function sample(x,z)
   local hit=workspace:Raycast(Vector3.new(x,top,z),Vector3.new(0,-depth,0),params)
   if hit and (not best or hit.Position.Y>best.Y) then best=hit.Position end
  end
  sample(center.X,center.Z)
  if highest then
   for x=-4,4 do for z=-4,4 do sample(center.X+size.X*x/9,center.Z+size.Z*z/9) end end
   for _,part in ipairs(island:GetDescendants()) do
    if part:IsA('BasePart') and part.CanCollide and part.Transparency<1 then sample(part.Position.X,part.Position.Z) end
   end
  end
  return (best or center)+Vector3.new(0,5,0)
 end
 local function shrinePosition(island)
  local center=islandBounds(island)
  local function point(object)
   if object:IsA('BasePart') then return object.Position end
   if object:IsA('Model') then return object:GetPivot().Position end
  end
  local best,distance
  local function consider(object)
   local name=object.Name:lower():gsub('[^%a]','')
   if name=='shrine' or name=='kitsuneshrine' or name=='bluemoonshrine' then
    local p=point(object)
    if p and (p-center).Magnitude<3000 then local d=(p-center).Magnitude;if not distance or d<distance then best=p;distance=d end end
   end
  end
  for _,object in ipairs(island:GetDescendants()) do consider(object) end
  local npcs=workspace:FindFirstChild('NPCs');if npcs then for _,object in ipairs(npcs:GetChildren()) do consider(object) end end
  if not best then pcall(function()
   for _,name in ipairs({'Kitsune Shrine','Blue Moon Shrine','BlueMoonShrine'}) do
    for _,npc in ipairs(require(RS.NPCManager).getNPCsByName(name)) do
     local model=npc:getModel();local p=model and model:GetPivot().Position
     if p and p.Y>-900 and (p-center).Magnitude<3000 then best=p;return end
    end
   end
  end) end
  return best and best+Vector3.new(0,4,7)
 end
 local function finishIsland(g)
  if not sea.searchIsland then return false end
  local island=islandPresent();if not island then return false end
  local found=sea.searchIsland;stopDrive();sea.phase='island';report(found..' found — leaving boat')
  local _,hum=body()
  if hum then
   hum.Sit=false;hum.Jump=true;hum:ChangeState(Enum.HumanoidStateType.Jumping)
   local deadline=os.clock()+2
   while active(g) and hum.SeatPart and os.clock()<deadline do hum.Sit=false;hum.Jump=true;task.wait(.1) end
  end
  if not active(g) then return true end
  -- Mirage goes straight to its highest loaded solid point, without a center stop.
  local arrived=false
  if found=='Mirage Island' then
   if not island:IsA('Model') then
    report('Loading Mirage peak')
    pcall(function()player:RequestStreamAroundAsync(island.Position,5)end)
    if not active(g) then return true end
    island=islandPresent()
   end
   if not island or not island:IsA('Model') then report('Waiting for Mirage geometry to load');return true end
  else
   local landing=sea.IslandLanding and sea.IslandLanding(found,island) or solidLanding(island,false)
   arrived=farm.SeaMove(landing,token)
   if not active(g) then return true end
  end
  local destination;local detail;local deadline=os.clock()+8
  repeat
   island=islandPresent()
   if not island then break end
   if found=='Prehistoric Island' then
    destination=sea.IslandLanding and sea.IslandLanding(found,island);detail='Prehistoric Island relic';if destination then break end
   elseif found=='Mirage Island' then
    if island:IsA('Model') then destination=solidLanding(island,true);detail='Mirage Island highest solid point';break end
   else destination=shrinePosition(island);detail='Kitsune Shrine';if destination then break end end
   task.wait(.25)
  until not active(g) or os.clock()>=deadline
  if not active(g) then return true end
  if destination then arrived=farm.SeaMove(destination,token)
  elseif found=='Mirage Island' and island then detail='Mirage Island center'
  else arrived=false end
  if not active(g) then return true end
  arrived=arrived and island and island.Parent~=nil
  if boatAlive(boat) and seat then rememberedBoat=boat;rememberedPosition=seat.Position;rememberedOwner=grouped() and sea.group.owner or player.UserId;rememberedCharacter=player.Character end
  farm.SeaEnd(token);generation=generation+1;sea.enabled=false;sea.phase='found'
  report(arrived and ('Arrived at '..detail) or (found=='Kitsune Island' and 'Island found; shrine not reached — check loaded map' or 'Island disappeared or arrival was not confirmed'))
  if sea.OnIslandFound then sea.OnIslandFound(found,arrived==true) end
  return true
 end
 local thresholds={80,160,240,300,400,500}
 local function direction(position)
  local radial=flat(position-origin)
  -- Tiki's sea-event route is west. A boat east of the dock must not sail inland.
  local outward=radial.X < -300 and radial.Unit or Vector3.new(-1,0,0)
  if (sea.continuous and not sea.searchIsland) or sea.searchIsland=='Prehistoric Island' then return outward end
  local raw=tonumber(player:GetAttribute('DangerLevel'))
  if not raw then error('Waiting for the game danger-level data') end
  local zone=sea.searchIsland=='Kitsune Island' and 6 or sea.searchIsland=='Mirage Island' and 5 or sea.zone
  local low=thresholds[zone];local high=thresholds[zone+1] or 650
  local mid=(low+high)/2
  -- Keep moving along the zone boundary, correcting inward/outward as danger changes.
  local correction=math.clamp((mid-raw)/math.max(15,(high-low)/3),-1,1)
  local tangent=Vector3.new(-outward.Z,0,outward.X)
  if raw<low-15 then return outward end
  if raw>high+15 then return -outward end
  return (tangent+outward*correction).Unit
 end
 local function patrol(g)
  if grouped() then
   while active(g) and boatAlive(boat) do
    if passenger() then local preferred=ownedBoat();if preferred and preferred~=boat then return end end
    local target,kind=scan();if target then return target,kind end
    local _,h=body();if not h or not h.SeatPart or not h.SeatPart:IsDescendantOf(boat) then return end
    if not passenger() and groupReady() then break end
    sea.phase=passenger() and 'riding' or 'waiting'
    report(passenger() and 'Riding with selected boat owner' or ('Waiting for friends: '..tostring(sea.group.aboard or 0)..' / '..sea.group.count))
    task.wait(.2)
   end
   if not active(g) or not boatAlive(boat) then return end
  end
  sea.phase='patrol';report(sea.searchIsland and ('Searching for '..sea.searchIsland..(sea.searchIsland=='Kitsune Island' and ' — Zone 6 / full moon' or sea.searchIsland=='Prehistoric Island' and ' — Zone 6' or ' — Zone 5')) or sea.continuous and 'Searching for selected events' or ('Patrolling zone '..sea.zone))
  local desired=direction(seat.Position);local errorMessage
  local directionNow=flat(seat.CFrame.LookVector).Unit
  steering=game:GetService('RunService').Heartbeat:Connect(function(dt)
   if not active(g) or not boatAlive(boat) or not seat.Parent then return end
   local char,hum=body();if not char or hum.SeatPart~=seat then return end
   seat.ThrottleFloat=0;seat.SteerFloat=0
   local heading=math.atan2(directionNow.Z,directionNow.X)
   local targetHeading=math.atan2(desired.Z,desired.X)
   local turn=math.atan2(math.sin(targetHeading-heading),math.cos(targetHeading-heading))
   heading=heading+turn*(1-math.exp(-3*dt))
   directionNow=Vector3.new(math.cos(heading),0,math.sin(heading))
   local step=directionNow*sea.boatSpeed*math.min(dt,.05)
   local nextSeat=CFrame.lookAt(seat.Position+step,seat.Position+step+directionNow)
   local offset=seat.CFrame:ToObjectSpace(boat:GetPivot())
   boat:PivotTo(nextSeat*offset)
   seat.AssemblyLinearVelocity=Vector3.zero;seat.AssemblyAngularVelocity=Vector3.zero
   local velocity=seat:FindFirstChildOfClass('BodyVelocity');if velocity then velocity.Velocity=Vector3.zero end
   local gyro=seat:FindFirstChildOfClass('BodyGyro');if gyro then gyro.CFrame=nextSeat.Rotation end
  end)
  while active(g) and boatAlive(boat) do
   local _,h=body();if not h or h.SeatPart~=seat then break end
   sea.distanceKm=flat(seat.Position-origin).Magnitude/10000 -- game compass uses 10 studs per metre
   if finishIsland(g) then return end
   local target,kind;if not sea.searchIsland then target,kind=scan() end;if target then stopDrive();return target,kind end
   if grouped() and not groupReady() then break end
   if not sea.searchIsland and sea.resetDistance and sea.distanceKm>=10 then resetPending=true;break end
   local ok,value=pcall(direction,seat.Position);if not ok then errorMessage=value;break end;desired=value
   onStatus(sea);task.wait(.2)
  end
  stopDrive()
  if errorMessage then error(errorMessage) end
 end
 local function combat(g,target,kind)
  sea.phase='combat';currentTarget=target;stopDrive()
  local _,h=body();if not h then return end;h.Sit=false;h.Jump=true;task.wait(.25)
  local root=targetRoot(target);if not root then return end
  local hp=health(target);local lastHP=hp;local damageAt=os.clock()
  report('Fighting '..kind)
  while active(g) and target.Parent and root.Parent and (not hp or hp>0) do
   if not boatAlive(boat) then resetPending=true end
   local _,hum,r=body();if not hum then break end
   if not sea.selected[kind] then break end
   if kind=='Sea Beast' and farm.weapon~='Demon Fruit' and farm.weapon~='Gun' then error('Choose Fruit or Gun for Sea Beast') end
   -- The hover follows the living target every simulation step, including during approach.
   local clearance=farm.weapon=='Gun' and (kind=='Terrorshark' and 180 or 30) or (kind=='Sea Beast' and 22 or 12)
   farm.SeaHover(root,token,clearance,farm.weapon=='Gun' and kind=='Terrorshark')
   local ok,message=farm.SeaAttack(target,token)
   if not ok then report(message or ('Fighting '..kind)) else report('Fighting '..kind) end
   hp=health(target)
   if hp and lastHP and hp<lastHP then damageAt=os.clock() end
   lastHP=hp
   local gap=r.Position-root.Position
   local reach=farm.weapon=='Gun' and 400 or 28
   if (kind=='Sea Beast' and farm.weapon=='Demon Fruit' and flat(gap).Magnitude or gap.Magnitude)>reach then damageAt=os.clock() end
   if os.clock()-damageAt>20 then error('No confirmed damage on '..kind..'; check selected weapon') end
   task.wait(kind=='Terrorshark' and farm.weapon=='Demon Fruit' and .03 or .06)
  end
  currentTarget=nil
  if hp and hp<=0 then sea.kills=sea.kills+1 end
 end
 local function reset(g)
  stopDrive();farm.SeaRelease(token)
  if not active(g) then return false end
  -- Reset even when this run reused a boat without visiting the dealer first.
  sea.phase='reset';report(spawnReady and 'Respawning at Tiki' or 'Respawning before buying a new boat')
  local old,h=body();if h then h.Health=0 end
  local deadline=os.clock()+25
  repeat task.wait(.25);local c=body();if c and c~=old then boat=nil;seat=nil;resetPending=false;return true end until not active(g) or os.clock()>deadline
  if active(g) then error('Waiting for character respawn') end
 end
 function sea.SetEnabled(value)
  value=value==true;if value==sea.enabled then return end
  if value then
   if grouped() then
    local n=0;for _,v in pairs(sea.group.members) do if v then n=n+1 end end
    if n<2 or n>5 or not sea.group.members[tostring(player.UserId)] or not sea.group.members[tostring(sea.group.owner)] then report('Choose 2–5 players including yourself and the boat owner');return false end
    sea.group.count=n
    if sea.group.role=='Driver' and sea.group.owner~=player.UserId then report('Choose yourself as boat owner when driving');return false end
    if passenger() and sea.group.owner==player.UserId then report('A passenger must choose the driver as boat owner');return false end
   end
   if (game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId)~=7449423635 then report('Travel to Sea 3 first');return false end
   if sea.searchIsland and sea.BeforeIslandSearch then local ok,message=sea.BeforeIslandSearch();if not ok then report(message);return false end end
   if not sea.searchIsland and not next(sea.selected) then report('Select at least one event');return false end
   if not sea.searchIsland and not sea.continuous and not sea.zone then report('Select a zone or enable continuous sailing');return false end
  end
  if not value and boatAlive(boat) then
   local bs=boat:FindFirstChild('VehicleSeat') or boat:FindFirstChildWhichIsA('VehicleSeat',true)
   if bs then rememberedBoat=boat;rememberedPosition=bs.Position;rememberedOwner=grouped() and sea.group.owner or player.UserId;rememberedCharacter=player.Character end
  end
  generation=generation+1;stopDrive();sea.enabled=value
  if not value then farm.SeaEnd(token);sea.phase='idle';report('Off');return end
  token=farm.SeaBegin();local g=generation;spawnReady=false;resetPending=false;forceNewBoat=false;origin=TIKI;lastCharacter=player.Character;boat=nil;seat=nil
  local _,_,startRoot=body()
  local ownerId=grouped() and sea.group.owner or player.UserId
  resumeBoat=rememberedPosition~=nil and rememberedOwner==ownerId and rememberedCharacter==player.Character
  if resumeBoat and boatAlive(rememberedBoat) then boat=rememberedBoat
  elseif startRoot then boat=ownedBoat(startRoot.Position,1000) end
  task.spawn(function()
   local setIdentity=setthreadidentity or setidentity
   if setIdentity then setIdentity(2) end
   local ok,err=pcall(function()
    while active(g) do
     if sea.StopWhen and sea.StopWhen() then return end
     if finishIsland(g) then return end
     local char,_,root=body()
     if not char then stopDrive();farm.SeaRelease(token);sea.phase='respawn';report('Waiting for respawn');task.wait(1)
     else
      if char~=lastCharacter then
       stopDrive();farm.SeaRelease(token);lastCharacter=char
       boat=passenger() and ownedBoat() or ownedBoat(root.Position,1000)
       forceNewBoat=not passenger() and boat==nil;seat=nil;resetPending=false
      end
      if passenger() then
       local preferred=ownedBoat()
       if preferred and preferred~=boat then stopDrive();farm.SeaRelease(token);boat=preferred;seat=nil;resetPending=false end
      end
      local target,kind;if not sea.searchIsland then target,kind=scan() end
      if target then combat(g,target,kind)
      elseif resetPending then
       if passenger() then boat=nil;seat=nil;resetPending=false;task.wait(.5) else reset(g) end
      elseif not boatAlive(boat) then
       if boat then resetPending=true else acquire(g) end
      else
       seat=boat:FindFirstChild('VehicleSeat')
       if not seat then error('Boat has no steering seat') end
       if board(g) then local nextTarget,nextKind=patrol(g);if nextTarget and active(g) then combat(g,nextTarget,nextKind) end end
      end
     end
     task.wait(.2)
    end
   end)
   if g==generation then stopDrive();farm.SeaEnd(token);sea.enabled=false;sea.phase='idle';report(ok and 'Off' or tostring(err):gsub('^.-:%d+: ','')) end
  end)
  return true
 end
 function sea.SetIslandSearch(name)
  if name~=nil and not islandNames[name] then return false end
  if sea.enabled then sea.SetEnabled(false) end
  sea.searchIsland=name
  if name then return sea.SetEnabled(true) end
  return true
 end
 function sea.Destroy() generation=generation+1;sea.enabled=false;stopDrive();farm.SeaEnd(token) end
 function sea.SetBoatSpeed(value) sea.boatSpeed=math.clamp(tonumber(value) or sea.boatSpeed,40,350);onStatus(sea) end
 function sea.Snapshot() return {group=sea.group,searchIsland=sea.searchIsland,enabled=sea.enabled,phase=sea.phase,message=sea.message,zone=sea.zone,boat=sea.boat,boatSpeed=sea.boatSpeed,continuous=sea.continuous,resetDistance=sea.resetDistance,distanceKm=sea.distanceKm,kills=sea.kills,selected=table.clone(sea.selected),resetPending=resetPending} end
 return sea
end

local function control(parent,name,x,y,w,h)
 local b=make('TextButton',parent,{Text=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),TextSize=12,Font=Enum.Font.GothamBold,TextColor3=pale,BackgroundColor3=Color3.fromRGB(49,46,40),BackgroundTransparency=.12,BorderSizePixel=0,ZIndex=4,AutoButtonColor=false})
 make('UICorner',b,{CornerRadius=UDim.new(0,6)});return b
end
local sidebar=make('ScrollingFrame',content,{Name='Sidebar',CanvasSize=UDim2.fromOffset(0,390),ScrollBarThickness=3,ScrollingDirection=Enum.ScrollingDirection.Y,ClipsDescendants=true,Position=UDim2.fromOffset(18,96),Size=UDim2.fromOffset(156,290),BackgroundColor3=Color3.fromRGB(23,25,28),BackgroundTransparency=.25,BorderSizePixel=0,ZIndex=3})
make('UICorner',sidebar,{CornerRadius=UDim.new(0,10)})
make('Frame',content,{Position=UDim2.fromOffset(184,96),Size=UDim2.fromOffset(1,388),BackgroundColor3=brass,BackgroundTransparency=.78,BorderSizePixel=0,ZIndex=3})
local sectionTitle=label(content,'Farming',202,65,300,28,15);sectionTitle.Font=Enum.Font.GothamBold
local panels={Farming=card};local tabs={}
local materialPopup,statsPopup
for _,name in ipairs({'Farm Setting','Player','Stack Farm','Farm Other','Sea Event','Info','Shop','Get Items','Raid + Fruit','V4 Trial'}) do
 local panel=make((name=='Raid + Fruit' or name=='Player' or name=='Farm Other' or name=='Stack Farm' or name=='Farm Setting' or name=='Info' or name=='Shop' or name=='Get Items' or name=='V4 Trial' or name=='Sea Event') and 'ScrollingFrame' or 'Frame',content,{Name=name,Position=card.Position,Size=UDim2.fromOffset(514,270),BackgroundColor3=card.BackgroundColor3,BackgroundTransparency=.3,BorderSizePixel=0,ZIndex=3,Visible=false})
 if name=='Raid + Fruit' or name=='Player' or name=='Farm Other' or name=='Stack Farm' or name=='Farm Setting' or name=='Info' or name=='Shop' or name=='Get Items' or name=='V4 Trial' or name=='Sea Event' then panel.CanvasSize=UDim2.fromOffset(0,630);panel.ScrollBarThickness=4;panel.ScrollingDirection=Enum.ScrollingDirection.Y end
 make('UICorner',panel,{CornerRadius=UDim.new(0,10)})
 make('UIStroke',panel,{Color=brass,Transparency=.82,Thickness=1});panels[name]=panel
end
local activeMark=make('Frame',sidebar,{Name='ActiveSection',Position=UDim2.fromOffset(10,22),Size=UDim2.fromOffset(3,18),BackgroundColor3=brass,BorderSizePixel=0,ZIndex=5})
make('UICorner',activeMark,{CornerRadius=UDim.new(1,0)})
local sectionNames={['Farm Setting']='Setting',['V4 Trial']='V4'}
local function showSection(name)
 if materialPopup then materialPopup.Visible=false end
 if statsPopup then statsPopup.Visible=false end
 sectionTitle.Text=sectionNames[name] or name
 for key,panel in pairs(panels) do panel.Visible=key==name end
 for key,tab in pairs(tabs) do
  tab.BackgroundColor3=key==name and Color3.fromRGB(112,22,40) or Color3.fromRGB(28,23,30)
  if key==name then activeMark.Position=UDim2.fromOffset(10,tab.Position.Y.Offset+7) end
 end
end
for i,name in ipairs({'Info','Shop','Player','Farm Setting','Farming','Stack Farm','Get Items','Farm Other','Sea Event','Raid + Fruit','V4 Trial'}) do
 local b=control(sidebar,sectionNames[name] or name,10,8+(i-1)*25,136,24);tabs[name]=b
 b.TextXAlignment=Enum.TextXAlignment.Left;b.TextSize=13
 make('UIPadding',b,{PaddingLeft=UDim.new(0,15)})
 bindControl(b,'Activated',function() showSection(name) end)
end
showSection('Farming')
local settings=panels['Farm Setting'];local playerPanel=panels.Player;local stackPanel=panels['Stack Farm']
local function line(panel,y)
 make('Frame',panel,{Position=UDim2.fromOffset(18,y),Size=UDim2.fromOffset(478,1),BackgroundColor3=brass,BackgroundTransparency=.83,BorderSizePixel=0,ZIndex=4})
end
label(settings,'Weapon',18,12,140,30,13)
local weaponButtons={}
for i,v in ipairs({{'Melee','Melee'},{'Sword','Sword'},{'Fruit','Demon Fruit'},{'Gun','Gun'}}) do
 weaponButtons[v[2]]=control(settings,v[1],202+(i-1)*74,14,68,27)
end
line(settings,51)
label(settings,'Auto Click',18,61,200,28,13)
local clickToggle=control(settings,'',468,62,26,26)
line(settings,98)
label(settings,'Bring Mobs',18,108,170,28,13)
local bringToggle=control(settings,'',468,109,26,26)
local less=control(settings,'-',310,109,28,26)
local limitLabel=label(settings,'4',343,108,38,28,13);limitLabel.TextXAlignment=Enum.TextXAlignment.Center
local more=control(settings,'+',386,109,28,26)
line(settings,145)
label(settings,'Tween Speed',18,156,180,28,13)
local slower=control(settings,'-',310,157,28,26)
local speedBox=make('TextBox',settings,{Name='TweenSpeed',Text='120',Position=UDim2.fromOffset(344,157),Size=UDim2.fromOffset(104,26),BackgroundColor3=Color3.fromRGB(49,46,40),TextColor3=pale,TextSize=13,Font=Enum.Font.Gotham,ClearTextOnFocus=false,BorderSizePixel=0,ZIndex=4})
make('UICorner',speedBox,{CornerRadius=UDim.new(0,6)})
local faster=control(settings,'+',466,157,28,26)
label(stackPanel,'Collect & Store Fruit',18,14,155,30,13)
local stackToggle=control(stackPanel,'',468,16,26,26)
line(stackPanel,56)
local stackStatus=label(stackPanel,'No fruit yet',185,14,215,30,12);stackStatus.TextWrapped=true;stackStatus.TextXAlignment=Enum.TextXAlignment.Center

card.Size=UDim2.fromOffset(514,226)
line(card,65)
label(card,'Farm Material',18,78,124,30,13)
local materialChoice=control(card,'Angel Wings  ▾',150,80,244,28)
local materialToggle=control(card,'OFF',410,80,80,28)
materialPopup=make('Frame',content,{Name='MaterialPicker',Position=card.Position,Size=UDim2.fromOffset(514,270),BackgroundColor3=Color3.fromRGB(25,27,30),BorderSizePixel=0,ZIndex=20,Visible=false})
make('UICorner',materialPopup,{CornerRadius=UDim.new(0,10)})
make('UIStroke',materialPopup,{Color=brass,Transparency=.35,Thickness=1})
local pickerTitle=label(materialPopup,'Choose Material',16,7,400,28,14);pickerTitle.ZIndex=22
local pickerClose=control(materialPopup,'×',469,7,28,28);pickerClose.ZIndex=22
local materialList=make('ScrollingFrame',materialPopup,{Name='Options',Position=UDim2.fromOffset(10,42),Size=UDim2.fromOffset(494,218),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=brass,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollingDirection=Enum.ScrollingDirection.Y,ZIndex=21})
make('UIListLayout',materialList,{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder})
line(card,120)
label(card,'Farm Tyrant',18,133,300,30,13)
local tyrantToggle=control(card,'OFF',410,135,80,28)
line(card,173)
label(card,'Farm Cake Prince',18,186,300,30,13)
local cakeToggle=control(card,'OFF',410,188,80,28)
local farm
local function check(box,value)
 box.Text=value and '✓' or ''
 box.BackgroundColor3=value and Color3.fromRGB(131,100,55) or Color3.fromRGB(49,46,40)
end
local function refresh()
 if not farm then return end
 tyrantToggle.Text=farm.enabled and farm.mode=='tyrant' and 'ON' or 'OFF'
 cakeToggle.Text=farm.enabled and farm.mode=='cake' and 'ON' or 'OFF'
 materialChoice.Text=farm.material..'  ▾'
 materialToggle.Text=farm.enabled and farm.mode=='material' and 'ON' or 'OFF'
 toggle.Text=farm.enabled and farm.mode=='level' and 'ON' or 'OFF'
 check(bringToggle,farm.bringMobs);check(clickToggle,farm.autoClick);check(stackToggle,farm.stackFruit)
 limitLabel.Text=tostring(farm.mobLimit)
 if not speedBox:IsFocused() then speedBox.Text=tostring(farm.tweenSpeed) end
 local fruitNames=farm.FruitNames and farm.FruitNames() or {}
 stackStatus.Text=#fruitNames>0 and table.concat(fruitNames,', ') or 'No fruit yet'
 for key,b in pairs(weaponButtons) do b.BackgroundColor3=farm.weapon==key and Color3.fromRGB(106,82,48) or Color3.fromRGB(49,46,40) end
end
farm=createFarm(function(message,enabled) state.Text=message;toggle.Text=enabled and 'ON' or 'OFF';refresh() end)
bindControl(toggle,'Activated',function() farm.SetMode('level',not (farm.enabled and farm.mode=='level')) end)
bindControl(materialToggle,'Activated',function() farm.SetMode('material',not (farm.enabled and farm.mode=='material')) end)
bindControl(tyrantToggle,'Activated',function() farm.SetMode('tyrant',not (farm.enabled and farm.mode=='tyrant')) end)
bindControl(cakeToggle,'Activated',function() farm.SetMode('cake',not (farm.enabled and farm.mode=='cake')) end)
bindControl(materialChoice,'Activated',function() materialPopup.Visible=not materialPopup.Visible end)
bindControl(pickerClose,'Activated',function() materialPopup.Visible=false end)
for i,entry in ipairs(farm.Materials) do
 local button=control(materialList,entry.name,0,0,484,30);button.LayoutOrder=i;button.ZIndex=22;button.TextXAlignment=Enum.TextXAlignment.Left
 make('UIPadding',button,{PaddingLeft=UDim.new(0,10)})
 bindControl(button,'Activated',function() farm.SelectMaterial(entry.name);materialPopup.Visible=false;refresh() end)
end
for key,b in pairs(weaponButtons) do bindControl(b,'Activated',function() farm.SetWeapon(key) end) end
bindControl(bringToggle,'Activated',function() farm.SetBringMobs(not farm.bringMobs) end)
bindControl(clickToggle,'Activated',function() farm.SetAutoClick(not farm.autoClick) end)
bindControl(stackToggle,'Activated',function() farm.SetStackFruit(not farm.stackFruit);refresh() end)
bindControl(less,'Activated',function() farm.SetMobLimit(farm.mobLimit-1) end)
bindControl(more,'Activated',function() farm.SetMobLimit(farm.mobLimit+1) end)
bindControl(slower,'Activated',function() farm.SetTweenSpeed(farm.tweenSpeed-20) end)
bindControl(faster,'Activated',function() farm.SetTweenSpeed(farm.tweenSpeed+20) end)
bindControl(speedBox,'FocusLost',function() farm.SetTweenSpeed(speedBox.Text) end)
refresh()
local pointsLabel=label(playerPanel,'',18,14,478,27,15);pointsLabel.Visible=false

local statStatus=label(playerPanel,'Select stats to spend points',18,185,478,46,12,Color3.fromRGB(213,213,206));statStatus.TextWrapped=true;statStatus.Visible=false
label(playerPanel,'Auto Stats',18,318,125,28,13)
local statChoice=control(playerPanel,'Select stats  ▾',150,318,344,28)
statChoice.TextTruncate=Enum.TextTruncate.AtEnd
statsPopup=make('Frame',content,{Name='StatPicker',Position=card.Position,Size=UDim2.fromOffset(514,270),BackgroundColor3=Color3.fromRGB(25,27,30),BorderSizePixel=0,ZIndex=20,Visible=false})
make('UICorner',statsPopup,{CornerRadius=UDim.new(0,10)})
make('UIStroke',statsPopup,{Color=brass,Transparency=.35,Thickness=1})
local statTitle=label(statsPopup,'Choose Stats',16,7,400,28,14);statTitle.ZIndex=22
local statClose=control(statsPopup,'×',469,7,28,28);statClose.ZIndex=22
local boxes={};local displayNames={Melee='Melee',Defense='Defense',Sword='Sword',Gun='Gun',['Demon Fruit']='Fruit'}
local function displayStats(selected)
 local names={}
 for _,key in ipairs({'Melee','Defense','Sword','Gun','Demon Fruit'}) do if selected[key] then table.insert(names,displayNames[key]) end end
 statChoice.Text=(#names>0 and table.concat(names,', ') or 'Select stats')..'  ▾'
 for key,box in pairs(boxes) do
  box.Text=(selected[key] and '✓  ' or '□  ')..displayNames[key]
  box.BackgroundColor3=selected[key] and Color3.fromRGB(106,82,48) or Color3.fromRGB(49,46,40)
 end
end
local stats=createAutoStats(function(message,selected,points)
 pointsLabel.Text='Stat Points: '..tostring(points);statStatus.Text=message
 displayStats(selected)
end)
for i,key in ipairs({'Melee','Defense','Sword','Gun','Demon Fruit'}) do
 local box=control(statsPopup,'□  '..displayNames[key],14,43+(i-1)*42,484,34);boxes[key]=box;box.ZIndex=22
 box.TextXAlignment=Enum.TextXAlignment.Left
 make('UIPadding',box,{PaddingLeft=UDim.new(0,12)})
 bindControl(box,'Activated',function() stats.Select(key,not stats.selected[key]);displayStats(stats.selected) end)
end
bindControl(statChoice,'Activated',function() statsPopup.Visible=not statsPopup.Visible;materialPopup.Visible=false end)
bindControl(statClose,'Activated',function() statsPopup.Visible=false end)
-- Hidden idle prevention, cleaned up with the rest of Nexo.
connect(player.Idled,function()
 pcall(function()
  local virtualUser=game:GetService('VirtualUser');virtualUser:CaptureController()
  virtualUser:Button2Down(Vector2.zero,workspace.CurrentCamera.CFrame)
  task.delay(.1,function() pcall(function() virtualUser:Button2Up(Vector2.zero,workspace.CurrentCamera.CFrame) end) end)
 end)
end)

local seaPanel=panels['Sea Event']
local seaPopup
local sea
local function seaRow(text,y)
 label(seaPanel,text,16,y,210,28,12)
 local b=control(seaPanel,'',244,y,252,28)
 return b
end
local zoneChoice=seaRow('Zone',10)
local eventChoice=seaRow('Events',40);eventChoice.TextTruncate=Enum.TextTruncate.AtEnd
local boatChoice=seaRow('Boat',70)
label(seaPanel,'Boat Speed',16,100,210,28,12)
local boatSlower=control(seaPanel,'−',244,100,28,28)
local boatSpeedBox=make('TextBox',seaPanel,{Name='BoatSpeed',Text='120',Position=UDim2.fromOffset(280,100),Size=UDim2.fromOffset(180,28),BackgroundColor3=Color3.fromRGB(49,46,40),TextColor3=pale,TextSize=13,Font=Enum.Font.Gotham,ClearTextOnFocus=false,BorderSizePixel=0,ZIndex=4})
make('UICorner',boatSpeedBox,{CornerRadius=UDim.new(0,6)})
local boatFaster=control(seaPanel,'+',468,100,28,28)
local continuousToggle=seaRow('Sail until selected event',130)
local resetToggle=seaRow('Reset beyond 10 km',160)
local seaToggle=seaRow('Auto Sea Event',190)
local mirageToggle=seaRow('Find Mirage Island',224)
local kitsuneToggle=seaRow('Find Kitsune Island',258)
seaPanel.CanvasSize=UDim2.fromOffset(0,342)
local seaStatus=label(seaPanel,'Off',16,296,480,36,11,Color3.fromRGB(210,191,161));seaStatus.TextWrapped=true
local function refreshSea()
 if not sea then return end
 zoneChoice.Text=sea.zone and ('Zone '..sea.zone..'  ▾') or 'Select zone  ▾'
 local names={};for _,n in ipairs({'Terrorshark','Shark','Sea Beast','Piranha','Kill Boats'}) do if sea.selected[n] then table.insert(names,n) end end
 eventChoice.Text=(#names>0 and table.concat(names,', ') or 'Select events')..'  ▾'
 boatChoice.Text=sea.boat..'  ▾'
 if not boatSpeedBox:IsFocused() then boatSpeedBox.Text=tostring(sea.boatSpeed) end
 continuousToggle.Text=sea.continuous and '✓' or '□'
 resetToggle.Text=sea.resetDistance and '✓' or '□'
 seaToggle.Text=sea.enabled and not sea.group.enabled and not sea.searchIsland and 'ON' or 'OFF'
 mirageToggle.Text=sea.enabled and sea.searchIsland=='Mirage Island' and 'ON' or 'OFF'
 kitsuneToggle.Text=sea.enabled and sea.searchIsland=='Kitsune Island' and 'ON' or 'OFF'
 seaToggle.BackgroundColor3=sea.enabled and Color3.fromRGB(131,100,55) or Color3.fromRGB(49,46,40)
 seaStatus.Text=sea.message..(sea.enabled and string.format('  ·  %.2f km',sea.distanceKm) or '')
end
sea=createSeaEvent(farm,function() refreshSea();refresh() end)
seaPopup=make('Frame',content,{Name='SeaPicker',Position=card.Position,Size=UDim2.fromOffset(514,270),BackgroundColor3=Color3.fromRGB(25,27,30),BorderSizePixel=0,ZIndex=20,Visible=false})
make('UICorner',seaPopup,{CornerRadius=UDim.new(0,10)})
make('UIStroke',seaPopup,{Color=brass,Transparency=.35,Thickness=1})
local seaPickerTitle=label(seaPopup,'',16,7,400,28,14);seaPickerTitle.ZIndex=22
local seaClose=control(seaPopup,'×',469,7,28,28);seaClose.ZIndex=22
local seaOptions=make('ScrollingFrame',seaPopup,{Position=UDim2.fromOffset(12,42),Size=UDim2.fromOffset(490,216),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollingDirection=Enum.ScrollingDirection.Y,ZIndex=21})
make('UIListLayout',seaOptions,{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder})
local pickerConnections={}
local function picker(title,choices,selected,choose,multi)
 if capturePicker then bindingPicker={choices=choices,selected=selected,choose=choose,multi=multi};return end
 for _,c in ipairs(pickerConnections) do c:Disconnect() end;pickerConnections={}
 for _,v in ipairs(seaOptions:GetChildren()) do if v:IsA('GuiButton') then v:Destroy() end end
 seaPickerTitle.Text=title;seaPopup.Visible=true
 for i,value in ipairs(choices) do
  local b=control(seaOptions,'',0,0,480,31);b.ZIndex=22;b.LayoutOrder=i;b.TextXAlignment=Enum.TextXAlignment.Left
  make('UIPadding',b,{PaddingLeft=UDim.new(0,12)})
  local function paint() b.Text=(selected(value) and '✓  ' or '□  ')..tostring(value) end
  paint();table.insert(pickerConnections,b.Activated:Connect(function() choose(value);paint();refreshSea();if not multi then seaPopup.Visible=false end end))
 end
end
bindControl(zoneChoice,'Activated',function() picker('Choose Zone',{1,2,3,4,5,6},function(v) return sea.zone==v end,function(v) sea.zone=v end,false) end)
bindControl(eventChoice,'Activated',function() picker('Choose Events',{'Terrorshark','Shark','Sea Beast','Piranha','Kill Boats'},function(v) return sea.selected[v] end,function(v) sea.selected[v]=not sea.selected[v] or nil end,true) end)
bindControl(boatChoice,'Activated',function() picker('Choose Boat',{'Guardian','Brigade','Beast Hunter'},function(v) return sea.boat==v end,function(v) sea.boat=v end,false) end)
bindControl(seaClose,'Activated',function() seaPopup.Visible=false end)
for _,b in pairs(tabs) do bindControl(b,'Activated',function() seaPopup.Visible=false end) end
bindControl(continuousToggle,'Activated',function() sea.continuous=not sea.continuous;refreshSea() end)
bindControl(resetToggle,'Activated',function() sea.resetDistance=not sea.resetDistance;refreshSea() end)
bindControl(seaToggle,'Activated',function() if sea.enabled then sea.SetEnabled(false) else sea.group.enabled=false;sea.searchIsland=nil;sea.SetEnabled(true) end;refreshSea() end)
bindControl(mirageToggle,'Activated',function() sea.SetIslandSearch(not (sea.enabled and sea.searchIsland=='Mirage Island') and 'Mirage Island' or nil);refreshSea() end)
bindControl(kitsuneToggle,'Activated',function() sea.SetIslandSearch(not (sea.enabled and sea.searchIsland=='Kitsune Island') and 'Kitsune Island' or nil);refreshSea() end)
bindControl(boatSlower,'Activated',function() sea.SetBoatSpeed(sea.boatSpeed-20) end)
bindControl(boatFaster,'Activated',function() sea.SetBoatSpeed(sea.boatSpeed+20) end)
bindControl(boatSpeedBox,'FocusLost',function() sea.SetBoatSpeed(boatSpeedBox.Text);refreshSea() end)
refreshSea()

-- Island travel reads only the current sea's live map definitions.
local travelPopup
local travelChoice=control(playerPanel,'Choose island  ▾',150,450,244,28)
label(playerPanel,'Travel',18,450,125,28,13)
local travelGo=control(playerPanel,'OFF',410,450,80,28)
local travelStop=control(playerPanel,'Stop',406,154,88,27);travelStop.Visible=false
statStatus.Position=UDim2.fromOffset(18,231);statStatus.Size=UDim2.fromOffset(478,30)
local travelStatus=label(playerPanel,'',18,190,478,35,11,Color3.fromRGB(213,213,206));travelStatus.TextWrapped=true;travelStatus.Visible=false
travelPopup=make('Frame',playerPanel,{Name='TravelPicker',Size=UDim2.fromOffset(514,270),BackgroundColor3=Color3.fromRGB(25,27,30),BorderSizePixel=0,ZIndex=25,Visible=false})
make('UICorner',travelPopup,{CornerRadius=UDim.new(0,10)})
local travelTitle=label(travelPopup,'Choose island',16,7,420,28,14);travelTitle.ZIndex=27
local travelClose=control(travelPopup,'×',469,7,28,28);travelClose.ZIndex=27
local travelList=make('ScrollingFrame',travelPopup,{Position=UDim2.fromOffset(10,42),Size=UDim2.fromOffset(494,218),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=26})
make('UIListLayout',travelList,{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder})
local travelSelection;local travelToken;local travelSerial=0
local function travelOptions()
 local canonical=({[85211729168715]=2753915549,[79091703265657]=4442272183,[100117331123089]=7449423635})[game.PlaceId] or game.PlaceId
 local recorded={
  [2753915549]={
   {name='Pirate Starter',position=Vector3.new(826.1,3.68,1466.78)},
   {name='Middle Town',position=Vector3.new(-449.78,9.06,1517.91)},
   {name='Jungle',position=Vector3.new(-1496.73,73.27,23.15)},
   {name='Colosseum',position=Vector3.new(-1364.25,12.49,-2897.61)},
   {name='Frozen Village',position=Vector3.new(1307.45,78.04,-1293.22)},
   {name='Whirlpool',position=Vector3.new(3896.57,3.81,-1906.42)},
   {name='Underwater City',position=Vector3.new(61363.33,24.95,1545.14)},
   {name='Prison',position=Vector3.new(4869.1,10.56,735.22)},
   {name='Fountain City',position=Vector3.new(5215.63,76.1,4077.03)},
   {name='Desert Island',position=Vector3.new(927.11,5.91,4249.54)},
   {name='Pirate Island',position=Vector3.new(-1128.89,8.31,3831.07)},
   {name='Marine Starter',position=Vector3.new(-2568.71,5.94,2062.71)},
   {name='Marine Fortress',position=Vector3.new(-4643.05,5.89,4165.15)},
   {name='Magma Village',position=Vector3.new(-5312.2,18.48,8444.13)},
   {name='Skyland 1',position=Vector3.new(-4781.98,8.15,-555.91)},
   {name='Skyland 2',position=Vector3.new(-4859.82,927.4,-899.38)},
   {name='Upper Sky',position=Vector3.new(-6005.11,5469.17,2173.58)},
   {name='Upper Sky 2',position=Vector3.new(-6911.25,5590.99,1094.28)},
  },
  [4442272183]={
   {name='Kingdom of Rose Dock',position=Vector3.new(-7.87,19.32,2837.2)},
   {name='Cafe',position=Vector3.new(-375.46,73.06,289.53)},
   {name='Green Zone',position=Vector3.new(-2050.08,72.38,-2704.36)},
   {name='Graveyard',position=Vector3.new(-5432.32,48.52,-725.06)},
   {name='Cursed Ship',position=Vector3.new(933.82,125.1,32874.97)},
   {name='Hot',position=Vector3.new(-4772.62,35.08,-4895.16)},
   {name='Cold',position=Vector3.new(-6214.01,81.86,-4932.27)},
   {name='Forgotten Island',position=Vector3.new(-3051.12,238.89,-10192.16)},
   {name='Snow Mountain',position=Vector3.new(585.51,401.46,-5366.12)},
   {name='Dark Arena',position=Vector3.new(3432.04,13.39,-3379.25)},
   {name='Ice Castle',position=Vector3.new(5577.43,28.23,-6315.38)},
   {name='Small Island',position=Vector3.new(4727.7,8.31,2852.89)},
  },
  [7449423635]={
   {name='Port Town',position=Vector3.new(-331.33,20.65,5528.43)},
   {name='Middle Hydra',position=Vector3.new(5286.78,1005.39,396.78)},
   {name='Castle on the Sea',position=Vector3.new(-5004.12,314.56,-3002.59)},
   {name='Mansion',position=Vector3.new(-12550.17,337.21,-7550.52)},
   {name='Floating Turtle',position=Vector3.new(-10745.15,331.8,-8556.58)},
   {name='Tiki',position=Vector3.new(-16927.68,9.1,382.41)},
   {name='Submerged Island',position=Vector3.new(11094.5,-2087.72,9810.07)},
   {name='Chocolate Island',position=Vector3.new(-2.02,20.56,-12039.15)},
   {name='Sea of Treats',position=Vector3.new(-937.1,7.81,-10817.81)},
   {name='Sea of Treats 2',position=Vector3.new(-2029.1,9.72,-9949.72)},
   {name='Sea of Treats 3',position=Vector3.new(-1855.12,13.83,-11626.64)},
   {name='North Pole',position=Vector3.new(-1024.88,19.92,-14092.41)},
   {name='Great Tree',position=Vector3.new(2183.1,21.76,-6621.52)},
   {name='Haunted Castle',position=Vector3.new(-9514.07,142.14,5547)},
  },
 }
 local entries=recorded[canonical] or {}
 for _,entry in ipairs(entries) do entry.key=entry.name;entry.sea=canonical;entry.recorded=true end
 return entries
end
bindControl(travelChoice,'Activated',function()
 for _,v in ipairs(travelList:GetChildren()) do if v:IsA('GuiButton') then v:Destroy() end end
 for i,entry in ipairs(travelOptions()) do
  local b=control(travelList,entry.name,0,0,484,30);b.LayoutOrder=i;b.ZIndex=27
  bindControl(b,'Activated',function() travelSelection=entry;travelChoice.Text=entry.name..'  ▾';travelPopup.Visible=false end)
 end
 travelPopup.Position=UDim2.fromOffset(0,playerPanel.CanvasPosition.Y)
 travelPopup.Visible=true
end)
bindControl(travelClose,'Activated',function() travelPopup.Visible=false end)
local function stopTravel()
 travelSerial=travelSerial+1
 if travelToken then farm.SeaEnd(travelToken);travelToken=nil end
 travelStatus.Text='Stopped';travelGo.Text='OFF'
end
bindControl(travelStop,'Activated',stopTravel)
local function startTravel()
 if travelToken then stopTravel();return end
 local entry=travelSelection
 if not entry or entry.sea~=(game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId) then travelStatus.Text='Choose an island in this sea';return end
 stopTravel();sea.SetEnabled(false)
 local serial=travelSerial;local token=farm.SeaBegin();travelToken=token;travelGo.Text='ON'
 task.spawn(function()
  local ok,err=pcall(function()
   travelStatus.Text='Travelling to '..entry.name
   local arrived=false
   for _=1,8 do
    if not farm.SeaActive(token) then return end
    arrived=farm.SeaMove(entry.position,token)
    if arrived then break end
    task.wait(1)
   end
   if not farm.SeaActive(token) then return end
   if not arrived then travelStatus.Text='Could not reach '..entry.name;return end
   task.wait(.5)
   travelStatus.Text='Arrived: '..entry.name
  end)
  if serial==travelSerial then
   farm.SeaEnd(token);travelToken=nil;travelGo.Text='OFF'
   if not ok then travelStatus.Text='Travel stopped: '..tostring(err) end
  end
 end)
end
bindControl(travelGo,'Activated',startTravel)
local travelAPI={Start=startTravel,Stop=stopTravel,Options=travelOptions}
function travelAPI.Select(key)
 for _,entry in ipairs(travelOptions()) do if entry.key==key then travelSelection=entry;travelChoice.Text=entry.name..'  ▾';return true end end
 return false
end
function travelAPI.Snapshot() return {key=travelSelection and travelSelection.key,active=travelToken~=nil,sea=(game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId)} end

local preferences={syn=true,save=true,autoSave=true,autoLoad=true,autoLoadTeam='Marines',safeRetreat=true,raid={selected='Flame',start=false,unstore=false,awaken=false},movement={fog=false,water=true,jump=false,speed=false,jumpPower=200,walkSpeed=200},auto={v3=false,v4=false,aura=true,rollFruit=false,storeFruit=false},other={berry=false,berryHop=false,aura=false,sword=false,chest=false,chestHop=false,limit=false,count=20}}
local beforeCleanup
local preferenceReady=false
local applyLanguage
local function updatePreferenceLabels() end
function preferences.SetLanguage(synKhmer) preferences.syn=synKhmer==true;updatePreferenceLabels() end
do
 local translations={["Auto Spawn Darkbeard"]="កោះហៅ Darkbeard ស្វ័យប្រវត្តិ",["Kill rip_indra"]="កម្ចាត់ rip_indra",["Kill Darkbeard"]="កម្ចាត់ Darkbeard",["Farm Level"]="បង្កើនកម្រិត",["Farm Material"]="ប្រមូលវត្ថុធាតុ",["Farm Setting"]="ការកំណត់",["Settings"]="ការកំណត់",["Bring Mobs"]="ប្រមូលសត្រូវ",["Tween Speed"]="ល្បឿនធ្វើដំណើរ",["Auto Stats"]="បន្ថែមពិន្ទុស្វ័យប្រវត្តិ",["Travel"]="ទៅកាន់កោះ",["Collect & Store Fruit"]="ប្រមូលនិងរក្សាទុកផ្លែ",["No fruit yet"]="មិនទាន់មានផ្លែ",["Auto Elite Pirate"]="កម្ចាត់ចោរសមុទ្រពិសេស",["Auto Factory"]="វាយរោងចក្រ",["Auto Pirate Raid"]="កម្ចាត់ការវាយឆ្មក់",["Stop All"]="បញ្ឈប់ទាំងអស់",["Translate"]="បកប្រែ",["Save Setting"]="រក្សាទុកការកំណត់",["Fruit Dealer"]="ហាងលក់ផ្លែ",["Mirage Fruit Dealer"]="ហាងផ្លែនៅកោះ Mirage",["Titles Specialist"]="អ្នកជំនាញងារ",["Awakenings Expert"]="អ្នកជំនាញដាស់ថាមពល",["Change Team"]="ប្តូរក្រុម",["Tween to NPC"]="ទៅកាន់ NPC",["Tween to Mirage"]="ទៅកាន់កោះ Mirage",["Tween to Prehistoric"]="ទៅកាន់កោះបុរេប្រវត្តិ",["Roll Fruit"]="បង្វិលយកផ្លែ",["Store Fruit"]="រក្សាទុកផ្លែ",["Pirates"]="ចោរសមុទ្រ",["Marines"]="ទាហានជើងទឹក",["Open"]="បើក",["ON"]="បើក",["OFF"]="បិទ",["Player"]="អ្នកលេង",["Shop"]="ហាង",["Info"]="ព័ត៌មាន",["Farming"]="ការប្រមូល",["Stack Farm"]="ការងារបន្ថែម",["Get Items"]="ទទួលវត្ថុ",["Farm Other"]="ប្រមូលផ្សេងៗ",["Sea Event"]="ព្រឹត្តិការណ៍សមុទ្រ",["Choose Stats"]="ជ្រើសរើសពិន្ទុ",["Melee"]="វាយប្រហារដៃ",["Defense"]="ការពារ",["Sword"]="ដាវ",["Gun"]="កាំភ្លើង",["Fruit"]="ផ្លែ"}
 preferences.TranslateText=function(text)return preferences.syn and translations[text]or text end
 local reverse={};for a,b in pairs(translations) do reverse[b]=a end
 local labels=setmetatable({},{__mode='k'});local changing=false
 local baseSizes=setmetatable({},{__mode='k'})
 local function sizeText(object)
  baseSizes[object]=baseSizes[object] or object.TextSize
  local khmer=object.Text:find('[\225][\158-\159]')~=nil
  object.TextScaled=false
  object.TextSize=khmer and math.max(18,baseSizes[object]+3) or baseSizes[object]
  if khmer and object:IsA('TextLabel') then object.TextWrapped=true end
 end
 local function translate(object)
  if changing or not object.Parent then return end
  local text=object.Text
  local original=reverse[text] or text
  if original=='Farm Setting' then original='Settings' end
  if translations[original] then
   labels[object]=original;changing=true
   object.Text=preferences.syn and translations[original] or original
   changing=false
  end
  sizeText(object)
 end
 local function watch(object)
  if object:IsA('TextLabel') or object:IsA('TextButton') then
   translate(object);connect(object:GetPropertyChangedSignal('Text'),function() translate(object) end)
  end
 end
 for _,v in ipairs(gui:GetDescendants()) do watch(v) end
 connect(gui.DescendantAdded,watch)
 applyLanguage=function()
  changing=true
  for object,original in pairs(labels) do if object.Parent then object.Text=preferences.syn and translations[original] or original;sizeText(object) end end
  changing=false
 end
 local eventButtons={}
 for i,entry in ipairs({{'elite','Auto Elite Pirate'},{'ripindra','Kill rip_indra'},{'darkbeard','Kill Darkbeard'},{'factory','Auto Factory'},{'raid','Auto Pirate Raid'},{'doughking','Kill Dough King'},{'reaper','Kill Soul Reaper'}}) do
  local y=i==1 and 104 or 104+i*40
  local indraRow=entry[1]=='ripindra' or entry[1]=='doughking'
  label(stackPanel,entry[2],18,y,indraRow and 150 or 380,30,13)
  local b=control(stackPanel,'OFF',indraRow and 174 or 410,y+2,indraRow and 60 or 80,28);eventButtons[entry[1]]=b
  bindControl(b,'Activated',function() farm.SetStackEvent(entry[1],not farm.stackEvents[entry[1]]);b.Text=farm.stackEvents[entry[1]] and 'ON' or 'OFF' end)
 end
 label(settings,'Save Setting',18,690,280,28,13)
 local saveButton=control(settings,'Save',410,690,80,28)
 label(playerPanel,'Translate',18,54,280,28,13)
 local languageButton=control(playerPanel,'Khmer',350,54,140,28)
 bindControl(languageButton,'Activated',function() preferences.syn=not preferences.syn;applyLanguage();languageButton.Text=preferences.syn and 'Khmer' or 'English' end)
 bindControl(saveButton,'Activated',function() preferences.ManualSave();saveButton.Text='Saved';task.delay(1,function()if alive then saveButton.Text='Save' end end) end)
 updatePreferenceLabels=function()
  saveButton.Text='Save';languageButton.Text=preferences.syn and 'Khmer' or 'English'
  for key,b in pairs(eventButtons) do b.Text=farm.stackEvents[key] and 'ON' or 'OFF' end
  applyLanguage();refresh();refreshSea()
 end
 task.spawn(function() while alive do refresh();for key,b in pairs(eventButtons) do b.Text=farm.stackEvents[key] and 'ON' or 'OFF' end;task.wait(3) end end)
end
do
 local http=game:GetService('HttpService')
 local path='Nexo/settings-'..tostring(player.UserId)..'.json'
 local teleporting=false;local queued=false;local lastWritten;local manualSave=false
 local available=type(readfile)=='function' and type(writefile)=='function' and type(isfile)=='function'
 local function snapshot(resume)
  return {soulPuzzleDone=preferences.soulPuzzleDone,autoSoulGuitar=preferences.autoSoulGuitar,autoRengoku=preferences.autoRengoku,autoSpawnDarkbeard=preferences.autoSpawnDarkbeard,autoSpawnDoughKing=preferences.autoSpawnDoughKing,raid=preferences.raid,autoSpawnIndra=preferences.autoSpawnIndra,autoTushita=preferences.autoTushita,levi=preferences.levi,autoSaber=preferences.autoSaber,styleJob=preferences.styleJob,styleWaitUntil=preferences.styleWaitUntil,collectFist=preferences.collectFist,autoTrial=preferences.autoTrial,raceV2=preferences.raceV2,raceV3=preferences.raceV3,v4Training=preferences.v4Training,findFullMoon=preferences.findFullMoon,skillUse=farm.skillUse,movement=table.clone(preferences.movement),safeRetreat=preferences.safeRetreat,auto=table.clone(preferences.auto),other=table.clone(preferences.other),autoSave=preferences.autoSave,autoLoad=preferences.autoLoad,autoLoadTeam=preferences.autoLoadTeam,version=1,userId=player.UserId,resume=resume,save=preferences.save,syn=preferences.syn,
   farm={enabled=farm.enabled,mode=farm.mode,material=farm.material,weapon=farm.weapon,tweenSpeed=farm.tweenSpeed,bringMobs=farm.bringMobs,mobLimit=farm.mobLimit,autoClick=farm.autoClick,stackFruit=farm.stackFruit,stackEvents=table.clone(farm.stackEvents)},
   hopWait=preferences.hopWait or 20,fruitHop=preferences.fruitHop==true,eliteHop=preferences.eliteHop==true,stats=table.clone(stats.selected),sea=sea.Snapshot(),travel=travelAPI.Snapshot()}
 end
 local function save(resume,force)
  if not available or not preferenceReady or preferences.priorityBusy then return end
  if not force and not preferences.autoSave then return end
  local data=snapshot(resume)
  if not preferences.autoSave and not manualSave then
   local ok,prior=pcall(function()return http:JSONDecode(readfile(path))end)
   if ok and type(prior)=='table' then data=prior end
   data.autoSave=preferences.autoSave;data.autoLoad=preferences.autoLoad;data.autoLoadTeam=preferences.autoLoadTeam;data.resume=resume
  end
  local ok,encoded=pcall(http.JSONEncode,http,data)
  if ok and (force or encoded~=lastWritten) then
   local written=pcall(function() if type(isfolder)=='function' and type(makefolder)=='function' and not isfolder('Nexo') then makefolder('Nexo') end;writefile(path,encoded) end)
   if written then lastWritten=encoded end
  end
 end
 beforeCleanup=function()
  -- Reinjection and teleport keep settings; an explicit close disables automatic resume.
  if not env.NexoReplacing and not teleporting then save(false,true) else save(true,true) end
 end
 preferences.Flush=function() save(true,true) end
 preferences.ManualSave=function()manualSave=true;save(true,true);manualSave=false end
 local function awaitSpawn(team)
  local nextTry=0
  while alive do
   local character=player.Character
   local humanoid=character and character:FindFirstChildOfClass('Humanoid')
   if player.Team and character and character:IsDescendantOf(workspace) and humanoid and humanoid.Health>0 and character:FindFirstChild('HumanoidRootPart') then return true end
   if not player.Team and os.clock()>=nextTry and env.NexoSelectTeamUI then
    if env.NexoSelectTeamUI(team) then nextTry=os.clock()+5 end
   end
   task.wait(.25)
  end
  return false
 end
 task.defer(function()
  local saved
  if available then pcall(function() if isfile(path) then saved=http:JSONDecode(readfile(path)) end end) end
  -- Preserve the saved active settings while the team screen and character load.
  if not awaitSpawn(saved and saved.autoLoadTeam or 'Marines') then return end
  if type(saved)=='table' and saved.userId==player.UserId then
   preferences.autoLoadTeam=saved.autoLoadTeam=='Pirates' and 'Pirates' or 'Marines'
   preferences.autoSave=saved.autoSave~=false;preferences.autoLoad=saved.autoLoad~=false;preferences.save=saved.save~=false;preferences.syn=saved.syn~=false;preferences.safeRetreat=saved.safeRetreat~=false;preferences.hopWait=math.clamp(tonumber(saved.hopWait) or 20,1,600)
   if preferences.save then
    preferences.autoSpawnDoughKing=saved.resume==true and saved.autoSpawnDoughKing==true
    preferences.soulPuzzleDone=saved.soulPuzzleDone==true
    preferences.autoSoulGuitar=saved.resume==true and saved.autoSoulGuitar==true
    preferences.autoRengoku=saved.resume==true and saved.autoRengoku==true
    preferences.autoSpawnDarkbeard=saved.resume==true and saved.autoSpawnDarkbeard==true
    preferences.autoSpawnIndra=saved.resume==true and saved.autoSpawnIndra==true
    preferences.autoTushita=saved.resume==true and saved.autoTushita==true
    if type(saved.skillUse)=='table' then
     for kind,keys in pairs(farm.skillUse) do
      local savedKeys=saved.skillUse[kind]
      if type(savedKeys)=='table' then for key in pairs(keys) do keys[key]=savedKeys[key]~=false end end
     end
    end
    local mv=type(saved.movement)=='table' and saved.movement or {}
    preferences.movement.jumpPower=math.clamp(tonumber(mv.jumpPower) or 200,1,250)
    preferences.movement.walkSpeed=math.clamp(tonumber(mv.walkSpeed) or 200,1,200)
    if type(saved.raid)=='table' and type(saved.raid.selected)=='string' then preferences.raid.selected=saved.raid.selected end
    if saved.resume==true then
     if type(saved.raid)=='table' then for _,k in ipairs({'start','unstore','awaken'}) do preferences.raid[k]=saved.raid[k]==true end end for _,key in ipairs({'fog','water','jump','speed'}) do preferences.movement[key]=mv[key]==true end end
    local f=type(saved.farm)=='table' and saved.farm or {}
    farm.SetWeapon(f.weapon);farm.SetTweenSpeed(f.tweenSpeed or 200);farm.SetBringMobs(f.bringMobs~=false);farm.SetMobLimit(f.mobLimit or 2)
    if type(f.material)=='string' then farm.SelectMaterial(f.material) end
    if f.mode=='level' or f.mode=='material' or f.mode=='tyrant' or f.mode=='cake' then farm.mode=f.mode end
    if type(saved.levi)=='table' then preferences.levi=saved.levi;preferences.levi.hunt=false;preferences.levi.ride=false;preferences.levi.attack=false;preferences.levi.manual=false end
    local ss=type(saved.sea)=='table' and saved.sea or {}
    if type(ss.group)=='table' then
     sea.group.enabled=ss.group.enabled==true;sea.group.count=math.clamp(math.floor(tonumber(ss.group.count) or 2),2,5)
     sea.group.owner=tonumber(ss.group.owner) or player.UserId;sea.group.role=ss.group.role=='Passenger' and 'Passenger' or 'Driver'
     sea.group.members=type(ss.group.members)=='table' and ss.group.members or {}
    end
    if type(ss.zone)=='number' and ss.zone>=1 and ss.zone<=6 then sea.zone=math.floor(ss.zone) end
    if ss.searchIsland=='Mirage Island' or ss.searchIsland=='Kitsune Island' then sea.searchIsland=ss.searchIsland end
    if ss.boat=='Guardian' or ss.boat=='Brigade' or ss.boat=='Beast Hunter' then sea.boat=ss.boat end
    sea.SetBoatSpeed(ss.boatSpeed);sea.continuous=ss.continuous==true;sea.resetDistance=ss.resetDistance==true
    for _,k in ipairs({'Terrorshark','Shark','Sea Beast','Piranha','Kill Boats'}) do sea.selected[k]=type(ss.selected)=='table' and ss.selected[k]==true or false end
    local travel=type(saved.travel)=='table' and saved.travel or {}
    local currentSeaId=game.PlaceId==100117331123089 and 7449423635 or game.PlaceId==85211729168715 and 2753915549 or game.PlaceId==79091703265657 and 4442272183 or game.PlaceId
    local travelChosen=(travel.sea==game.PlaceId or travel.sea==currentSeaId) and travelAPI.Select(travel.key)
    if saved.resume==true then
     preferences.autoSaber=saved.autoSaber==true
     preferences.collectFist=saved.collectFist==true
     preferences.autoTrial=saved.autoTrial==true
     preferences.raceV2=saved.raceV2==true;preferences.raceV3=saved.raceV3==true
     preferences.v4Training=saved.v4Training==true
     preferences.findFullMoon=saved.findFullMoon==true
     preferences.styleJob=type(saved.styleJob)=='string' and saved.styleJob or nil
     preferences.styleWaitUntil=tonumber(saved.styleWaitUntil)
     if type(saved.auto)=='table' then for _,k in ipairs({'v3','v4','aura','rollFruit','storeFruit'}) do preferences.auto[k]=saved.auto[k]==true end end
     if type(saved.other)=='table' then
      for _,key in ipairs({'berry','berryHop','aura','sword','chest','chestHop','limit','haki','hakiHop'}) do preferences.other[key]=saved.other[key]==true end
      preferences.other.count=math.clamp(math.floor(tonumber(saved.other.count) or 20),1,1000)
      preferences.other.job=saved.other.job;preferences.other.collected=tonumber(saved.other.collected) or 0
     end
     preferences.eliteHop=saved.eliteHop==true;preferences.fruitHop=saved.fruitHop==true
     for _,k in ipairs({'Melee','Defense','Sword','Gun','Demon Fruit'}) do stats.Select(k,type(saved.stats)=='table' and saved.stats[k]==true) end
     for _,k in ipairs({'elite','factory','raid','ripindra','darkbeard','doughking','reaper'}) do farm.stackEvents[k]=type(f.stackEvents)=='table' and f.stackEvents[k]==true or false end
     farm.stackFruit=f.stackFruit==true;farm.SetAutoClick(f.autoClick==true)
     farm.SetMode(farm.mode,f.enabled==true)
     if ss.enabled then sea.SetEnabled(true) elseif travelChosen and travel.active then travelAPI.Start() end
    end
   end
  end
  preferences.auto.aura=true;preferences.movement.water=true;farm.autoAura=true
  preferenceReady=true;updatePreferenceLabels();save(true,true)
 end)
 connect(game:GetService('TeleportService').TeleportInitFailed,function(who)
  if who==player then teleporting=false end
 end)
 connect(player.OnTeleport,function(state)
  if state==Enum.TeleportState.Failed then teleporting=false;queued=false;return end
  if state~=Enum.TeleportState.Started and state~=Enum.TeleportState.InProgress then return end
  teleporting=true;save(true,true)
  if queued or not preferences.autoLoad or not available then return end
  local queue=queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
  if type(queue)~='function' then warn('Nexo: executor does not expose teleport reinjection');return end
  if not isfile('Nexo/main.lua') then warn('Nexo: run the installer to enable teleport reinjection');return end
  local loader=[==[
local env=type(getgenv)=='function' and getgenv() or _G
local arrival=tostring(game.PlaceId)..':'..game.JobId
if env.NexoArrivalClaim==arrival then return end
env.NexoArrivalClaim=arrival
local ok,err=xpcall(function()
 if not game:IsLoaded() then game.Loaded:Wait() end
 local players=game:GetService('Players');local p=players.LocalPlayer
 while not p do task.wait(.25);p=players.LocalPlayer end
 local path='Nexo/settings-'..p.UserId..'.json'
 local c=game:GetService('HttpService'):JSONDecode(readfile(path))
 if type(c)~='table' or c.autoLoad==false or not c.resume or c.userId~=p.UserId then return end
 local current=env.NexoFarmUI
 if current and current.Status and current.Status().alive then return end
 env.NexoTeleportBoot=true
 local f,e=loadstring(readfile('Nexo/main.lua'));assert(f,e);f()
end,debug.traceback)
env.NexoTeleportBoot=nil
if not ok then env.NexoArrivalClaim=nil;warn('Nexo auto-load: '..tostring(err)) end
]==]
  queued=pcall(queue,loader)
 end)
 task.spawn(function() while alive do task.wait(2);if alive and preferenceReady and preferences.autoSave and not teleporting then save(true,false) end end end)
end

local otherFarm={busy=false,stopped=false,chestReady=false,berryReady=false}
preferences.Other=otherFarm
do
 local rs=game:GetService('ReplicatedStorage')
 local collection=game:GetService('CollectionService')
 local panel=panels['Farm Other']
 local buttons={};local deferred=setmetatable({},{__mode='k'})
 local token;local resumeFarm;local currentChest;local chestConfirmed=false;local nextVendor={};local knownOffers={}
 local patrolVisited={};local patrolDone=false;local patrolRestart=0
 local function config() return preferences.other end
 local function refreshButtons()
  for key,b in pairs(buttons) do
   local enabled=config()[key]==true
   b.Text=enabled and 'ON' or 'OFF'
   b.BackgroundColor3=enabled and Color3.fromRGB(97,76,43) or Color3.fromRGB(49,46,40)
  end
 end
 local function row(text,key,y,hopKey)
  label(panel,text,18,y,240,28,13)
  if hopKey then
   label(panel,'Hop',275,y,48,28,12)
   local hop=control(panel,'OFF',323,y,60,27);buttons[hopKey]=hop
   bindControl(hop,'Activated',function()
    otherFarm.stopped=false
    config()[hopKey]=not config()[hopKey]
    if config()[hopKey] then config()[key]=true;preferences.save=true end
    refreshButtons();task.defer(preferences.Flush)
   end)
  end
  local b=control(panel,'OFF',410,y,80,27);buttons[key]=b
  bindControl(b,'Activated',function()
   otherFarm.stopped=false
   config()[key]=not config()[key]
   if key=='aura' or key=='sword' then nextVendor[key]=0 end
   if key=='chest' then patrolVisited={};patrolDone=false;otherFarm.chestReady=config().chest end
   if not config()[key] and key~='limit' and token then farm.SeaEnd(token);token=nil end
   refreshButtons();task.defer(preferences.Flush)
  end)
 end
 row('Pick up berry','berry',12,'berryHop')
 row('Buy aura / recipe','aura',54)
 row('Buy legendary sword','sword',96)
 row('Collect chest','chest',138,'chestHop')
 row('Limit chests per server','limit',180)
 local countBox=make('TextBox',panel,{Name='ChestLimit',Text='20',Position=UDim2.fromOffset(323,180),Size=UDim2.fromOffset(60,27),BackgroundColor3=Color3.fromRGB(49,46,40),TextColor3=pale,TextSize=13,Font=Enum.Font.Gotham,ClearTextOnFocus=false,BorderSizePixel=0,ZIndex=4})
 make('UICorner',countBox,{CornerRadius=UDim.new(0,6)})
 bindControl(countBox,'FocusLost',function() config().count=math.clamp(math.floor(tonumber(countBox.Text) or 20),1,1000);countBox.Text=tostring(config().count);preferences.Flush() end)
 local statusText=label(panel,'Chests: 0',18,224,478,30,12)
 local function say(text) otherFarm.message=text;statusText.Text='Chests: '..tostring(config().collected or 0)..'  •  '..text end
 function otherFarm.Stop()
  otherFarm.stopped=true;otherFarm.paused=false
  resumeFarm=nil;currentChest=nil;otherFarm.busy=false;otherFarm.chestReady=false;otherFarm.berryReady=false
  for _,k in ipairs({'berry','berryHop','aura','sword','chest','chestHop'}) do config()[k]=false end
  if token then farm.SeaEnd(token);token=nil end
  refreshButtons()
 end
 function otherFarm.PausePriority()
  otherFarm.paused=true;otherFarm.busy=false
  local previous=resumeFarm and table.clone(resumeFarm)
  if token then farm.SeaEnd(token);token=nil end
  resumeFarm=nil
  return previous
 end
 function otherFarm.ResumePriority() otherFarm.paused=false end
 local function safe()
  return alive and not otherFarm.paused and not otherFarm.stopped and not (preferences.HasRareItem and preferences.HasRareItem())
 end
 local function root() local c=player.Character;return c and c:FindFirstChild('HumanoidRootPart') end
 local function berries(includeDeferred)
  local r=root();if not r then return end
  local best,gap
  for _,bush in ipairs(collection:GetTagged('BerryBush')) do
   local parent=bush.Parent;local base=parent and parent:GetAttribute('CFrame')
   if typeof(base)=='CFrame' then for key,value in pairs(bush:GetAttributes()) do
    local offset=parent:GetAttribute(key)
    if type(key)=='string' and key:sub(1,12)=='_BerryCFrame' and type(value)=='string' and typeof(offset)=='CFrame' then
     local p=base:ToWorldSpace(offset).Position;local d=(p-r.Position).Magnitude
     if (includeDeferred or (deferred[bush] or 0)<os.clock()) and (not gap or d<gap) then best={object=bush,id=parent.Name,key=key,position=p};gap=d end
    end
   end end
  end
  return best
 end
 local chestTypes
 pcall(function() chestTypes=require(rs.ChestConfiguration.ChestTypes) end)
 local chestParts={}
 local function watchChest(v)
  if v:IsA('BasePart') and chestTypes and chestTypes[v.Name] then chestParts[v]=true end
 end
 for _,v in ipairs(workspace:GetDescendants()) do watchChest(v) end
 connect(workspace.DescendantAdded,watchChest)
 connect(workspace.DescendantRemoving,function(v) chestParts[v]=nil end)
 local function chests(includeDeferred)
  local r=root();if not r then return end
  local best,gap
  for v in pairs(chestParts) do
   if v.Parent and not v:GetAttribute('IsDisabled') and (includeDeferred or (deferred[v] or 0)<os.clock()) then
    local d=(v.Position-r.Position).Magnitude
    if not gap or d<gap then best=v;gap=d end
   end
  end
  return best
 end
 local remote=rs:FindFirstChild('Remotes') and rs.Remotes:FindFirstChild('Chest')
 if remote then connect(remote.OnClientEvent,function(chest,available)
  local r=root()
  if chest==currentChest and available==false and r and chest:IsA('BasePart') and (r.Position-chest.Position).Magnitude<20 then chestConfirmed=true end
 end) end
 local function beginMove(position)
  if not safe() then return false end
  resumeFarm={enabled=farm.enabled,stackFruit=farm.stackFruit,autoClick=farm.autoClick}
  sea.SetEnabled(false);travelAPI.Stop()
  token=farm.SeaBegin();otherFarm.busy=true
  return farm.SeaMove(position,token) and safe() and farm.SeaActive(token)
 end
 local function finishMove()
  local ownsMovement=token and farm.SeaActive(token)
  if token then farm.SeaEnd(token);token=nil end
  currentChest=nil;otherFarm.busy=false
  if resumeFarm and safe() and ownsMovement then
   farm.stackFruit=resumeFarm.stackFruit;farm.SetAutoClick(resumeFarm.autoClick);farm.SetMode(farm.mode,resumeFarm.enabled)
  end
  resumeFarm=nil
 end
 local function collectBerry(b)
  say('Collecting berry')
  if beginMove(b.position+Vector3.new(0,2,0)) and config().berry then
   local net=rs.Modules.Net:FindFirstChild('RF/ClaimBerry')
   if net and safe() then net:InvokeServer(b.id,b.key) end
   task.wait(.15)
  end
  deferred[b.object]=os.clock()+10;finishMove()
 end
 local function patrolChests()
  if not config().chest or not safe() then return end
  if patrolDone then
   if config().chestHop then return end
   if os.clock()<patrolRestart then say('Waiting for chest respawns');return end
   patrolVisited={};patrolDone=false
  end
  local r=root();if not r then return end
  local entries=travelAPI.Options();local best,gap
  for _,entry in ipairs(entries) do
   if not patrolVisited[entry.key] then
    local distance=(entry.position-r.Position).Magnitude
    if not gap or distance<gap then best=entry;gap=distance end
   end
  end
  if not best then
   if #entries==0 then say('Waiting for island locations');return end
   patrolDone=true;patrolRestart=os.clock()+15
   otherFarm.chestReady=not config().chestHop
   say(config().chestHop and 'Island sweep complete; waiting to hop' or 'Island sweep complete');return
  end
  say('Searching '..best.name);otherFarm.chestReady=true
  if beginMove(best.position+Vector3.new(0,5,0)) and config().chest then
   local deadline=os.clock()+2
   repeat task.wait(.1) until chests() or not safe() or not config().chest or not farm.SeaActive(token) or os.clock()>=deadline
   if safe() and config().chest and farm.SeaActive(token) then patrolVisited[best.key]=true end
  end
  finishMove()
 end
 local function collectChest(chest)
  say('Collecting chest');currentChest=chest;chestConfirmed=false
  local data=player:FindFirstChild('Data')
  local beli=data and data:FindFirstChild('Beli')
  local beforeMoney=beli and beli.Value
  if beginMove(chest.Position+Vector3.new(0,2,0)) and config().chest then
   local deadline=os.clock()+5
   repeat
    if not safe() then break end
    local r=root()
    if r and chest.Parent and (r.Position-chest.Position).Magnitude<12 and type(firetouchinterest)=='function' then
     firetouchinterest(r,chest,0);firetouchinterest(r,chest,1)
    end
    task.wait(.2)
   until chestConfirmed or not chest.Parent or chest:GetAttribute('IsDisabled') or os.clock()>deadline
   if not chestConfirmed and chest.Parent and chest:GetAttribute('IsDisabled') then
    local rewardDeadline=os.clock()+2
    repeat
     if beforeMoney and beli and beli.Value>beforeMoney then chestConfirmed=true;break end
     if preferences.HasRareItem and preferences.HasRareItem() then chestConfirmed=true;break end
     task.wait(.1)
    until not alive or os.clock()>rewardDeadline
   end
   if chestConfirmed then config().collected=(config().collected or 0)+1;preferences.Flush();say('Pickup confirmed')
   else say('Pickup not confirmed; retry later') end
  end
  deferred[chest]=os.clock()+15;finishMove()
 end
 local function vendor(kind)
  if not config()[kind] or (nextVendor[kind] or 0)>os.clock() then return false end
  nextVendor[kind]=os.clock()+30
  if kind=='aura' then
   local places={[4442272183]=true,[79091703265657]=true,[7449423635]=true,[100117331123089]=true}
   if not places[game.PlaceId] then otherFarm.auraMessage='Aura recipes require Sea 2 or Sea 3';say(otherFarm.auraMessage);return false end
   local comm=rs.Remotes:FindFirstChild('CommF_');if not comm then return false end
   local offer=comm:InvokeServer('ColorsDealer','1')
   if not alive or not config().aura or not safe() then return false end
   if offer==1 then otherFarm.auraMessage='Upgrade Aura before learning recipes';say(otherFarm.auraMessage);return true end
   if type(offer)~='string' or offer=='' then otherFarm.auraMessage='Waiting for an Aura recipe offer';return false end
   if knownOffers['aura'..offer] then otherFarm.auraMessage='Recipe already known: '..offer;return false end
   local result=comm:InvokeServer('ColorsDealer','2')
   if result==1 or result==2 then
    knownOffers['aura'..offer]=true
    otherFarm.auraMessage=(result==1 and 'Recipe obtained: ' or 'Recipe already known: ')..offer
   elseif result==0 then otherFarm.auraMessage='Not enough money for recipe: '..offer
   else otherFarm.auraMessage='Aura offer changed or unavailable; will check again' end
   say(otherFarm.auraMessage);return true
  end
  local npcs=workspace:FindFirstChild('NPCs');local found
  if npcs then for _,npc in ipairs(npcs:GetChildren()) do
   local n=npc.Name:lower()
   if npc:IsA('Model') and ((kind=='sword' and n=='legendary sword dealer') or (kind=='aura' and (n=='master of enhancement' or n=='barista cousin'))) then found=npc;break end
  end end
  if not found then return false end
  local command=kind=='sword' and 'LegendarySwordDealer' or 'ColorsDealer'
  local comm=rs.Remotes:FindFirstChild('CommF_');if not comm then return false end
  local offer=comm:InvokeServer(command,'1')
  if type(offer)~='string' or knownOffers[kind..offer] then return false end
  say('Visiting '..found.Name)
  if beginMove(found:GetPivot().Position+Vector3.new(0,0,5)) and config()[kind] and safe() then
   local result=comm:InvokeServer(command,'2')
   if result==1 or result==2 then knownOffers[kind..offer]=true;say(result==1 and ('Purchased: '..offer) or ('Already owned: '..offer))
   else nextVendor[kind]=os.clock()+60;say('Purchase unavailable or insufficient funds') end
  end
  finishMove();return true
 end
 task.spawn(function()
  while alive do
   if preferenceReady then
    local c=config()
    if c.job~=game.JobId then c.job=game.JobId;c.collected=0;patrolVisited={};patrolDone=false end
    refreshButtons()
    if not countBox:IsFocused() then countBox.Text=tostring(c.count) end
    if safe() and not farm.HasStackTarget() then
     local ok,err=pcall(function()
      local berry=c.berry and berries();local limited=c.limit and (c.collected or 0)>=c.count
      local chest=c.chest and not limited and chests()
      -- A retry delay must not look like an empty server to the hop controller.
      otherFarm.berryReady=c.berry and berries(true)~=nil or false
      otherFarm.chestReady=c.chest and not limited and (chests(true)~=nil or not patrolDone or not c.chestHop) or false
      if vendor('aura') or vendor('sword') then return end
      if berry then collectBerry(berry)
      elseif chest then collectChest(chest)
      elseif c.chest and not limited and not chests(true) then patrolChests()
      else say(limited and 'Chest limit reached' or c.aura and otherFarm.auraMessage or 'Waiting for collectibles') end
     end)
     if not ok then finishMove();say('Retry: '..tostring(err)) end
    end
   end
   task.wait(.2)
  end
 end)
end

-- Elite hopping and a higher-priority Chalice guard.
do
 local http=game:GetService('HttpService')
 local teleport=game:GetService('TeleportService')
 local rs=game:GetService('ReplicatedStorage')
 local busy=false;local protected=false;local absentSince=os.clock();local nextHop=0
 local retreatStarted=false;local retreatToken
 label(settings,'Retreat to Safety with Rare Items',18,406,370,28,13)
 local retreatToggle=control(settings,'ON',410,406,80,28)
 bindControl(retreatToggle,'Activated',function()
  preferences.safeRetreat=not preferences.safeRetreat
  retreatToggle.Text=preferences.safeRetreat and 'ON' or 'OFF'
  if not preferences.safeRetreat and retreatToken then farm.SeaEnd(retreatToken);retreatToken=nil;retreatStarted=false end
  task.defer(preferences.Flush)
 end)
 local visited={[game.JobId]=true}
 local serverBrowser=rs:FindFirstChild('__ServerBrowser')
 local hopPlaceId=game.PlaceId
 local serverCursor=nil
 local browserPage=1
 local candidates={};local attempted={};local attempts=0
 local httpUnavailableUntil=0;local nativeUnavailableUntil=0
 local listFailures=0;local lastListError
 local function report(message) farm.message=message;preferences.HopMessage=message end
 -- Keep the exact joined place. Never substitute the other variant of a sea.
 local seaByPlace={[2753915549]=1,[85211729168715]=1,[4442272183]=2,[79091703265657]=2,[7449423635]=3,[100117331123089]=3}
 preferences.HopPlaceId=hopPlaceId;preferences.HopSea=seaByPlace[hopPlaceId]
 if type(readfile)=='function' and type(isfile)=='function' then pcall(function()
  local path='Nexo/visited-'..player.UserId..'.json'
  if isfile(path) then
   for id,t in pairs(http:JSONDecode(readfile(path))) do
    if type(t)=='number' and os.time()-t<3600 then visited[id]=t end
   end
  end
 end) end
 visited[game.JobId]=os.time()
 pcall(function() writefile('Nexo/visited-'..player.UserId..'.json',http:JSONEncode(visited)) end)
 local function boundedCall(fn,seconds)
  local done,ok,result=false,false,nil
  local thread=task.spawn(function() ok,result=pcall(fn);done=true end)
  local deadline=os.clock()+seconds
  repeat task.wait(.1) until done or not alive or os.clock()>=deadline
  if not done then pcall(task.cancel,thread);error("Server request timed out") end
  if not ok then error(result) end
  return result
 end
 local pending;local retrySoon=false;local manualMode;local preferredJoinRoute=({[85211729168715]=true,[79091703265657]=true,[100117331123089]=true})[hopPlaceId] and 'native' or nil
 local function teleportFailed(reason)
  if not pending then return end
  local failed=pending;pending=nil;retrySoon=true;nextHop=os.clock()+2
  preferredJoinRoute=failed.route=='public' and 'native' or 'public'
  attempted[failed.id]=os.clock()+60
  if tostring(reason):lower():find('restrict',1,true) then
   if failed.route=='native' then nativeUnavailableUntil=os.clock()+60 else httpUnavailableUntil=os.clock()+30 end
   candidates={}
  end
  report('Hop failed ('..tostring(reason)..'); trying another server')
 end
 connect(teleport.TeleportInitFailed,function(who,result,message,placeId)
  if who==player and pending then teleportFailed(tostring(result)..': '..tostring(message)) end
 end)
 connect(player.OnTeleport,function(state)
  if state==Enum.TeleportState.Failed then
   local attempt=pending
   task.delay(.25,function() if pending and pending==attempt then teleportFailed('teleport failed') end end)
  elseif pending and state==Enum.TeleportState.InProgress then pending.inProgress=true end
 end)
 label(settings,'Hop wait (seconds)',18,232,290,28,13)
 local waitBox=make('TextBox',settings,{Name='HopWait',Text=tostring(preferences.hopWait or 20),Position=UDim2.fromOffset(344,232),Size=UDim2.fromOffset(150,26),BackgroundColor3=Color3.fromRGB(49,46,40),TextColor3=pale,TextSize=13,Font=Enum.Font.Gotham,ClearTextOnFocus=false,BorderSizePixel=0,ZIndex=4})
 make('UICorner',waitBox,{CornerRadius=UDim.new(0,6)})
 bindControl(waitBox,'FocusLost',function()
  preferences.hopWait=math.clamp(math.floor(tonumber(waitBox.Text) or preferences.hopWait or 20),1,600)
  waitBox.Text=tostring(preferences.hopWait);absentSince=os.clock();preferences.Flush()
 end)
 label(stackPanel,'Hop server',18,144,380,30,13)
 local button=control(stackPanel,'OFF',410,146,80,28)
 label(stackPanel,'Hop server',18,64,380,30,13)
 local fruitButton=control(stackPanel,'OFF',410,66,80,28)
 local function hasChalice()
  for _,container in pairs({player:FindFirstChild('Backpack'),player.Character}) do
   if container then for _,tool in ipairs(container:GetChildren()) do
    local n=tool.Name:lower():gsub('[^%a]','')
    if tool:IsA('Tool') and (n=='godschalice' or n=='godchalice' or n=='sweetchalice' or n=='fistofdarkness') then return tool.Name end
   end end
  end
  return false
 end
 preferences.HasRareItem=hasChalice
 local function elitePresent()
  for _,container in ipairs({rs,workspace:FindFirstChild('Enemies')}) do
   if container then for _,enemy in ipairs(container:GetChildren()) do
    local n=enemy.Name:lower():gsub('%s*%[.-%]','')
    if n=='urban' or n=='diablo' or n=='deandre' then
     local h=enemy:FindFirstChildOfClass('Humanoid')
     if h and h.Health>0 then return true end
    end
   end end
  end
  return false
 end
 local function stopEverything()
  for k in pairs(preferences.auto) do preferences.auto[k]=false end;farm.autoAura=false;farm.autoStore=false
  preferences.eliteHop=false;preferences.fruitHop=false;button.Text='OFF';fruitButton.Text='OFF'
  otherFarm.Stop();travelAPI.Stop();sea.SetEnabled(false)
  for k in pairs(farm.stackEvents) do farm.stackEvents[k]=false end
  farm.stackFruit=false;farm.SetAutoClick(false);farm.SetMode(farm.mode,false)
  for _,k in ipairs({'Melee','Defense','Sword','Gun','Demon Fruit'}) do stats.Select(k,false) end
  preferences.Flush()
 end
 local function shelter()
  local item=hasChalice() or "Rare item"
  local fist=item:lower():find("fist",1,true)~=nil
  protected=true;stopEverything()
  farm.message=item..": moving to safety"
  local token=farm.SeaBegin();retreatToken=token
  -- Never reset or teleport while carrying a rare summon item.
  local destination=fist and Vector3.new(-385,73,297) or Vector3.new(-12548,338,-7481)
  for _=1,5 do
   if not alive or not preferences.safeRetreat or preferences.autoSpawnIndra or preferences.autoSpawnDoughKing or preferences.autoSpawnDarkbeard or not farm.SeaActive(token) then return end
   if farm.SeaMove(destination,token) then
    farm.SeaEnd(token);if fist then preferences.fistSheltered=true end;farm.message=item..(fist and ": staying at Cafe" or ": staying at Mansion");return
   end
   task.wait(1)
  end
  farm.SeaEnd(token);farm.message=item..": stopped; safe-zone travel needs attention"
 end
 local function canHop()
  if preferences.collectFist then return false end
  if manualMode=='moon' and not preferences.findFullMoon then return false end
  if manualMode=='haki' and not (preferences.other.haki and preferences.other.hakiHop) then return false end
  if preferences.StyleHasKey and preferences.StyleHasKey() then return false end
  if preferences.styleJob and manualMode~='style' then return false end
  if preferences.priorityBusy or farm.PriorityBoss() then return false end
  if manualMode then return alive and not protected and not hasChalice() end
  local c=preferences.other
  local otherWants=(c.berry and c.berryHop) or (c.chest and c.chestHop)
  local otherTarget=(c.berry and otherFarm.berryReady) or (c.chest and otherFarm.chestReady)
  return alive and not protected and preferences.save and not otherFarm.busy and not otherTarget
   and ((preferences.eliteHop and farm.stackEvents.elite) or (preferences.fruitHop and farm.stackFruit) or otherWants)
   and not hasChalice() and not farm.HasStackTarget() and not (farm.stackEvents.elite and elitePresent()) and not (farm.stackFruit and farm.HasLooseFruit())
 end
 preferences.CancelHakiHop=function() if manualMode=='haki' then manualMode=nil;retrySoon=false;nextHop=0 end end
 preferences.CancelAllHop=function() manualMode=nil;retrySoon=false;nextHop=0 end
 preferences.CancelMoonHop=function() if manualMode=='moon' then manualMode=nil;retrySoon=false;nextHop=0 end end
 preferences.CancelStyleHop=function() if manualMode=='style' then manualMode=nil;retrySoon=false;nextHop=0 end end
 preferences.RequestHop=function(mode)
  if protected or hasChalice() or (preferences.StyleHasKey and preferences.StyleHasKey()) then return false,'Key or rare item: hopping blocked' end
  if busy or pending or manualMode then return false,'Already looking for a server' end
  manualMode=mode=='haki' and 'haki' or mode=='moon' and 'moon' or mode=='style' and 'style' or mode=='low' and 'low' or 'random';retrySoon=true;nextHop=0
  candidates={};serverCursor=nil;browserPage=1;attempts=0
  preferences.save=true;preferences.Flush();report('Finding a server...');return true,'Finding a server...'
 end
 local function eligible(id,count,capacity)
  if type(id)~='string' or id=='' or id==game.JobId then return false end
  local seen=visited[id]
  if type(seen)=='number' and os.time()-seen>=3600 then visited[id]=nil;seen=nil end
  count=tonumber(count);capacity=tonumber(capacity)
  return not seen and (not attempted[id] or os.clock()>=attempted[id])
   and count and capacity and count>=0 and count<capacity
   and (manualMode~='low' or count<2) -- fewer than three players including us
 end
 local function consider(id,count,capacity,route,destination)
  if destination and tonumber(destination)~=hopPlaceId then return end
  if eligible(id,count,capacity) then
   candidates[#candidates+1]={id=id,count=count,capacity=capacity,route=route}
  end
 end
 local function publicPage()
  local requestFn=request or http_request
  if type(requestFn)~='function' or os.clock()<httpUnavailableUntil then return false end
  local order=manualMode=='low' and 'Asc' or 'Desc' -- Only the explicit low-player action uses sparse-first listings.
  local url='https://games.roblox.com/v1/games/'..hopPlaceId..'/servers/Public?sortOrder='..order..'&limit=100'
  if serverCursor then url=url..'&cursor='..http:UrlEncode(serverCursor) end
  local ok,reply=pcall(function() return boundedCall(function()return requestFn({Url=url,Method='GET'})end,15) end)
  if not ok or type(reply)~='table' or tonumber(reply.StatusCode)~=200 then
   listFailures=listFailures+1
   httpUnavailableUntil=os.clock()+math.min(60,15*2^math.min(listFailures-1,2))
   lastListError=ok and ('HTTP '..tostring(type(reply)=='table' and reply.StatusCode or 'invalid reply')) or tostring(reply)
   return false
  end
  local decoded,data=pcall(function()return http:JSONDecode(reply.Body)end)
  if not decoded or type(data)~='table' or type(data.data)~='table' then httpUnavailableUntil=os.clock()+5;return false end
  listFailures=0;lastListError=nil
  serverCursor=type(data.nextPageCursor)=='string' and data.nextPageCursor or nil
  for _,server in ipairs(data.data) do
   if type(server)=='table' then consider(server.id,server.playing,server.maxPlayers,'public',hopPlaceId) end
  end
  return true
 end
 local function nativePage()
  serverBrowser=rs:FindFirstChild('__ServerBrowser')
  if not serverBrowser or not serverBrowser:IsA('RemoteFunction') or os.clock()<nativeUnavailableUntil then return false end
  local page=browserPage;browserPage=browserPage%100+1
  local ok,data=pcall(function()return boundedCall(function()return serverBrowser:InvokeServer(page)end,5)end)
  if not ok or type(data)~='table' then nativeUnavailableUntil=os.clock()+8;return false end
  for id,server in pairs(data) do
   if type(server)=='table' then
    consider(server.id or server.JobId or id,server.Count or server.playing,server.MaxPlayers or server.maxPlayers or game:GetService('Players').MaxPlayers,'native',server.PlaceId or server.placeId)
   end
  end
  return true
 end
 local function hop()
  if busy or pending or not canHop() then return end
  busy=true;retrySoon=true
  local ok,err=pcall(function()
   -- Keep unused candidates so a full/failed destination can be replaced quickly.
   local candidate
   for _=1,4 do
    if not canHop() then return end
    while #candidates>0 do
     local index=manualMode=='low' and 1 or math.random(1,#candidates)
     local c=table.remove(candidates,index)
     if eligible(c.id,c.count,c.capacity) and (c.route~='public' or os.clock()>=httpUnavailableUntil) and (c.route~='native' or os.clock()>=nativeUnavailableUntil) then candidate=c;break end
    end
    if candidate then break end
    local listed=publicPage()
    if #candidates==0 and (not listed or not serverCursor) and canHop() then nativePage() end
   end
   if not candidate then
    -- The last page may have just filled the queue; use it on the next quick pass.
    report(#candidates>0 and 'Server found; preparing hop' or (lastListError and ('Server list unavailable; retrying ('..lastListError..')') or 'No eligible server yet; searching again'))
    return
   end
   if not canHop() then return end
   preferences.Flush()
   if not canHop() then return end
   attempts=attempts+1;attempted[candidate.id]=os.clock()+60
   local route=candidate.route
   serverBrowser=rs:FindFirstChild('__ServerBrowser')
   if preferredJoinRoute=='native' and serverBrowser and serverBrowser:IsA('RemoteFunction') and os.clock()>=nativeUnavailableUntil then route='native' end
   pending={id=candidate.id,route=route,started=os.clock()}
   report('Joining server (attempt '..attempts..')')
   if route=='native' then
    local result=boundedCall(function()return serverBrowser:InvokeServer('teleport',candidate.id)end,8)
    if result==false then teleportFailed('game declined destination') end
   else
    teleport:TeleportToPlaceInstance(hopPlaceId,candidate.id,player)
   end
  end)
  if not ok then
   if pending then teleportFailed(err) else report('Server search failed; retrying: '..tostring(err)) end
  end
  nextHop=os.clock()+2;busy=false
 end
 bindControl(button,'Activated',function()
  if protected or hasChalice() then return end
  preferences.eliteHop=not preferences.eliteHop
  if preferences.eliteHop then preferences.save=true;farm.SetStackEvent('elite',true) end
  absentSince=os.clock();preferences.Flush();button.Text=preferences.eliteHop and 'ON' or 'OFF'
 end)
 bindControl(fruitButton,'Activated',function()
  if protected or hasChalice() then return end
  preferences.fruitHop=not preferences.fruitHop
  if preferences.fruitHop then preferences.save=true;farm.SetStackFruit(true) end
  absentSince=os.clock();preferences.Flush();fruitButton.Text=preferences.fruitHop and 'ON' or 'OFF'
 end)
 task.spawn(function()
  while alive do
   if preferenceReady then
    if pending and os.clock()-pending.started>(pending.inProgress and 60 or 12) then teleportFailed('destination did not load') end
    if not waitBox:IsFocused() then waitBox.Text=tostring(preferences.hopWait or 20) end
    button.Text=preferences.eliteHop and 'ON' or 'OFF';fruitButton.Text=preferences.fruitHop and 'ON' or 'OFF'
    retreatToggle.Text=preferences.safeRetreat and 'ON' or 'OFF'
    local rare=hasChalice()
    local intentional=(preferences.autoSpawnDarkbeard and rare=='Fist of Darkness') or ((preferences.autoSpawnIndra or preferences.autoSpawnDoughKing) and rare and rare:lower():find('chalice',1,true)) or (preferences.autoSpawnDoughKing and os.clock()<(preferences.doughExchangeUntil or 0))
    if protected and not rare and not intentional then
     -- Consumed/lost item: release protection, but leave canceled jobs OFF.
     if retreatToken then farm.SeaEnd(retreatToken);retreatToken=nil end
     protected=false;retreatStarted=false;absentSince=os.clock()
    end
    if intentional then
     if retreatToken then farm.SeaEnd(retreatToken);retreatToken=nil end
     retreatStarted=false;protected=false;absentSince=os.clock()
    elseif not protected and hasChalice() then
     protected=true;stopEverything()
     if preferences.safeRetreat then retreatStarted=true;task.spawn(shelter)
     else farm.message=tostring(hasChalice())..': stopped here; server hopping blocked' end
    elseif protected and hasChalice() and preferences.safeRetreat and not retreatStarted then
     retreatStarted=true;task.spawn(shelter)
    elseif not protected then
     if not canHop() then absentSince=os.clock() end
     if canHop() and (retrySoon or os.clock()-absentSince>=(preferences.hopWait or 20)) and os.clock()>=nextHop and not busy and not pending then task.spawn(hop) end
    end
   end
   task.wait(.2)
  end
 end)
end

do
 local buttons={};local pending={};local nextTry={}
 farm.autoAura=preferences.auto.aura==true
 local function reflect()
  for key,b in pairs(buttons) do
   local enabled=preferences.auto[key]==true
   b.Text=enabled and 'ON' or 'OFF'
   b.BackgroundColor3=enabled and Color3.fromRGB(97,76,43) or Color3.fromRGB(49,46,40)
  end
 end
 for i,entry in ipairs({{'v3','Auto V3'},{'v4','Auto V4'},{'aura','Auto Aura'}}) do
  local key=entry[1];local y=274+(i-1)*44
  label(settings,entry[2],18,y,290,28,13)
  local b=control(settings,'OFF',410,y,80,28);buttons[key]=b
  bindControl(b,'Activated',function()
   if preferences.HasRareItem and preferences.HasRareItem() then return end
   preferences.auto[key]=not preferences.auto[key]
   farm.autoAura=preferences.auto.aura==true
   nextTry[key]=0;reflect();task.defer(preferences.Flush)
  end)
 end
 local function findTool(kind)
  local v3Names={['Last Resort']=true,Agility=true,['Water Body']=true,['Heavenly Blood']=true,['Heightened Senses']=true,['Energy Core']=true,['Primordial Reign']=true}
  for _,container in pairs({player.Character,player:FindFirstChild('Backpack')}) do
   for _,tool in ipairs(container:GetChildren()) do
    if tool:IsA('Tool') then
     if kind=='v4' and tool.Name=='Awakening' then return tool end
     if kind=='v3' then
      local refs=tostring(tool:GetAttribute('FolderReferences') or '')
      if v3Names[tool.Name] or refs:find('RaceV3Auras',1,true) then return tool end
     end
    end
   end
  end
 end
 local function readyV4(char)
  local energy=char:FindFirstChild('RaceEnergy');local transformed=char:FindFirstChild('RaceTransformed')
  return energy and energy.Value>=1 and transformed and not transformed.Value
 end
 local function invoke(kind,tool)
  if pending[kind] or os.clock()<(nextTry[kind] or 0) then return end
  pending[kind]=true;nextTry[kind]=os.clock()+2
  task.spawn(function()
   pcall(function()
    if not alive or not preferences.auto[kind] or (preferences.HasRareItem and preferences.HasRareItem()) then return end
    if kind=='v4' then
     local char=player.Character
     if char and readyV4(char) then game.ReplicatedStorage.Events.ActivateRaceV4:Fire() end
    else
     game.ReplicatedStorage.Remotes.CommE:FireServer('ActivateAbility')
    end
   end)
   pending[kind]=false
  end)
 end
 task.spawn(function()
  while alive do
   if preferenceReady then
    reflect();farm.autoAura=preferences.auto.aura==true
    local char=player.Character;local h=char and char:FindFirstChildOfClass('Humanoid')
    local busy=char and char:FindFirstChild('Busy');local stun=char and char:FindFirstChild('Stun')
    if h and h.Health>0 and not (preferences.HasRareItem and preferences.HasRareItem()) then
     if preferences.auto.aura then farm.EnsureAura() end
     if not (busy and busy.Value) and not (stun and stun.Value>0) then
      if preferences.auto.v4 and readyV4(char) then
       local ok,transformed=pcall(function() return require(game.ReplicatedStorage.Util.IsTransformed)(char,false,false) end)
       if ok and not transformed then local tool=findTool('v4');if tool then invoke('v4',tool) end end
      end
      if preferences.auto.v3 then local tool=findTool('v3');if tool and tool.Enabled then invoke('v3',tool) end end
     end
    end
   end
   task.wait(.25)
  end
 end)
end

do
 line(panels['Raid + Fruit'],168);line(panels['Raid + Fruit'],208);line(panels['Raid + Fruit'],248)
 label(panels['Raid + Fruit'],'Roll Fruit',18,174,280,28,13)
 local toggle=control(panels['Raid + Fruit'],'OFF',410,174,80,28)
 label(panels['Raid + Fruit'],'Store Fruit',18,214,280,28,13)
 local storeToggle=control(panels['Raid + Fruit'],'OFF',410,214,80,28)
 bindControl(storeToggle,'Activated',function()
  preferences.auto.storeFruit=not preferences.auto.storeFruit
  farm.autoStore=preferences.auto.storeFruit
  storeToggle.Text=farm.autoStore and 'ON' or 'OFF'
  task.defer(preferences.Flush)
 end)
 local rollStatus=label(panels['Raid + Fruit'],'',18,252,470,24,10)
 local nextCheck=0;local busy=false
 local function closeRollResult()
  task.spawn(function()
   local deadline=os.clock()+45
   local sawOpen=false
   while alive and os.clock()<deadline do
    local gui=player:FindFirstChild('PlayerGui')
    local screen=gui and gui:FindFirstChild('SpinnerWindow')
    if screen and screen:IsA('ScreenGui') and screen.Enabled then
     sawOpen=true
     local button=screen:FindFirstChild('CloseButton',true)
     if button and button:IsA('GuiObject') and button.Visible then
      task.wait(.8)
      if not alive or not screen.Parent or not screen.Enabled or not button.Parent or not button.Visible then return end
      pcall(function()
       local ui=game.ReplicatedStorage.Controllers.UI
       require(ui.Spinner):Close()
       task.wait(.1)
       if alive then require(ui.GachaWindow):Close(true) end
      end)
      return
     end
    elseif sawOpen then return end
    task.wait(.2)
   end
  end)
 end
 bindControl(toggle,'Activated',function()
  preferences.auto.rollFruit=not preferences.auto.rollFruit
  toggle.Text=preferences.auto.rollFruit and 'ON' or 'OFF'
  nextCheck=0
  if not preferences.auto.rollFruit then rollStatus.Text='' end
  task.defer(preferences.Flush)
 end)
 task.spawn(function()
  while alive do
   if preferenceReady then
    farm.autoStore=preferences.auto.storeFruit==true
    storeToggle.Text=farm.autoStore and 'ON' or 'OFF'
    toggle.Text=preferences.auto.rollFruit and 'ON' or 'OFF'
    if preferences.auto.rollFruit and not busy and os.clock()>=nextCheck and not (preferences.HasRareItem and preferences.HasRareItem()) then
     busy=true;nextCheck=os.clock()+30
     task.spawn(function()
      local ok,err=pcall(function()
       local net=game.ReplicatedStorage.Modules.Net
       local remote=net:FindFirstChild('RF/GachaNetworkRF')
       if not remote then rollStatus.Text='Gacha unavailable';return end
       local check=remote:InvokeServer({Context='Check',BoxName='ZiolesGacha',SpokeNPC='Blox Fruit Gacha'})
       if not alive or not preferences.auto.rollFruit then return end
       if type(check)~='table' then rollStatus.Text='Waiting for gacha';return end
       if check.RequirementsMet~=true then
        rollStatus.Text='Waiting until a roll is available'
        for _,key in ipairs({'Level','Price','Cooldown'}) do
         local requirement=check[key]
         if type(requirement)=='table' and requirement.RequirementMet==false then
          rollStatus.Text=tostring(requirement.ErrorMessage or rollStatus.Text);break
         end
        end
        return
       end
       -- Recheck toggle and rare-item guard immediately before spending money.
       if not alive or not preferences.auto.rollFruit or (preferences.HasRareItem and preferences.HasRareItem()) then return end
       rollStatus.Text='Rolling fruit...'
       closeRollResult()
       remote:InvokeServer({Context='Purchase',BoxName='ZiolesGacha'})
       if alive and preferences.auto.rollFruit then rollStatus.Text='Roll requested; waiting for next availability' end
      end)
      busy=false
      if not ok and alive and preferences.auto.rollFruit then rollStatus.Text='Roll unavailable; retrying later' end
     end)
    end
   end
   task.wait(1)
  end
 end)
end

do
 local lighting=game:GetService('Lighting')
 local savedFog;local atmospheres={};local fogLayers={};local savedHumanoid;local savedMovement={};local speedConnection
 local visibilityEffects={};local frozenFog={};local waterPart;local getWaterHeight
 pcall(function() getWaterHeight=require(game.ReplicatedStorage.Util.GetWaterHeightAtLocation) end)
 local buttons={};local fields={}
 local function reflect()
  for key,b in pairs(buttons) do b.Text=preferences.movement[key] and 'ON' or 'OFF' end
  for key,box in pairs(fields) do if not box:IsFocused() then box.Text=tostring(preferences.movement[key]) end end
 end
 local function row(name,key,y,valueKey,minimum,maximum)
  label(settings,name,18,y,260,28,13)
  local b=control(settings,'OFF',410,y,80,28);buttons[key]=b
  bindControl(b,'Activated',function() preferences.movement[key]=not preferences.movement[key];reflect();task.defer(preferences.Flush) end)
  if valueKey then
   local box=make('TextBox',settings,{Text=tostring(preferences.movement[valueKey]),Position=UDim2.fromOffset(290,y),Size=UDim2.fromOffset(105,28),BackgroundColor3=Color3.fromRGB(49,46,40),TextColor3=pale,TextSize=13,Font=Enum.Font.Gotham,ClearTextOnFocus=false,BorderSizePixel=0,ZIndex=4})
   make('UICorner',box,{CornerRadius=UDim.new(0,6)});fields[valueKey]=box
   bindControl(box,'FocusLost',function() preferences.movement[valueKey]=math.clamp(tonumber(box.Text) or preferences.movement[valueKey],minimum,maximum);reflect();task.defer(preferences.Flush) end)
  end
 end
 row('Remove Fog','fog',450)
 row('Walk on Water','water',494)
 row('Jump Power','jump',538,'jumpPower',1,250)
 row('Walk Speed','speed',582,'walkSpeed',1,200)
 local function restoreFog()
  if savedFog then lighting.FogStart=savedFog.start;lighting.FogEnd=savedFog.finish;savedFog=nil end
  for atmosphere,value in pairs(atmospheres) do if atmosphere.Parent then atmosphere.Density=value.density;atmosphere.Haze=value.haze end end
  atmospheres={}
  for intensity,value in pairs(fogLayers) do if intensity.Parent then intensity.Value=value end end
  fogLayers={}
  for effect,value in pairs(frozenFog) do if effect.Parent then effect.Enabled=value end end
  frozenFog={}
  for effect,value in pairs(visibilityEffects) do if effect.Parent then effect.Enabled=value end end
  visibilityEffects={}
 end
 local nextFrozenScan=0
 local watchFrozenFog
 local function watchVisibility(effect)
  if not effect:IsA('PostEffect') then return end
  local n=effect:GetFullName():lower():gsub('[^%a]','')
  if n:find('seaterror',1,true) or n:find('frozendimension',1,true) or n:find('darkfog',1,true) or n:find('kitsunefog',1,true) then
   if visibilityEffects[effect]==nil then visibilityEffects[effect]=effect.Enabled end
  end
 end
 local function discoverFog()
  for _,a in ipairs(lighting:GetDescendants()) do
   watchVisibility(a)
   if a:IsA('Atmosphere') and not atmospheres[a] then atmospheres[a]={density=a.Density,haze=a.Haze} end
  end
  local camera=workspace.CurrentCamera
  if camera then for _,effect in ipairs(camera:GetDescendants()) do watchVisibility(effect) end end
  local layers=lighting:FindFirstChild('LightingLayers')
  if layers then for _,layer in ipairs(layers:GetChildren()) do
   if layer.Name:lower()=='haze' or layer.Name:lower():find('fog',1,true) or layer.Name:lower():gsub('[^%a]',''):find('frozendimension',1,true) then
    local intensity=layer:FindFirstChild('Intensity')
    if intensity and intensity:IsA('NumberValue') and fogLayers[intensity]==nil then fogLayers[intensity]=intensity.Value end
   end
  end end
 end
 watchFrozenFog=function(effect)
  if not effect:IsA('ParticleEmitter') and not effect:IsA('Smoke') then return end
  local path=effect:GetFullName():lower():gsub('[^%a]','')
  if path:find('frozen',1,true) and (path:find('fog',1,true) or path:find('mist',1,true) or path:find('blizzard',1,true)) then
   if frozenFog[effect]==nil then frozenFog[effect]=effect.Enabled end
  end
 end
 for _,effect in ipairs(workspace:GetDescendants()) do watchFrozenFog(effect) end
 connect(workspace.DescendantAdded,watchFrozenFog)
 local function clearFog()
  for effect in pairs(visibilityEffects) do if effect.Parent then effect.Enabled=false else visibilityEffects[effect]=nil end end
  for effect,value in pairs(frozenFog) do if effect.Parent then effect.Enabled=false else frozenFog[effect]=nil end end
  savedFog=savedFog or {start=lighting.FogStart,finish=lighting.FogEnd}
  if lighting.FogStart~=100000 then savedFog.start=lighting.FogStart;lighting.FogStart=100000 end
  if lighting.FogEnd~=1000000 then savedFog.finish=lighting.FogEnd;lighting.FogEnd=1000000 end
  for atmosphere,value in pairs(atmospheres) do
   if atmosphere.Parent then
    if atmosphere.Density~=0 then value.density=atmosphere.Density;atmosphere.Density=0 end
    if atmosphere.Haze~=0 then value.haze=atmosphere.Haze;atmosphere.Haze=0 end
   else atmospheres[atmosphere]=nil end
  end
  for intensity,value in pairs(fogLayers) do
   if intensity.Parent then
    if intensity.Value~=0 then fogLayers[intensity]=intensity.Value;intensity.Value=0 end
   else fogLayers[intensity]=nil end
  end
 end
 local fogBinding='NexoRemoveFog_'..tostring(runId)
 local render=game:GetService('RunService')
 render:BindToRenderStep(fogBinding,Enum.RenderPriority.Last.Value+10,function()
  if alive and preferenceReady and preferences.movement.fog then clearFog()
  elseif savedFog then restoreFog() end
 end)
 connect(lighting.DescendantAdded,function()
  if alive and preferenceReady and preferences.movement.fog then task.defer(function()if alive and preferences.movement.fog then discoverFog() end end) end
 end)
 local function restoreMovement()
  if speedConnection then speedConnection:Disconnect();speedConnection=nil end
  if savedHumanoid and savedHumanoid.Parent then
   if savedMovement.speed then savedHumanoid.WalkSpeed=savedMovement.speed end
   if savedMovement.jump then savedHumanoid.JumpPower=savedMovement.jump.power;savedHumanoid.JumpHeight=savedMovement.jump.height end
  end
  savedMovement={};savedHumanoid=nil
 end
 local function destroyWater() if waterPart then waterPart:Destroy();waterPart=nil end end
 local previousCleanup=beforeCleanup
 beforeCleanup=function()
  render:UnbindFromRenderStep(fogBinding);restoreFog();restoreMovement();destroyWater()
  if previousCleanup then previousCleanup() end
 end
 connect(game:GetService('RunService').Heartbeat,function()
  if not alive or not preferenceReady then return end
  local cfg=preferences.movement;local char=player.Character;local h=char and char:FindFirstChildOfClass('Humanoid');local root=char and char:FindFirstChild('HumanoidRootPart')
  if h~=savedHumanoid then
   restoreMovement();savedHumanoid=h
   if h then speedConnection=h:GetPropertyChangedSignal('WalkSpeed'):Connect(function()
    if alive and preferences.movement.speed and h.Health>0 and h.WalkSpeed~=preferences.movement.walkSpeed then
     savedMovement.speed=savedMovement.speed or h.WalkSpeed;h.WalkSpeed=preferences.movement.walkSpeed
    end
   end) end
  end
  if h and h.Health>0 then
   if cfg.speed then savedMovement.speed=savedMovement.speed or h.WalkSpeed;h.WalkSpeed=cfg.walkSpeed
   elseif savedMovement.speed then h.WalkSpeed=savedMovement.speed;savedMovement.speed=nil end
   if cfg.jump then
    savedMovement.jump=savedMovement.jump or {power=h.JumpPower,height=h.JumpHeight}
    if h.UseJumpPower then h.JumpPower=cfg.jumpPower else h.JumpHeight=cfg.jumpPower^2/(2*math.max(workspace.Gravity,1)) end
   elseif savedMovement.jump then h.JumpPower=savedMovement.jump.power;h.JumpHeight=savedMovement.jump.height;savedMovement.jump=nil end
  end
  if cfg.water and root and h and h.Health>0 and not h.Sit then
   local y=0
   if getWaterHeight then local ok,value=pcall(getWaterHeight,root.Position);if ok and type(value)=='number' then y=value end end
   if math.abs(root.Position.Y-y)<12 then
    if not waterPart then waterPart=Instance.new('Part');waterPart.Name='NexoWaterSurface';waterPart.Anchored=true;waterPart.Transparency=1;waterPart.Size=Vector3.new(12,1,12);waterPart.CanTouch=false;waterPart.CanQuery=false;waterPart.Parent=workspace end
    waterPart.CFrame=CFrame.new(root.Position.X,y-.5,root.Position.Z);waterPart.CanCollide=true
   elseif waterPart then waterPart.CanCollide=false end
  else destroyWater() end
 end)
 task.spawn(function()
  while alive do
   if preferenceReady then
    reflect()
    if preferences.movement.fog then
     discoverFog();if os.clock()>=nextFrozenScan then nextFrozenScan=os.clock()+5;for _,effect in ipairs(workspace:GetDescendants()) do watchFrozenFog(effect) end end;clearFog()
    else restoreFog() end
   end
   task.wait(.25)
  end
 end)
end

do
 line(settings,628)
 label(settings,'Skill Use',18,638,125,28,13)
 local choice=control(settings,'All skills  ▾',150,638,344,28)
 local popup=make('Frame',content,{Name='SkillPicker',Position=card.Position,Size=UDim2.fromOffset(514,270),BackgroundColor3=Color3.fromRGB(25,27,30),BorderSizePixel=0,ZIndex=25,Visible=false})
 make('UICorner',popup,{CornerRadius=UDim.new(0,10)})
 make('UIStroke',popup,{Color=brass,Transparency=.35,Thickness=1})
 local title=label(popup,'Choose Skills',16,7,400,28,14);title.ZIndex=27
 local close=control(popup,'×',469,7,28,28);close.ZIndex=27
 bindControl(choice,'Activated',function() popup.Visible=not popup.Visible end)
 bindControl(close,'Activated',function() popup.Visible=false end)
 for _,tab in pairs(tabs) do bindControl(tab,'Activated',function() popup.Visible=false end) end
 local buttons={}
 local function reflect()
  local count=0
  for _,entry in ipairs(buttons) do
   local enabled=farm.skillUse[entry.kind][entry.key]
   if enabled then count=count+1 end
   entry.button.Text=(enabled and '✓ ' or '□ ')..entry.key
   entry.button.BackgroundColor3=enabled and Color3.fromRGB(97,76,43) or Color3.fromRGB(49,46,40)
  end
  choice.Text=(count==20 and 'All skills' or count==0 and 'No skills' or tostring(count)..' / 20 enabled')..'  ▾'
 end
 for i,kind in ipairs({'Fruit','Sword','Gun','Melee'}) do
  local y=52+(i-1)*48
  local name=label(popup,kind,18,y,110,28,13);name.ZIndex=27
  for j,key in ipairs({'Z','X','C','V','F'}) do
   local b=control(popup,'',144+(j-1)*70,y,64,28);b.ZIndex=27
   table.insert(buttons,{button=b,kind=kind,key=key})
   bindControl(b,'Activated',function()
    farm.skillUse[kind][key]=not farm.skillUse[kind][key]
    reflect();task.defer(preferences.Flush)
   end)
  end
 end
 settings.CanvasSize=UDim2.fromOffset(0,684)
 reflect()
 task.spawn(function() while alive do reflect();task.wait(1) end end)
end

do
 local lighting=game:GetService('Lighting')
 local info=panels.Info
 local joined=label(info,'Time: checking',18,10,475,26,13)
 local countdown=label(info,'Moon phase: checking',18,44,475,26,13)
 local moonTimer=label(info,'Full Moon in: measuring',18,78,475,26,13)
 local eyes=label(info,'Tyrant eyes: 0 eye',18,112,475,26,13)
 local prehistoric=label(info,'Prehistoric Island: checking',18,146,475,26,13)
 local mirage=label(info,'Mirage Island: checking',18,180,475,26,13)
 local elite=label(info,'Elite Pirate: checking',18,214,475,26,13)
 local cake=label(info,'Cake Prince: checking',18,248,475,26,13)
 local dealer=label(info,'Legendary Sword Dealer: checking',18,282,475,26,13)
 local auraOffer=label(info,'Aura Seller: checking',18,316,475,26,13)
 label(info,'Place ID: '..tostring(game.PlaceId),18,350,475,26,13)
 for y=40,380,34 do line(info,y) end
 local hop=control(info,'Hop Server',18,398,229,30)
 local low=control(info,'Hop to Less People',259,398,229,30)
 local hopStatus=label(info,'',18,438,475,48,11)
 info.CanvasSize=UDim2.fromOffset(0,502)
 hopStatus.TextWrapped=true
 local function requestHop(mode)
  local ok,message=preferences.RequestHop(mode)
  hopStatus.Text=message or '';if ok then preferences.HopMessage=message end
 end
 bindControl(hop,'Activated',function() requestHop('random') end)
 bindControl(low,'Activated',function() requestHop('low') end)
 task.spawn(function()
  local remote=game:GetService('ReplicatedStorage').Remotes.CommF_
  while alive do
   if game.PlaceId==2753915549 or game.PlaceId==85211729168715 then
    auraOffer.Text='Aura Seller: Sea 2 / Sea 3 only';auraOffer.TextColor3=pale
   else
    -- Dialogue step 1 reads the offer; step 2 purchases and is never used here.
    local ok,name,tier=pcall(function() return remote:InvokeServer('ColorsDealer','1') end)
    if not alive then return end
    if ok and type(name)=='string' and name~='' then
     name=name:gsub('<[^>]*>',''):gsub('[\r\n]+',' ')
     auraOffer.Text='Aura Seller: ✓ | '..name..(type(tier)=='number' and (tier>=3 and ' | Legendary' or ' | Rare') or '')
     auraOffer.TextColor3=Color3.fromRGB(103,220,140)
    elseif ok and name==1 then
     auraOffer.Text='Aura Seller: color locked — upgrade Aura';auraOffer.TextColor3=pale
    elseif ok and (name==nil or name==false) then
     auraOffer.Text='Aura Seller: ✕ | no color offer available';auraOffer.TextColor3=Color3.fromRGB(240,105,110)
    else
     auraOffer.Text='Aura Seller: offer unavailable';auraOffer.TextColor3=pale
    end
   end
   preferences.auraSellerInfo=auraOffer.Text
   task.wait(10)
  end
 end)
 local function arrivalHint(text)
  local n=text:lower()
  if n:find('left not too long ago',1,true) then return 'Left recently | arrival unknown' end
  if n:find('getting here soon',1,true) then return 'ETA ~0–15 min' end
  if n:find('nearby today',1,true) then return 'ETA ~15–75 min' end
  if n:find('last week',1,true) then return 'ETA ~75–285 min' end
  if n:find('just saw him',1,true) then return 'Manager reports arrival; checking current availability' end
  return 'Arrival unknown'
 end
 task.spawn(function()
  local rs=game:GetService('ReplicatedStorage')
  local remote=rs.Remotes.CommF_
  while alive do
   if game.PlaceId~=4442272183 and game.PlaceId~=79091703265657 then
    dealer.Text='Legendary Sword Dealer: Sea 2 only';dealer.TextColor3=pale
   else
    local checked,gate=pcall(function() return remote:InvokeServer('Manager','1') end)
    local managerText
    if checked and gate==0 then local read,text=pcall(function() return remote:InvokeServer('Manager','2') end);if read and type(text)=='string' then managerText=text end end
    local reported=managerText and managerText:lower():find('just saw him',1,true)~=nil
    local location;local parked=false
    local present=false
    pcall(function()
     local manager=require(rs.NPCManager)
     for _,npc in ipairs(manager.getNPCsByName('Legendary Sword Dealer')) do
      local model=npc:getModel()
      if model then
       location=model:GetPivot().Position
       if model:IsDescendantOf(workspace) then present=true end
       local state=npc._modelState;local target=state and state._targetLocation
       if typeof(target)=='CFrame' then if target.Position.Y>-900 then location=target.Position else parked=true end end
       break
      end
     end
    end)
    local npcs=workspace:FindFirstChild('NPCs')
    if npcs and npcs:FindFirstChild('Legendary Sword Dealer') then present=true end
    if not alive then return end
    local place='Location not available'
    if location then
     local origin=workspace:FindFirstChild('_WorldOrigin');local locations=origin and origin:FindFirstChild('Locations');local best
     if locations then for _,v in ipairs(locations:GetChildren()) do
      if v:IsA('BasePart') and v.Name~='Sea' and v.Name~='???' then
       local delta=v.Position-location;local distance=Vector2.new(delta.X,delta.Z).Magnitude
       if not best or distance<best then best=distance;place=v.Name end
      end
     end end
     if place=='Green Zone' and location.Y>400 then place=place..' — high beanstalk' end
    end
    if present or reported then
     dealer.Text='Sword Dealer: ✓ | '..((not present and parked) and 'last seen: ' or '')..place
     dealer.TextColor3=Color3.fromRGB(103,220,140)
    else
     dealer.TextColor3=checked and Color3.fromRGB(240,105,110) or pale
     local hint='Arrival: unknown'
     if checked and gate==0 then
      if managerText then hint=arrivalHint(managerText) end
     elseif checked and gate==-1 then hint='ETA locked: Colosseum quest'
     elseif checked and type(gate)=='number' then hint='ETA locked: wait after joining' end
     if not alive then return end
     dealer.Text='Sword Dealer: '..(checked and '✕' or '?')..' | '..hint
    end
   end
   preferences.swordDealerInfo={status=dealer.Text}
   task.wait(5)
  end
 end)
 local function hasBoss(names)
  for _,container in pairs({workspace:FindFirstChild('Enemies'),game.ReplicatedStorage}) do
   for _,enemy in ipairs(container:GetChildren()) do
    local n=enemy.Name:lower():gsub('%s*%[.-%]','')
    if names[n] then local h=enemy:FindFirstChildOfClass('Humanoid');if h and h.Health>0 then return true end end
   end
  end
  return false
 end
 task.spawn(function()
  while alive do
   if workspace:GetAttribute('MAP')~='Sea3' then cake.Text='Cake Prince: Sea 3 only'
   elseif hasBoss({['cake prince']=true}) then cake.Text='Cake Prince: spawned'
   else
    local ok,result=pcall(function() return game.ReplicatedStorage.Remotes.CommF_:InvokeServer('CakePrinceSpawner',true) end)
    if not alive then return end
    if ok and type(result)=='string' then
     result=result:gsub('<[^>]*>','')
     local count=result:match('(%d+)%s+more') or result:match('(%d+)%s+enemies')
     cake.Text=count and ('Cake Prince: '..count..' mobs left') or (result:lower():find('open the portal',1,true) and 'Cake Prince: 0 mobs left — ready' or 'Cake Prince: status unavailable')
    else cake.Text='Cake Prince: status unavailable' end
   end
   task.wait(15)
  end
 end)
 local function formatTime(seconds)
  seconds=math.max(0,math.floor(seconds))
  return string.format('%02d:%02d:%02d',math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
 end
 local function moonHours(phase,hour)
  -- Noon full-moon phase is the upcoming evening, not the expired night.
  local night=hour>=18 or hour<5
  if phase==5 and night then return true,(5-hour)%24,'full' end
  if phase==5 and hour>=12 and hour<18 then return false,18-hour,'near' end
  local steps=(5-phase)%8
  if steps==0 then steps=8 end -- 05:00 to noon: the previous full moon ended.
  local hours=(18-hour)%24+(steps-1)*24
  local state=phase==4 and 'near' or phase==5 and 'late' or 'bad'
  return false,hours,state
 end
 local eyeParts={};local eyeScanAt=0;local eyeIsland
 local sampleClock=lighting.ClockTime;local sampleAt=os.clock();local rate
 task.spawn(function()
  while alive do
   local now=os.clock();local hour=lighting.ClockTime;local dt=now-sampleAt
   if dt>=2 then
    local delta=(hour-sampleClock)%24
    local measured=delta/dt
    if measured>.001 and measured<.1 then rate=rate and rate*.7+measured*.3 or measured else rate=nil end
    sampleAt=now;sampleClock=hour
   end
   local phase=tonumber(lighting:GetAttribute('MoonPhase'))
   if phase and phase>=1 and phase<=8 and phase%1==0 then
    local full,hours,state=moonHours(phase,hour)
    preferences.MoonForecast={job=game.JobId,measuredAt=now,full=full,state=state,phase=phase,hour=hour,seconds=rate and hours/rate or nil}
    local displayState=full and 'Full Moon' or state=='near' and (hour>=12 and hour<18 and 'Full Moon' or 'Near Full Moon') or 'Bad Moon'
    countdown.Text='Moon phase: '..displayState..' | '..string.format('%02d:%02d',math.floor(hour),math.floor(hour%1*60))
    moonTimer.Text=(full and 'Full Moon ends in: ' or 'Full Moon in: ')..(rate and ('~'..formatTime(hours/rate)) or 'measuring server clock')
   else
    preferences.MoonForecast=nil
    countdown.Text='Moon phase: unknown | '..string.format('%02d:%02d',math.floor(hour),math.floor(hour%1*60));moonTimer.Text='Full Moon in: unknown'
   end
   local map=workspace:FindFirstChild('Map')
   local tiki=map and map:FindFirstChild('TikiOutpost');local openedEyes={}
   if tiki~=eyeIsland or now>=eyeScanAt then
    eyeIsland=tiki;eyeScanAt=now+10;eyeParts={}
    if tiki then for _,part in ipairs(tiki:GetDescendants()) do
     if part:IsA('BasePart') and part.Name:match('^Eye[1-4]$') then eyeParts[#eyeParts+1]=part end
    end end
   end
   for _,part in ipairs(eyeParts) do
    if part.Parent and part.Transparency<.5 and part.Color.R>part.Color.G*1.5 then openedEyes[part.Name]=true end
   end
   local eyeCount=0;for _ in pairs(openedEyes) do eyeCount=eyeCount+1 end
   eyes.Text='Tyrant eyes: '..eyeCount..' eye'
   local pre,mir=false,false
   for _,folder in pairs({map,workspace:FindFirstChild('_WorldOrigin') and workspace._WorldOrigin:FindFirstChild('Locations')}) do
    for _,item in ipairs(folder:GetChildren()) do
     local n=item.Name:lower():gsub('[^%a]','')
     if n=='prehistoricisland' then pre=true end
     if n=='mirageisland' or n=='mysticisland' then mir=true end
    end
   end
   for _,entry in ipairs({{prehistoric,'Prehistoric Island',pre},{mirage,'Mirage Island',mir}}) do
    entry[1].Text=entry[2]..': '..(entry[3] and '✓' or '✕')
    entry[1].TextColor3=entry[3] and Color3.fromRGB(103,220,140) or Color3.fromRGB(240,105,110)
   end
   joined.Text='Time: '..formatTime(time())
   local present=hasBoss({urban=true,diablo=true,deandre=true})
   elite.Text='Elite Pirate: '..(present and '✓' or '✕')
   elite.TextColor3=present and Color3.fromRGB(103,220,140) or Color3.fromRGB(240,105,110)
   if preferences.HopMessage then hopStatus.Text=preferences.HopMessage end
   task.wait(1)
  end
 end)
end

-- Codes checked against https://bloxfruitswiki.org/wiki/codes/ on 2026-10-23.
do
 local panel=panels.Shop
 local button=control(panel,'Redeem All Codes',18,4,472,28)
 local status=label(panel,'Includes XP boosts and stat-reset codes.',18,36,472,34,11);status.TextWrapped=true
 local running=false
 local codes={"EASTEREXP","fudd10","fudd10_V2","Chandler","BIGNEWS","KITT_RESET","Sub2UncleKizaru","SUB2GAMERROBOT_RESET1","Sub2Fer999","Enyu_is_Pro","JCWK","StarcodeHEO","MagicBUS","KittGaming","Sub2CaptainMaui","Sub2OfficialNoobie","TheGreatAce","Sub2NoobMaster123","Sub2Daigrock","Axiore","StrawHatMaine","TantaiGaming","Bluxxy","SUB2GAMERROBOT_EXP1"}
 bindControl(button,'Activated',function()
  if running then return end
  running=true;button.Text='Redeeming...'
  task.spawn(function()
   local remote=game.ReplicatedStorage.Remotes:FindFirstChild('Redeem')
   if not remote or not remote:IsA('RemoteFunction') then running=false;button.Text='Redeem All Codes';status.Text='Code redemption is unavailable in this server.';return end
   local results={};preferences.CodeResults=results
   for i,code in ipairs(codes) do
    if not alive then return end
    status.Text='Redeeming '..i..'/'..#codes..': '..code
    local ok,reply=pcall(function() return remote:InvokeServer(code) end)
    results[#results+1]={code=code,ok=ok,result=tostring(reply)}
    if not alive then return end
    status.Text=code..': '..(ok and tostring(reply) or 'request failed')
    task.wait(.6)
   end
   running=false;button.Text='Redeem All Codes'
   status.Text='Finished '..#codes..' codes. Already-used or expired codes are skipped by the game.'
  end)
 end)
end

local function purchaseRace(remote,key,isAlive)
 if not isAlive() then return 'closed' end
 if key=='Cyborg' then
  local state=remote:InvokeServer('CyborgTrainer','Check')
  if state==2 then return 'current' end
  if state~=true and state~=1 then return 'locked' end
  if not isAlive() then return 'closed' end
  local reply=remote:InvokeServer('CyborgTrainer','Buy')
  return reply==1 and 'bought' or reply==2 and 'money' or 'unknown'
 elseif key=='Ghoul' then
  local state=remote:InvokeServer('Ectoplasm','BuyCheck',4)
  if state==2 then return 'current' end
  -- Only the free, previously unlocked change-back path is allowed here.
  if state~=1 then return 'locked' end
  if not isAlive() then return 'closed' end
  return remote:InvokeServer('Ectoplasm','Change',4)==1 and 'bought' or 'unknown'
 elseif key=='ResetStats' then
  local reply=remote:InvokeServer('BlackbeardReward','Refund','2')
  return reply==1 and 'bought' or reply==0 and 'money' or 'unknown'
 elseif key=='Random' then
  local eligible=remote:InvokeServer('BlackbeardReward','Reroll','1')
  if not eligible then return 'unavailable' end
  if not isAlive() then return 'closed' end
  local reply=remote:InvokeServer('BlackbeardReward','Reroll','2')
  return reply==1 and 'bought' or reply==0 and 'money' or 'unknown'
 end
 return 'unknown'
end

do
 local panel=make('Frame',panels.Shop,{Name='AbilityRaceShop',Position=UDim2.fromOffset(0,76),Size=UDim2.fromOffset(514,372),BackgroundTransparency=1})
 local title=label(panel,'Abilities',18,4,478,24,14);title.Font=Enum.Font.GothamBold
 local entries={
  {name='Air Jump',price='$10,000',key='Geppo'},
  {name='Aura',price='$25,000',key='Buso'},
  {name='Flash Step',price='$100,000',key='Soru'},
  {name='Instinct',price='$750,000',key='Ken'},
 }
 local message=label(panel,'',18,164,478,28,11);message.TextWrapped=true
 local pending=false
 local remote=game:GetService('ReplicatedStorage').Remotes.CommF_
 for i,entry in ipairs(entries) do
  local y=34+(i-1)*32
  label(panel,entry.name,18,y,210,28,13)
  local price=label(panel,entry.price,242,y,144,28,12);price.TextXAlignment=Enum.TextXAlignment.Right
  local buy=control(panel,'Buy',410,y,80,28)
  line(panel,y+30)
  local owned=false
  bindControl(buy,'Activated',function()
   if pending or owned then return end
   pending=true;buy.Text='...';message.Text='Buying '..entry.name..'...'
   task.spawn(function()
    local ok,result=pcall(function()
     if entry.key=='Ken' then
      local state=remote:InvokeServer('KenTalk','Start')
      if state==0 then return 'owned' end
      if state~=1 then return 'requirements' end
      if not alive then return 'closed' end
      return remote:InvokeServer('KenTalk','Buy')==0 and 'bought' or 'money'
     end
     local reply=remote:InvokeServer('BuyHaki',entry.key)
     if reply==1 then return 'bought' elseif reply==2 then return 'owned' elseif reply==0 then return 'money' end
     return 'unknown'
    end)
    pending=false
    if not alive then return end
    if ok and (result=='bought' or result=='owned') then
     owned=true;buy.Text='Owned';buy.BackgroundColor3=Color3.fromRGB(51,75,57)
     message.Text=entry.name..(result=='bought' and ' learned.' or ' is already learned.')
    else
     buy.Text='Buy'
     if not ok then message.Text='Purchase could not be confirmed. Check your connection before retrying.'
     elseif result=='money' then message.Text='Not enough money for '..entry.name..'.'
     elseif result=='requirements' then message.Text='Instinct requirements are not complete: level 300 and Saber Expert defeated.'
     else message.Text='The game did not confirm this purchase.' end
    end
   end)
  end)
 end
 -- Race changes are single purchases, never automatic retries.
 line(panel,198)
 local raceTitle=label(panel,'Race Shop',18,184,478,24,14);raceTitle.Font=Enum.Font.GothamBold
 local raceMessage=label(panel,'',18,342,478,28,11);raceMessage.TextWrapped=true
 local raceButtons={}
 local function currentRace()
  local data=player:FindFirstChild('Data');local race=data and data:FindFirstChild('Race')
  return race and tostring(race.Value) or ''
 end
 local function refreshRaces()
  if pending then return end
  for key,b in pairs(raceButtons) do b.Text=currentRace()==key and 'Current' or key=='Random' and 'Roll' or 'Buy' end
 end
 for i,entry in ipairs({{key='Cyborg',name='Cyborg',price='Fragments 2,500'},{key='Ghoul',name='Ghoul',price='Free'},{key='ResetStats',name='Reset Stats',price='2,500 Fragments'},{key='Random',name='Random Race',price='Fragments 3,000 / roll'}}) do
  local y=212+(i-1)*32
  label(panel,entry.name,18,y,200,28,13)
  local price=label(panel,entry.price,222,y,164,28,12);price.TextXAlignment=Enum.TextXAlignment.Right
  local button=control(panel,'Buy',410,y,80,28);raceButtons[entry.key]=button
  line(panel,y+30)
  bindControl(button,'Activated',function()
   if pending then return end
   if entry.key=='ResetStats' then
    local data=player:FindFirstChild('Data');local fragments=data and data:FindFirstChild('Fragments')
    if not fragments or fragments.Value<2500 then raceMessage.Text='Reset Stats requires 2,500 fragments.';return end
   end
   if entry.key~='Random' and currentRace()==entry.key then raceMessage.Text='You are already '..entry.name..'.';return end
   pending=true;button.Text='...';raceMessage.Text='Checking '..entry.name..'...'
   task.spawn(function()
    local ok,result=pcall(purchaseRace,remote,entry.key,function() return alive end)
    pending=false
    if not alive then return end
    if not ok then raceMessage.Text='Race change not confirmed. Check your race and fragments before retrying.'
    elseif result=='bought' then raceMessage.Text=entry.key=='ResetStats' and 'Stat reset purchased.' or entry.key=='Random' and 'Race reroll purchased.' or ('Race changed to '..entry.name..'.')
    elseif result=='current' then raceMessage.Text='You are already '..entry.name..'.'
    elseif result=='locked' then raceMessage.Text='Unlock '..entry.name..' first, then change back here.'
    elseif result=='money' then raceMessage.Text='Not enough fragments.'
    elseif result=='unavailable' then raceMessage.Text='Race reroll is unavailable; check the game requirements and your fragments.'
    else raceMessage.Text='The game did not confirm the purchase.' end
    refreshRaces()
   end)
  end)
 end
 panels.Shop.CanvasSize=UDim2.fromOffset(0,448)
 refreshRaces()
 task.spawn(function() while alive do refreshRaces();task.wait(1) end end)

end

-- Fighting-style purchases and one cancellable unlock job per account.
do
 local RS=game:GetService('ReplicatedStorage')
 local remote=RS.Remotes.CommF_
 local panel=panels.Shop
 local styles={
  {name='Dark Step',command='BuyBlackLeg',price='$150,000'},
  {name='Water Kung Fu',command='BuyFishmanKarate',price='$750,000',get=true},
  {name='Electric',command='BuyElectro',price='$500,000',get=true},
  {name='Dragon Breath',command='DragonClaw',price='1,500 Fragments'},
  {name='Superhuman',command='BuySuperhuman',price='$3,000,000'},
  {name='Death Step',command='BuyDeathStep',price='$2,500,000 + Fragments 5,000',get=true},
  {name='Sharkman Karate',command='BuySharkmanKarate',price='$2,500,000 + Fragments 5,000',get=true},
  {name='Electric Claw',command='BuyElectricClaw',price='$3,000,000 + Fragments 5,000',get=true},
  {name='Dragon Talon',command='BuyDragonTalon',price='$3,000,000 + Fragments 5,000',get=true},
  {name='Godhuman',command='BuyGodhuman',price='$5,000,000 + Fragments 5,000',get=true},
  {name='Sanguine Art',command='BuySanguineArt',price='Previously unlocked',ownedOnly=true},
 }
 local byName={};for _,entry in ipairs(styles) do byName[entry.name]=entry end
 local token,serial,buyBusy=nil,0,false
 local getButtons={}
 local statusLabel
 local function say(text) if statusLabel then statusLabel.Text=text end end
 local function root() local c=player.Character;return c and c:FindFirstChild('HumanoidRootPart') end
 local function tool(name)
  local c=player.Character;local bag=player:FindFirstChild('Backpack')
  return (c and c:FindFirstChild(name)) or (bag and bag:FindFirstChild(name))
 end
 local function keyHeld() return tool('Library Key') or tool('Water Key') or tool('Fire Essence') end
 local function currentSea()
  if game.PlaceId==4442272183 or game.PlaceId==79091703265657 then return 2 end
  if game.PlaceId==7449423635 or game.PlaceId==100117331123089 then return 3 end
  return 1
 end
 local function active(id) return alive and serial==id and preferences.styleJob~=nil end
 local function release()
  if token then farm.SeaEnd(token);token=nil end
  if farm.enabled and farm.mode=='material' then farm.SetEnabled(false) end
 end
 local function stop(text)
  serial=serial+1;release();preferences.styleJob=nil;preferences.styleBusy=false;preferences.styleWaitUntil=nil
  if preferences.CancelStyleHop then preferences.CancelStyleHop() end
  otherFarm.ResumePriority();preferences.Flush();say(text or '')
 end
 local function move(position,id)
  if not active(id) then return false end
  if not token or not farm.SeaActive(token) then token=farm.SeaBegin() end
  return farm.SeaMove(position,token) and active(id)
 end
 local function travelSea(seaId,id)
  if currentSea()==seaId then return true end
  if keyHeld() or (preferences.HasRareItem and preferences.HasRareItem()) then
   stop('Deliver the held key or rare item before changing seas.');return false
  end
  release();preferences.Flush();say('Travelling to Sea '..seaId)
  remote:InvokeServer(({[1]='TravelMain',[2]='TravelDressrosa',[3]='TravelZou'})[seaId])
  local untilTime=os.clock()+12
  repeat task.wait(.3) until not active(id) or os.clock()>untilTime
  if active(id) then say('Sea travel not confirmed. Check that this sea is unlocked.') end
  return false
 end
 local function npcPosition(names,fallback)
  local found
  pcall(function()
   local manager=require(RS.NPCManager)
   for _,name in ipairs(names) do for _,npc in ipairs(manager.getNPCsByName(name)) do
    local model=npc:getModel()
    if model then found=model:GetPivot().Position+Vector3.new(0,0,4);return end
   end end
  end)
  if found then return found end
  local folder=workspace:FindFirstChild('NPCs')
  if folder then for _,npc in ipairs(folder:GetChildren()) do
   for _,name in ipairs(names) do if npc.Name==name then
    local r=npc:FindFirstChild('HumanoidRootPart') or npc:FindFirstChild('Head')
    if r then return r.Position+Vector3.new(0,0,4) end
   end end
  end end
  local ok,guide=pcall(require,RS:FindFirstChild('GuideModule'))
  if ok and guide.Data then for _,npc in pairs(guide.Data.NPCList or {}) do
   for _,name in ipairs(names) do if (npc.NPCName==name or npc.Name==name) and typeof(npc.Position)=='Vector3' then return npc.Position+Vector3.new(0,0,4) end end
  end end
  return fallback
 end
 local teacherNames={['Dark Step']={'Dark Step Teacher'},['Water Kung Fu']={'Water Kung-fu Teacher'},Electric={'Mad Scientist'},['Dragon Breath']={'Sabi'},Superhuman={'Martial Arts Master'},['Death Step']={'Phoeyu, the Reformed'},['Sharkman Karate']={'Sharkman Teacher'},['Electric Claw']={'Previous Hero'},['Dragon Talon']={'Uzoth'},Godhuman={'Ancient Monk'},['Sanguine Art']={'Shafi'}}
 local function buyRequest(entry)
  if entry.command=='DragonClaw' then return remote:InvokeServer('BlackbeardReward','DragonClaw','2') end
  return remote:InvokeServer(entry.command)
 end
 local styleAliases={['Dark Step']='Black Leg',['Water Kung Fu']='Fishman Karate',Electric='Electro',['Dragon Breath']='Dragon Claw'}
 local function styleTool(entry) return tool(styleAliases[entry.name] or entry.name) or tool(entry.name) end
 local function confirmStyle(entry)
  local deadline=os.clock()+4
  repeat
   local found=styleTool(entry)
   if found then
    local c=player.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
    if h then h:EquipTool(found) end
    return true,entry.name..' equipped.'
   end
   task.wait(.15)
  until not alive or os.clock()>=deadline
  return false
 end
 local function balance()
  local data=player:FindFirstChild('Data');local b=data and data:FindFirstChild('Beli');local f=data and data:FindFirstChild('Fragments')
  return b and b.Value or 0,f and f.Value or 0
 end
 local function purchase(entry)
  if styleTool(entry) then return confirmStyle(entry) end
  if entry.ownedOnly and remote:InvokeServer(entry.command,true)~=1 then return false,'Unlock '..entry.name..' first.' end
  if entry.command=='DragonClaw' then
   local eligible=remote:InvokeServer('BlackbeardReward','DragonClaw','1')
   if eligible==false or eligible==nil then return false,'Dragon Breath is unavailable.' end
  end
  local beforeB,beforeF=balance()
  local result=buyRequest(entry)
  local confirmed,message=confirmStyle(entry);if confirmed then return true,message end
  local afterB,afterF=balance()
  if afterB<beforeB or afterF<beforeF then
   return false,entry.name..': currency spent, but tool has not arrived. Stopped to avoid charging again.'
  end
  if not alive then return false,'Closed' end
  local position=npcPosition(teacherNames[entry.name] or {},nil)
  if position then
   say('Meeting '..teacherNames[entry.name][1]..' to equip '..entry.name)
   sea.SetEnabled(false);travelAPI.Stop();otherFarm.PausePriority()
   local buyToken=farm.SeaBegin()
   local ok,success,detail=pcall(function()
    if not farm.SeaMove(position,buyToken) or not alive or not farm.SeaActive(buyToken) then return false,'Travel cancelled.' end
    task.wait(.4)
    if entry.command=='DragonClaw' then remote:InvokeServer('BlackbeardReward','DragonClaw','1') end
    result=buyRequest(entry)
    return confirmStyle(entry)
   end)
   farm.SeaEnd(buyToken)
   if not preferences.styleJob then otherFarm.ResumePriority() end
   if ok and success then return true,detail end
  end
  return false,entry.name..' not equipped. Teacher reply: '..tostring(result)..'. Check unlocks, combat status and currency.'
 end
 preferences.PurchaseStyle=function(name)
  if buyBusy then return false,'Purchase already in progress.' end
  local entry=byName[name];if not entry then return false,'Unknown style.' end
  buyBusy=true;local ok,success,message=pcall(purchase,entry);buyBusy=false
  return ok and success or false,ok and message or tostring(success)
 end
 local function finishPurchase(entry,id)
  if not active(id) then return end
  release();say('Buying '..entry.name)
  local ok,message=purchase(entry)
  if active(id) then stop(ok and (entry.name..' ready.') or message) end
 end
 local function enemyByName(name)
  local enemies=workspace:FindFirstChild('Enemies')
  if enemies then for _,enemy in ipairs(enemies:GetChildren()) do
   local h=enemy:FindFirstChildOfClass('Humanoid')
   if enemy.Name:find(name,1,true) and h and h.Health>0 then return enemy end
  end end
 end
 local function fight(enemy,id)
  local h=enemy:FindFirstChildOfClass('Humanoid');local r=enemy:FindFirstChild('HumanoidRootPart')
  if not h or not r then return end
  if not move(r.Position+Vector3.new(0,16,0),id) then return end
  while active(id) and farm.SeaActive(token) and enemy.Parent and h.Health>0 and not keyHeld() do
   farm.SeaHover(r,token,18,false);farm.SeaAttack(enemy,token);task.wait(.06)
  end
  if token then farm.SeaRelease(token) end
 end
 local function huntKey(entry,id)
  if not travelSea(2,id) then return end
  local death=entry.name=='Death Step'
  local keyName=death and 'Library Key' or 'Water Key'
  if tool(keyName) then
   if preferences.CancelStyleHop then preferences.CancelStyleHop() end
   local point=death and Vector3.new(6373,296,-6844) or npcPosition({'Sharkman Teacher','SharkmanTeacher'},Vector3.new(-2604,239,-10315))
   if not move(point,id) then return end
   if death then
    local map=workspace:FindFirstChild('Map');local castle=map and map:FindFirstChild('IceCastle')
    local hall=castle and castle:FindFirstChild('Hall');local door=hall and hall:FindFirstChild('LibraryDoor')
    local detect=door and door:FindFirstChild('Detect',true)
    if detect and detect:IsA('BasePart') and not move(detect.Position,id) then return end
    if not remote:InvokeServer('OpenLibrary') then say('Library key found; waiting for the door to open.');return end
   else remote:InvokeServer('BuySharkmanKarate',true) end
   finishPurchase(entry,id);return
  end
  -- Already unlocked styles should not farm another disposable key.
  local check=remote:InvokeServer(entry.command,true)
  if check==1 then finishPurchase(entry,id);return end
  if death and remote:InvokeServer('OpenLibrary')==true then finishPurchase(entry,id);return end
  local bossName=death and 'Awakened Ice Admiral' or 'Tide Keeper'
  local spawn=death and Vector3.new(6400,340,-6890) or Vector3.new(-3570,123,-11555)
  say('Finding '..bossName)
  if not move(spawn+Vector3.new(0,18,0),id) then return end
  local enemy=enemyByName(bossName)
  if enemy then say('Fighting '..bossName);fight(enemy,id);task.wait(1.5) end
  if not active(id) or tool(keyName) then return end
  local deadline=os.clock()+(preferences.hopWait or 20)
  repeat
   if tool(keyName) or enemyByName(bossName) then return end
   say('No '..keyName..'; hopping in '..math.max(0,math.ceil(deadline-os.clock()))..'s')
   task.wait(.25)
  until not active(id) or os.clock()>=deadline
  if active(id) and not keyHeld() then
   release();preferences.Flush()
   local requested,message=preferences.RequestHop('style')
   say(requested and 'Finding another server for '..bossName or tostring(message or 'Retrying server search'))
   task.wait(3)
  end
 end
 local function electricClaw(entry,id)
  if not travelSea(3,id) then return end
  local hero=npcPosition({'Previous Hero','PreviousHero'},Vector3.new(-10371,331,-10131))
  if not move(hero,id) then return end
  local state=remote:InvokeServer('BuyElectricClaw',true)
  if state==4 then
   remote:InvokeServer('BuyElectricClaw','Start');say('Reaching Mansion within 30 seconds')
   if not move(Vector3.new(-12548,337,-7481),id) then return end
   task.wait(.5)
   if not move(hero,id) then return end
   state=remote:InvokeServer('BuyElectricClaw',true)
   if state==4 then stop('Mansion timer expired. Raise tween speed and try again.');return end
  end
  finishPurchase(entry,id)
 end
 local function waterQuest(entry,id)
  if not travelSea(1,id) then return end
  if remote:InvokeServer('CheckFishmanKarate') then finishPurchase(entry,id);return end
  say('Solving Underwater City crystals')
  if not move(Vector3.new(61680,55,1030),id) then return end
  local map=workspace:FindFirstChild('Map');local fish=map and map:FindFirstChild('Fishmen')
  local puzzle=fish and fish:FindFirstChild('FishmanKarate')
  if not puzzle then say('Waiting for the crystal puzzle to load');return end
  -- The game's puzzle moves Pillar3 to (1,2), Pillar4 to (4,2)
  -- by touching each root from the opposite side of the desired move.
  for _,pair in ipairs({{3,Vector2.new(1,2)},{4,Vector2.new(4,2)}}) do
   local pillar=puzzle:FindFirstChild('Pillar'..pair[1]);local r=pillar and pillar:FindFirstChild('Root')
   if not r then return end
   local failures=0
   for _=1,16 do
    if not active(id) then return end
    local p=pillar:GetAttribute('Position');if typeof(p)~='Vector2' then say('Waiting for the puzzle to initialize');return end
    if p==pair[2] then break end
    local dx=math.sign(pair[2].X-p.X);local dz=dx==0 and math.sign(pair[2].Y-p.Y) or 0
    local direction=Vector3.new(dx,0,dz)
    local distance=math.max(r.Size.X,r.Size.Z)*.5+5
    if not move(r.Position-direction*distance,id) then return end
    if not move(r.Position-direction*1,id) then return end
    task.wait(.8)
    if pillar:GetAttribute('Position')==p then failures=failures+1 else failures=0 end
    if failures>=3 then stop('Crystal did not move. Retry Get Water Kung Fu near the puzzle.');return end
   end
  end
  task.wait(2)
  if remote:InvokeServer('CheckFishmanKarate') then finishPurchase(entry,id)
  else say('Waiting for the light beam to open the teacher room') end
 end
 local electricCloud;local cloudHiddenSince
 local function chargedCloud(part)
  if not part or not part.Parent or not part:IsA('BasePart') then return false end
  local sky=workspace:FindFirstChild('Map') and workspace.Map:FindFirstChild('Sky')
  if not sky or not part:IsDescendantOf(sky) then return false end
  local c=part.Color
  return part.Name:lower():find('cloud',1,true)~=nil and c.R<.55 and c.G<.55 and c.B<.6 and part.Transparency<1
 end
 local function electricQuest(entry,id)
  if not travelSea(1,id) then return end
  local state=remote:InvokeServer('ElectroQuestState')
  local teacher=npcPosition({'Mad Scientist','SkyElectroTeacher'},Vector3.new(-4970,718,-2623))
  if state==3 or state==4 or tool('Lightning Bolt') then
   electricCloud=nil
   if not move(teacher,id) then return end
   if remote:InvokeServer('DeliverLightningBolt')~=1 then say('Lightning Bolt delivery not confirmed');return end
   finishPurchase(entry,id);return
  elseif state==2 then electricCloud=nil;finishPurchase(entry,id);return
  elseif state==0 or state==5 then
   if not move(teacher,id) then return end
   if remote:InvokeServer('AcceptElectroQuest')~=1 then stop('Electric quest could not be accepted.');return end
  end
  if electricCloud and electricCloud.Parent and electricCloud.Transparency>=1 then
   cloudHiddenSince=cloudHiddenSince or os.clock()
   if os.clock()-cloudHiddenSince>10 then electricCloud=nil;cloudHiddenSince=nil end
  else cloudHiddenSince=nil end
  if not electricCloud or not electricCloud.Parent then
   electricCloud=nil
   local sky=workspace:FindFirstChild('Map') and workspace.Map:FindFirstChild('Sky')
   if not sky then move(teacher,id);say('Waiting for Lower Skylands to load');return end
   local gap
   for _,part in ipairs(sky:GetDescendants()) do
    if chargedCloud(part) then
     local d=root() and (part.Position-root().Position).Magnitude or math.huge
     if not gap or d<gap then electricCloud=part;gap=d end
    end
   end
  end
  if not electricCloud then say('Waiting for a charged Lower Skylands cloud');task.wait(2);return end
  local cloud=electricCloud
  say('Breaking charged cloud')
  local attackPosition=cloud.Position+Vector3.new(0,cloud.Size.Y*.5+12,0)
  if not token or not farm.SeaActive(token) or not root() or (root().Position-attackPosition).Magnitude>25 then
   if not move(attackPosition,id) then return end
  end
  if not active(id) or not cloud.Parent then return end
  farm.HoverCloud(cloud,token)
  farm.BreakCloud(cloud,token)
  if active(id) then say(farm.message or 'Breaking charged cloud') end
 end
 local function materialCount(name)
  local ok,result=pcall(function()
   if not require(RS.ItemReplicationService).IsInitialized then return nil end
   local ids=require(RS.IdMap);local replication=require(RS.Util.ItemReplication)
   local group=ids.Material;local id=group and group[name]
   if not id then return nil end
   return replication.Quantity.readClient(id) or 0
  end)
  if ok and type(result)=='number' then return result end
  return nil
 end
 local function farmMaterial(name,amount,id)
  if token then farm.SeaEnd(token);token=nil end
  farm.SelectMaterial(name);farm.SetMode('material',true)
  local generation=farm.generation
  while active(id) and farm.enabled and farm.generation==generation do
   if name=='Bones' and tool('Fire Essence') then farm.SetEnabled(false);return true end
   local count=name=='Bones' and remote:InvokeServer('Bones','Check') or materialCount(name)
   if type(count)~='number' then stop('Material inventory not ready; no purchase was made.');return false end
   say(name..': '..count..' / '..amount)
   if count>=amount then farm.SetEnabled(false);return true end
   task.wait(1)
  end
  if active(id) then stop('Material farming stopped.') end
  return false
 end
 local function dragonTalon(entry,id)
  if not travelSea(3,id) then return end
  if tool('Fire Essence') then
   local uzoth=npcPosition({'Uzoth','TalonTeacher'},Vector3.new(-1029,353,-9454))
   if not move(uzoth,id) then return end
   remote:InvokeServer('BuyDragonTalon',true);finishPurchase(entry,id);return
  end
  local state=remote:InvokeServer('BuyDragonTalon',true)
  if type(state)=='number' then finishPurchase(entry,id);return end
  local bones,offers,left,minutes=remote:InvokeServer('Bones','Check')
  if type(bones)~='number' or type(left)~='number' then stop('Death King did not return his stock.');return end
  if bones<500 then if not farmMaterial('Bones',500,id) then return end end
  if not active(id) or tool('Fire Essence') then return end
  bones,offers,left,minutes=remote:InvokeServer('Bones','Check')
  if type(left)~='number' then stop('Death King stock is unavailable.');return end
  if left<=0 then
   release();local waitSeconds=math.max(30,(tonumber(minutes) or 120)*60)
   preferences.styleWaitUntil=os.time()+waitSeconds;preferences.Flush()
   say('500 Bones ready; waiting for Death King reset');return
  end
  local group,index
  if type(offers)=='table' then for g,items in pairs(offers) do if type(items)=='table' then for i,item in pairs(items) do
   if type(item)=='table' and tostring(item[1]):lower():find('random',1,true) then group=g;index=i end
  end end end end
  if not group then stop('Random Surprise offer unavailable.');return end
  release()
  for i=1,math.min(10,left) do
   if not active(id) or tool('Fire Essence') then return end
   say('Death King roll '..i..' / '..math.min(10,left))
   local reply=remote:InvokeServer('Bones','Buy',group,index)
   if reply~=1 then say('Death King paused: '..tostring(reply));break end
   task.wait(.8)
  end
 end
 local function godhuman(entry,id)
  for _,req in ipairs({{'Magma Ore',20,2},{'Mystic Droplet',10,2},{'Fish Tail',20,3},{'Dragon Scale',10,3}}) do
   local count=materialCount(req[1])
   if count==nil then stop('Waiting for material inventory. Retry when it has loaded.');return end
   if count<req[2] then
    if not travelSea(req[3],id) then return end
    if not farmMaterial(req[1],req[2],id) then return end
   end
  end
  if not travelSea(3,id) then return end
  if not move(npcPosition({'Ancient Monk','GodhumanTeacher'},Vector3.new(-13771,334,-9877)),id) then return end
  finishPurchase(entry,id)
 end
 local function run(entry,id)
  while active(id) do
   if preferences.HasRareItem and preferences.HasRareItem() then stop('Rare item found; fighting-style task stopped.');return end
   if (preferences.styleWaitUntil or 0)>os.time() and not tool('Fire Essence') then
    say('Death King reset: '..math.ceil((preferences.styleWaitUntil-os.time())/60)..' min');task.wait(1)
   else
    preferences.styleWaitUntil=nil
    if entry.name=='Water Kung Fu' then waterQuest(entry,id)
    elseif entry.name=='Electric' then electricQuest(entry,id)
    elseif entry.name=='Death Step' or entry.name=='Sharkman Karate' then huntKey(entry,id)
    elseif entry.name=='Electric Claw' then electricClaw(entry,id)
    elseif entry.name=='Dragon Talon' then dragonTalon(entry,id)
    elseif entry.name=='Godhuman' then godhuman(entry,id) end
    task.wait(entry.name=='Electric' and .05 or 1)
   end
  end
 end
 local function start(name)
  stop();local entry=byName[name];if not entry or not entry.get then return end
  sea.SetEnabled(false);travelAPI.Stop();otherFarm.PausePriority()
  farm.SetEnabled(false);farm.stackFruit=false;farm.SetAutoClick(false)
  for key in pairs(farm.stackEvents) do farm.stackEvents[key]=false end
  preferences.eliteHop=false;preferences.fruitHop=false
  preferences.styleJob=name;preferences.styleBusy=true;preferences.save=true;preferences.Flush()
  local id=serial
  task.spawn(function()
   local ok,err=xpcall(function()
    local setIdentity=setthreadidentity or setidentity
    if setIdentity then setIdentity(2) end
    run(entry,id)
   end,debug.traceback)
   if not ok and active(id) then stop('Unlock task stopped: '..tostring(err)) end
  end)
 end
 preferences.StartStyle=start
 preferences.StyleHasKey=keyHeld
 preferences.StopStyle=function() stop('Stopped.') end
 local title=label(panel,'Fighting Styles',18,450,478,24,14);title.Font=Enum.Font.GothamBold
 local y=478
 for _,entry in ipairs(styles) do
  label(panel,entry.name,18,y,179,26,13)
  local price=label(panel,entry.price,205,y,193,26,11);price.TextXAlignment=Enum.TextXAlignment.Right
  local b=control(panel,'Buy',416,y,74,26)
  bindControl(b,'Activated',function()
   if buyBusy then return end
   if preferences.styleJob then stop('Unlock task stopped for purchase.') end
   buyBusy=true;b.Text='...'
   task.spawn(function()
    local ok,success,message=pcall(purchase,entry)
    buyBusy=false;if not alive then return end
    b.Text='Buy';say(ok and (success and entry.name..' ready.' or message) or 'Purchase not confirmed; check your inventory before retrying.')
   end)
  end)
  y=y+30
  if entry.get then
   label(panel,'Get '..entry.name,30,y,330,24,12)
   local toggle=control(panel,'OFF',416,y,74,24);getButtons[entry.name]=toggle
   bindControl(toggle,'Activated',function()
    if buyBusy then return end
    if preferences.styleJob==entry.name then stop('Stopped.') else start(entry.name) end
   end)
   y=y+28
  end
  line(panel,y);y=y+3
 end
 statusLabel=label(panel,'',18,y+4,478,28,11);statusLabel.TextWrapped=true
 panel.CanvasSize=UDim2.fromOffset(0,y+58)
 preferences.ShopItemsY=y+38
 task.spawn(function()
  repeat task.wait(.2) until preferenceReady or not alive
  if not alive then return end
  local saved=preferences.styleJob;local deadline=preferences.styleWaitUntil
  if saved then start(saved);preferences.styleWaitUntil=deadline end
  while alive do
   for name,b in pairs(getButtons) do b.Text=preferences.styleJob==name and 'ON' or 'OFF' end
   if keyHeld() and preferences.CancelStyleHop then preferences.CancelStyleHop() end
   task.wait(.2)
  end
  release()
 end)
end

-- Item purchases use current inventory confirmation, not reply codes alone.
do
local itemShopCatalog={{name="Katana",price="$1,000",sea=1,kind="Swords",seller="Sword Dealer",level=0,method="beli"},{name="Cutlass",price="$1,000",sea=1,kind="Swords",seller="Sword Dealer",level=0,method="beli"},{name="Dual Katana",price="$12,000",sea=1,kind="Swords",seller="Sword Dealer of the West",level=0,method="beli"},{name="Iron Mace",price="$25,000",sea=1,kind="Swords",seller="Sword Dealer of the West",level=0,method="beli"},{name="Triple Katana",price="$60,000",sea=1,kind="Swords",seller="Sword Dealer of the East",level=0,method="beli"},{name="Pipe",price="$100,000",sea=1,kind="Swords",seller="Sword Dealer of the East",level=0,method="beli"},{name="Dual-Headed Blade",price="$400,000",sea=1,kind="Swords",seller="Master Sword Dealer",level=0,method="beli"},{name="Bisento",price="$1,000,000",sea=1,kind="Swords",seller="Master Sword Dealer",level=0,method="beli"},{name="Soul Cane",price="$750,000",sea=1,kind="Swords",seller="Living Skeleton",level=0,method="beli"},{name="Slingshot",price="$5,000",sea=1,kind="Guns",seller="Weapon Dealer",level=0,method="beli"},{name="Musket",price="$8,000",sea=1,kind="Guns",seller="Weapon Dealer",level=0,method="beli"},{name="Flintlock",price="$10,500",sea=1,kind="Guns",seller="Weapon Dealer",level=0,method="beli"},{name="Refined Slingshot",price="$30,000",sea=1,kind="Guns",seller="Advanced Weapon Dealer",level=0,method="beli"},{name="Dual Flintlock",price="$65,000",sea=1,kind="Guns",seller="Advanced Weapon Dealer",level=0,method="beli"},{name="Cannon",price="$100,000",sea=1,kind="Guns",seller="Advanced Weapon Dealer",level=0,method="beli"},{name="Black Cape",price="$50,000",sea=1,kind="Accessories",seller="Parlus",level=50,method="beli"},{name="Swordsman Hat",price="$150,000",sea=1,kind="Accessories",seller="Hasan",level=0,method="beli"},{name="Tomoe Ring",price="$500,000",sea=1,kind="Accessories",seller="Yoshi",level=0,method="beli"},{name="Kabucha",price="1,500 Fragments",sea=2,kind="Guns",seller="The Strongest God",level=0,method="kabucha"},{name="Bizarre Revolver",price="25 Ectoplasm",sea=2,kind="Guns",seller="El Rodolfo",level=0,method="ectoplasm",index=1,amount=25},{name="Ghoul Mask",price="50 Ectoplasm",sea=2,kind="Accessories",seller="El Perro",level=0,method="ectoplasm",index=2,amount=50},{name="Midnight Blade",price="100 Ectoplasm",sea=2,kind="Swords",seller="El Admin",level=0,method="ectoplasm",index=3,amount=100}}

 local rs=game.ReplicatedStorage;local remote=rs.Remotes.CommF_;local panel=panels.Shop
 local seaId=({[2753915549]=1,[85211729168715]=1,[4442272183]=2,[79091703265657]=2,[7449423635]=3,[100117331123089]=3})[game.PlaceId]
 local hasItems=false
 for _,entry in ipairs(itemShopCatalog) do if entry.sea==seaId then hasItems=true;break end end
 if hasItems then
 local y=preferences.ShopItemsY or 1300
 label(panel,'Items — Sea '..tostring(seaId),18,y,470,26,15);y=y+28
 local message=label(panel,'',18,y,470,28,11);message.TextWrapped=true;y=y+30
 local busy=false;local job;local buttons={}
 local function normalized(n) return tostring(n):lower():gsub('[^%w]','') end
 local function inventory(name)
  local wanted=normalized(name)
  local rep=require(rs.ItemReplicationService);local config=require(rs.ItemConfig)
  if not rep.IsInitialized then return nil end
  for _,item in pairs(rep:GetItems(rep.KEYS.QUANTITY) or {}) do
   if type(item.Value)=='number' and item.Value>0 then
    local result=config.match(item.ItemId)
    if result:isOk() then
     local c=result:unwrap();local key=c.Index and c.Index.StorageKey;local display=c.Display and c.Display.Name
     if normalized(key)==wanted or normalized(display)==wanted then return item,c end
    end
   end
  end
 end
 local function equip(entry)
  local item,c=inventory(entry.name);if not item then return false end
  local actions=c.Inventory and c.Inventory.Actions or {}
  for _,action in pairs(actions) do
   if action=='EquipItem' then
    require(rs.Controllers.UI.Inventory.RemoteUtil).invokeAction(action,item.ItemId,item.NetworkedUID,false):await()
    return true
   end
  end
  remote:InvokeServer('LoadItem',c.Index.StorageKey);return true
 end
 local function confirmed(entry)
  local deadline=os.clock()+4
  repeat
   if inventory(entry.name) then return true end
   task.wait(.2)
  until not alive or os.clock()>=deadline
  return false
 end
 local function buy(entry)
  if inventory(entry.name) then equip(entry);message.Text=entry.name..' is owned; equip requested.';return end
  if entry.level and player.Data.Level.Value<entry.level then message.Text='Requires level '..entry.level;return end
  local result
  if entry.method=='beli' then
   local shop=require(rs.Shop);local d=shop.LEGACY_BELI_ITEMS and shop.LEGACY_BELI_ITEMS[entry.name]
   if d and type(d.Price)=='number' and player.Data.Beli.Value<d.Price then message.Text='Not enough money.';return end
   result=remote:InvokeServer('BuyItem',entry.name)
  elseif entry.method=='ectoplasm' then result=remote:InvokeServer('Ectoplasm','Buy',entry.index)
  elseif entry.method=='kabucha' then
   if not remote:InvokeServer('BlackbeardReward','Slingshot','1') then message.Text='Kabucha is unavailable.';return end
   result=remote:InvokeServer('BlackbeardReward','Slingshot','2')

  end
  if confirmed(entry) then message.Text=entry.name..' received.';equip(entry)
  else message.Text=entry.name..' not confirmed. Reply: '..tostring(result)..'. '..(entry.requirement or 'Check the seller and requirements.') end
 end
 local function stopJob()
  if job then job=nil;if farm.enabled and farm.mode=='material' then farm.SetEnabled(false) end;otherFarm.ResumePriority() end
 end
 preferences.StopItemShop=stopJob
 for _,kind in ipairs({'Swords','Guns','Accessories'}) do
  local hasKind=false
  for _,entry in ipairs(itemShopCatalog) do if entry.sea==seaId and entry.kind==kind then hasKind=true;break end end
  if hasKind then label(panel,kind,18,y,470,24,14);y=y+28 end
  for _,entry in ipairs(itemShopCatalog) do
   if entry.sea==seaId and entry.kind==kind then
    label(panel,entry.name,18,y,235,25,13)
    local price=label(panel,entry.price,255,y,145,25,11);price.TextXAlignment=Enum.TextXAlignment.Right
    local button=control(panel,'Buy',416,y,74,25)
    buttons[#buttons+1]={button=button,entry=entry}
    bindControl(button,'Activated',function()
     if busy then return end
     stopJob();busy=true;button.Text='...';message.Text='Checking '..entry.name
     task.spawn(function()
      local ok,err=pcall(buy,entry);busy=false
      if alive and not ok then message.Text='Could not confirm '..entry.name..': '..tostring(err):sub(1,130) end
     end)
    end)
    y=y+27
    if entry.method=='ectoplasm' then
     label(panel,'Get '..entry.name,30,y,350,24,12)
     local get=control(panel,'OFF',416,y,74,24)
     bindControl(get,'Activated',function()
      if busy then return end
      if job==entry then stopJob();get.Text='OFF';return end
      stopJob();job=entry;sea.SetEnabled(false);travelAPI.Stop();otherFarm.PausePriority();farm.SetAutoClick(false);farm.SelectMaterial('Ectoplasm');farm.SetMode('material',true)
      task.spawn(function()
       while alive and job==entry do
        get.Text='ON'
        local ok,amount=pcall(function() return remote:InvokeServer('Ectoplasm','Check') end)
        if ok and type(amount)=='number' and amount>=entry.amount then
         stopJob();busy=true;local success,err=pcall(buy,entry);busy=false
         if not success then message.Text=tostring(err) end;break
        end
        message.Text='Collecting Ectoplasm for '..entry.name..': '..tostring(amount)..'/'..entry.amount
        task.wait(2)
       end
       if alive then get.Text='OFF' end
      end)
     end)
     y=y+28
    elseif entry.requirement then
     local hint=label(panel,entry.requirement,30,y,455,28,10);hint.TextWrapped=true;y=y+30
    end
    line(panel,y);y=y+3
   end
  end
 end
 panel.CanvasSize=UDim2.fromOffset(0,y+16)
 local cleanup=beforeCleanup;beforeCleanup=function()stopJob();if cleanup then cleanup() end end
 task.spawn(function()
  while alive do
   if not busy then for _,row in ipairs(buttons) do
    local ok,owned=pcall(inventory,row.entry.name)
    row.button.Text=ok and owned and 'Equip' or 'Buy'
   end end
   task.wait(3)
  end
 end)
 end
end

-- One movement owner during a selected world boss; resume only if the user
-- has not replaced the job and the rare-item guard has not stopped it.
do
 local session
 local function protectedItem() return preferences.HasRareItem and preferences.HasRareItem() end
 local function finish(resume)
  local old=session;if not old then return end
  session=nil;farm.priorityOnly=false;preferences.priorityBusy=false
  otherFarm.ResumePriority()
  if not resume or not alive or protectedItem() then return end
  farm.stackFruit=old.farm.stackFruit;farm.SetAutoClick(old.farm.autoClick)
  farm.SetMode(old.farm.mode,old.farm.enabled)
  if old.sea then sea.SetEnabled(true)
  elseif old.travel.active then travelAPI.Select(old.travel.key);travelAPI.Start() end
  preferences.Flush()
 end
 task.spawn(function()
  while alive do
   local ok,err=xpcall(function()
   if preferenceReady then
    local boss=farm.PriorityBoss()
    if session then
     if protectedItem() or farm.generation~=session.token then finish(false)
     elseif boss then session.absentAt=nil
     else
      session.absentAt=session.absentAt or os.clock()
      if os.clock()-session.absentAt>=4 then finish(true) end
     end
    elseif boss and not protectedItem() and not preferences.styleJob and not preferences.itemQuestBusy then
     local snapshot={mode=farm.mode,enabled=farm.enabled,stackFruit=farm.stackFruit,autoClick=farm.autoClick}
     local wasSea=sea.enabled;local travel=travelAPI.Snapshot()
     preferences.priorityBusy=true
     local interrupted=otherFarm.PausePriority()
     if interrupted then
      snapshot.enabled=interrupted.enabled;snapshot.stackFruit=interrupted.stackFruit;snapshot.autoClick=interrupted.autoClick
     end
     sea.SetEnabled(false);travelAPI.Stop()
     farm.priorityOnly=true
     farm.SetMode(snapshot.mode,snapshot.enabled)
     session={farm=snapshot,sea=wasSea,travel=travel,token=farm.generation}
    end
   end
   end,debug.traceback)
   if not ok then
    -- A failed scan must not leave the paused-job flags latched forever.
    session=nil;farm.priorityOnly=false;preferences.priorityBusy=false
    otherFarm.ResumePriority()
    warn('Nexo boss priority recovered: '..tostring(err))
    task.wait(1)
   end
   task.wait(.25)
  end
  finish(false)
 end)
end

-- Auto Saber uses the same quest stages as the standalone progression script.
do
 local remote=game.ReplicatedStorage.Remotes.CommF_
 local RS=game.ReplicatedStorage
 local panel=panels['Get Items']
 label(panel,'Auto Saber',18,18,350,30,14)
 local toggle=control(panel,'OFF',410,18,80,28)
 local status=label(panel,'',18,62,470,100,12);status.TextWrapped=true;status.TextYAlignment=Enum.TextYAlignment.Top
 local token;local generation=0;local action='Stopped';local nextAction;local completed={};local resume
 local function state() return completed end
 local function tool(name) local c=player.Character;local b=player:FindFirstChild('Backpack');return (c and c:FindFirstChild(name)) or (b and b:FindFirstChild(name)) end
 local function active(id) return alive and preferences.autoSaber==true and generation==id end
 local function release()
  if token then farm.SeaEnd(token);token=nil end
  otherFarm.ResumePriority()
 end
 local function suspend()
  if not resume then resume={enabled=farm.enabled,mode=farm.mode};farm.SetEnabled(false);sea.SetEnabled(false);travelAPI.Stop();otherFarm.PausePriority() end
 end
 local function move(point,id)
  if not active(id) then return false end
  if not token or not farm.SeaActive(token) then token=farm.SeaBegin() end
  return farm.SeaMove(point,token) and active(id)
 end
 local function position(object)
  if not object then return nil end
  if object:IsA('BasePart') then return object.Position end
  if object:IsA('Model') then return object:GetPivot().Position end
 end
 local function npc(name,fallback)
  local result
  pcall(function() for _,v in ipairs(require(RS.NPCManager).getNPCsByName(name)) do local m=v:getModel();if m then result=m:GetPivot().Position+Vector3.new(0,0,4);break end end end)
  return result or fallback
 end
 local function equipNamed(name)
  local t=tool(name);local c=player.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
  if t and h then h:EquipTool(t) end
  return t
 end
 local function fightBoss(name,point,id)
  if not move(point+Vector3.new(0,22,0),id) then return end
  local enemy
  for _,v in ipairs(workspace.Enemies:GetChildren()) do local h=v:FindFirstChildOfClass('Humanoid');if v.Name:find(name,1,true) and h and h.Health>0 then enemy=v;break end end
  if not enemy then action='Waiting for '..name;return end
  local h=enemy:FindFirstChildOfClass('Humanoid');local r=enemy:FindFirstChild('HumanoidRootPart')
  if not r then return end
  while active(id) and farm.SeaActive(token) and enemy.Parent and h.Health>0 do farm.SeaHover(r,token,24,false);farm.SeaAttack(enemy,token);task.wait(.06) end
 end
 local function saber(id)
  suspend();action='Completing Saber quest';nextAction='Unlock Instinct, then resume level farming'
  local q=remote:InvokeServer('ProQuestProgress')
  if type(q)~='table' then release();return end
  if q.KilledShanks then state().saber=true;release();preferences.Flush();return end
  local map=workspace:FindFirstChild('Map');if not map then return end
  local jungle=map:FindFirstChild('Jungle');local desert=map:FindFirstChild('Desert');local ice=map:FindFirstChild('Ice')
  for i=1,5 do if not (q.Plates and (q.Plates[i] or q.Plates[tostring(i)])) then
   if not jungle then move(Vector3.new(-1612,37,149),id);return end
   local plates=jungle:FindFirstChild('QuestPlates');local plate=plates and plates:FindFirstChild('Plate'..i);local b=plate and plate:FindFirstChild('Button')
   if b and move(b.Position,id) then remote:InvokeServer('ProQuestProgress','Plate',i) end
   return
  end end
  if not q.UsedTorch then
   if not tool('Torch') then
    local t=jungle and jungle:FindFirstChild('Torch')
    if move(position(t) or Vector3.new(-1612,12,149),id) then remote:InvokeServer('ProQuestProgress','GetTorch') end;return
   end
   if not desert then move(Vector3.new(1094,7,4193),id);return end
   local burn=desert:FindFirstChild('Burn');local fire=burn and burn:FindFirstChild('Fire')
   equipNamed('Torch');if fire and move(position(fire),id) then task.wait(5);if active(id) then remote:InvokeServer('ProQuestProgress','DestroyTorch') end end;return
  end
  if not q.UsedCup then
   if not tool('Cup') then
    if not desert then move(Vector3.new(1094,7,4193),id);return end
    local cup=desert:FindFirstChild('Cup',true)
    action='Saber: collecting the cup in Desert'
    if move(position(cup) or Vector3.new(1114,6,4366),id) then remote:InvokeServer('ProQuestProgress','GetCup') end;return
   end
   if not ice then move(Vector3.new(1347,37,-1325),id);return end
   local drop=ice:FindFirstChild('ParticleDrop');local water=drop and drop:FindFirstChild('Water')
   action='Saber: filling the cup and helping Sick Man'
   local cup=equipNamed('Cup');if water and move(position(water),id) then remote:InvokeServer('ProQuestProgress','FillCup',cup) end
   if move(npc('Sick Man',Vector3.new(1397,37,-1321)),id) then remote:InvokeServer('ProQuestProgress','SickMan') end;return
  end
  if not q.TalkedSon or (q.KilledMob and not tool('Relic') and not q.UsedRelic) then
   if move(npc('Rich Man',Vector3.new(-910,14,4077)),id) then remote:InvokeServer('ProQuestProgress','RichSon') end;return
  end
  if not q.KilledMob then fightBoss('Mob Leader',Vector3.new(-2848,7,5354),id);return end
  if not q.UsedRelic then
   local door
   if jungle then for _,v in ipairs(jungle:GetChildren()) do if v.Name=='Final' and not v:FindFirstChild('Invis') then door=v;break end end end
   local socket=door and (door:FindFirstChild('Cross',true) or door:FindFirstChild('Part'))
   action='Saber: placing the relic at the entrance'
   equipNamed('Relic')
   if move(position(socket) or Vector3.new(-1462,30,45),id) and active(id) then
    equipNamed('Relic');task.wait(.25)
    if active(id) then remote:InvokeServer('ProQuestProgress','PlaceRelic') end
   end;return
  end
  action='Saber: finding Saber Expert'
  fightBoss('Saber Expert',Vector3.new(-1405,29,4),id)
 end

 local function setEnabled(on)
  generation=generation+1;preferences.autoSaber=on==true;toggle.Text=on and 'ON' or 'OFF'
  if not on then release();local old=resume;resume=nil;if old and alive then farm.SetMode(old.mode,old.enabled) end;preferences.Flush();return end
  local id=generation
  task.spawn(function()
   local setIdentity=setthreadidentity or setidentity;if setIdentity then setIdentity(2) end
   while active(id) do
    local data=player:FindFirstChild('Data');local level=data and data:FindFirstChild('Level')
    if game.PlaceId~=2753915549 and game.PlaceId~=85211729168715 then action='Auto Saber requires Sea 1'
    elseif not level or level.Value<200 then action='Reach level 200 to complete Saber'
    elseif preferences.styleJob or preferences.priorityBusy then action='Waiting for the current quest'
    elseif preferences.HasRareItem and preferences.HasRareItem() then action='Protected item: paused'
    else
     local ok,err=pcall(saber,id)
     if not ok then action='Retrying: '..tostring(err) end
     if completed.saber then action='✓ Saber quest complete';setEnabled(false);break end
    end
    task.wait(1)
   end
  end)
  preferences.Flush()
 end
 preferences.SetAutoSaber=setEnabled
 bindControl(toggle,'Activated',function()if preferenceReady then setEnabled(not preferences.autoSaber)end end)
 task.spawn(function()
  repeat task.wait(.2) until preferenceReady or not alive
  if not alive then return end
  if preferences.autoSaber then setEnabled(true) end
  while alive do status.Text=action;task.wait(.3) end
  release()
 end)
end

-- A join-time wait followed by the existing cross-island chest patrol.
do
 local panel=panels['Get Items']
 label(panel,'Collect Fist of Darkness',18,170,365,30,14)
 local button=control(panel,'OFF',410,170,80,28)
 local message=label(panel,'Wait 4 hours from joining, then search chests. Sea 2 only.',18,210,470,64,12)
 message.TextWrapped=true;message.TextYAlignment=Enum.TextYAlignment.Top
 panel.CanvasSize=UDim2.fromOffset(0,290)
 local searching=false;local found=false
 local function isSea2() return game.PlaceId==4442272183 or game.PlaceId==79091703265657 end
 local function hasFist()
  for _,container in pairs({player.Character,player:FindFirstChild('Backpack')}) do
   for _,item in ipairs(container:GetChildren()) do
    if item:IsA('Tool') and item.Name:lower():gsub('[^%a]','')=='fistofdarkness' then return item end
   end
  end
 end
 local function stopJobs()
  if preferences.SetAutoSaber then preferences.SetAutoSaber(false) end
  if preferences.StopStyle then preferences.StopStyle() end
  preferences.eliteHop=false;preferences.fruitHop=false
  if preferences.CancelAllHop then preferences.CancelAllHop() end
  otherFarm.Stop();travelAPI.Stop();sea.SetEnabled(false)
  for key in pairs(farm.stackEvents) do farm.stackEvents[key]=false end
  farm.SetStackFruit(false);farm.SetAutoClick(false);farm.SetEnabled(false)
 end
 local function setEnabled(on)
  if on and not isSea2() then message.Text='Sea 2 is required for this chest search.';return end
  preferences.collectFist=on==true;searching=false;found=false
  stopJobs()
  if on then preferences.safeRetreat=true;preferences.fistSheltered=false end
  button.Text=on and 'ON' or 'OFF'
  if not on then message.Text='Stopped' end
  preferences.Flush()
 end
 preferences.SetCollectFist=setEnabled
 bindControl(button,'Activated',function() if preferenceReady then setEnabled(not preferences.collectFist) end end)
 task.spawn(function()
  repeat task.wait(.2) until preferenceReady or not alive
  if not alive then return end
  if preferences.collectFist then setEnabled(true) end
  while alive do
   if preferences.collectFist then
    if not isSea2() then setEnabled(false);message.Text='Stopped: Sea 2 required.'
    elseif hasFist() then
     -- The existing rare-item guard owns the retreat. Never consume or reset.
     found=true;preferences.safeRetreat=true;preferences.other.chest=false;preferences.other.chestHop=false
     message.Text='Fist collected — moving to Café. Keeping it in your backpack.'
     if preferences.fistSheltered then
      local char=player.Character;local h=char and char:FindFirstChildOfClass('Humanoid')
      if h then h:UnequipTools() end
      preferences.collectFist=false;button.Text='OFF';preferences.Flush()
      message.Text='Fist collected ✓  Waiting at Café. Anti-AFK stays active.'
     end
    elseif found then
     setEnabled(false);message.Text='Fist no longer present. Search stopped.'
    else
     local remaining=math.max(0,14400-time())
     if remaining>0 then
      message.Text=string.format('Chest search begins in %02d:%02d:%02d',math.floor(remaining/3600),math.floor(remaining/60)%60,math.floor(remaining)%60)
     else
      if not searching then
       stopJobs();otherFarm.stopped=false;otherFarm.ResumePriority()
       preferences.other.limit=false;preferences.other.chestHop=false;preferences.other.chest=true
       searching=true;preferences.Flush()
      end
      message.Text='Searching chests across islands until a Fist is collected.'
     end
    end
   end
   task.wait(.5)
  end
 end)
end

do
 local rs=game:GetService('ReplicatedStorage');local remote=rs.Remotes.CommF_
 local panel=panels['V4 Trial'];local token;local generation=0
 label(panel,'Tween to Trial',18,14,350,30,14)
 local enter=control(panel,'GO',410,14,80,28)
 label(panel,'Go to Race Room',18,58,350,30,14)
 local room=control(panel,'GO',410,58,80,28)
 label(panel,'Auto Buy Training',18,102,350,30,14)
 local buy=control(panel,'OFF',410,102,80,28)
 local trainingStatus=label(panel,'Training: checking',18,132,475,22,12)
 label(panel,'Find Full Moon (within 10 min)',18,164,350,30,14)
 local moon=control(panel,'OFF',410,164,80,28)
 local raceLabel=label(panel,'Race: checking',18,202,475,26,13)
 local status=label(panel,'',18,232,475,34,12);status.TextWrapped=true;status.TextYAlignment=Enum.TextYAlignment.Top
 for _,y in ipairs({50,94,158,198}) do line(panel,y) end
 local function race()
  local data=player:FindFirstChild('Data');local v=data and data:FindFirstChild('Race')
  return v and tostring(v.Value) or ''
 end
 local function root() local c=player.Character;return c and c:FindFirstChild('HumanoidRootPart') end
 local function sea3() return game.PlaceId==7449423635 or game.PlaceId==100117331123089 end
 local function active(id) return alive and generation==id and token and farm.SeaActive(token) end
 local function stop()
  generation=generation+1
  if token then farm.SeaEnd(token);token=nil end
  otherFarm.ResumePriority();enter.Text='GO';room.Text='GO'
 end
 local function npcPosition(name)
  local point
  pcall(function() for _,npc in ipairs(require(rs.NPCManager).getNPCsByName(name)) do
   local m=npc:getModel();if m then point=m:GetPivot().Position;break end
  end end)
  return point
 end
 local function temple()
  local map=workspace:FindFirstChild('Map');local stash=rs:FindFirstChild('MapStash')
  return (map and map:FindFirstChild('Temple of Time')) or (stash and stash:FindFirstChild('Temple of Time'))
 end
 local function enterTemple(id)
  local r=root();if r and r.Position.Y>14000 then return true end
  local stage=remote:InvokeServer('RaceV4Progress','Check')
  if not active(id) then return false end
  if type(stage)~='number' or stage<2 then status.Text='Temple access is not unlocked yet.';return false end
  local point=npcPosition('Mysterious Force')
  if not point then status.Text='Great Tree NPC not available; try again.';return false end
  status.Text='Travelling to Mysterious Force at Great Tree'
  if not farm.SeaMove(point+Vector3.new(0,0,5),token) or not active(id) then return false end
  local t=temple();local map=workspace:FindFirstChild('Map')
  -- Same map preparation used by the game's TempleTeleport dialogue.
  if t and map and t.Parent~=map then t.Parent=map end
  remote:InvokeServer('RaceV4Progress','Teleport')
  local deadline=os.clock()+12
  repeat
   if not active(id) then return false end
   r=root();if r and r.Position.Y>14000 then return true end
   task.wait(.2)
  until os.clock()>deadline
  status.Text='Temple entry was not confirmed; try again.';return false
 end
 local function start(goRoom)
  preferences.findFullMoon=false;preferences.CancelMoonHop();preferences.Flush()
  if token then stop();status.Text='Travel stopped';return end
  if not sea3() then status.Text='V4 Trial travel requires Sea 3.';return end
  if preferences.collectFist or (preferences.HasRareItem and preferences.HasRareItem()) then status.Text='Travel paused while protecting your rare item.';return end
  if preferences.SetAutoSaber then preferences.SetAutoSaber(false) end
  if preferences.StopStyle then preferences.StopStyle() end
  sea.SetEnabled(false);travelAPI.Stop();otherFarm.PausePriority()
  farm.SetEnabled(false);farm.SetStackFruit(false);farm.SetAutoClick(false)
  for k in pairs(farm.stackEvents) do farm.stackEvents[k]=false end
  token=farm.SeaBegin();generation=generation+1;local id=generation
  enter.Text=goRoom and 'GO' or 'STOP';room.Text=goRoom and 'STOP' or 'GO'
  task.spawn(function()
   local ok,err=pcall(function()
    if not enterTemple(id) or not active(id) then return end
    if not goRoom then status.Text='Arrived at Temple of Time';return end
    local names={angel='Skypiea',skypiea='Skypiea',ghoul='Ghoul',cyborg='Cyborg',human='Human',rabbit='Mink',mink='Mink',shark='Fishman',fishman='Fishman'}
    local current=race();local key=names[current:lower()]
    if not key then status.Text='No supported trial door for '..current;return end
    local t=temple();local corridor=t and t:FindFirstChild(key..'Corridor')
    local door=corridor and corridor:FindFirstChild('Door');local entrance=door and door:FindFirstChild('Entrance')
    if not entrance or not entrance:IsA('BasePart') then status.Text='No trial door found for '..current;return end
    status.Text='Travelling to '..current..' trial door'
    -- Entrance.LookVector points outside the temple; stand on its corridor side.
    local inside=entrance.Position-entrance.CFrame.LookVector*(entrance.Size.Z*.5+6)
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={corridor};params.RespectCanCollide=true
    local floor=workspace:Raycast(inside+Vector3.new(0,2,0),Vector3.new(0,-40,0),params)
    if not floor then status.Text='Trial corridor floor has not loaded; try again.';return end
    local hr=root();local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
    local height=math.max(3,(hum and hum.HipHeight or 2)+(hr and hr.Size.Y*.5 or 1))+.2
    local destination=floor.Position+Vector3.new(0,height,0)
    if farm.SeaMove(destination,token) and active(id) then status.Text='Arrived inside '..current..' trial corridor' end
   end)
   if generation==id then if not ok then status.Text='Travel failed: '..tostring(err) end;stop() end
  end)
 end
 bindControl(enter,'Activated',function() start(false) end)
 bindControl(room,'Activated',function() start(true) end)
 bindControl(buy,'Activated',function()
  preferences.v4Training=not preferences.v4Training
  buy.Text=preferences.v4Training and 'ON' or 'OFF';preferences.Flush()
 end)
 local searchStarted=os.clock();local matching=0;local notifiedAt;local noticeGeneration=0
 local notice=make('Frame',gui,{Name='MoonSearchNotice',AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,24),Size=UDim2.new(.9,0,0,90),BackgroundColor3=Color3.fromRGB(23,25,28),BackgroundTransparency=.12,BorderSizePixel=0,Visible=false,ZIndex=60})
 make('UISizeConstraint',notice,{MaxSize=Vector2.new(510,90)})
 make('UICorner',notice,{CornerRadius=UDim.new(0,10)})
 make('UIStroke',notice,{Color=brass,Thickness=1,Transparency=.3})
 local noticeText=make('TextLabel',notice,{Position=UDim2.fromOffset(14,10),Size=UDim2.new(1,-28,1,-20),BackgroundTransparency=1,TextColor3=pale,Font=Enum.Font.GothamMedium,TextSize=15,TextWrapped=true,Text='',ZIndex=61})
 local function notifyMoon(text,found)
  noticeGeneration=noticeGeneration+1;local id=noticeGeneration
  noticeText.Text=text;noticeText.TextColor3=found and Color3.fromRGB(103,220,140) or pale;notice.Visible=true
  task.delay(found and 12 or 8,function() if alive and noticeGeneration==id then notice.Visible=false end end)
 end
 local function moonMessage(f)
  if not f then return 'This server: moon phase is unknown.' end
  if f.state=='late' then return 'This server: too late — full moon has already passed.' end
  if f.state=='bad' then return 'This server: bad moon — next night is not full moon.' end
  if f.full then return 'This server: full moon is already active.' end
  if f.state~='near' or type(f.seconds)~='number' then return 'This server: measuring time before the next full moon.' end
  return string.format('This server: near full moon — approximately %d min %02d sec remaining.',math.floor(f.seconds/60),math.floor(f.seconds)%60)
 end
 local function setMoon(on)
  if on and not sea3() then preferences.findFullMoon=false;preferences.CancelMoonHop();preferences.Flush();status.Text='Full-moon search requires Sea 3.';return end
  if on and (preferences.collectFist or (preferences.HasRareItem and preferences.HasRareItem()) or (preferences.StyleHasKey and preferences.StyleHasKey())) then
   status.Text='Search blocked: protect your rare item or quest key.';return
  end
  stop();preferences.findFullMoon=on==true;matching=0;searchStarted=os.clock();notifiedAt=nil
  preferences.CancelMoonHop()
  if on then
   preferences.save=true;preferences.eliteHop=false;preferences.fruitHop=false
   if preferences.SetAutoSaber then preferences.SetAutoSaber(false) end
   if preferences.StopStyle then preferences.StopStyle() end
   otherFarm.Stop();sea.SetEnabled(false);travelAPI.Stop()
   for key in pairs(farm.stackEvents) do farm.stackEvents[key]=false end
   farm.SetStackFruit(false);farm.SetAutoClick(false);farm.SetEnabled(false)
   status.Text='Measuring this server’s moon clock...'
  else status.Text='Full-moon search stopped' end
  preferences.Flush()
 end
 preferences.SetMoonSearch=setMoon
 bindControl(moon,'Activated',function() if preferenceReady then setMoon(not preferences.findFullMoon) end end)
 task.spawn(function()
  repeat task.wait(.2) until preferenceReady or not alive
  if not alive then return end
  if preferences.findFullMoon then setMoon(true) end
  while alive do
   moon.Text=preferences.findFullMoon and 'ON' or 'OFF'
   if preferences.findFullMoon then
    if preferences.HasRareItem and preferences.HasRareItem() then
     setMoon(false);status.Text='Rare item found: server search stopped.'
    else
     local f=preferences.MoonForecast
     local fresh=f and f.job==game.JobId and os.clock()-f.measuredAt<3
     local measured=fresh and type(f.seconds)=='number'
     local reject=fresh and f.state~='near' and not f.full
     if not notifiedAt and os.clock()-searchStarted>=2 and (measured or reject or os.clock()-searchStarted>8) then
      notifiedAt=os.clock();notifyMoon(moonMessage(fresh and f or nil),false)
     end
     if os.clock()-searchStarted<2 then status.Text='Measuring this server’s moon clock...'
     elseif fresh and (f.full or (measured and f.state=='near' and f.seconds>=0 and f.seconds<=600)) then
      matching=matching+1
      if matching>=2 then
       setMoon(false)
       status.Text=f.full and 'Found ✓ Full moon is active. Staying here.' or string.format('Found ✓  Full moon in ~%d min %02d sec. Staying here.',math.floor(f.seconds/60),math.floor(f.seconds)%60)
       notifyMoon('Matching server found ✓\n'..moonMessage(f)..'\nServer hopping stopped.',true)
      end
     elseif measured or reject or os.clock()-searchStarted>8 then
      matching=0
      if notifiedAt and os.clock()-notifiedAt>=.5 then
       local ok,message=preferences.RequestHop('moon')
       status.Text=ok and (reject and 'Wrong moon phase — finding another server...' or 'Full moon more than 10 min away — finding another server...') or (message or 'Retrying server search...')
      end
     end
    end
   end
   task.wait(.5)
  end
 end)
 task.spawn(function()
  while alive do
   raceLabel.Text='Race: '..(({Skypiea='Angel',Fishman='Shark',Mink='Rabbit'})[race()] or race())
   buy.Text=preferences.v4Training and 'ON' or 'OFF'
   task.wait(.5)
  end
 end)
 task.spawn(function()
  while alive do
   if preferenceReady then
    local ok,err=pcall(function()
     trainingStatus.TextColor3=pale
     if not sea3() then trainingStatus.Text='Training: Sea 3 only';return end
     local c=player.Character
     if not c or not c:FindFirstChild('RaceTransformed') then trainingStatus.Text='Training: V4 not unlocked';return end
     local trainingRace=race()
     local function trainingRequest(action)
      if trainingRace=='Draco' then return remote:InvokeServer('UpgradeRace',action,2) end
      return remote:InvokeServer('UpgradeRace',action)
     end
     local state,level,cost=trainingRequest('Check')
     if not alive then return end
     if state==2 or state==4 or state==7 then
      trainingStatus.Text='Training: ready to buy'..(type(cost)=='number' and (' | '..cost..' fragments') or '')
      trainingStatus.TextColor3=Color3.fromRGB(103,220,140)
      if not preferences.v4Training or preferences.findFullMoon then return end
      local data=player:FindFirstChild('Data');local fragments=data and data:FindFirstChild('Fragments')
      if type(cost)~='number' or not fragments or fragments.Value<cost then if not token then status.Text='Waiting for training fragments: '..tostring(cost or '?') end;return end
      if race()~=trainingRace then return end
      local purchased=trainingRequest('Buy')
      if alive then trainingStatus.Text=purchased and 'Training purchased — checking next stage...' or 'Training: ready, purchase not accepted' end
     elseif state==5 then
      trainingStatus.Text='Training: complete';trainingStatus.TextColor3=Color3.fromRGB(103,220,140)
      if preferences.v4Training then preferences.v4Training=false;preferences.Flush() end
     elseif state==0 then trainingStatus.Text='Training: complete — next trial ready'
     elseif state==9 then trainingStatus.Text='Training: unavailable for this race'
     elseif state==1 or state==3 or state==6 or state==8 then trainingStatus.Text='Training: not ready yet';trainingStatus.TextColor3=Color3.fromRGB(240,170,100)
     else trainingStatus.Text='Training: status unavailable' end
    end)
    if not ok and alive then trainingStatus.Text='Training: check unavailable; retrying' end
   end
   task.wait(10)
  end
 end)
 preferences.V4Trial={Enter=function()start(false)end,RaceRoom=function()start(true)end,Stop=stop}
end

-- Trial-only controller. Never targets players or enemies outside the trial area.
do
 local panel=panels['V4 Trial'];local token;local currentArea;local machineIndex=0;local machineAt=0
 label(panel,'Auto Trial',18,278,350,30,14)
 local toggle=control(panel,'OFF',410,278,80,28)
 local message=label(panel,'Waiting for a trial',18,316,475,60,12)
 message.TextWrapped=true;message.TextYAlignment=Enum.TextYAlignment.Top
 panel.CanvasSize=UDim2.fromOffset(0,388)
 local races={Human='Trial of Strength',Ghoul='Trial of Carnage',Fishman='Trial of Water',Shark='Trial of Water',Skypiea='Trial of the King',Angel='Trial of the King',Mink='Trial of Speed',Rabbit='Trial of Speed',Cyborg='Trial of the Machine',Draco='Trial of Flames'}
 local function root() local c=player.Character;return c and c:FindFirstChild('HumanoidRootPart') end
 local function area()
  local data=player:FindFirstChild('Data');local r=data and data:FindFirstChild('Race');local name=r and races[r.Value]
  local origin=workspace:FindFirstChild('_WorldOrigin');local locations=origin and origin:FindFirstChild('Locations')
  local marker=name and locations and locations:FindFirstChild(name);local hr=root()
  if not marker or not hr or (hr.Position-marker.Position).Magnitude>1800 then return end
  -- CurrentLocation/ExactLocation comes from the game, not from our own teleport.
  if player:GetAttribute('CurrentLocation')~=name and player:GetAttribute('ExactLocation')~=name then return end
  return name,marker
 end
 local function stop()
  if token then farm.SeaEnd(token);token=nil end
  currentArea=nil;machineIndex=0;machineAt=0;otherFarm.ResumePriority()
 end
 local function enabled()
  return alive and preferences.autoTrial and currentArea and area()==currentArea and token and farm.SeaActive(token)
 end
 local function takeControl(name)
  if token and (currentArea~=name or not farm.SeaActive(token)) then stop() end
  if token then return end
  if preferences.V4Trial then preferences.V4Trial.Stop() end
  preferences.findFullMoon=false;preferences.CancelMoonHop()
  if preferences.StopStyle then preferences.StopStyle() end
  if preferences.SetAutoSaber then preferences.SetAutoSaber(false) end
  farm.SetEnabled(false);farm.SetStackFruit(false);farm.SetAutoClick(false)
  for k in pairs(farm.stackEvents) do farm.stackEvents[k]=false end
  sea.SetEnabled(false);travelAPI.Stop();otherFarm.PausePriority()
  token=farm.SeaBegin();currentArea=name
 end
 local function endpoint()
  local map=workspace:FindFirstChild('Map');local sky=map and map:FindFirstChild('SkyTrial')
  local model=sky and sky:FindFirstChild('Model')
  local finish=model and model:FindFirstChild('FinishPart')
  if finish and finish:IsA('BasePart') then return finish end
 end
 local function rabbitExit()
   local map=workspace:FindFirstChild('Map');local maze=map and map:FindFirstChild('MinkTrial')
   if not maze then return end
   -- V3 recording: red Workspace.StartPoint was underfoot immediately before Temple return.
   local floor=maze:FindFirstChild('Floor')
   local exits={}
   if floor and floor:IsA('BasePart') then
    for _,part in ipairs(workspace:GetChildren()) do
     if part.Name=='StartPoint' and part:IsA('BasePart') then
      local c=part.Color
      if c.R>.8 and c.G<.2 and c.B<.2 and part.CanTouch and part.Transparency<.5
       and (part.Position-floor.Position).Magnitude<300 then table.insert(exits,part) end
     end
    end
   end
   if #exits==1 then return exits[1] end
   local named,pads={},{}
   for _,part in ipairs(maze:GetDescendants()) do
    if part:IsA('BasePart') then
     local name=part.Name:lower():gsub('[^%a]','')
     if name=='finish' or name=='finishpart' or name=='exit' or name=='exitpart' or name=='endpoint' then table.insert(named,part) end
     local c,size=part.Color,part.Size
     local red=c.R>=.55 and c.R>c.G*1.6 and c.R>c.B*1.6
     local flat=size.Y<=math.min(size.X,size.Z)*.6 and math.abs(part.CFrame.UpVector.Y)>.85
     if red and flat and part.Transparency<.95 and part.CanTouch and size.X>=2 and size.Z>=2 then table.insert(pads,part) end
    end
   end
   if #named==1 then return named[1] end
   if #pads==1 then return pads[1] end
  end
  -- Offsets observed throughout the successful Cyborg recording, relative to its floor.
 local machineRoute={{-6.3,-24.6},{-2.1,-15.1},{-2,34},{-40.6,2.3},{-6.3,10},{16.7,-25.1},{33.3,-6.2}}
 local function machineTrial()
  local map=workspace:FindFirstChild('Map');local trial=map and map:FindFirstChild('CyborgTrial')
  local floor=trial and trial:FindFirstChild('Floor')
  if not floor or not floor:IsA('BasePart') then message.Text='Waiting for Cyborg trial floor';return end
  if os.clock()<machineAt then return end
  machineIndex=machineIndex%#machineRoute+1
  local offset=machineRoute[machineIndex]
  local char=player.Character;local h=char and char:FindFirstChildOfClass('Humanoid');local hr=root()
  local height=math.max(3,(h and h.HipHeight or 2)+(hr and hr.Size.Y*.5 or 1))
  local destination=floor.Position+Vector3.new(offset[1],floor.Size.Y*.5+height,offset[2])
  message.Text='Cyborg trial: following recorded floor route'
  if enabled() then farm.SeaMove(destination,token) end
  machineAt=os.clock()+.3
 end
 local skillIndex=0;local used={}
 local function castSkill(target)
  local char=player.Character;local hum=char and char:FindFirstChildOfClass('Humanoid');local hr=root()
  if not hum or not hr or not enabled() then return end
  local tools={}
  for _,container in pairs({char,player:FindFirstChild('Backpack')}) do for _,t in ipairs(container:GetChildren()) do
   if t:IsA('Tool') and farm.SkillCategory(t) then table.insert(tools,t) end
  end end
  local queue=farm.SkillQueue(tools);if #queue==0 then message.Text='Enable trial skills in Settings > Skill Use';return end
  for _=1,#queue do
   skillIndex=skillIndex%#queue+1;local item=queue[skillIndex];local tool,key=item.tool,item.key
   local kind=farm.SkillCategory(tool);local cooldown=tonumber(char:GetAttribute(kind..key.Name..'Cooldown')) or 0
   local id=tool.Name..key.Name
   if cooldown<=0 and farm.SkillReady(tool,key) and os.clock()>=(used[id] or 0) then
    hum:EquipTool(tool);used[id]=os.clock()+1
    local mouse=tool:FindFirstChild('MousePos');local old=mouse and mouse:IsA('Vector3Value') and mouse.Value
    if old then mouse.Value=target.Position end
    local camera=workspace.CurrentCamera;local cf=camera.CFrame;local focus=camera.Focus;local ct=camera.CameraType
    local input=game:GetService('VirtualInputManager');local setIdentity=setthreadidentity or setidentity;local getIdentity=getthreadidentity or getidentity
    local previous=getIdentity and getIdentity() or 2
    pcall(function()
     if not enabled() then return end
     camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=CFrame.lookAt(hr.Position+Vector3.new(0,4,0),target.Position);camera.Focus=CFrame.new(target.Position)
     local point=camera:WorldToViewportPoint(target.Position);local inset=game:GetService('GuiService'):GetGuiInset()
     if setIdentity then setIdentity(8) end
     input:SendMouseMoveEvent(point.X+inset.X,point.Y+inset.Y,game)
     input:SendKeyEvent(true,key,false,game);task.wait(.1)
    end)
    pcall(function()input:SendKeyEvent(false,key,false,game)end)
    if setIdentity then setIdentity(previous) end
    pcall(function()camera.CameraType=ct;camera.CFrame=cf;camera.Focus=focus;if old then mouse.Value=old end end)
    return
   end
  end
 end
 local function fight(marker,water)
  local hr=root();if not hr then return end;local best,distance
  for _,folder in pairs({workspace:FindFirstChild('Enemies'),water and workspace:FindFirstChild('SeaBeasts') or nil}) do
   for _,enemy in ipairs(folder:GetChildren()) do
    local h=enemy:FindFirstChildOfClass('Humanoid');local r=enemy:FindFirstChild('HumanoidRootPart') or enemy:FindFirstChild('RootPart') or enemy.PrimaryPart
    local hp=enemy:FindFirstChild('Health');local living=h and h.Health>0 or hp and hp:IsA('NumberValue') and hp.Value>0
    if living and r and (r.Position-marker.Position).Magnitude<1800 then
     local d=(r.Position-hr.Position).Magnitude;if not distance or d<distance then distance=d;best={enemy=enemy,root=r} end
    end
   end
  end
  if not best then message.Text='Waiting for trial enemies';return end
  local destination=best.root.Position+Vector3.new(0,24,0)
  if water then
   local map=workspace:FindFirstChild('Map');local trial=map and map:FindFirstChild('FishmanTrial');local surface=trial and trial:FindFirstChild('Seabeast')
   destination=Vector3.new(best.root.Position.X,surface and surface.Position.Y+25 or 30,best.root.Position.Z)
  end
  if (hr.Position-destination).Magnitude>90 then farm.SeaMove(destination,token);return end
  if not enabled() then return end
  farm.SeaHover(best.root,token,30,false)
  if water then
   local head=best.enemy:FindFirstChild('Head')
   castSkill(head and head:IsA('BasePart') and head or best.root)
  else farm.SeaAttack(best.enemy,token) end
  message.Text=water and 'Trial: rotating available skills on Sea Beast' or ('Trial: fighting '..best.enemy.Name)
 end
 -- Draco report: pickup Relic2/1/3, then the corresponding enabled EndRelic prompt.
 local dracoPromptAt=setmetatable({},{__mode='k'})
 local function dracoTrial()
  local map=workspace:FindFirstChild('Map');local trial=map and map:FindFirstChild('DracoTrial')
  if not trial or not enabled() then message.Text='Waiting for Draco trial objects';return end
  local function relicPrompt(name)
   -- Several siblings share the name Model; resolve the relic by its prompt ancestry.
   for _,candidate in ipairs(trial:GetDescendants()) do
    if candidate:IsA('ProximityPrompt') then
     local ancestor=candidate.Parent
     while ancestor and ancestor~=trial do
      if ancestor.Name==name then return candidate end
      ancestor=ancestor.Parent
     end
    end
   end
  end
  local function redeemed(number)
   local brazier=trial:FindFirstChild('Brazier'..number,true)
   local slot=brazier and brazier:FindFirstChild('Relic'..number)
   if slot then for _,fx in ipairs(slot:GetDescendants()) do
    if fx:IsA('ParticleEmitter') and fx.Enabled and (fx.Name=='Fire' or fx.Name=='FireShaded' or fx.Name=='Embers') then return true end
   end end
   return false
  end
  local count=0;for n=1,3 do if redeemed(n) then count=count+1 end end
  if count==3 then farm.SeaRelease(token);message.Text='Draco: 3 relics delivered — waiting for game completion';return end
  local chosen;local number;local delivering=false
  for _,n in ipairs({2,1,3}) do
   local p=relicPrompt('EndRelic'..n)
   if not redeemed(n) and p and p.Enabled then chosen=p;number=n;delivering=true;break end
  end
  if not chosen then
   for _,n in ipairs({2,1,3}) do
    local p=relicPrompt('Relic'..n)
    if not redeemed(n) and p and p.Enabled then chosen=p;number=n;break end
   end
  end
  if not chosen then farm.SeaRelease(token);message.Text='Draco: waiting for pickup / delivery confirmation';return end
  local anchor=chosen.Parent
  local destination=anchor:IsA('Attachment') and anchor.WorldPosition or anchor:IsA('BasePart') and anchor.Position
  if not destination then message.Text='Draco prompt anchor not loaded';return end
  message.Text='Draco: '..(delivering and 'delivering' or 'collecting')..' relic '..number..' ('..count..'/3)'
  local holdPoint=destination+Vector3.new(0,2,2)
  local current=root();local arrived=current and (current.Position-holdPoint).Magnitude<5
  if not arrived then arrived=farm.SeaMove(holdPoint,token,function() return enabled() and chosen.Parent~=nil and chosen.Enabled end) end
  if not arrived or not enabled() or not chosen.Parent or not chosen.Enabled then return end
  farm.SeaHold(holdPoint,token)
  local hr=root();if not hr or (hr.Position-destination).Magnitude>chosen.MaxActivationDistance then return end
  if os.clock()-(dracoPromptAt[chosen] or 0)<2 then return end
  dracoPromptAt[chosen]=os.clock()
  if fireproximityprompt then fireproximityprompt(chosen)
  else chosen:InputHoldBegin();task.wait(chosen.HoldDuration+.1);chosen:InputHoldEnd() end
  -- Neither pressing the prompt nor reaching the point counts as completion.
  message.Text='Draco: waiting for game to confirm relic '..number
 end
 bindControl(toggle,'Activated',function()
  preferences.autoTrial=not preferences.autoTrial
  if not preferences.autoTrial then stop();message.Text='Auto Trial stopped' end
  preferences.Flush()
 end)
 task.spawn(function()
  while alive do
   toggle.Text=preferences.autoTrial and 'ON' or 'OFF'
   if preferenceReady and preferences.autoTrial then
    local name,marker=area()
    if not name or (preferences.HasRareItem and preferences.HasRareItem()) then
     if token then stop() end;message.Text='Waiting for an active race trial'
    else
     local ok,err=pcall(function()
      if name=='Trial of Carnage' then
       message.Text='Ghoul trial recording pending';return
      end
      if name=='Trial of Speed' and not rabbitExit() then
       if token then stop() end
       message.Text='Waiting for the Rabbit red finish pad to load';return
      end
      takeControl(name)
      if name=='Trial of Strength' or name=='Trial of Carnage' or name=='Trial of Water' then fight(marker,name=='Trial of Water')
      elseif name=='Trial of Flames' then dracoTrial()
      elseif name=='Trial of the Machine' then machineTrial()
      elseif name=='Trial of the King' or name=='Trial of Speed' then
       local point=name=='Trial of the King' and endpoint() or rabbitExit()
       if point then
        if enabled() then farm.SeaMove(point.Position+Vector3.new(0,point.Size.Y*.5+3,0),token) end
        message.Text='At trial exit; waiting for the game to finish the trial'
       else message.Text='Waiting for the recorded Angel finish platform to load' end
      else
       stop();message.Text='This race needs a complete exit recording before automation'
      end
     end)
     if not ok then stop();message.Text='Trial retry: '..tostring(err):gsub('^.-:%d+: ',''):sub(1,160);task.wait(1) end
    end
   elseif token then stop() end
   task.wait(.15)
  end
  stop()
 end)
end

-- Race upgrade quests; server quest state is the completion authority.
do
 local rs=game:GetService('ReplicatedStorage');local remote=rs.Remotes.CommF_
 local panel=panels['V4 Trial'];local token;local owned=false;local serial=0
 local buttons={};local job;local lastCharacter;local defeated={};local visited={};local deferred={}
 local turnInAt=0;local travelAt=0;local fruitStoreSaved;local fruitHeld=false;local boatBuyAt=0;local seaBoat;local seaSeat
 local defeatedPlayers={};local flowerPatrol=0;local boatDrive;local boatWaypoint=1;local sharkSkills={}
 for i,key in ipairs({'raceV2','raceV3'}) do
  local y=390+(i-1)*38
  label(panel,i==1 and 'Auto Get Race V2' or 'Auto Get Race V3',18,y,350,30,14)
  buttons[key]=control(panel,'OFF',410,y,80,28);line(panel,y+33)
 end
 local message=label(panel,'',18,470,475,64,12);message.TextWrapped=true
 message.TextYAlignment=Enum.TextYAlignment.Top;panel.CanvasSize=UDim2.fromOffset(0,546)
 local function root() local c=player.Character;return c and c:FindFirstChild('HumanoidRootPart') end
 local function value(name)
  local data=player:FindFirstChild('Data');local v=data and data:FindFirstChild(name)
  return v and v.Value
 end
 local function tool(name)
  local c=player.Character;local b=player:FindFirstChild('Backpack')
  return (c and c:FindFirstChild(name)) or (b and b:FindFirstChild(name))
 end
 local function active(id) return alive and id==serial and job and preferences[job]==true end
 local function stopBoat()
  if boatDrive then boatDrive:Disconnect();boatDrive=nil end
  if seaSeat and seaSeat.Parent then seaSeat.ThrottleFloat=0;seaSeat.SteerFloat=0;seaSeat.AssemblyLinearVelocity=Vector3.zero end
 end
 local function release()
  stopBoat()
  if token then farm.SeaEnd(token);token=nil end
  if owned then otherFarm.ResumePriority();owned=false;farm.trevorFruitReservation=false end
  if fruitHeld then preferences.auto.storeFruit=fruitStoreSaved;fruitHeld=false end
 end
 local function stop(text)
  serial=serial+1;release();job=nil;defeated={};visited={};deferred={};defeatedPlayers={};seaBoat=nil;seaSeat=nil
  if text then message.Text=text end
 end
 local function claim()
  if owned then return end
  if preferences.Service then
   local queued=preferences.Service.Snapshot().queue
   for _,key in ipairs(queued) do preferences.Service.Toggle(key) end
  end
  if preferences.V4Trial then preferences.V4Trial.Stop() end
  if preferences.SetAutoSaber then preferences.SetAutoSaber(false) end
  if preferences.StopStyle then preferences.StopStyle() end
  preferences.autoTrial=false;preferences.findFullMoon=false;preferences.eliteHop=false;preferences.fruitHop=false
  if preferences.CancelAllHop then preferences.CancelAllHop() end
  otherFarm.PausePriority();travelAPI.Stop();sea.SetEnabled(false)
  farm.SetEnabled(false);farm.SetStackFruit(false);farm.SetAutoClick(false)
  for key in pairs(farm.stackEvents) do farm.stackEvents[key]=false end
  owned=true
 end
 local function movement(id)
  if not active(id) then return false end
  claim()
  if not token or not farm.SeaActive(token) then token=farm.SeaBegin() end
  return true
 end
 local function move(point,id)
  return movement(id) and farm.SeaMove(point,token) and active(id)
 end
 local function call(id,...)
  if not active(id) then return nil end
  local args=table.pack(...);local done=false;local ok,result
  task.spawn(function() ok,result=pcall(remote.InvokeServer,remote,table.unpack(args,1,args.n));done=true end)
  local deadline=os.clock()+12
  repeat task.wait(.1) until done or not active(id) or os.clock()>deadline
  if not active(id) then return nil end
  if not done or not ok then
   preferences[job]=false;stop('Game request not confirmed; toggle again to retry.');task.defer(preferences.Flush)
   return nil
  end
  return result
 end
 local function visit(name,fallback,id)
  local point=fallback
  pcall(function()
   for _,npc in ipairs(require(rs.NPCManager).getNPCsByName(name)) do
    local model=npc:getModel();if model then point=model:GetPivot().Position;break end
   end
  end)
  local r=root();if r and (r.Position-point).Magnitude<15 then return true end
  return move(point+Vector3.new(0,2,4),id)
 end
 local function touch(part,id)
  if not part or not part.Parent or not move(part.Position+Vector3.new(0,2,0),id) then return end
  local r=root()
  if r and active(id) and type(firetouchinterest)=='function' then
   pcall(function() firetouchinterest(r,part,0);firetouchinterest(r,part,1) end)
  end
 end
 local function enemy(name)
  local folder=workspace:FindFirstChild('Enemies')
  if folder then for _,e in ipairs(folder:GetChildren()) do
   local h=e:FindFirstChildOfClass('Humanoid')
   if e.Name:match('^'..name) and h and h.Health>0 then return e end
  end end
 end
 local function fight(e,id)
  local h=e and e:FindFirstChildOfClass('Humanoid');local r=e and (e:FindFirstChild('HumanoidRootPart') or e.PrimaryPart)
  local hp=e and e:FindFirstChild('Health')
  local function health() return h and h.Health or hp and hp:IsA('ValueBase') and tonumber(hp.Value) or 0 end
  if not r or health()<=0 or not movement(id) then return end
  message.Text='Race quest: fighting '..e.Name
  local deadline=os.clock()+3
  repeat
   if not active(id) or not e.Parent or not farm.SeaActive(token) then return end
   farm.SeaHover(r,token,40,false);farm.SeaAttack(e,token);task.wait(.1)
  until health()<=0 or os.clock()>deadline
  if health()<=0 then defeated[e.Name:match('^(.-) %[') or e.Name]=true end
 end
 local function finish(key)
  preferences[key]=false;stop(key=='raceV2' and 'Race V2 unlocked.' or 'Race V3 unlocked.')
  task.defer(preferences.Flush)
 end
 local function v2(id)
  local state=call(id,'Alchemist','1');if not active(id) then return end
  if state==-2 then finish('raceV2');return end
  if (tonumber(value('Level')) or 0)<850 then message.Text='Race V2 requires level 850.';return end
  if (tonumber(value('Beli')) or 0)<500000 then message.Text='Race V2 requires $500,000.';return end
  if state==0 then
   if movement(id) and farm.RaceBartilo(token) then message.Text='Completing the Colosseum prerequisite';return end
   if visit('Alchemist',Vector3.new(-2779,72,-3574),id) then call(id,'Alchemist','2') end
   return
  elseif state==2 then
   if visit('Alchemist',Vector3.new(-2779,72,-3574),id) then
    call(id,'Alchemist','3')
    if active(id) and call(id,'Alchemist','1')==-2 then finish('raceV2') end
   end
   return
  elseif state~=1 then message.Text='Alchemist requirements not confirmed: '..tostring(state);return end
  -- Use the proven level-farm combat path for land enemies, not sea-event hover.
  -- Get Yellow Flower first so an uncollected world flower cannot starve combat.
  if not tool('Flower 3') then
   local best,gap;local r=root();local folder=workspace:FindFirstChild('Enemies')
   if r and folder then for _,e in ipairs(folder:GetChildren()) do
    local h=e:FindFirstChildOfClass('Humanoid');local er=e:FindFirstChild('HumanoidRootPart')
    if e.Name:find('Swan Pirate',1,true) and h and h.Health>0 and er then
     local distance=(er.Position-r.Position).Magnitude
     if not gap or distance<gap then best=e;gap=distance end
    end
   end end
   if best and movement(id) then
    message.Text='Farming Swan Pirates for Yellow Flower'
    farm.RaceFightEnemy(best,token)
   else message.Text='Looking for Swan Pirates for Yellow Flower';move(Vector3.new(970,162,1217),id) end
   return
  end
  for _,name in ipairs({'Flower 1','Flower 2'}) do
   if not tool(name) then
    local part=workspace:FindFirstChild(name:gsub(' ',''),true)
    if part and part:IsA('BasePart') and part.Transparency<1 and (deferred[part] or 0)<os.clock() then
     message.Text='Collecting '..name;touch(part,id);deferred[part]=os.clock()+10;return
    end
   end
  end
  if tool('Flower 1') and tool('Flower 2') then message.Text='All three flowers collected; checking Alchemist';return end
  if token then farm.SeaRelease(token) end
  message.Text='Searching islands for flowers (blue: night; red: day)'
  local options=travelAPI.Options()
  if #options>0 then flowerPatrol=flowerPatrol%#options+1;move(options[flowerPatrol].position+Vector3.new(0,5,0),id) end
 end
 local chestTypes={};pcall(function() chestTypes=require(rs.ChestConfiguration.ChestTypes) end)
 local chests=setmetatable({}, {__mode='k'})
 local function watch(part) if part:IsA('BasePart') and chestTypes[part.Name] then chests[part]=true end end
 for _,part in ipairs(workspace:GetDescendants()) do watch(part) end
 connect(workspace.DescendantAdded,watch)
 local function collectChest(id)
  local r=root();if not r then return end
  local best,gap
  for p in pairs(chests) do
   if p.Parent and not p:GetAttribute('IsDisabled') and (deferred[p] or 0)<os.clock() then
    local d=(p.Position-r.Position).Magnitude;if not gap or d<gap then best=p;gap=d end
   end
  end
  if best then message.Text='Rabbit V3: collecting quest chests';touch(best,id);deferred[best]=os.clock()+10;return end
  for _,entry in ipairs(travelAPI.Options()) do
   if not visited[entry.key] then message.Text='Rabbit V3: checking '..entry.name
    if move(entry.position+Vector3.new(0,4,0),id) then visited[entry.key]=true end
    return
   end
  end
  visited={};message.Text='Waiting for chests to respawn'
 end
 local function beastTarget()
  local folder=workspace:FindFirstChild('SeaBeasts');local r=root();local best,gap
  if folder and r then for _,e in ipairs(folder:GetChildren()) do
   local h=e:FindFirstChildOfClass('Humanoid');local hp=e:FindFirstChild('Health')
   local health=h and h.Health or hp and hp:IsA('ValueBase') and tonumber(hp.Value) or 0
   local target=e:FindFirstChild('Head') or e:FindFirstChild('HumanoidRootPart') or (e:IsA('Model') and e.PrimaryPart)
   if target and health>0 then
    local distance=(target.Position-r.Position).Magnitude
    if not gap or distance<gap then best=e;gap=distance end
   end
  end end
  return best
 end
 local function sharkSearch(id)
  local boats=workspace:FindFirstChild('Boats')
  local boatHumanoid=seaBoat and seaBoat:FindFirstChildOfClass('Humanoid')
  if not seaBoat or not seaBoat.Parent or not seaSeat or not seaSeat.Parent or (boatHumanoid and boatHumanoid.Health<=0) then
   stopBoat();seaBoat=nil;seaSeat=nil
   if boats then for _,b in ipairs(boats:GetChildren()) do
    local owner=b:FindFirstChild('Owner');local seat=b:FindFirstChildWhichIsA('VehicleSeat',true)
    local hp=b:FindFirstChildOfClass('Humanoid')
    if owner and owner:IsA('ObjectValue') and owner.Value==player and seat and (not hp or hp.Health>0) then seaBoat=b;seaSeat=seat;break end
   end end
  end
  if not seaBoat then
   if os.clock()<boatBuyAt then message.Text='Waiting for the boat';return end
   -- Select the Kingdom of Rose dock, not the first dealer from another island.
   local dock=Vector3.new(-13,10,2927);local nearest;local distance
   pcall(function()
    for _,npc in ipairs(require(rs.NPCManager).getNPCsByName('Boat Dealer')) do
     local model=npc:getModel()
     if model then local point=model:GetPivot().Position;local d=(point-dock).Magnitude
      if d<1500 and (not distance or d<distance) then nearest=point;distance=d end
     end
    end
   end)
   message.Text='Shark V3: going to Kingdom of Rose dock'
   if move((nearest or dock)+Vector3.new(0,3,5),id) then
    boatBuyAt=os.clock()+20;message.Text='Buying a boat for Shark V3'
    local boatName=sea.boat=='Brigade' and (player.Team and player.Team.Name=='Marines' and 'MarineBrigade' or 'PirateBrigade') or 'Guardian'
    local reply=call(id,'BuyBoat',boatName)
    if reply~=1 then message.Text='Boat purchase not confirmed: '..tostring(reply) end
   end
   return
  end
  local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
  if not h then return end
  if h.SeatPart~=seaSeat then
   stopBoat();message.Text='Boarding boat for Shark V3'
   if move(seaSeat.Position+Vector3.new(0,3,0),id) and active(id) then farm.SeaRelease(token);seaSeat:Sit(h) end
   return
  end
  message.Text='Shark V3: sailing for a natural Sea Beast'
  if boatDrive then return end
  local route={Vector3.new(-13,0,6500),Vector3.new(-2500,0,10000),Vector3.new(2500,0,12000),Vector3.new(4000,0,8500)}
  boatDrive=game:GetService('RunService').Heartbeat:Connect(function(dt)
   if not active(id) or not seaBoat or not seaBoat.Parent or not seaSeat.Parent or h.Health<=0 or h.SeatPart~=seaSeat or beastTarget() then stopBoat();return end
   local hp=seaBoat:FindFirstChildOfClass('Humanoid');if hp and hp.Health<=0 then stopBoat();return end
   local p=seaSeat.Position;local point=route[boatWaypoint]
   local destination=Vector3.new(point.X,p.Y,point.Z);local delta=destination-p
   if delta.Magnitude<120 then boatWaypoint=boatWaypoint%#route+1;return end
   local nextSeat=CFrame.lookAt(p+delta.Unit*math.clamp(sea.boatSpeed or 120,40,200)*math.min(dt,.05),p+delta.Unit*100)
   local offset=seaSeat.CFrame:ToObjectSpace(seaBoat:GetPivot())
   seaBoat:PivotTo(nextSeat*offset);seaSeat.AssemblyLinearVelocity=Vector3.zero;seaSeat.AssemblyAngularVelocity=Vector3.zero
   local velocity=seaSeat:FindFirstChildOfClass('BodyVelocity');if velocity then velocity.Velocity=Vector3.zero end
   local gyro=seaSeat:FindFirstChildOfClass('BodyGyro');if gyro then gyro.CFrame=nextSeat.Rotation end
  end)
 end
 local function sharkFight(e,id)
  stopBoat()
  local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
  if h and h.Sit then h.Sit=false;h.Jump=true;task.wait(.1) end
  local target=e:FindFirstChild('Head') or e:FindFirstChild('HumanoidRootPart') or e.PrimaryPart
  if not target or not movement(id) then return end
  local r=root()
  if r and (r.Position-target.Position).Magnitude>80 then
   if not move(Vector3.new(target.Position.X,math.max(target.Position.Y+30,40),target.Position.Z),id) then return end
  end
  farm.SeaHover(target,token,35,false)
  local deadline=os.clock()+8
  repeat
   if not active(id) or not e.Parent or not target.Parent or not farm.SeaActive(token) then return end
   local hum=e:FindFirstChildOfClass('Humanoid');local hp=e:FindFirstChild('Health')
   local health=hum and hum.Health or hp and hp:IsA('ValueBase') and tonumber(hp.Value) or 0
   if health<=0 then return end
   message.Text='Shark V3: cycling enabled skills on Sea Beast'
   local used,why=farm.CastSkillCycle(sharkSkills,function() return e.Parent and target.Parent and target.Position or nil end,token)
   if not used then message.Text=why or 'Waiting for ready skills';task.wait(.1) end
  until os.clock()>deadline
 end
 local bosses={{'Diamond',Vector3.new(-1576,224,-31)},{'Jeremy',Vector3.new(2006,449,853)},{'Fajita',Vector3.new(-2172,1036,-4015)}}
 local function v3(id)
  local state=call(id,'Wenlocktoad','1');if not active(id) then return end
  if state==-2 then finish('raceV3');return end
  if (tonumber(value('Level')) or 0)<1000 then message.Text='Race V3 requires level 1,000.';return end
  if (tonumber(value('Beli')) or 0)<2000000 then message.Text='Race V3 requires $2,000,000.';return end
  if state==0 then
   if visit('Arowe',Vector3.new(-1990,125,-70),id) then call(id,'Wenlocktoad','2') end
   return
  elseif state==2 then
   if visit('Arowe',Vector3.new(-1990,125,-70),id) then
    call(id,'Wenlocktoad','3')
    if active(id) and call(id,'Wenlocktoad','1')==-2 then finish('raceV3') end
   end
   return
  elseif state~=1 then
   if state==-1 then
    local v2state=call(id,'Alchemist','1')
    if v2state~=-2 then message.Text='Complete Race V2 first (enable Auto Get Race V2).';return end
    message.Text='Completing Don Swan prerequisite'
    if movement(id) then farm.RaceDonSwan(token) end
   else message.Text='Arowe requirements not confirmed: '..tostring(state) end
   return
  end
  if os.clock()>=turnInAt then
   turnInAt=os.clock()+15
   call(id,'Wenlocktoad','3')
   if not active(id) then return end
   if call(id,'Wenlocktoad','1')==-2 then finish('raceV3');return end
  end
  local race=value('Race')
  if race=='Mink' or race=='Rabbit' then collectChest(id)
  elseif race=='Human' then
   for _,entry in ipairs(bosses) do
    if not defeated[entry[1]] then
     local e=enemy(entry[1]) or (entry[1]=='Fajita' and enemy('Orbitus'));if e then fight(e,id);local h=e:FindFirstChildOfClass('Humanoid');if h and h.Health<=0 then defeated[entry[1]]=true end;return end
    end
   end
   for _,entry in ipairs(bosses) do
    if not defeated[entry[1]] then message.Text='Waiting for '..entry[1];move(entry[2]+Vector3.new(0,25,0),id);return end
   end
   message.Text='Waiting for Arowe to confirm the three boss defeats'
  elseif race=='Cyborg' then
   if not fruitHeld then fruitStoreSaved=preferences.auto.storeFruit;fruitHeld=true;preferences.auto.storeFruit=false end
   local found
   for _,container in pairs({player.Character,player:FindFirstChild('Backpack')}) do
    for _,t in ipairs(container:GetChildren()) do if t:IsA('Tool') and t.Name:find('Fruit',1,true) then found=t;break end end
   end
   if found then
    if visit('Arowe',Vector3.new(-1990,125,-70),id) then call(id,'Wenlocktoad','3') end
   else message.Text='Cyborg V3: hold a physical fruit; auto-store paused' end
  elseif race=='Fishman' or race=='Shark' then
   local e=beastTarget();if e then sharkFight(e,id) else sharkSearch(id) end
  elseif race=='Skypiea' or race=='Angel' or race=='Ghoul' then
   local best,gap;local r=root()
   for _,other in ipairs(game:GetService('Players'):GetPlayers()) do
    if other~=player and not defeatedPlayers[other.UserId] then
     local data=other:FindFirstChild('Data');local rv=data and data:FindFirstChild('Race')
     local c=other.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local hr=c and c:FindFirstChild('HumanoidRootPart')
     if h and h.Health>0 and hr and r and (race=='Ghoul' or rv and (rv.Value=='Skypiea' or rv.Value=='Angel')) then
      local d=(hr.Position-r.Position).Magnitude
      if not gap or d<gap then best=other;gap=d end
     end
    end
   end
   if best then
    local c=best.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
    fight(c,id)
    if h and h.Health<=0 then defeatedPlayers[best.UserId]=true end
   else
    if token then farm.SeaRelease(token) end
    message.Text='Waiting for eligible players or Arowe quest completion'
   end
  else message.Text='Unsupported race quest: '..tostring(race) end
 end
 for key,b in pairs(buttons) do bindControl(b,'Activated',function()
  if not preferenceReady then return end
  preferences[key]=not preferences[key];b.Text=preferences[key] and 'ON' or 'OFF'
  stop();task.defer(preferences.Flush)
 end) end
 preferences.RaceUpgrades={Stop=function() preferences.raceV2=false;preferences.raceV3=false;stop() end}
 task.spawn(function()
  local setIdentity=setthreadidentity or setidentity
  if setIdentity then setIdentity(2) end
  while alive do
   for key,b in pairs(buttons) do b.Text=preferences[key] and 'ON' or 'OFF' end
   if preferenceReady then
    local nextJob=preferences.raceV2 and 'raceV2' or preferences.raceV3 and 'raceV3'
    if nextJob then
     if job~=nextJob or lastCharacter~=player.Character then stop();job=nextJob;lastCharacter=player.Character end
     local id=serial
     local ok,err=pcall(function()
      if not value('Race') then message.Text='Waiting for player data';return end
      if token and not farm.SeaActive(token) then preferences.raceV2=false;preferences.raceV3=false;stop('Race upgrade stopped: another task took control');task.defer(preferences.Flush);return end
      if value('Race')=='Draco' then message.Text='Draco has a separate upgrade quest; not supported here';return end
      if preferences.HasRareItem and preferences.HasRareItem() then release();message.Text='Paused to protect your rare item';return end
      local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
      if not h or h.Health<=0 then release();return end
      if game.PlaceId~=4442272183 and game.PlaceId~=79091703265657 then
       if (tonumber(value('Level')) or 0)<700 then message.Text='Unlock Second Sea first';return end
       if os.clock()>=travelAt then
        claim();travelAt=os.clock()+30;message.Text='Travelling to Second Sea for race upgrade'
        preferences.Flush();call(id,'TravelDressrosa')
       end
       return
      end
      claim()
      if job=='raceV2' then v2(id) else v3(id) end
     end)
     if not ok then preferences[nextJob]=false;stop('Upgrade stopped: '..tostring(err));task.defer(preferences.Flush) end
    elseif job then stop() end
   end
   task.wait(1)
  end
  release()
 end)
end

-- Island searches own movement and stop server hopping while sailing.
do
 sea.BeforeIslandSearch=function()
  if preferences.collectFist or (preferences.HasRareItem and preferences.HasRareItem()) or (preferences.StyleHasKey and preferences.StyleHasKey()) then return false,'Island search blocked: protecting your rare item or quest key' end
  preferences.findFullMoon=false;preferences.eliteHop=false;preferences.fruitHop=false
  if preferences.CancelAllHop then preferences.CancelAllHop() end
  if preferences.SetAutoSaber then preferences.SetAutoSaber(false) end
  if preferences.StopStyle then preferences.StopStyle() end
  otherFarm.Stop();travelAPI.Stop()
  farm.SetEnabled(false);farm.SetStackFruit(false);farm.SetAutoClick(false)
  for key in pairs(farm.stackEvents) do farm.stackEvents[key]=false end
  task.defer(preferences.Flush)
  return true
 end
 sea.OnIslandFound=function(name,arrived)
  preferences.Flush()
  pcall(function() game:GetService('StarterGui'):SetCore('SendNotification',{Title=name,Text=arrived and 'Island found. You have arrived.' or 'Island found, but arrival was not confirmed.',Duration=10}) end)
 end
end

-- Service section removed at user request.

-- Coordinated Leviathan hunt: only this client is moved; every passenger runs its own copy.
do
 local function installLeviathan()
 local rs=game:GetService('ReplicatedStorage');local players=game:GetService('Players')
 local panel=panels['Sea Event'];local token;local serial=0;local boat;local seat;local driving
 local sailingCollisions={};local sailingVelocity={};local flying;local phase='idle';local chosen;local noDamage={};local tracked={};local hadBoss=false;local damageDone={}
 local arrivalCharacter;local arrivalPoint
 local bodyParts={};local arrived=false;local savedWeapon;local savedTool;local pending=false;local boatBuyAt=0
 local TIKI=Vector3.new(-16929,8,435)
 local function config()
  preferences.levi=preferences.levi or {}
  local c=preferences.levi
  c.owner=tonumber(c.owner) or player.UserId;c.role=c.role=='Passenger' and 'Passenger' or 'Driver'
  c.weapon=c.weapon=='M1 Fruit' and 'M1 Fruit' or 'Dragonstorm'
  if c.dodge==nil then c.dodge=true end
  if c.heart==nil then c.heart=true end
  if c.returnHeart==nil then c.returnHeart=true end
  c.returnIsland=c.returnIsland=='Hydra' and 'Hydra' or 'Tiki'
  c.speed=math.clamp(tonumber(c.speed) or 120,40,350)
  return c
 end
 local function row(name,y)
  label(panel,name,16,y,224,28,12);return control(panel,'OFF',244,y,252,28)
 end
 line(panel,344);label(panel,'Leviathan Hunt',16,352,480,28,15)
 local bribe=row('Spy bribe (1,500 fragments)',386);bribe.Text='BUY'
 local ownerChoice=row('Boat owner',420)
 local refreshPlayers=row('Refresh player list',454);refreshPlayers.Text='REFRESH'
 local role=row('My role',488)
 local board=row('Tween to boat / Ride',522)
 local hunt=row('Find Frozen Dimension',556)
 local attackToggle=row('Auto Attack Leviathan',590)
 local weapon=row('Attack weapon',624)
 local dodge=row('Lift boat away from danger',658)
 local manual=row('Manual driving speed',692)
 label(panel,'Manual speed value',16,726,224,28,12)
 local speed=make('TextBox',panel,{Text='120',Position=UDim2.fromOffset(244,726),Size=UDim2.fromOffset(252,28),BackgroundColor3=Color3.fromRGB(49,46,40),TextColor3=pale,TextSize=13,Font=Enum.Font.Gotham,ClearTextOnFocus=false,BorderSizePixel=0,ZIndex=4})
 make('UICorner',speed,{CornerRadius=UDim.new(0,6)})
 local heartToggle=row('Auto Get Leviathan Heart',764)
 local returnToggle=row('Auto Return After Heart',802)
 local returnChoice=row('Return destination',836)
 local status=label(panel,'Select the same boat owner on each account.',16,870,480,58,11);status.Name='LeviStatus';status.TextWrapped=true
 panel.CanvasSize=UDim2.fromOffset(0,870)
 local roster={};local rosterIds={}
 local function refreshRoster()
  roster={};rosterIds={}
  for _,p in ipairs(players:GetPlayers()) do local text=p.Name..' ('..p.DisplayName..')';table.insert(roster,text);rosterIds[text]=p.UserId end
  table.sort(roster)
 end
 refreshRoster()
 local function paint()
  local c=config();local owner=players:GetPlayerByUserId(c.owner)
  ownerChoice.Text=(owner and owner.Name or ('User '..c.owner))..'  ▾';role.Text=c.role..'  ↔'
  weapon.Text=c.weapon..'  ↔'
  returnToggle.Text=c.returnHeart and 'ON' or 'OFF'
  returnChoice.Text=c.returnIsland=='Hydra' and 'Hydra · Draco V4  ▾' or 'Tiki · Heart  ▾'
  for _,entry in ipairs({{board,'ride'},{hunt,'hunt'},{attackToggle,'attack'},{dodge,'dodge'},{manual,'manual'},{heartToggle,'heart'}}) do entry[1].Text=c[entry[2]] and 'ON' or 'OFF' end
  if not speed:IsFocused() then speed.Text=tostring(c.speed) end
 end
 local function body()
  local c=player.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
  if h and h.Health>0 and r then return h,r end
 end
 local function stopDrive()
  if driving then driving:Disconnect();driving=nil end
  if flying and boat and boat.Parent and seat and seat.Parent then boat:PivotTo(boat:GetPivot()+Vector3.new(0,flying.y-seat.Position.Y,0)) end
  flying=nil
  for part,value in pairs(sailingCollisions) do if part.Parent then part.CanCollide=value end end
  sailingCollisions={}
  for mover,value in pairs(sailingVelocity) do if mover.Parent then mover.Velocity=value end end
  sailingVelocity={}
  if seat and seat.Parent then seat.ThrottleFloat=0;seat.SteerFloat=0;seat.AssemblyLinearVelocity=Vector3.zero end
 end
 local function release()
  stopDrive();if token then farm.SeaEnd(token);token=nil end
  if savedWeapon then farm.SetWeapon(savedWeapon);farm.serviceTool=savedTool;savedWeapon=nil end
  otherFarm.ResumePriority()
 end
 local rememberedPosition;local rememberedOwner;local recoverBoat=false
 local function stop()
  if boat and boat.Parent and seat and seat.Parent then rememberedPosition=seat.Position;rememberedOwner=config().owner;recoverBoat=true end
  local keepHeart=phase=='heart-done' or phase=='heart-return' or phase=='heart-arrived'
  serial=serial+1;release();phase=keepHeart and phase or 'idle';arrived=false;arrivalCharacter=nil;arrivalPoint=nil;chosen=nil;tracked={};bodyParts={};hadBoss=false;damageDone={}
 end
 local function claim()
  if token and farm.SeaActive(token) then return true end
  if preferences.HasRareItem and preferences.HasRareItem() then status.Text='Paused to protect your rare item';return false end
  if preferences.Service then for _,key in ipairs(preferences.Service.Snapshot().queue) do preferences.Service.Toggle(key) end end
  if preferences.RaceUpgrades then preferences.RaceUpgrades.Stop() end
  if preferences.V4Trial then preferences.V4Trial.Stop() end
  if preferences.SetAutoSaber then preferences.SetAutoSaber(false) end
  if preferences.StopStyle then preferences.StopStyle() end
  preferences.autoTrial=false;preferences.findFullMoon=false;preferences.eliteHop=false;preferences.fruitHop=false
  if preferences.CancelAllHop then preferences.CancelAllHop() end
  otherFarm.PausePriority();travelAPI.Stop();sea.SetEnabled(false)
  farm.SetEnabled(false);farm.SetStackFruit(false);farm.SetAutoClick(false)
  for key in pairs(farm.stackEvents) do farm.stackEvents[key]=false end
  token=farm.SeaBegin();return true
 end
 local function active(id) return alive and serial==id and token and farm.SeaActive(token) end
 local function move(point,id) return active(id) and farm.SeaMove(point,token) and active(id) end
 local function request(id,...)
  if not active(id) then return end
  local args=table.pack(...);local done=false;local ok,result
  task.spawn(function() ok,result=pcall(rs.Remotes.CommF_.InvokeServer,rs.Remotes.CommF_,table.unpack(args,1,args.n));done=true end)
  local deadline=os.clock()+10
  repeat task.wait(.1) until done or not active(id) or os.clock()>deadline
  if not done or not ok then error('Request unconfirmed; stopped to avoid duplicate purchases') end
  if active(id) then return result end
 end
 local function npc(name,near)
  local best,gap
  pcall(function() for _,n in ipairs(require(rs.NPCManager).getNPCsByName(name)) do
   local m=n:getModel();if m then local p=m:GetPivot().Position;local d=near and (p-near).Magnitude or 0
    if not gap or d<gap then best=p;gap=d end
   end
  end end)
  return best
 end
 local function healthy(b)
  if not b or not b.Parent then return false end
  local h=b:FindFirstChildOfClass('Humanoid');local hp=b:FindFirstChild('Health')
  return (not h or h.Health>0) and (not hp or not hp:IsA('ValueBase') or (tonumber(hp.Value) or 1)>0)
 end
 local function getBoat()
  local keptOwner=boat and boat:FindFirstChild('Owner')
  if healthy(boat) and keptOwner and keptOwner.Value and keptOwner.Value.UserId==config().owner then return boat end
  boat=nil;seat=nil
  local folder=workspace:FindFirstChild('Boats');local h,r=body();local gap
  if folder then for _,b in ipairs(folder:GetChildren()) do
   local owner=b:FindFirstChild('Owner');local match=owner and owner:IsA('ObjectValue') and owner.Value and owner.Value.UserId==config().owner
   local s=b:FindFirstChild('VehicleSeat') or b:FindFirstChildWhichIsA('VehicleSeat',true)
   if match and healthy(b) and s then local d=r and (s.Position-r.Position).Magnitude or 0
    if not gap or d<gap then boat=b;seat=s;gap=d end
   end
  end end
  return boat
 end
 local function acquire(id)
  if getBoat() then recoverBoat=false;return true end
  if recoverBoat and rememberedPosition and rememberedOwner==config().owner then
   status.Text='Returning to previous Leviathan boat'
   if not move(rememberedPosition+Vector3.new(0,5,0),id) then return false end
   recoverBoat=false
   if getBoat() then return true end
  end
  if config().owner~=player.UserId or config().role~='Driver' then status.Text='Waiting for selected owner to spawn a boat';return false end
  if os.clock()<boatBuyAt then return false end
  status.Text='Going to Tiki boat dealer'
  if move((npc('Boat Dealer',TIKI) or TIKI)+Vector3.new(0,3,4),id) then
   if getBoat() then return true end
   boatBuyAt=os.clock()+20
   local name=sea.boat=='Brigade' and (player.Team and player.Team.Name=='Marines' and 'MarineBrigade' or 'PirateBrigade') or sea.boat
   local result=request(id,'BuyBoat',name)
   status.Text=result==1 and 'Boat purchased; waiting for it to load' or 'Boat unavailable or not unlocked'
  end
  return false
 end
 local function sit(id)
  if not getBoat() then return false end
  local h,r=body();if not h then return false end
  if h.SeatPart and h.SeatPart:IsDescendantOf(boat) then
   if config().role=='Passenger' and h.SeatPart~=seat and not (config().heart and h.SeatPart:FindFirstAncestor('Harpoon')) or config().role=='Driver' and h.SeatPart==seat then return true end
  end
  local target=config().role=='Driver' and seat or nil
  if config().role=='Passenger' then
   local available={}
   for _,s in ipairs(boat:GetDescendants()) do
    if (s:IsA('Seat') or s:IsA('VehicleSeat')) and s~=seat and not s.Occupant and not (config().heart and s:FindFirstAncestor('Harpoon')) then table.insert(available,s) end
   end
   table.sort(available,function(a,b) return a:GetFullName()<b:GetFullName() end)
   -- Offset first choice per account; recheck occupancy after arrival to resolve races.
   if #available>0 then target=available[player.UserId%#available+1] end
  end
  if not target or (target.Occupant and target.Occupant~=h) then status.Text='Waiting for an empty '..(config().role=='Driver' and 'driver' or 'passenger/cannon')..' seat';return false end
  status.Text='Boarding selected boat'
  if move(target.Position+Vector3.new(0,3,0),id) and not target.Occupant then
   farm.SeaRelease(token);target:Sit(h);task.wait(.2)
  end
  return h.SeatPart==target
 end
 local function dimension()
  local origin=workspace:FindFirstChild('_WorldOrigin')
  for _,folder in pairs({workspace,workspace:FindFirstChild('Map'),origin and origin:FindFirstChild('Locations')}) do
   for _,v in ipairs(folder:GetChildren()) do if v.Name:lower():gsub('[^%a]','')=='frozendimension' then
    if v:IsA('Model') then return v:GetPivot().Position elseif v:IsA('BasePart') then return v.Position end
   end end
  end
 end
 local function danger()
  if not seat then return end
  for _,folder in pairs({workspace:FindFirstChild('Enemies'),workspace:FindFirstChild('SeaBeasts')}) do
   for _,e in ipairs(folder:GetChildren()) do
    local n=e.Name:lower():gsub('[^%a]','')
    if n:find('terrorshark',1,true) and healthy(e) then
     local r=e:FindFirstChild('HumanoidRootPart') or e:FindFirstChild('RootPart') or (e:IsA('Model') and e.PrimaryPart) or e:FindFirstChildWhichIsA('BasePart',true)
     if r then
      local delta=r.Position-seat.Position
      if Vector3.new(delta.X,0,delta.Z).Magnitude<650 then return r.Position end
     end
    end
   end
  end
 end
 local function drive(id,destination)
  if driving then return end
  local occupants=0
  for _,s in ipairs(boat:GetDescendants()) do if (s:IsA('Seat') or s:IsA('VehicleSeat')) and s.Occupant then occupants=occupants+1 end end
  if not destination and occupants<5 then status.Text='Waiting for 5 seated players ('..occupants..'/5)';return end
  status.Text=destination and ('Returning to '..config().returnIsland) or 'Sailing outward until Frozen Dimension appears';phase=destination and 'heart-return' or 'sailing'
  local checkAt=0;local waterY=seat.Position.Y
  -- Keep one outward heading; danger level must never turn this hunt into a circle.
  local radial=Vector3.new(seat.Position.X-TIKI.X,0,seat.Position.Z-TIKI.Z)
  local direction=radial.Magnitude>3000 and radial.Unit or Vector3.new(-1,0,0)
  driving=game:GetService('RunService').Heartbeat:Connect(function(dt)
   local ok,err=pcall(function()
    local h=body()
    if not active(id) or (not destination and not config().hunt) or (destination and not config().returnHeart) or not healthy(boat) or not h or h.SeatPart~=seat then stopDrive();return end
    for _,container in pairs({boat,player.Character}) do
     for _,part in ipairs(container:GetDescendants()) do
      if part:IsA('BasePart') then
       if sailingCollisions[part]==nil then sailingCollisions[part]=part.CanCollide end
       part.CanCollide=false
      end
     end
    end
    if os.clock()>=checkAt then
     checkAt=os.clock()+.2
     if not destination and dimension() then stopDrive();return end
     local threat=config().dodge and danger()
     if threat then
      if not flying then
       flying={y=waterY,untilTime=os.clock()+2}
       boat:PivotTo(boat:GetPivot()+Vector3.new(0,waterY+250-seat.Position.Y,0))
      end
      flying.untilTime=os.clock()+2
      status.Text='Avoiding Terrorshark above water; continuing outward'
     elseif flying and os.clock()>=flying.untilTime then
      boat:PivotTo(boat:GetPivot()+Vector3.new(0,waterY-seat.Position.Y,0));flying=nil
      status.Text='Sailing outward until Frozen Dimension appears'
     end
    end
    local p=seat.Position
    if destination then
     local delta=Vector3.new(destination.X-p.X,0,destination.Z-p.Z)
     if delta.Magnitude<=35 then
      stopDrive();phase='heart-arrived';config().ride=false;config().hunt=false;config().attack=false
      status.Text='Arrived at '..config().returnIsland..' coast; boat stopped';task.defer(preferences.Flush);return
     end
     direction=delta.Unit
    end
    local nextPosition=Vector3.new(p.X,waterY+(flying and 250 or 0),p.Z)+direction*sea.boatSpeed*math.min(dt,.05)
    local nextSeat=CFrame.lookAt(nextPosition,nextPosition+direction)
    boat:PivotTo(nextSeat*seat.CFrame:ToObjectSpace(boat:GetPivot()))
    seat.ThrottleFloat=0;seat.SteerFloat=0
    seat.AssemblyLinearVelocity=Vector3.zero;seat.AssemblyAngularVelocity=Vector3.zero
    local velocity=seat:FindFirstChildOfClass('BodyVelocity')
    if velocity then
     if sailingVelocity[velocity]==nil then sailingVelocity[velocity]=velocity.Velocity end
     velocity.Velocity=Vector3.zero
    end
    local gyro=seat:FindFirstChildOfClass('BodyGyro');if gyro then gyro.CFrame=nextSeat.Rotation end
   end)
   if not ok then stopDrive();status.Text='Boat search stopped: '..tostring(err) end
  end)
 end
 local function health(object)
  if not object then return nil end
  local h=object:FindFirstChildOfClass('Humanoid');if h then return h.Health end
  local hp=object:FindFirstChild('Health') or object:FindFirstChild('HP')
  if hp and hp:IsA('ValueBase') then return tonumber(hp.Value) end
  local attr=tonumber(object:GetAttribute('Health')) or tonumber(object:GetAttribute('HP'))
  if attr then return attr end
  if object:IsA('BasePart') and object.Parent and object.Parent:IsA('Model') then
   local ph=object.Parent:FindFirstChildOfClass('Humanoid')
   if ph then return ph.Health end
  end
  return nil
 end
 local function segments()
  local result={};local seen={}
  local aliveBodyCount=0
  for _,folder in pairs({workspace:FindFirstChild('SeaBeasts'),workspace:FindFirstChild('Enemies'),workspace}) do
   for _,boss in ipairs(folder:GetChildren()) do if boss:IsA('Model') and boss.Name:lower():find('leviathan',1,true) then
    local candidates={boss};for _,v in ipairs(boss:GetDescendants()) do if v:IsA('Model') or v:IsA('BasePart') then table.insert(candidates,v) end end
    for _,v in ipairs(candidates) do
     local hp=health(v);local p=v:IsA('BasePart') and v or v:FindFirstChild('HumanoidRootPart') or v.PrimaryPart or v:FindFirstChild('Head') or v:FindFirstChildWhichIsA('BasePart',true)
     if hp and p and not seen[v] then
      seen[v]=true;tracked[v]=hp;hadBoss=true
      local n=v.Name:lower()
      local isHead=n:find('head',1,true)~=nil or n:find('main',1,true)~=nil
      local explicitBody=n:find('segment',1,true)~=nil or n:find('body',1,true)~=nil or n:find('tail',1,true)~=nil
      local isMain=isHead or (v==boss and not explicitBody)
      if not isMain then bodyParts[v]=hp end
      local blocked=v:GetAttribute('Invulnerable')==true or v:GetAttribute('CanDamage')==false or v:GetAttribute('Damageable')==false
      if hp>0 and not blocked then
       if not isMain then aliveBodyCount=aliveBodyCount+1 end
       table.insert(result,{object=v,model=v:IsA('Model') and v or boss,part=p,hp=hp,main=isMain})
      end
     end
    end
   end end
  end
  local count,dead=0,0
  for object,lastHP in pairs(bodyParts) do
   count=count+1
   local isDead=false
   if not object or not object.Parent or not object:IsDescendantOf(workspace) then
    isDead=true
   else
    local hp=health(object)
    if not hp or hp<=0 then isDead=true end
   end
   if isDead then dead=dead+1 end
  end
  -- ក្បាល Leviathan អាចវ៉ៃបាននៅពេល:
  -- 1) body parts ដែលបាន track ងាប់អស់ (dead >= count)
  -- 2) ឬគ្មាន body parts នៅរស់ក្នុង workspace ទៀតទេ (aliveBodyCount == 0)
  local mainReady=(count>0 and dead>=count) or (aliveBodyCount==0 and (count>0 or hadBoss))
  if mainReady then
   for _,v in ipairs(result) do if v.main then noDamage[v.object]=nil end end
  end
  local filtered={};for _,v in ipairs(result) do if not v.main or mainReady then table.insert(filtered,v) end end
  return filtered
 end
 local function combat(target,id)
  stopDrive();phase='combat';local h,r=body();if not h then return end
  h.Sit=false;h.Jump=true
  if not savedWeapon then savedWeapon=farm.weapon;savedTool=farm.serviceTool end
  farm.SetWeapon(config().weapon=='Dragonstorm' and 'Gun' or 'Demon Fruit');farm.serviceTool=config().weapon=='Dragonstorm' and 'Dragonstorm' or nil
  local point=target.part.Position
  if (r.Position-point).Magnitude>70 then if not move(point+Vector3.new(0,18,10),id) then return end end
  farm.SeaHover(target.part,token,18,false)
  local startHP=health(target.object);local deadline=os.clock()+5
  local lastHP=startHP;local preCombat=damageDone[target.object] or 0
  repeat
   if not active(id) or not config().attack or not target.part.Parent then return end
   local hp=health(target.object);if not hp or hp<=0 then return end
   -- track HP drop ក្នុង loop ភ្លាម
   if hp<lastHP then
    damageDone[target.object]=(damageDone[target.object] or 0)+(lastHP-hp)
    lastHP=hp
   end
   if target.main then
    status.Text='Attacking Leviathan Head ['..math.floor(hp)..' HP remaining]'
   else
    status.Text='Attacking '..target.object.Name..' ['..math.floor(damageDone[target.object] or 0)..'/25000 HP]'
   end
   -- ដល់ 25000 → ចេញភ្លាម មិនរង់ deadline (បើជាក្បាល/main វ៉ៃបន្តរហូតដល់ងាប់)
   if not target.main and (damageDone[target.object] or 0)>=25000 then
    status.Text='25000 HP dealt on '..target.object.Name..'; rotating to next segment'
    return
   end
   farm.SeaAttackPart(target.model,target.part,token);task.wait(.08)
  until os.clock()>deadline
  -- ពិនិត្យ no-damage ប្រសិនបើ loop ផុត deadline ដោយ damage = 0
  if (damageDone[target.object] or 0)==preCombat then
   noDamage[target.object]=os.clock()+10;status.Text='No damage confirmed; checking another segment'
  end
 end
 local heartTarget;local heartScanAt=0;local heartShotAt=0;local heartShots=0;local shotObjects={}
 local function findHeart()
  if heartTarget and heartTarget.Parent then return heartTarget end
  if os.clock()<heartScanAt then return end
  heartScanAt=os.clock()+2
  local best,gap
  for _,v in ipairs(workspace:GetDescendants()) do
   local n=v.Name:lower():gsub('[^%a]','')
   if (n=='frozenheart' or n=='leviathanheart') and (v:IsA('Model') or v:IsA('BasePart')) then
    local part=v:IsA('BasePart') and v or v.PrimaryPart or v:FindFirstChildWhichIsA('BasePart',true)
    if part then local _,r=body();local d=r and (r.Position-part.Position).Magnitude or 0
     if not gap or d<gap then best=part;gap=d end
    end
   end
  end
  heartTarget=best;return best
 end
 local function heartAttached(target)
  -- A successful remote response means a shot, not a captured heart.
  for _,v in ipairs(workspace:GetDescendants()) do
   if v:IsA('BasePart') and not shotObjects[v] and v:GetAttribute('Welded')==true then
    for _,joint in ipairs(v:GetJoints()) do
     if joint:IsA('JointInstance') or joint:IsA('WeldConstraint') then
      local other=joint.Part0==v and joint.Part1 or joint.Part0
      if other and (other==target or (target.Parent and target.Parent:IsA('Model') and other:IsDescendantOf(target.Parent))) then return true end
     elseif joint:IsA('Constraint') then
      local a0,a1=joint.Attachment0,joint.Attachment1
      local other=a0 and a0.Parent==v and a1 and a1.Parent or a1 and a1.Parent==v and a0 and a0.Parent
      if other and (other==target or (target.Parent and other:IsDescendantOf(target.Parent))) then return true end
     end
    end
   end
  end
  return false
 end
 local function harpoonAim(cannon,target,shift)
  local cs=cannon:FindFirstChild('Seat');local bw=cs and cs:FindFirstChild('BoatWeld')
  local cw=cs and cs:FindFirstChild('CannonWeld');local tw=cs and cs:FindFirstChild('TubeWeld')
  if not bw or not cw or not tw or not bw.Part0 or not bw.Part1 or not cw.Part0 or not cw.Part1 or not tw.Part0 or not tw.Part1 then return end
  local bc=bw.Part1.CFrame:ToObjectSpace(cw.Part0.CFrame)
  local ct=cw.Part1.CFrame:ToObjectSpace(tw.Part0.CFrame)
  local function miss(p,y)
   local rise=math.max(p-math.rad(25),0)/math.rad(35)*2.5
   local tilt=CFrame.new(0,rise,0)*CFrame.Angles(p,0,0)*CFrame.new(0,0,-rise/math.sqrt(2))
   local muzzle=(shift or CFrame.new())*bw.Part0.CFrame*CFrame.Angles(0,-y,0)*bc*tilt*cw.C1:Inverse()*ct*tw.C0*tw.C1:Inverse()
   local velocity=muzzle.LookVector*400;local delta=target-muzzle.Position
   local h2=velocity.X*velocity.X+velocity.Z*velocity.Z
   if h2<1 then return math.huge end
   local t=(delta.X*velocity.X+delta.Z*velocity.Z)/h2
   if t<=0 or t>4 then return math.huge end
   return (muzzle.Position+velocity*t-Vector3.new(0,workspace.Gravity*t*t/2,0)-target).Magnitude
  end
  local pitch,yaw,best=0,0,math.huge
  for p=-10,45,5 do for y=-65,65,5 do local e=miss(math.rad(p),math.rad(y));if e<best then best=e;pitch=p;yaw=y end end end
  for _,stepSize in ipairs({1,.2}) do
   local oldP,oldY=pitch,yaw
   for pi=-5,5 do for yi=-5,5 do
    local p=math.clamp(oldP+pi*stepSize,-10,45);local y=math.clamp(oldY+yi*stepSize,-65,65)
    local e=miss(math.rad(p),math.rad(y));if e<best then best=e;pitch=p;yaw=y end
   end end
  end
  if best<=3 then return math.rad(pitch),math.rad(yaw),best end
 end
 local heartTraceAt=0
 local function heartLog(kind,data)
  local env=getgenv and getgenv() or _G
  env.NexoHeartTrace=env.NexoHeartTrace or {sequence=0,events={}}
  local trace=env.NexoHeartTrace;trace.sequence=trace.sequence+1
  trace.events[#trace.events+1]={id=trace.sequence,time=workspace:GetServerTimeNow(),kind=kind,data=data}
  if #trace.events>300 then table.remove(trace.events,1) end
 end
 local function collectHeart(target,id)
  stopDrive();phase='heart';local h=body();if not h then return end
  if not getBoat() then status.Text='Heart found; waiting for your Beast Hunter';return end
  local cannon=boat:FindFirstChild('Harpoon');local cs=cannon and cannon:FindFirstChild('Seat')
  if not cs then status.Text='A Beast Hunter harpoon is required for the heart';return end
  if heartShots>0 and heartAttached(target) then
   config().hunt=false;config().attack=false;config().ride=true;phase='heart-done'
   heartLog('ATTACHED',{target=target:GetFullName()})
   status.Text='Heart attachment detected; returning to driver seat'
   sit(id);return
  end
  -- Solve before changing seats. Never approach directly underneath the heart.
  local horizontal=Vector3.new(seat.Position.X-target.Position.X,0,seat.Position.Z-target.Position.Z)
  local pitch,yaw=harpoonAim(cannon,target.Position)
  if not pitch or horizontal.Magnitude<180 then
   local bw=cs:FindFirstChild('BoatWeld');local cw=cs:FindFirstChild('CannonWeld');local tw=cs:FindFirstChild('TubeWeld')
   if not bw or not cw or not tw or not bw.Part0 or not bw.Part1 or not cw.Part0 or not cw.Part1 or not tw.Part0 or not tw.Part1 then status.Text='Waiting for harpoon rig';return end
   local neutral=bw.Part0.CFrame*bw.Part1.CFrame:ToObjectSpace(cw.Part0.CFrame)*cw.C1:Inverse()*cw.Part1.CFrame:ToObjectSpace(tw.Part0.CFrame)*tw.C0*tw.C1:Inverse()
   local forward=Vector3.new(neutral.LookVector.X,0,neutral.LookVector.Z)
   local outward=horizontal.Magnitude>1 and horizontal.Unit or Vector3.new(1,0,0)
   local desired=-outward
   local angle=math.atan2(forward.Z*desired.X-forward.X*desired.Z,forward.X*desired.X+forward.Z*desired.Z)
   local rotation=CFrame.Angles(0,angle,0)
   local destination
   for _,range in ipairs({250,220,280,310,340,380,420,460}) do
    local p=Vector3.new(target.Position.X,seat.Position.Y,target.Position.Z)+outward*range
    local shift=CFrame.new(p)*rotation*CFrame.new(-seat.Position)
    local testPitch=harpoonAim(cannon,target.Position,shift)
    if testPitch and testPitch<=math.rad(44) then destination=p;break end
   end
   if not destination then status.Text='No reachable harpoon arc yet — keep manual control available';return end
   if not sit(id) then return end
   status.Text='Positioning boat for a clear harpoon arc'
   if os.clock()-heartTraceAt>1 then heartTraceAt=os.clock();heartLog('POSITION',{target={target.Position.X,target.Position.Y,target.Position.Z},destination={destination.X,destination.Y,destination.Z},distance=horizontal.Magnitude}) end
   local delta=destination-seat.Position
   local stepSize=math.min(delta.Magnitude,math.max(8,sea.boatSpeed*.2))
   local p=delta.Magnitude>.01 and seat.Position+delta.Unit*stepSize or destination
   local shift=CFrame.new(p)*rotation*CFrame.new(-seat.Position)
   boat:PivotTo(shift*boat:GetPivot())
   seat.AssemblyLinearVelocity=Vector3.zero;seat.AssemblyAngularVelocity=Vector3.zero
   seat.ThrottleFloat=0;seat.SteerFloat=0
   local bv=seat:FindFirstChildOfClass('BodyVelocity');if bv then bv.Velocity=Vector3.zero end
   return
  end
  if cs.Occupant and cs.Occupant~=h then status.Text='Waiting for passenger to leave the harpoon seat';return end
  if h.SeatPart~=cs then
   h.Sit=false;h.Jump=true
   if move(cs.Position+Vector3.new(0,3,0),id) then farm.SeaRelease(token);cs:Sit(h) end
   return
  end
  if cannon:FindFirstChild('Cooldown') or os.clock()<heartShotAt then status.Text='Waiting for harpoon cooldown / heart attachment';return end
  if heartShots>=5 then status.Text='Heart not confirmed after 5 shots; toggle collection OFF/ON to retry';return end
  local busy=player.Character and player.Character:FindFirstChild('Busy');if busy and busy.Value then return end
  pitch,yaw=harpoonAim(cannon,target.Position)
  if not pitch then status.Text='Harpoon moved; recalculating aim';return end
  shotObjects={};for _,v in ipairs(workspace:GetDescendants()) do if v:IsA('BasePart') then shotObjects[v]=true end end
  heartShots=heartShots+1;heartShotAt=os.clock()+6
  status.Text='Firing harpoon at the heart ('..heartShots..'/5)'
  heartLog('FIRE',{pitch=pitch,yaw=yaw,shot=heartShots,target={target.Position.X,target.Position.Y,target.Position.Z},cannon=cannon:GetFullName()})
  local result=request(id,'FireHarpoon',pitch,yaw,cannon,workspace:GetServerTimeNow())
  heartLog('RESPONSE',{result=tostring(result),shot=heartShots})
 end
 local function step(id)
  local c=config();local h=body();if not h then release();return end
  if c.heart and c.role=='Driver' and phase~='heart-done' and phase~='heart-return' and phase~='heart-arrived' then
   local target=findHeart();if target then collectHeart(target,id);return end
   if phase=='heart' then status.Text='Heart no longer visible; capture not confirmed';return end
  end
  if phase=='heart-done' or phase=='heart-return' then
   if not healthy(boat) then stopDrive();status.Text='Return paused: heart boat is unavailable';return end
   if sit(id) then
    if c.returnHeart then
     -- Sea-level approaches, not the elevated character travel markers.
     local destination=c.returnIsland=='Hydra' and Vector3.new(3212,0,2380) or Vector3.new(-17049,0,435)
     drive(id,destination)
    else stopDrive();status.Text='Heart attached; auto return is OFF' end
   end;return
  end
  if phase=='heart-arrived' then return end
  if c.attack then
   local list=segments();local target
   -- ជ្រើស segment ដែល noDamage ផុត + (damageDone < 25000 ឬជាក្បាល/main)
   for _,v in ipairs(list) do
    if (noDamage[v.object] or 0)<os.clock() and (v.main or (damageDone[v.object] or 0)<25000) then
     target=v;break
    end
   end
   -- ប្រសិនបើ segments ទាំងអស់ deal ≥ 25000 HP ហើយ → reset cycle ទាំងអស់
   if not target then
    local allRotated=true
    for _,v in ipairs(list) do
     if (noDamage[v.object] or 0)<os.clock() and (v.main or (damageDone[v.object] or 0)<25000) then allRotated=false;break end
    end
    if allRotated and #list>0 then
     for _,v in ipairs(list) do damageDone[v.object]=0 end
     status.Text='Rotation cycle complete; restarting 25000 HP cycle'
     return
    end
   end
   if target then combat(target,id);return end
   if #list>0 then stopDrive();status.Text='Waiting to retry damageable Leviathan segments';return end
   if hadBoss and #list==0 then
    local complete=true;for object,lastHP in pairs(tracked) do
     local hp=object.Parent and health(object) or nil
     if hp~=nil then tracked[object]=hp end
     if hp and hp>0 then complete=false end
    end
    if complete then c.attack=false;c.hunt=false;c.ride=true;phase='return';status.Text='Leviathan defeated; returning to boat';hadBoss=false;task.defer(preferences.Flush)
    else stopDrive();status.Text='Waiting for Leviathan segment health to load or defeat confirmation';return end
   end
  end
  local place=dimension()
  if (c.hunt or c.ride) and place and phase~='return' and not hadBoss then
   stopDrive();phase='found'
   if arrivalCharacter~=player.Character then
    arrived=false;arrivalPoint=nil;arrivalCharacter=player.Character
   end
   local function aboveWater(p,margin)
    local surface=0
    pcall(function() local fn=require(rs.Util.GetWaterHeightAtLocation);local y=fn(p);if type(y)=='number' then surface=y end end)
    return Vector3.new(p.X,math.max(p.Y+margin,surface+16),p.Z)
   end
   if not arrived then
    h.Sit=false;h.Jump=true
    local watcher=npc('Frozen Watcher',place)
    local destination=aboveWater(watcher or place,watcher and 5 or 30)
    local _,root=body();if not root then return end
    -- Rise before crossing the sea; streamed-out markers can sit below water.
    local cruiseY=math.max(root.Position.Y,destination.Y+8,aboveWater(root.Position,0).Y)
    if not move(Vector3.new(root.Position.X,cruiseY,root.Position.Z),id) then return end
    if not move(Vector3.new(destination.X,cruiseY,destination.Z),id) then return end
    watcher=npc('Frozen Watcher',place)
    if not watcher then
     farm.SeaHold(Vector3.new(destination.X,cruiseY,destination.Z),token)
     status.Text='Waiting above water for Frozen Watcher to load';return
    end
    arrivalPoint=aboveWater(watcher+Vector3.new(0,0,6),5)
    if move(arrivalPoint,id) then
     arrived=true;farm.SeaHold(arrivalPoint,token)
     status.Text='At Frozen Watcher. Start the encounter when your group is ready.'
    end
   elseif arrivalPoint then
    -- Do not release flight over the water while waiting for the encounter.
    farm.SeaHold(arrivalPoint,token)
   end
   return
  end
  if c.ride or c.hunt or phase=='return' then
   if not acquire(id) or not sit(id) then return end
   if c.hunt and c.role=='Driver' and not arrived then drive(id) else status.Text='Seated on selected boat' end
  elseif c.attack then status.Text=hadBoss and 'Waiting for verified Leviathan health/segments' or 'Waiting for Leviathan to spawn' end
 end
 bindControl(returnToggle,'Activated',function() config().returnHeart=not config().returnHeart;if not config().returnHeart then stopDrive() end;paint();task.defer(preferences.Flush) end)
 bindControl(returnChoice,'Activated',function() picker('Return after heart',{'Tiki','Hydra'},function(v)return config().returnIsland==v end,function(v) stopDrive();config().returnIsland=v;paint();task.defer(preferences.Flush) end,false) end)
 bindControl(refreshPlayers,'Activated',function() refreshRoster();status.Text='Player list refreshed';paint() end)
 bindControl(ownerChoice,'Activated',function() picker('Select Boat Owner',roster,function(v) return rosterIds[v]==config().owner end,function(v) stop();config().owner=rosterIds[v];paint();task.defer(preferences.Flush) end,false) end)
 bindControl(role,'Activated',function() stop();config().role=config().role=='Driver' and 'Passenger' or 'Driver';paint();task.defer(preferences.Flush) end)
 bindControl(weapon,'Activated',function() config().weapon=config().weapon=='Dragonstorm' and 'M1 Fruit' or 'Dragonstorm';paint();task.defer(preferences.Flush) end)
 for _,entry in ipairs({{board,'ride'},{hunt,'hunt'},{attackToggle,'attack'},{dodge,'dodge'},{manual,'manual'},{heartToggle,'heart'}}) do
  bindControl(entry[1],'Activated',function() config()[entry[2]]=not config()[entry[2]];if entry[2]=='hunt' then arrived=false;phase='idle' end
   if entry[2]=='heart' then heartShots=0;heartShotAt=0;shotObjects={};heartTarget=nil;if phase=='heart-done' or phase=='heart' then phase='return' end end
   if not config().hunt then stopDrive() end
   if not config().hunt and not config().ride and not config().attack then stop() end
   paint();task.defer(preferences.Flush)
  end)
 end
 bindControl(speed,'FocusLost',function() config().speed=math.clamp(tonumber(speed.Text) or 120,40,350);paint();task.defer(preferences.Flush) end)
 bindControl(bribe,'Activated',function()
  if pending then return end;pending=true;bribe.Text='...'
  task.spawn(function()
   local setID=setthreadidentity or setidentity;if setID then setID(2) end
   local ok,err=pcall(function()
    if not claim() then return end
    stopDrive()
    local id=serial;local p=npc('Spy',TIKI)
    if not p then status.Text='Spy not loaded; go to Tiki and retry';return end
    if move(p+Vector3.new(0,3,5),id) then
     local state=request(id,'InfoLeviathan','1')
     if state==-1 then status.Text='Spy has no clues available for this account';return end
     local reply=request(id,'InfoLeviathan','2')
     status.Text=reply==0 and 'Not enough fragments for Spy bribe' or ('Spy response: '..tostring(reply))
    end
   end)
   pending=false;bribe.Text='BUY';if not ok then status.Text=tostring(err) end
   if not config().hunt and not config().ride and not config().attack then release() end
  end)
 end)
 -- Manual speed changes only apply while this account occupies the driver seat.
 local speedSaved={}
 connect(game:GetService('RunService').Heartbeat,function()
  if not alive or not preferenceReady then return end
  local h=body();local s=h and h.SeatPart
  if config().manual and not driving and s and s:IsA('VehicleSeat') and s==seat then
   if speedSaved[s]==nil then speedSaved[s]=s.MaxSpeed end;s.MaxSpeed=config().speed
   if math.abs(s.ThrottleFloat)>.05 then
    local direction=s.CFrame.LookVector;local horizontal=Vector3.new(direction.X,0,direction.Z)
    if horizontal.Magnitude>.01 then local v=horizontal.Unit*config().speed*s.ThrottleFloat;s.AssemblyLinearVelocity=Vector3.new(v.X,s.AssemblyLinearVelocity.Y,v.Z) end
   end
  else for part,value in pairs(speedSaved) do if part.Parent then part.MaxSpeed=value end;speedSaved[part]=nil end end
 end)
 -- Boat subassemblies can be simulated by seated passengers. Apply locally on
 -- every rider before physics, not only on the driver's Heartbeat.
 local riderCollisions={}
 local function restoreRiderCollisions()
  for part,value in pairs(riderCollisions) do
   if part.Parent then part.CanCollide=value end
  end
  riderCollisions={}
 end
 connect(game:GetService('RunService').PreSimulation,function()
  local c=config();local h=body();local occupied=h and h.SeatPart
  local boats=workspace:FindFirstChild('Boats');local riding=occupied
  while riding and riding.Parent~=boats do riding=riding.Parent end
  local owner=riding and riding:FindFirstChild('Owner')
  local correct=owner and owner:IsA('ObjectValue') and owner.Value and owner.Value.UserId==c.owner
  if not alive or not preferenceReady or not (c.hunt or c.ride) or not correct then restoreRiderCollisions();return end
  local containers={riding}
  for _,p in ipairs(players:GetPlayers()) do
   local ch=p.Character;local hum=ch and ch:FindFirstChildOfClass('Humanoid')
   if hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(riding) then table.insert(containers,ch) end
  end
  local keep={}
  for _,container in ipairs(containers) do
   for _,part in ipairs(container:GetDescendants()) do
    if part:IsA('BasePart') then
     keep[part]=true
     if riderCollisions[part]==nil then
      local original=sailingCollisions[part]
      riderCollisions[part]=original~=nil and original or part.CanCollide
     end
     part.CanCollide=false
    end
   end
  end
  for part,value in pairs(riderCollisions) do
   if not keep[part] then if part.Parent then part.CanCollide=value end;riderCollisions[part]=nil end
  end
 end)
 local oldCleanup=beforeCleanup
 beforeCleanup=function() stop();restoreRiderCollisions();for part,value in pairs(speedSaved) do if part.Parent then part.MaxSpeed=value end end;if oldCleanup then oldCleanup() end end
 preferences.Leviathan={Stop=function() config().hunt=false;config().ride=false;config().attack=false;stop() end}
 task.spawn(function()
  local setID=setthreadidentity or setidentity;if setID then setID(2) end
  while alive do
   if preferenceReady then
    paint();local c=config()
    if (c.hunt or c.ride or c.attack) and not pending then
     if game.PlaceId~=7449423635 and game.PlaceId~=100117331123089 then status.Text='Leviathan Hunt requires Third Sea'
     elseif token and not farm.SeaActive(token) then c.hunt=false;c.ride=false;c.attack=false;stop();status.Text='Hunt stopped: another task took control'
     elseif claim() then
      local ok,err=pcall(step,serial)
      if not ok then c.hunt=false;c.ride=false;c.attack=false;stop();status.Text='Hunt stopped: '..tostring(err) end
     end
    elseif c.manual then getBoat() end
   end
   task.wait(.25)
  end
  release()
 end)
 end
 installLeviathan()
end

-- Summon and timed sword quest share one movement owner.
do
 local function installIndraTushita()
 local rs=game:GetService('ReplicatedStorage');local remote=rs.Remotes.CommF_
 local items=panels['Get Items'];local stack=panels['Stack Farm']
 label(stack,'Auto Spawn Indra',250,184,172,30,13)
 local spawnButton=control(stack,'OFF',430,186,60,28);bindingObjects[spawnButton].title="Auto Spawn Indra"
 label(stack,'Auto Spawn Dough King',250,344,172,30,12)
 local doughButton=control(stack,'OFF',430,346,60,28);bindingObjects[doughButton].title="Auto Spawn Dough King"
 local doughStatus=label(stack,'',18,498,478,58,11);doughStatus.TextWrapped=true
 local spawnStatus=label(stack,'',18,424,478,64,11);spawnStatus.TextWrapped=true
 stack.CanvasSize=UDim2.fromOffset(0,498)
 label(items,'Auto Tushita',18,300,360,28,13)
 local tushitaButton=control(items,'OFF',410,300,80,28)
 local questStatus=label(items,'',18,338,478,76,11);questStatus.TextWrapped=true
 label(items,'Get Rengoku (Hidden Key)',18,440,370,28,13)
 local rengokuButton=control(items,'OFF',410,440,80,28)
 local rengokuStatus=label(items,'',18,478,478,60,11);rengokuStatus.TextWrapped=true
 items.CanvasSize=UDim2.fromOffset(0,552)
 local rengokuPending=0;local rengokuRetry=0
 -- Insert directly below Kill Darkbeard, keeping later rows aligned.
 for _,v in ipairs(stack:GetChildren()) do
  if v:IsA('GuiObject') and v.Position.Y.Offset>=264 then
   v.Position=UDim2.new(v.Position.X.Scale,v.Position.X.Offset,v.Position.Y.Scale,v.Position.Y.Offset+40)
  end
 end
 label(stack,'Auto Spawn Darkbeard',18,264,380,30,13)
 local darkButton=control(stack,'OFF',410,266,80,28);bindingObjects[darkButton].title="Auto Spawn Darkbeard"
 local darkStatus=label(stack,'',18,604,478,42,11);darkStatus.TextWrapped=true
 stack.CanvasSize=UDim2.fromOffset(0,660)
 local darkPending=0;local darkRetry=0
 local token;local serial=0;local owner;local resume;local torchIndex=1;local torchDeadline;local requestBusy=false
 local function tool(name)
  for _,root in pairs({player.Character,player:FindFirstChild('Backpack')}) do
   local t=root:FindFirstChild(name);if t and t:IsA('Tool') then return t end
  end
 end
 local function body()
  local c=player.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local r=c and c:FindFirstChild('HumanoidRootPart')
  if h and h.Health>0 and r then return h,r end
 end
 local function enemy(name)
  local folder=workspace:FindFirstChild('Enemies');if not folder then return end
  for _,e in ipairs(folder:GetChildren()) do local h=e:FindFirstChildOfClass('Humanoid')
   if e.Name:lower():find(name,1,true) and h and h.Health>0 then return e end
  end
  -- Streamed-out live bosses are kept directly in ReplicatedStorage.
  if name=='rip_indra' or name=='dough king' or name=='darkbeard' then for _,e in ipairs(rs:GetChildren()) do
   if e:IsA('Model') and e.Name:lower():find(name,1,true) then local h=e:FindFirstChildOfClass('Humanoid');if h and h.Health>0 then return e end end
  end end
 end
 local function active(id)
  return alive and serial==id and token and farm.SeaActive(token) and (owner=='rengoku' and preferences.autoRengoku or owner=='dark' and preferences.autoSpawnDarkbeard or owner=='spawn' and preferences.autoSpawnIndra or owner=='tushita' and preferences.autoTushita or owner=='dough' and preferences.autoSpawnDoughKing)
 end
 local function release()
  local canResume=token and farm.SeaActive(token)
  serial=serial+1;if token then farm.SeaEnd(token);token=nil end
  preferences.itemQuestBusy=false;otherFarm.ResumePriority()
  local old=resume;resume=nil;owner=nil
  if old and alive and canResume then
   for k,v in pairs(old.events) do farm.stackEvents[k]=v end
   farm.stackFruit=old.stackFruit;farm.SetAutoClick(old.autoClick)
   if not (preferences.HasRareItem and preferences.HasRareItem()) then farm.SetMode(old.mode,old.enabled) end
  end
 end
 local function claim(job)
  if token and owner==job and farm.SeaActive(token) then return true end
  if token then release() end
  if preferences.styleJob or preferences.autoSaber or preferences.priorityBusy then return false end
  resume={mode=farm.mode,enabled=farm.enabled,events=table.clone(farm.stackEvents),stackFruit=farm.stackFruit,autoClick=farm.autoClick}
  preferences.itemQuestBusy=true;otherFarm.PausePriority();sea.SetEnabled(false);travelAPI.Stop()
  if preferences.CancelAllHop then preferences.CancelAllHop() end
  for k in pairs(farm.stackEvents) do farm.stackEvents[k]=false end
  farm.SetEnabled(false);farm.SetStackFruit(false);farm.SetAutoClick(false)
  owner=job;token=farm.SeaBegin();return true
 end
 local function move(p,id)
  if not active(id) then return false end
  local h=body();if h and h.Sit then h.Sit=false;h.Jump=true end
  return farm.SeaMove(p,token) and active(id)
 end
 local function equip(name)
  local t=tool(name);local h=body();if t and h then h:EquipTool(t) end;return t
 end
 local function invoke(id,...)
  if requestBusy or not active(id) then return end
  requestBusy=true;local args=table.pack(...);local done=false;local ok,result
  task.spawn(function() ok,result=pcall(remote.InvokeServer,remote,table.unpack(args,1,args.n));done=true;requestBusy=false end)
  local limit=os.clock()+8
  repeat task.wait(.1) until done or os.clock()>limit or not active(id)
  if not done then error('Server reply pending; waiting before any retry') end
  if not ok then error(tostring(result)) end
  if active(id) then return result end
 end
 local function point(o)
  if o and o:IsA('BasePart') then return o.Position end
  if o and o:IsA('Model') then return o:GetPivot().Position end
 end
 local function touch(part,id,name,confirmed)
  if part and not part:IsA('BasePart') then
   local found
   for _,v in ipairs(part:GetDescendants()) do if v:IsA('TouchTransmitter') and v.Parent:IsA('BasePart') then found=v.Parent;break end end
   part=found or part:FindFirstChildWhichIsA('BasePart',true)
  end
  if not part or not part:IsA('BasePart') or not active(id) then return false end
  local function sendTouch()
   if name then equip(name) end
   local _,root=body();if not root or type(firetouchinterest)~='function' then return end
   local t=name and tool(name);local handle=t and t:FindFirstChild('Handle')
   local parts={root};if handle and handle:IsA('BasePart') then table.insert(parts,handle) end
   for _,source in ipairs(parts) do
    if not active(id) or not part.Parent then return end
    pcall(firetouchinterest,source,part,0);task.wait(.1);pcall(firetouchinterest,source,part,1)
   end
  end
  if confirmed then
   if confirmed() then return true end
   sendTouch()
   local deadline=os.clock()+1.2
   repeat task.wait(.1) until not active(id) or confirmed() or os.clock()>deadline
   if not active(id) then return false end
   if confirmed() then return true end
  end
  if not move(part.Position+Vector3.new(0,2,0),id) then return false end
  sendTouch();task.wait(.5)
  return active(id) and (not confirmed or confirmed())
 end
 local function fight(e,id)
  local root=e and e:FindFirstChild('HumanoidRootPart');if not root then return end
  if not move(root.Position+Vector3.new(0,8,8),id) then return end
  local untilTime=os.clock()+8;local h=e:FindFirstChildOfClass('Humanoid')
  repeat
   if not active(id) or not e.Parent or not h or h.Health<=0 or (owner=='rengoku' and tool('Hidden Key')) then return end
   farm.SeaHover(root,token,farm.weapon=='Demon Fruit' and 3 or 24,false);farm.SeaAttack(e,token);task.wait(.07)
  until os.clock()>untilTime
 end
 -- Quest handlers are below; they only advance after observing game state.
 local function itemId(name,kind)
  local ok,value=pcall(function()return require(rs.Economy.ItemId).getId(name,kind):asNullable()end)
  if ok then return value end
 end
 local function owns(name,kind)
  if tool(name) then return true end
  local id=itemId(name,kind);if not id then return false end
  local ok,value=pcall(function()return require(rs.Util.ItemReplication).IsOwned.readClient(id)end)
  return ok and value==true
 end
 local colors={
  {name='Snow White',point=Vector3.new(-4971.476,331.566,-3720.030)},
  {name='Pure Red',point=Vector3.new(-5414.414,309.866,-2212.458)},
  {name='Winter Sky',point=Vector3.new(-5420.166,1084.966,-2666.821)}
 }
 local function buttonActivated(button)
  local function green(part)
   return part:IsA('BasePart') and part.Color.G>.7 and part.Color.G>part.Color.R+.2 and part.Color.G>part.Color.B+.2
  end
  if green(button) then return true end
  for _,part in ipairs(button:GetDescendants()) do if green(part) then return true end end
  return false
 end
 local colorIndex=1;local summonAt=0
 local function summon(id)
  if enemy('rip_indra') then preferences.autoSpawnIndra=false;spawnStatus.Text='Indra is spawned';release();preferences.Flush();return end
  if not tool("God's Chalice") and not tool('God Chalice') then spawnStatus.Text="Waiting for God's Chalice";return end
  local castle=workspace.Map:FindFirstChild('Boat Castle');local summoner=castle and castle:FindFirstChild('Summoner')
  if not summoner then spawnStatus.Text='Travelling to Castle on the Sea';move(Vector3.new(-5500,325,-2800),id);return end
  if colorIndex<=3 then
   local entry=colors[colorIndex];local circle=summoner:FindFirstChild('Circle');local button
   if circle then for _,part in ipairs(circle:GetChildren()) do if part:IsA('BasePart') and (part.Position-entry.point).Magnitude<15 then button=part;break end end end
   if not button then spawnStatus.Text='Waiting for '..entry.name..' button to load';move(entry.point+Vector3.new(0,5,0),id);return end
   -- Already green buttons can be activated by another player.
   if buttonActivated(button) then colorIndex=colorIndex+1;return end
   if not owns(entry.name,'Skin') then
    spawnStatus.Text='Need '..entry.name..' Aura, or another player to activate its button';return
   end
   local skin=itemId(entry.name,'Skin')
   spawnStatus.Text='Activating '..entry.name..' button'
   require(rs.Controllers.ModificationController):SetEquipAsync(skin,true)
   if not active(id) then return end
   if not game:GetService('CollectionService'):HasTag(player.Character,'Buso') and not player.Character:FindFirstChild('HasBuso') then invoke(id,'Buso') end
   if touch(button,id,nil,function()return buttonActivated(button)end) then
    local deadline=os.clock()+2
    repeat task.wait(.1) until not active(id) or not button.Parent or buttonActivated(button) or os.clock()>deadline
    if active(id) and button.Parent and buttonActivated(button) then colorIndex=colorIndex+1
    else spawnStatus.Text=entry.name..' button not confirmed; retrying' end
   end
   return
  end
  local detection=summoner:FindFirstChild('Detection')
  if not detection then spawnStatus.Text='Summon pedestal not loaded';return end
  if os.clock()<summonAt then return end
  summonAt=os.clock()+5;spawnStatus.Text='Offering Chalice at the pedestal'
  local name=tool("God's Chalice") and "God's Chalice" or 'God Chalice'
  equip(name);touch(detection,id,name,function()return enemy('rip_indra')~=nil or tool(name)==nil end)
  if active(id) and not enemy('rip_indra') then
   spawnStatus.Text='Waiting for summon confirmation; checking Aura buttons again';colorIndex=1
  end
 end
 local torchPoints={Vector3.new(-10752.786,413.983,-9367.361),Vector3.new(-11671.515,334.049,-9474.318),Vector3.new(-12131.793,520.368,-10655.042),Vector3.new(-13335.087,485.469,-6985.520),Vector3.new(-13488.117,335.760,-7923.950)}
 local function lit(torch)
  local particles=torch and torch:FindFirstChild('Particles');local light=particles and particles:FindFirstChild('PointLight')
  local emitter=particles and particles:FindFirstChild('Main')
  return light and light.Enabled or emitter and emitter.Enabled
 end
 local function finishTushita()
  preferences.autoTushita=false;questStatus.Text='Tushita obtained';torchDeadline=nil;torchIndex=1;release();preferences.Flush()
 end
 local function tushita(id)
  if owns('Tushita','Moveset') then finishTushita();return end
  local holy=tool('Holy Torch')
  if holy or torchIndex>1 then
   if not torchDeadline then torchDeadline=os.clock()+300 end
   if os.clock()>torchDeadline and torchIndex<=5 then
    torchDeadline=nil;torchIndex=1;questStatus.Text='Torch challenge timed out; waiting to enter again';return
   end
   local turtle=workspace.Map:FindFirstChild('Turtle');local torches=turtle and turtle:FindFirstChild('QuestTorches')
   if torchIndex<=5 then
    if not holy then torchIndex=1;torchDeadline=nil;questStatus.Text='Holy Torch missing; waiting to restart';return end
    local target=torches and torches:FindFirstChild('Torch'..torchIndex)
    if not target then questStatus.Text='Loading torch '..torchIndex;move(torchPoints[torchIndex]+Vector3.new(0,4,0),id);return end
    if lit(target) then torchIndex=torchIndex+1;return end
    questStatus.Text='Lighting torch '..torchIndex..'/5';equip('Holy Torch')
    if touch(target,id,'Holy Torch',function()return lit(target)end) and lit(target) then torchIndex=torchIndex+1 end
    return
   end
   questStatus.Text='Finding Longma'
   local boss=enemy('longma')
   if boss then fight(boss,id) else move(Vector3.new(-10238,390,-9550),id) end
   if owns('Tushita','Moveset') then finishTushita() end
   return
  end
  if not enemy('rip_indra') then questStatus.Text='Waiting for Indra to spawn';return end
  questStatus.Text='Travelling directly to the Tushita portal'
  local gate
  for _,v in ipairs(workspace.Map:GetDescendants()) do
   local n=v.Name:lower():gsub('[^%a]','')
   if n=='tushitagate' or n=='tushitadoor' or n=='tushitaportal' or ((n=='gate' or n=='door' or n=='teleport' or n=='portal') and v:GetFullName():lower():find('secretroom',1,true)) then
    local pos=point(v)
    if pos and (pos-Vector3.new(5387,76,503)).Magnitude<1500 then gate=v;break end
   end
  end
  local part=gate and (gate:IsA('BasePart') and gate or gate:FindFirstChild('Hitbox',true) or gate:FindFirstChildWhichIsA('BasePart',true))
  if not part then
   questStatus.Text='Loading the Tushita portal'
   local origin=workspace:FindFirstChild('_WorldOrigin');local locations=origin and origin:FindFirstChild('Locations')
   local temple=locations and locations:FindFirstChild('Secret Temple')
   move(temple and temple.Position+Vector3.new(0,3,0) or Vector3.new(5226.19,66.52,858.84),id)
   return
  end
  questStatus.Text='Entering Tushita gate';touch(part,id,nil,function()return tool('Holy Torch')~=nil end)
 end
 local doughRetry=0;local doughHadSweet=false;local doughPollAt=0;local doughReply
 local function dough(id)
  if enemy('dough king') then
   preferences.autoSpawnDoughKing=false;doughStatus.Text='Dough King spawned';release();preferences.Flush();return
  end
  local sweet=tool('Sweet Chalice')
  if sweet and not doughHadSweet then doughRetry=0;doughPollAt=0;doughReply=nil;doughHadSweet=true end
  if not sweet then
   if not tool("God's Chalice") and not tool('God Chalice') then
    if os.clock()<(preferences.doughExchangeUntil or 0) then doughStatus.Text='Waiting for chalice exchange confirmation';return end
    doughHadSweet=false;doughStatus.Text="Waiting for God's Chalice";release();return
   end
   local ok,count=pcall(function()
    if not require(rs.ItemReplicationService).IsInitialized then return nil end
    local id=require(rs.IdMap).Material['Conjured Cocoa']
    if not id then return nil end
    return require(rs.Util.ItemReplication).Quantity.readClient(id) or 0
   end)
   if not ok or type(count)~='number' then doughStatus.Text='Waiting for cocoa inventory';return end
   if count<10 then
    doughStatus.Text='Conjured Cocoa '..count..'/10'
    farm.SummonMobs({'Cocoa Warrior','Chocolate Bar Battler'},Vector3.new(231,24,-12200),'Dough King: farming cocoa',token)
    return
   end
   if os.clock()<doughRetry then return end
   doughRetry=os.clock()+8;doughStatus.Text='Exchanging for Sweet Chalice'
   preferences.doughExchangeUntil=os.clock()+12
   invoke(id,'SweetChaliceNpc')
   local deadline=os.clock()+5
   repeat
    if not active(id) then return end
    sweet=tool('Sweet Chalice')
    if sweet then break end
    task.wait(.1)
   until os.clock()>=deadline
   if not sweet then doughStatus.Text='Sweet Chalice exchange not confirmed; waiting';return end
   preferences.doughExchangeUntil=nil;doughRetry=0;doughHadSweet=true
   doughStatus.Text='Sweet Chalice ready; checking Dough King progress'
  end
  if os.clock()>=doughPollAt then
   doughPollAt=os.clock()+3
   doughReply=invoke(id,'CakePrinceSpawner',true)
   if not active(id) then return end
  end
  local plain=type(doughReply)=='string' and doughReply:gsub('<[^>]*>',''):lower() or ''
  local remaining=tonumber(plain:match('(%d+)%s+more') or plain:match('(%d+)%s+enemies'))
  if plain:find('open the portal now',1,true) or remaining==0 then
   if not tool('Sweet Chalice') or os.clock()<doughRetry then return end
   doughStatus.Text='Summoning Dough King';equip('Sweet Chalice');doughRetry=os.clock()+8
   invoke(id,'CakePrinceSpawner')
  elseif remaining and remaining>0 then
   doughStatus.Text='Cake Land: '..remaining..' enemies remaining'
   farm.SummonMobs({'Cookie Crafter','Cake Guard','Baking Staff','Head Baker'},Vector3.new(-2091,70,-12142),'Dough King: '..remaining..' remaining',token)
  else doughStatus.Text='Waiting for Cake Land summon progress' end
 end
 local function summonDark(id)
  if enemy('darkbeard') then
   preferences.autoSpawnDarkbeard=false;darkPending=0;darkStatus.Text='Darkbeard spawned';release();preferences.Flush();return
  end
  if not tool('Fist of Darkness') then
   if darkPending>0 and os.clock()>=darkPending then
    preferences.autoSpawnDarkbeard=false;darkPending=0;darkStatus.Text='Fist consumed; spawn not confirmed';release();preferences.Flush()
   else darkStatus.Text='Waiting for Darkbeard to appear' end
   return
  end
  if os.clock()<darkRetry then return end
  local map=workspace:FindFirstChild('Map');local arena=map and map:FindFirstChild('DarkbeardArena')
  local summoner=arena and arena:FindFirstChild('Summoner');local detection=summoner and summoner:FindFirstChild('Detection')
  if not detection then
   darkStatus.Text='Travelling to Dark Arena'
   move(Vector3.new(3778.696,18,-3499.441),id);return
  end
  darkStatus.Text='Summoning Darkbeard'
  equip('Fist of Darkness')
  if not move(detection.Position+Vector3.new(0,2,0),id) then return end
  darkPending=os.clock()+12;darkRetry=os.clock()+3
  touch(detection,id,'Fist of Darkness',function()return enemy('darkbeard')~=nil or not tool('Fist of Darkness')end)
 end
 local function getRengoku(id)
  if owns('Rengoku','Moveset') then
   preferences.autoRengoku=false;rengokuPending=0;rengokuStatus.Text='Rengoku owned';release();preferences.Flush();return
  end
  local key=tool('Hidden Key')
  if key then
   if preferences.CancelAllHop then preferences.CancelAllHop() end
   if os.clock()<rengokuRetry then return end
   rengokuStatus.Text='Hidden Key found; opening Rengoku chest'
   local map=workspace:FindFirstChild('Map');local castle=map and map:FindFirstChild('IceCastle')
   local chest=castle and castle:FindFirstChild('RengokuChest');local detection=chest and chest:FindFirstChild('Detection')
   if not detection then move(Vector3.new(6571.226,302,-6967.385),id);return end
   equip('Hidden Key')
   if not move(detection.Position+Vector3.new(0,2,0),id) then return end
   rengokuPending=os.clock()+12;rengokuRetry=os.clock()+3
   touch(detection,id,'Hidden Key',function()return not tool('Hidden Key') or owns('Rengoku','Moveset')end)
   return
  end
  if rengokuPending>0 then
   rengokuStatus.Text='Confirming Rengoku ownership'
   if os.clock()>=rengokuPending then
    preferences.autoRengoku=false;rengokuPending=0;rengokuStatus.Text='Key consumed; check sword inventory';release();preferences.Flush()
   end
   return
  end
  local target=enemy('awakened ice admiral')
  if not target then
   local folder=workspace:FindFirstChild('Enemies');local _,root=body();local best
   if folder and root then for _,e in ipairs(folder:GetChildren()) do
    local n=e.Name:lower();local h=e:FindFirstChildOfClass('Humanoid');local r=e:FindFirstChild('HumanoidRootPart')
    if (n:find('snow lurker',1,true) or n:find('arctic warrior',1,true)) and h and h.Health>0 and r then
     local distance=(r.Position-root.Position).Magnitude
     if not best or distance<best then target=e;best=distance end
    end
   end end
  end
  if target then rengokuStatus.Text='Farming Hidden Key: '..target.Name;fight(target,id)
  else rengokuStatus.Text='Waiting for Ice Castle enemies';move(Vector3.new(5514,52,-6600),id) end
 end
 local function setToggle(key,on)
  preferences[key]=on==true;release()
  if key=='autoRengoku' then rengokuPending=0;rengokuRetry=0 end
  if key=='autoSpawnDarkbeard' then darkPending=0;darkRetry=0 end
  if key=='autoSpawnDoughKing' then doughRetry=0;doughHadSweet=false;doughPollAt=0;doughReply=nil;preferences.doughExchangeUntil=nil end
  if key=='autoSpawnIndra' then colorIndex=1 end
  if key=='autoTushita' and not on then torchDeadline=nil;torchIndex=1 end
  preferences.Flush()
 end
 preferences.SetAutoTushita=function(on) setToggle('autoTushita',on) end
 bindControl(rengokuButton,'Activated',function()if preferenceReady then setToggle('autoRengoku',not preferences.autoRengoku)end end)
 bindControl(darkButton,'Activated',function()if preferenceReady then setToggle('autoSpawnDarkbeard',not preferences.autoSpawnDarkbeard)end end)
 bindControl(doughButton,'Activated',function()if preferenceReady then setToggle('autoSpawnDoughKing',not preferences.autoSpawnDoughKing);doughRetry=0 end end)
 bindControl(spawnButton,'Activated',function()if preferenceReady then setToggle('autoSpawnIndra',not preferences.autoSpawnIndra)end end)
 bindControl(tushitaButton,'Activated',function()if preferenceReady then setToggle('autoTushita',not preferences.autoTushita)end end)
 local oldCleanup=beforeCleanup
 beforeCleanup=function()farm.blockIndraForTushita=false;release();if oldCleanup then oldCleanup()end end
 task.spawn(function()
  local setID=setthreadidentity or setidentity;if setID then setID(2) end
  while alive do
   if preferenceReady then
    farm.blockIndraForTushita=preferences.autoTushita==true and not tool('Holy Torch') and torchIndex==1
    rengokuButton.Text=preferences.autoRengoku and 'ON' or 'OFF'
    darkButton.Text=preferences.autoSpawnDarkbeard and 'ON' or 'OFF'
    doughButton.Text=preferences.autoSpawnDoughKing and 'ON' or 'OFF'
    spawnButton.Text=preferences.autoSpawnIndra and 'ON' or 'OFF';tushitaButton.Text=preferences.autoTushita and 'ON' or 'OFF'
    local sea2=game.PlaceId==4442272183 or game.PlaceId==79091703265657
    local sea3=game.PlaceId==7449423635 or game.PlaceId==100117331123089
    local level=player:FindFirstChild('Data') and player.Data:FindFirstChild('Level')
    local wanted
    if preferences.autoRengoku and sea2 then wanted='rengoku'
    elseif preferences.autoSpawnDarkbeard and sea2 and (tool('Fist of Darkness') or darkPending>0 or enemy('darkbeard')) then wanted='dark'
    elseif preferences.autoSpawnDoughKing and sea3 and (tool("God's Chalice") or tool('God Chalice') or tool('Sweet Chalice') or os.clock()<(preferences.doughExchangeUntil or 0) or enemy('dough king')) then wanted='dough'
    elseif preferences.autoTushita and sea3 and level and level.Value>=2000 and (enemy('rip_indra') or tool('Holy Torch') or torchIndex>1 or owns('Tushita','Moveset')) then wanted='tushita'
    elseif preferences.autoSpawnIndra and sea3 and (tool("God's Chalice") or tool('God Chalice') or enemy('rip_indra')) then wanted='spawn' end
    if token and not farm.SeaActive(token) then
     local interrupted=owner;release();wanted=nil
     if interrupted=='rengoku' then preferences.autoRengoku=false;rengokuPending=0;rengokuStatus.Text='Stopped: another task took control'
     elseif interrupted=='dark' then preferences.autoSpawnDarkbeard=false;darkPending=0;darkStatus.Text='Stopped: another task took control'
     elseif interrupted=='spawn' then preferences.autoSpawnIndra=false;spawnStatus.Text='Stopped: another task took control'
     elseif interrupted=='dough' then preferences.autoSpawnDoughKing=false;doughStatus.Text='Stopped: another task took control';preferences.doughExchangeUntil=nil
     elseif interrupted=='tushita' then preferences.autoTushita=false;questStatus.Text='Stopped: another task took control' end
     preferences.Flush()
    end
    if wanted and claim(wanted) then
     local ok,err=pcall(wanted=='rengoku' and getRengoku or wanted=='dark' and summonDark or wanted=='dough' and dough or wanted=='spawn' and summon or tushita,serial)
     if not ok then local text='Waiting: '..tostring(err);if wanted=='rengoku' then rengokuStatus.Text=text elseif wanted=='dark' then darkStatus.Text=text elseif wanted=='dough' then doughStatus.Text=text elseif wanted=='spawn' then spawnStatus.Text=text else questStatus.Text=text end end
    elseif not wanted and token then release()
    elseif not wanted then
     if preferences.autoRengoku then rengokuStatus.Text='Requires Second Sea' end
     if preferences.autoSpawnDarkbeard then darkStatus.Text=sea2 and 'Waiting for Fist of Darkness' or 'Requires Second Sea' end
     if preferences.autoSpawnDoughKing then doughStatus.Text=sea3 and "Waiting for God's Chalice" or 'Requires Third Sea' end
     if preferences.autoSpawnIndra then spawnStatus.Text=sea3 and "Waiting for God's Chalice" or 'Requires Third Sea' end
     if preferences.autoTushita then questStatus.Text=not sea3 and 'Requires Third Sea' or (not level or level.Value<2000) and 'Requires level 2000' or 'Waiting for Indra to spawn' end
    end
   end
   task.wait(.3)
  end
  release()
 end)
 end
 installIndraTushita()
end

-- Soul Guitar: finish the puzzle before collecting crafting materials.
do
 local panel=panels['Get Items']
 label(panel,'Auto Soul Guitar',18,552,370,28,13)
 local button=control(panel,'OFF',410,552,80,28)
 local status=label(panel,'',18,590,475,74,11);status.TextWrapped=true;status.TextYAlignment=Enum.TextYAlignment.Top
 panel.CanvasSize=UDim2.fromOffset(0,680)
 local rs=game:GetService('ReplicatedStorage')
 local remote=rs.Remotes.CommF_
 local serial=0;local token;local previous;local lastTravel=0;local lastPray=0;local lastBuy=0;local checklist=''
 local ownedFist,ownedDark,ownedMoon,ownedRaid,ownedDarkEvent=false,false,false,false,false
 local sea2={[4442272183]=true,[79091703265657]=true}
 local sea3={[7449423635]=true,[100117331123089]=true}
 local function active(id) return alive and preferences.autoSoulGuitar==true and serial==id end
 local function say(message)
  status.Text=(checklist~='' and checklist..'\n' or '')..message
  preferences.soulGuitarStatus=message
 end
 local function data(name) local folder=player:FindFirstChild('Data');return folder and folder:FindFirstChild(name) end
 local function inventory()
  local counts={}
  local rep=require(rs.ItemReplicationService);local config=require(rs.ItemConfig)
  if not rep.IsInitialized then return nil end
  for _,item in pairs(rep:GetItems(rep.KEYS.QUANTITY) or {}) do
   if type(item.Value)=='number' and item.Value>0 then
    local result=config.match(item.ItemId)
    if result:isOk() then local info=result:unwrap();local index=info.Index
     local name=index and (index.StorageKey or index.Name)
     if name then counts[name]=(counts[name] or 0)+item.Value end
    end
   end
  end
  return counts
 end
 local function owned()
  for _,name in ipairs({'Skull Guitar','Soul Guitar'}) do
   for _,bag in pairs({player.Character,player:FindFirstChild('Backpack')}) do
    if bag and bag:FindFirstChild(name) then return true end
   end
   local ok,value=pcall(function()
    local id=require(rs.Economy.ItemId).getId(name,'Gun'):asNullable()
    return id and require(rs.Util.ItemReplication).IsOwned.readClient(id)
   end)
   if ok and value==true then return true end
  end
  return false
 end
 local function fist()
  for _,bag in pairs({player.Character,player:FindFirstChild('Backpack')}) do
   if bag then for _,item in ipairs(bag:GetChildren()) do
    if item:IsA('Tool') and item.Name:lower():gsub('[^%a]','')=='fistofdarkness' then return true end
   end end
  end
  return false
 end
 local function darkbeardPresent()
  local enemies=workspace:FindFirstChild('Enemies')
  for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
   local h=enemy:FindFirstChildOfClass('Humanoid')
   if enemy.Name:lower():find('darkbeard',1,true) and h and h.Health>0 then return true end
  end
  return false
 end
 local function releaseMovement()
  if token then farm.SeaEnd(token);token=nil end
 end
 local function move(point,id)
  if not active(id) then return false end
  if not token or not farm.SeaActive(token) then token=farm.SeaBegin() end
  return farm.SeaMove(point,token) and active(id)
 end
 local function stopOwnedJobs()
  releaseMovement()
  if ownedFist and preferences.collectFist and preferences.SetCollectFist then preferences.SetCollectFist(false) end
  if ownedDark and preferences.autoSpawnDarkbeard then preferences.autoSpawnDarkbeard=false end
  if ownedDarkEvent and farm.stackEvents.darkbeard then farm.SetStackEvent('darkbeard',false) end
  if ownedMoon and preferences.findFullMoon then
   if preferences.SetMoonSearch then preferences.SetMoonSearch(false) else preferences.findFullMoon=false;if preferences.CancelMoonHop then preferences.CancelMoonHop() end end
  end
  if ownedRaid and preferences.raid then preferences.raid.start=false end
  ownedFist,ownedDark,ownedMoon,ownedRaid,ownedDarkEvent=false,false,false,false,false
 end
 local function restore()
  local old=previous;previous=nil
  if old and alive then
   for key,value in pairs(old.events) do farm.SetStackEvent(key,value) end
   farm.SetBringMobs(old.bringMobs);farm.SetMobLimit(old.mobLimit);farm.SelectMaterial(old.material);farm.SetMode(old.mode,old.enabled)
  end
 end
 local function setEnabled(on)
  serial=serial+1;preferences.autoSoulGuitar=on==true;button.Text=on and 'ON' or 'OFF'
  if on then
   if owned() then say('Skull Guitar already owned');preferences.autoSoulGuitar=false;button.Text='OFF'
   else
    if not previous then previous={mode=farm.mode,enabled=farm.enabled,material=farm.material,mobLimit=farm.mobLimit,bringMobs=farm.bringMobs,events=table.clone(farm.stackEvents)} end
    say('Checking level, materials, and puzzle progress')
   end
  else stopOwnedJobs();restore();checklist='';say('Stopped') end
  preferences.Flush()
 end
 preferences.SetAutoSoulGuitar=setEnabled
 bindControl(button,'Activated',function() if preferenceReady then setEnabled(not preferences.autoSoulGuitar) end end)
 local function travel(where)
  if os.clock()<lastTravel then return end
  lastTravel=os.clock()+20
  releaseMovement()
  if preferences.HasRareItem and preferences.HasRareItem() then say('Protected item: travel paused');return end
  say('Travelling to '..(where==2 and 'Second Sea' or 'Third Sea'))
  remote:InvokeServer(where==2 and 'TravelDressrosa' or 'TravelZou')
 end
 local function farmMaterial(name,amount,id)
  if not active(id) then return end
  releaseMovement()
  if ownedFist and preferences.collectFist and preferences.SetCollectFist then preferences.SetCollectFist(false) end
  if ownedDark and preferences.autoSpawnDarkbeard then preferences.autoSpawnDarkbeard=false end
  if ownedDarkEvent and farm.stackEvents.darkbeard then farm.SetStackEvent('darkbeard',false);ownedDarkEvent=false end
  if farm.mode~='material' or farm.material~=name or not farm.enabled then
   farm.SelectMaterial(name);farm.SetMode('material',true)
  end
  say('Farming '..name..' ('..amount..' needed)')
 end
 local function castle()
  local map=workspace:FindFirstChild('Map');return map and map:FindFirstChild('Haunted Castle')
 end
 local function progress()
  local result=remote:InvokeServer('GuitarPuzzleProgress','Check')
  return type(result)=='table' and result or nil
 end
 local function click(part,id)
  if not active(id) or not part or type(fireclickdetector)~='function' then return false end
  local detector=part:IsA('ClickDetector') and part or part:FindFirstChildWhichIsA('ClickDetector',true)
  if not detector then return false end
  local target=detector.Parent
  local point=target and (target:IsA('BasePart') and target.Position or target:IsA('Model') and target:GetPivot().Position)
  if point and not move(point+Vector3.new(0,2,0),id) then return false end
  if not active(id) then return false end
  fireclickdetector(detector);task.wait(.25);return true
 end
 local function puzzle(id)
  local state=progress()
  local place=castle()
  if not place then say('Loading Haunted Castle');move(Vector3.new(-9530,140,6060),id);return end
  if not state then
   local forecast=preferences.MoonForecast
   if not forecast or not forecast.full then
    releaseMovement();say('Finding a full moon to start the puzzle')
    if forecast and forecast.state=='near' and type(forecast.seconds)=='number' and forecast.seconds>0 and forecast.seconds<=600 then
     say('Full moon approaching; waiting at this server')
     return
    end
    if not preferences.findFullMoon then
     ownedMoon=true
     if preferences.SetMoonSearch then preferences.SetMoonSearch(true) else preferences.findFullMoon=true;preferences.Flush() end
    end
    return
   end
   if ownedMoon and preferences.findFullMoon then
    if preferences.SetMoonSearch then preferences.SetMoonSearch(false) else preferences.findFullMoon=false;if preferences.CancelMoonHop then preferences.CancelMoonHop() end end
   end
   if os.clock()<lastPray then return end
   lastPray=os.clock()+15
   say('Praying at the Haunted Castle gravestone')
   if move(Vector3.new(-8655,141,6160),id) then
    remote:InvokeServer('gravestoneEvent',2)
    if active(id) then remote:InvokeServer('gravestoneEvent',2,true) end
   end
   return
  end
  if ownedMoon and preferences.findFullMoon then
   if preferences.SetMoonSearch then preferences.SetMoonSearch(false) else preferences.findFullMoon=false;if preferences.CancelMoonHop then preferences.CancelMoonHop() end end
  end
  if state.Swamp==false then
   say('Puzzle: gathering Living Zombies')
   local enemies=workspace:FindFirstChild('Enemies');local zombies={}
   for _,enemy in ipairs(enemies and enemies:GetChildren() or {}) do
    local h=enemy:FindFirstChildOfClass('Humanoid')
    if enemy.Name:find('Living Zombie',1,true) and h and h.Health>0 then zombies[#zombies+1]=enemy end
   end
   if #zombies<6 then move(Vector3.new(-10170,139,5934),id);return end
   -- Gather six network-owned zombies for a shared hit. Keep the normal combat API.
   if not token or not farm.SeaActive(token) then token=farm.SeaBegin() end
   if not farm.bringMobs then farm.SetBringMobs(true) end
   if farm.mobLimit~=6 then farm.SetMobLimit(6) end
   local primary=zombies[1];local root=primary:FindFirstChild('HumanoidRootPart')
   if root then
    local character=player.Character;local hr=character and character:FindFirstChild('HumanoidRootPart')
    if not hr or (hr.Position-root.Position).Magnitude>35 then move(root.Position+Vector3.new(0,24,0),id);return end
    farm.SeaHover(root,token,24,false)
    local count=farm.SeaGather(primary,token)
    if count>=6 then farm.SeaAttack(primary,token)
    else say('Puzzle: gathering 6 Living Zombies ('..count..'/6)') end
   end
   return
  end
  if state.Gravestones==false then
   say('Puzzle: aligning graveyard signs')
   local sides={'Right','Right','Left','Right','Left','Left','Left'}
   for i=1,7 do
    if not active(id) then return end
    local placard=place:FindFirstChild('Placard'..i,true)
    local side=placard and placard:FindFirstChild(sides[i])
    local indicator=side and side:FindFirstChild('Indicator')
    if indicator and indicator:IsA('BasePart') and indicator.BrickColor.Name~='Pearl' then click(side,id);return end
   end
   return
  end
  if state.Ghost==false then
   say('Puzzle: speaking with the Ghost')
   releaseMovement()
   remote:InvokeServer('GuitarPuzzleProgress','Ghost')
   if active(id) then remote:InvokeServer('GuitarPuzzleProgress','Ghost',true) end
   return
  end
  if state.Trophies==false then
   say('Puzzle: aligning trophy tablet')
   local tablet=place:FindFirstChild('Tablet')
   if not tablet then move(Vector3.new(-9533,6,6078),id);return end
   for _,i in ipairs({2,5,6,8,9}) do
    local segment=tablet:FindFirstChild('Segment'..i)
    if segment and segment:IsA('Model') and segment:GetPivot().Position.Y>-500 then click(segment,id);return end
   end
   local mapping={1,3,4,7,10}
   for i=1,5 do
    local trophy=place:FindFirstChild('Trophy'..i,true)
    local segment=tablet:FindFirstChild('Segment'..mapping[i])
    local handle=trophy and trophy:FindFirstChild('Handle',true)
    local line=segment and segment:FindFirstChild('Line')
    if handle and line and line:IsA('BasePart') then
     local target=math.abs(handle.CFrame.LookVector.X)>math.abs(handle.CFrame.LookVector.Z)
     local current=math.abs(line.CFrame.LookVector.X)>math.abs(line.CFrame.LookVector.Z)
     if current~=target then click(segment,id);return end
    end
   end
   return
  end
  if state.Pipes==false then
   say('Puzzle: matching pipe colors')
   local lab=place:FindFirstChild('Lab Puzzle')
   local pipes=lab and lab:FindFirstChild('Pipes')
   local floor=lab and (lab:FindFirstChild('ColorFloor') or lab:FindFirstChild('Floor'))
   if lab and not floor then
    for _,folder in ipairs(lab:GetChildren()) do
     local sample=folder~=pipes and folder:FindFirstChild('Part1',true)
     if sample and sample:FindFirstChildWhichIsA('ClickDetector',true) then floor=folder;break end
    end
   end
   if not floor or not pipes then move(Vector3.new(-9628,6,6157),id);return end
   for i=1,10 do
    local name='Part'..i
    local tile=floor:FindFirstChild(name,true)
    local pipe=pipes:FindFirstChild(name);pipe=pipe and (pipe:FindFirstChild(name) or pipe)
    local target=pipe and pipe:IsA('BasePart') and pipe.BrickColor or BrickColor.new('Storm blue')
    if tile and tile:IsA('BasePart') and tile.BrickColor~=target then click(tile,id);return end
   end
   return
  end
  say('Puzzle complete; visiting Weird Machine')
  releaseMovement()
  if os.clock()<lastBuy then return end
  lastBuy=os.clock()+10
  if move(Vector3.new(-9681,6,6341),id) then
   remote:InvokeServer('soulGuitarBuy',true)
   if active(id) and owned() then setEnabled(false);say('Skull Guitar obtained ✓') end
  end
 end
 task.spawn(function()
  repeat task.wait(.2) until preferenceReady or not alive
  if not alive then return end
  if preferences.autoSoulGuitar then setEnabled(true) end
  while alive do
   if preferences.autoSoulGuitar then
    local id=serial
    local ok,err=pcall(function()
     if owned() then setEnabled(false);say('Skull Guitar obtained ✓');return end
     local level=data('Level')
     if not level or level.Value<2300 then
      say('Requires level 2300; farming levels')
      if not farm.enabled or farm.mode~='level' then farm.SetMode('level',true) end
      return
     end
     if not preferences.soulPuzzleDone then
      checklist='Puzzle first • crafting materials afterward'
      if not sea3[game.PlaceId] then travel(3);return end
      local stage=progress()
      if stage and stage.Pipes==true then
       preferences.soulPuzzleDone=true
       releaseMovement();say('Puzzle complete; collecting crafting materials')
       preferences.Flush()
      else
       if farm.enabled then farm.SetEnabled(false) end
       puzzle(id)
       return
      end
     end
     local items=inventory();if not items then say('Waiting for item inventory');return end
     local fragments=data('Fragments')
     checklist=string.format('Bones %d/500 • Ectoplasm %d/250\nDark Fragment %d/1 • Fragments %d/5000',
      items.Bones or 0,items.Ectoplasm or 0,items['Dark Fragment'] or 0,fragments and fragments.Value or 0)
     if (items['Dark Fragment'] or 0)<1 then
      if not sea2[game.PlaceId] then travel(2);return end
      if fist() or darkbeardPresent() then
       say(fist() and 'Summoning Darkbeard for Dark Fragment' or 'Fighting Darkbeard for Dark Fragment')
       if fist() and not preferences.autoSpawnDarkbeard then preferences.autoSpawnDarkbeard=true;ownedDark=true end
       if preferences.collectFist and preferences.SetCollectFist then preferences.SetCollectFist(false) end
       if not farm.stackEvents.darkbeard then farm.SetStackEvent('darkbeard',true);ownedDarkEvent=true end
      else
       say('Finding a Fist of Darkness for Darkbeard')
       if ownedDarkEvent and farm.stackEvents.darkbeard then farm.SetStackEvent('darkbeard',false);ownedDarkEvent=false end
       if preferences.SetCollectFist and not preferences.collectFist then ownedFist=true;preferences.SetCollectFist(true) end
      end
      return
     end
     if ownedDarkEvent and farm.stackEvents.darkbeard then farm.SetStackEvent('darkbeard',false);ownedDarkEvent=false end
     if ownedDark and preferences.autoSpawnDarkbeard then preferences.autoSpawnDarkbeard=false;ownedDark=false end
     if (items.Ectoplasm or 0)<250 then
      if not sea2[game.PlaceId] then travel(2) else farmMaterial('Ectoplasm',250-(items.Ectoplasm or 0),id) end
      return
     end
     if (items.Bones or 0)<500 then
      if not sea3[game.PlaceId] then travel(3) else farmMaterial('Bones',500-(items.Bones or 0),id) end
      return
     end
     if not fragments or fragments.Value<5000 then
      releaseMovement();say('Farming '..(5000-(fragments and fragments.Value or 0))..' Fragments with raids')
      if preferences.raid and not preferences.raid.start then preferences.raid.start=true;ownedRaid=true;preferences.Flush() end
      return
     end
     if not sea3[game.PlaceId] then travel(3);return end
     if farm.enabled and farm.mode=='material' then farm.SetEnabled(false) end
     if preferences.raid and preferences.raid.start then preferences.raid.start=false end
     puzzle(id)
    end)
    if not ok then say('Retrying: '..tostring(err)) end
   end
   task.wait(2)
  end
  stopOwnedJobs()
 end)
end
-- Prehistoric Island uses the existing boat search and skill scheduler.
do
 local function installVolcano()
 local panel=panels['Sea Event'];local enabled=false;local token;local serial=0;local pending=false
 local finding=false;local entered=false;local cast={};local lastPrompt=0;local savedWeapon;local savedTool
 local crackJob={};local golemWeapon='Gun';local crackTools={Fruit=true,Gun=true,Sword=true,Melee=true}
 line(panel,874);label(panel,'Volcano',16,882,480,28,15)
 local function row(text,y) label(panel,text,16,y,224,28,12);return control(panel,'OFF',244,y,252,28) end
 local findToggle=row('Find Prehistoric Island',916)
 local toggle=row('Auto Volcano Event',950)
 local weaponChoice=row('Golem weapon',984)
 local skillChoice=row('Crack skill tools',1018)
 local status=label(panel,'Off',16,1056,480,66,11);status.TextWrapped=true
 panel.CanvasSize=UDim2.fromOffset(0,1134)
 local function paint()
  toggle.Text=enabled and 'ON' or 'OFF';findToggle.Text=finding and 'ON' or 'OFF'
  weaponChoice.Text=golemWeapon..'  ▾'
  local list={};for _,kind in ipairs({'Fruit','Gun','Sword','Melee'}) do if crackTools[kind] then list[#list+1]=kind end end
  skillChoice.Text=(#list>0 and table.concat(list,', ') or 'None')..'  ▾';skillChoice.TextTruncate=Enum.TextTruncate.AtEnd
 end
 local function norm(s) return tostring(s):lower():gsub('[^%a]','') end
 local function point(v)
  if v:IsA('BasePart') then return v.Position end
  if v:IsA('Model') then return v:GetPivot().Position end
  if v:IsA('Attachment') then return v.WorldPosition end
 end
 local function island()
  local map=workspace:FindFirstChild('Map');return map and map:FindFirstChild('PrehistoricIsland')
 end
 local function relic(map)
  local core=map:FindFirstChild('Core');local actual=core and core:FindFirstChild('PrehistoricRelic')
  if actual and point(actual) then return actual end
  for _,v in ipairs(map:GetDescendants()) do
   local n=norm(v.Name)
   if (n=='prehistoricrelic' or n=='fossilancientrelic' or n=='fossilrelic' or n=='ancientrelic' or n=='relic') and point(v) then return v end
  end
 end
 local function activation(map,r)
  local core=map:FindFirstChild('Core');local holder=core and core:FindFirstChild('ActivationPrompt')
  local prompt=holder and holder:FindFirstChildWhichIsA('ProximityPrompt',true)
  if not prompt and r then prompt=r:FindFirstChildWhichIsA('ProximityPrompt',true) end
  local anchor=prompt and prompt.Parent
  local position=anchor and point(anchor) or holder and point(holder) or r and point(r)
  return prompt,position
 end
 local oldLanding=sea.IslandLanding
 sea.IslandLanding=function(name,map)
  if name~='Prehistoric Island' then return oldLanding and oldLanding(name,map) end
  local r=relic(map);if r then local _,p=activation(map,r);return p+Vector3.new(0,3,3) end
  -- Never land on the summit: the volcano's upper region is lethal.
  local center,size
  if map:IsA('Model') then center,size=map:GetBoundingBox() else center,size=map.CFrame,map.Size end
  return center.Position+Vector3.new(math.max(size.X,size.Z)*.55,12-center.Position.Y,0)
 end
 local function release()
  if token then farm.SeaEnd(token);token=nil end
  if savedWeapon then farm.SetWeapon(savedWeapon);farm.serviceTool=savedTool;savedWeapon=nil;savedTool=nil end
  otherFarm.ResumePriority()
 end
 local function stop(message)
  enabled=false;crackJob={};serial=serial+1;toggle.Text='OFF';release()
  status.Text=message or 'Off'
  getgenv().NexoVolcanoLastStop={reason=status.Text,weapon=golemWeapon,time=os.time()}
 end
 local function active(id) return alive and enabled and serial==id and token and farm.SeaActive(token) end
 local oldFound=sea.OnIslandFound
 sea.OnIslandFound=function(name,ok)
  if oldFound then oldFound(name,ok) end
  if name=='Prehistoric Island' then finding=false;paint();status.Text=enabled and 'Island found; locating Fossil Relic' or 'Island found — Auto Event is OFF' end
 end
 local function prepare()
  if game.PlaceId~=7449423635 and game.PlaceId~=100117331123089 then status.Text='Volcano requires Third Sea';return false end
  if preferences.Leviathan then preferences.Leviathan.Stop() end
  if preferences.RaceUpgrades then preferences.RaceUpgrades.Stop() end
  if preferences.V4Trial then preferences.V4Trial.Stop() end
  local ok,message=sea.BeforeIslandSearch()
  if not ok then status.Text=message;return false end
  return true
 end
 local function start()
  if not finding and not prepare() then return end
  serial=serial+1;enabled=true;entered=false;crackJob={};cast={categories=crackTools};paint()
  status.Text=island() and 'Approaching Fossil Relic' or 'Waiting for island — enable Find Island to search'
 end
 bindControl(toggle,'Activated',function() if enabled then stop() else start() end end)
 bindControl(findToggle,'Activated',function()
  if finding then finding=false;if sea.searchIsland=='Prehistoric Island' then sea.SetIslandSearch(nil) end;paint();return end
  if not prepare() then return end
  release();finding=true;paint()
  if not sea.SetIslandSearch('Prehistoric Island') then finding=false;status.Text=sea.message;paint() end
 end)
 bindControl(weaponChoice,'Activated',function()
  picker('Golem weapon',{'Gun','Melee','Sword','Fruit'},function(v) return golemWeapon==v end,function(v) golemWeapon=v;paint() end,false)
 end)
 bindControl(skillChoice,'Activated',function()
  picker('Crack skill tools',{'Fruit','Gun','Sword','Melee'},function(v) return crackTools[v]==true end,function(v) crackTools[v]=not crackTools[v] or nil;cast.cursor=0;paint() end,true)
 end)
 paint()
 local function crackActive(part)
  if not part or not part.Parent or part.Transparency>=.95 or part:GetAttribute('Destroyed')==true then return false end
  if part:FindFirstAncestor('VolcanoRocks') then
   if part.Material~=Enum.Material.Neon then return false end
   local layer=part.Parent:FindFirstChild('VFXLayer');local glow=layer and layer:FindFirstChild('Glow',true)
   if glow and glow:IsA('ParticleEmitter') then return glow.Enabled end
   return part.Color.R>part.Color.G*1.3
  end
  return part:GetAttribute('Active')~=false
 end
 local function crack(map)
  if crackJob.part and crackJob.part:IsDescendantOf(map) and crackActive(crackJob.part) then return crackJob.part end
  crackJob={}
  local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart');local best,distance
  local core=map:FindFirstChild('Core');local rocks=core and core:FindFirstChild('VolcanoRocks')
  if rocks then
   for _,rock in ipairs(rocks:GetChildren()) do
    local part=rock:FindFirstChild('volcanorock')
    if part and part:IsA('BasePart') and crackActive(part) then
     local d=root and (root.Position-part.Position).Magnitude or 0
     if not distance or d<distance then best=part;distance=d end
    end
   end
   return best
  end
  for _,v in ipairs(map:GetDescendants()) do
   if v:IsA('BasePart') then
    local n=norm(v.Name);local parent=v.Parent and norm(v.Parent.Name) or ''
    local named=n:find('crack',1,true) or n=='pressurepoint' or parent:find('crack',1,true) or parent=='pressurepoints'
    if named and v.Transparency<.95 and v:GetAttribute('Destroyed')~=true and v:GetAttribute('Active')~=false then
     local activeVisual=v:GetAttribute('Active')==true or v.Material==Enum.Material.Neon
     for _,fx in ipairs(v:GetDescendants()) do if fx:IsA('ParticleEmitter') and fx.Enabled then activeVisual=true;break end end
     if activeVisual then local d=root and (root.Position-v.Position).Magnitude or 0;if not distance or d<distance then best=v;distance=d end end
    end
   end
  end
  return best
 end
 local function golem(map)
  local enemies=workspace:FindFirstChild('Enemies');if not enemies then return end
  local r=relic(map);local origin=r and point(r) or point(map);local best,distance
  for _,v in ipairs(enemies:GetChildren()) do
   local h=v:FindFirstChildOfClass('Humanoid');local p=v:FindFirstChild('HumanoidRootPart')
   if norm(v.Name):find('lavagolem',1,true) and h and h.Health>0 and p then
    local d=(p.Position-origin).Magnitude;if d<2500 and (not distance or d<distance) then best=v;distance=d end
   end
  end
  return best
 end
 -- Short flank approach: no full perimeter tour or separate vertical legs.
 local function volcanoRoute(target,map,keepMoving)
  local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
  if not root or not keepMoving() then return false end
  local core=map:FindFirstChild('Core');local rocks=core and core:FindFirstChild('VolcanoRocks')
  local center=Vector3.zero;local count=0
  if rocks then for _,rock in ipairs(rocks:GetChildren()) do
   local part=rock:FindFirstChild('volcanorock')
   if part and part:IsA('BasePart') then center=center+part.Position;count=count+1 end
  end end
  if count==0 then return false end
  center=center/count
  local from=root.Position
  local a=(from-center)*Vector3.new(1,0,1);local b=(target-center)*Vector3.new(1,0,1)
  if a.Magnitude>1 and b.Magnitude>1 then
   local first=math.atan2(a.Z,a.X);local last=math.atan2(b.Z,b.X)
   local turn=(last-first+math.pi)%(2*math.pi)-math.pi
   -- Only add flank waypoints when switching to a different side of the volcano.
   if math.abs(turn)>math.rad(65) then
    local segments=math.ceil(math.abs(turn)/math.rad(65))
    local radius=math.max(math.min(a.Magnitude,b.Magnitude+40),b.Magnitude)+12
    for i=1,segments-1 do
     if not keepMoving() then return false end
     local fraction=i/segments;local angle=first+turn*fraction
     local waypoint=Vector3.new(center.X+math.cos(angle)*radius,from.Y+(target.Y-from.Y)*fraction,center.Z+math.sin(angle)*radius)
     if not farm.SeaMove(waypoint,token,keepMoving) then return false end
    end
   end
  end
  return keepMoving() and farm.SeaMove(target,token,keepMoving)
 end
 local function holdCurrent(id)
  if not active(id) then return end
  local c=player.Character;local root=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
  if root and h and h.Health>0 then farm.SeaHold(root.Position,token);root.AssemblyLinearVelocity=Vector3.zero end
 end
 local function moveToCrack(target,id,map,part)
  if not active(id) then return false end
  if golem(map) or not crackActive(part) then holdCurrent(id);return false end
  local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
  if not root then return false end
  if (root.Position-target).Magnitude<8 then farm.SeaHold(target,token,part.Position);return true end
  local arrived=volcanoRoute(target,map,function() return active(id) and not golem(map) and crackActive(part) end)
  if arrived and active(id) and not golem(map) and crackActive(part) then farm.SeaHold(target,token,part.Position);return true end
  holdCurrent(id)
  status.Text=golem(map) and 'Switching to Lava Golem' or not crackActive(part) and 'Crack closed; selecting next target' or 'Crack approach interrupted; retrying'
  return false
 end
 local function step(id,map)
  local character=player.Character;local h=character and character:FindFirstChildOfClass('Humanoid')
  if not h or h.Health<=0 then stop('Auto Event stopped: character died');return end
  local participating=player:GetAttribute('PrehistoricIslandParticipant')
  if participating then entered=true elseif entered and participating==false then stop('Event participation ended — check the game result');return end
  local enemy=golem(map);local c=crack(map)
  -- Activate before attacking. Existing active event objects also establish the event has started.
  if not entered and not enemy and not c then
   farm.SeaRelease(token);local r=relic(map)
   if not r then status.Text='Waiting for Fossil Relic to load';return end
   status.Text='Approaching Fossil Relic'
   local prompt,position=activation(map,r)
   if farm.SeaMove(position+Vector3.new(0,2,2),token) and active(id) then
    if prompt and prompt.Enabled and os.clock()-lastPrompt>5 then
     lastPrompt=os.clock();status.Text='Activating Volcano Event'
     if fireproximityprompt then fireproximityprompt(prompt) else prompt:InputHoldBegin();task.wait(prompt.HoldDuration+.1);prompt:InputHoldEnd() end
    else status.Text='Waiting for event activation / first crack' end
   end
   return
  end
  -- Golems always win: never alternate with cracks while a live golem remains.
  if enemy then
   crackJob={}
   status.Text='Protecting relic — '..enemy.Name
   farm.SetWeapon(golemWeapon=='Fruit' and 'Demon Fruit' or golemWeapon);farm.serviceTool=nil
   local p=enemy:FindFirstChild('HumanoidRootPart');local eh=enemy:FindFirstChildOfClass('Humanoid')
   if golemWeapon=='Melee' or golemWeapon=='Sword' then
    local hit=enemy:FindFirstChild('Head');if hit and hit:IsA('BasePart') then p=hit end
   end
   local root=character:FindFirstChild('HumanoidRootPart')
   local near=p and root and (root.Position-p.Position).Magnitude<22
   if p and (near or volcanoRoute(p.Position+Vector3.new(0,10,4),map,function() return active(id) and p.Parent~=nil and eh and eh.Parent and eh.Health>0 end)) and active(id) then
    farm.SeaHover(p,token,18,false);local deadline=os.clock()+1
    repeat
     if not enemy.Parent or not p.Parent or not eh or not eh.Parent or eh.Health<=0 then break end
     farm.SeaAttack(enemy,token);task.wait(.06)
    until not active(id) or not p.Parent or not eh.Parent or eh.Health<=0 or os.clock()>=deadline

   end
   holdCurrent(id)
  elseif c then
   if not next(crackTools) then status.Text='Select crack skill tools';return end
   status.Text='Closing active lava crack'
   local core=map:FindFirstChild('Core');local interior=core and core:FindFirstChild('InteriorLava');local top=interior and interior:FindFirstChild('Top')
   local origin=top and top.Position or map:GetPivot().Position
   local rocks=core and core:FindFirstChild('VolcanoRocks');local sum=Vector3.zero;local count=0
   if rocks then for _,rock in ipairs(rocks:GetChildren()) do local part=rock:FindFirstChild('volcanorock');if part and part:IsA('BasePart') then sum=sum+part.Position;count=count+1 end end end
   if count>0 then origin=sum/count end
   local offset=Vector3.new(c.Position.X-origin.X,0,c.Position.Z-origin.Z)
   if offset.Magnitude<1 then offset=Vector3.new(1,0,0) end
   -- Stand outside the actual rotated rock bounds, not a fixed offset inside it.
   local direction=offset.Unit
   local localDirection=c.CFrame:VectorToObjectSpace(direction)
   local half=c.Size*.5
   local extent=math.huge
   for _,axis in ipairs({'X','Y','Z'}) do
    local component=math.abs(localDirection[axis])
    if component>.001 then extent=math.min(extent,half[axis]/component) end
   end
   if crackJob.part~=c then crackJob={part=c,attempts=0,standOff=24,lastHealth=h.Health};cast={categories=crackTools} end
   if crackJob.lastHealth and h.Health<crackJob.lastHealth-1 then crackJob.standOff=math.min(48,(crackJob.standOff or 24)+8) end
   crackJob.lastHealth=h.Health
   -- Raycast this rock alone to aim at its exposed mesh face instead of its center.
   local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={c}
   local reach=c.Size.Magnitude+40
   local hit=workspace:Raycast(c.Position+direction*reach,-direction*(reach+5),params)
   local surface=hit and hit.Position or c.Position+direction*extent
   local aimPoint=surface-direction*1.5
   local target=surface+direction*(crackJob.standOff or 24)+Vector3.new(0,3,0)
   -- One target, one cast, then confirmation. Do not restart travel during an animation.
   local busy=character:FindFirstChild('Busy')
   if busy and busy.Value then farm.SeaHold(target,token,aimPoint);status.Text='Finishing skill outside crack';return end
   if not moveToCrack(target,id,map,c) then return end
   local castHealth=h.Health
   local function valid()
    return active(id) and c.Parent~=nil and crackActive(c) and not golem(map) and h.Health>0 and h.Health>=castHealth-1
   end
   local settle=os.clock()+.25
   repeat task.wait(.05) until os.clock()>=settle or not valid()
   if not valid() then return end
   local root=character:FindFirstChild('HumanoidRootPart')
   if not root or (root.Position-target).Magnitude>10 then status.Text='Aligning outside crack';return end
   status.Text='Aiming at crack'
   cast.categories=crackTools
   cast.confirmSeconds=1.2
   local used,why=farm.CastSkillCycle(cast,function()
    if not valid() then return nil end
    return aimPoint
   end,token)
   if used then
    crackJob.attempts=crackJob.attempts+1
    if not crackActive(c) then crackJob={};status.Text='Crack closed'
    else status.Text='Crack still open — selecting next ready skill' end
    holdCurrent(id)
   else status.Text=why or 'Waiting for a ready selected skill' end

  else
   local r=relic(map);local root=character:FindFirstChild('HumanoidRootPart')
   if r and root then
    local safe=point(r)+Vector3.new(0,14,18)
    if (root.Position-safe).Magnitude<8 or volcanoRoute(safe,map,function() return active(id) and not golem(map) and not crack(map) end) then
     if active(id) then farm.SeaHold(safe,token) end
    end
   end
   holdCurrent(id)
   status.Text='Waiting near relic for cracks / Lava Golems'
  end
 end
 local oldCleanup=beforeCleanup
 beforeCleanup=function() stop();if finding and sea.searchIsland=='Prehistoric Island' then sea.SetIslandSearch(nil) end;if oldCleanup then oldCleanup() end end
 preferences.Volcano={Snapshot=function()return {enabled=enabled,weapon=golemWeapon,tools=table.clone(crackTools)}end,Stop=stop,Start=start,Configure=function(weapon,tools)
  if weapon=='Gun' or weapon=='Melee' or weapon=='Sword' or weapon=='Fruit' then golemWeapon=weapon end
  if type(tools)=='table' then for _,k in ipairs({'Fruit','Gun','Sword','Melee'}) do crackTools[k]=tools[k]==true or nil end end
  paint()
 end}
 task.spawn(function()
  local setIdentity=setthreadidentity or setidentity
  if setIdentity then setIdentity(2) end
  while alive do
   if finding and not sea.enabled then finding=false;paint() end
   if enabled and not pending then
    if token and not farm.SeaActive(token) then stop('Stopped: another task took control')
    elseif finding or (sea.enabled and sea.searchIsland=='Prehistoric Island') then status.Text=sea.message
    else
     local map=island()
     if not map then release();status.Text='Waiting for island — enable Find Island to search'
     else
      if not token then
       if not prepare() then stop(status.Text)
       else sea.SetEnabled(false);otherFarm.PausePriority();savedWeapon=farm.weapon;savedTool=farm.serviceTool;token=farm.SeaBegin() end
      end
      if token then
       local id=serial;pending=true;local ok,err=pcall(step,id,map);pending=false
       if not ok then stop('Volcano stopped: '..tostring(err)) end
      end
     end
    end
   end
   task.wait(.08)
  end
 end)
 end
 installVolcano()
end

-- Observation training and the Hungry Man upgrade are separate phases of one job.
do
 local function installHaki()
 local panel=panels['Farm Other'];panel.CanvasSize=UDim2.fromOffset(0,410)
 line(panel,264);label(panel,'Auto V2 Haki',18,276,240,28,13)
 local toggle=control(panel,'OFF',410,276,80,27)
 label(panel,'Hop when dodges run out',18,314,350,28,12)
 local hopToggle=control(panel,'OFF',410,314,80,27)
 local progress=label(panel,'Instinct: waiting for check',18,350,478,54,12);progress.TextWrapped=true
 local seaTravelAt=0;local token;local xp;local nextCheck=0;local nextKey=0;local target;local exhaustedAt;local retreated=false;local hopQueued=false;local nextQuest=0;local stage;local citizenState;local citizenCheck=0;local questStarted=false
 local remote=game:GetService('ReplicatedStorage').Remotes.CommF_
 local function config() return preferences.other end
 local function body() local c=player.Character;return c,c and c:FindFirstChildOfClass('Humanoid'),c and c:FindFirstChild('HumanoidRootPart') end
 local function value(name) local d=player:FindFirstChild('Data');local v=d and d:FindFirstChild(name);return v and tonumber(v.Value) or 0 end
 local function say(text)
  local left=player:GetAttribute('KenDodgesLeft');local maximum=player:GetAttribute('KenMaxDodges')
  progress.Text='Instinct EXP: '..(xp and tostring(xp)..'/5000' or 'unknown')..'  |  Dodges: '..tostring(left or '?')..'/'..tostring(maximum or '?')..'\n'..text
 end
 local function release()
  if token then farm.SeaEnd(token);token=nil end
  target=nil;exhaustedAt=nil;retreated=false;hopQueued=false
  if preferences.CancelHakiHop then preferences.CancelHakiHop() end
  otherFarm.ResumePriority()
 end
 local function stop(message)
  config().haki=false;release();preferences.Flush();say(message)
 end
 local function valid() return alive and config().haki and token and farm.SeaActive(token) end
 local function begin()
  if token then return true end
  farm.SetEnabled(false);farm.SetAutoClick(false);farm.SetStackFruit(false)
  for k in pairs(farm.stackEvents) do farm.stackEvents[k]=false end
  sea.SetEnabled(false);travelAPI.Stop();otherFarm.PausePriority()
  token=farm.SeaBegin();return true
 end
 local function move(position)
  if not valid() then return false end
  return farm.SeaMove(position,token,valid)
 end
 local function npc(name,fallback)
  local folder=workspace:FindFirstChild('NPCs');local n=folder and folder:FindFirstChild(name)
  return n and n:GetPivot().Position or fallback
 end
 local function visit(name,fallback)
  local _,_,r=body();local p=npc(name,fallback)
  if not p or not r then return false end
  if (r.Position-p).Magnitude>12 and not move(p+Vector3.new(0,0,5)) then return false end
  farm.SeaRelease(token);return valid()
 end
 local function nearest(name)
  local _,_,r=body();local folder=workspace:FindFirstChild('Enemies');local best,dist
  if not folder or not r then return end
  for _,e in ipairs(folder:GetChildren()) do
   local h=e:FindFirstChildOfClass('Humanoid');local p=e:FindFirstChild('HumanoidRootPart')
   local match=name and e.Name:find(name,1,true) or not name and not e.Name:lower():find('boss') and not e.Name:lower():find('golem')
   if match and h and h.Health>0 and p then
    local d=(r.Position-p.Position).Magnitude
    if d<2500 and (not dist or d<dist) then best=e;dist=d end
   end
  end
  return best
 end
 local function attack(name,spawn)
  local e=nearest(name)
  if not e then say('Waiting for '..name);move(spawn+Vector3.new(0,18,0));return end
  local p=e:FindFirstChild('HumanoidRootPart');local h=e:FindFirstChildOfClass('Humanoid');local _,_,r=body()
  if (r.Position-p.Position).Magnitude>35 and not move(p.Position+Vector3.new(0,12,0)) then return end
  if not valid() or not p.Parent or h.Health<=0 then return end
  farm.SeaHover(p,token,18,false);farm.SeaAttack(e,token)
 end
 local function hasTool(name)
  local c=player.Character;return player.Backpack:FindFirstChild(name) or c and c:FindFirstChild(name)
 end
 local fruitSpawns={
  {'Apple',Vector3.new(-12464,332,-7677)},
  {'Banana',Vector3.new(3692,453,-1129)},
  {'Pineapple',Vector3.new(-484,100,31)}
 }
 local function food()
  for _,entry in ipairs(fruitSpawns) do
   if not hasTool(entry[1]) then
    local found
    for _,v in ipairs(workspace:GetDescendants()) do if v.Name==entry[1] and (v:IsA('Tool') or v:IsA('Model') or v:IsA('BasePart')) then found=v;break end end
    local p=found and (found:IsA('BasePart') and found or found:FindFirstChild('Handle') or found:FindFirstChildWhichIsA('BasePart',true))
    say('Collecting '..entry[1])
    if not p then move(entry[2]);return end
    if move(p.Position) then
     farm.SeaRelease(token)
     local prompt=found:FindFirstChildWhichIsA('ProximityPrompt',true)
     if prompt and prompt.Enabled and fireproximityprompt then fireproximityprompt(prompt) end
    end
    return
   end
  end
  if visit('Citizen',Vector3.new(-12444,332,-7673)) then remote:InvokeServer('CitizenQuestProgress','Citizen');nextQuest=0 end
 end
 local function upgrade()
  if game.PlaceId~=7449423635 and game.PlaceId~=100117331123089 then
   say('Training complete — travelling to Third Sea for V2')
   if value('Level')>=1800 and os.clock()>=seaTravelAt then seaTravelAt=os.clock()+30;preferences.save=true;preferences.Flush();remote:InvokeServer('TravelZou') end
   return
  end
  if value('Level')<1800 then say('Training complete — level 1800 required');return end
  if value('Beli')<5000000 then say('Training complete — $5,000,000 required');return end
  if stage==nil or os.clock()>=nextQuest then
   nextQuest=os.clock()+60
   if not visit('Hungry Man',Vector3.new(-10920,624,-10268)) then return end
   stage=remote:InvokeServer('KenTalk2','Start')
   if stage==0 then stop('Instinct V2 already owned');return end
   if stage==1 or stage==4 then
    if remote:InvokeServer('KenTalk2','Buy')==0 then stop('Instinct V2 purchased') else say('V2 purchase not confirmed') end
    return
   end
  end
  if stage~=2 and stage~=5 and stage~=6 then say('Hungry Man requirements not yet accepted');return end
  if os.clock()>=citizenCheck then
   citizenCheck=os.clock()+10;citizenState=remote:InvokeServer('CitizenQuestProgress','Citizen')
  end
  local citizen=citizenState
  if citizen==0 then
   local gui=player.PlayerGui:FindFirstChild('Main');local q=gui and gui:FindFirstChild('Quest')
   if not questStarted or not q or not q.Visible then
    if not visit('Citizen',Vector3.new(-12444,332,-7673)) then return end
    remote:InvokeServer('StartQuest','CitizenQuest',1);questStarted=true
   end
   say('Citizen quest: Forest Pirates')
   attack('Forest Pirate',Vector3.new(-13220,332,-7620))
  elseif citizen==1 then
   say('Citizen quest: Captain Elephant')
   attack('Captain Elephant',Vector3.new(-13221,325,-8405))
  elseif citizen==2 then
   say('Collecting Citizen treasure')
   if move(Vector3.new(-12548,337,-7481)) then farm.SeaRelease(token) end
  elseif citizen==3 or citizen==4 then food()
  else say('Waiting for Citizen quest progress') end
 end
 local function train()
  if game.PlaceId~=2753915549 and game.PlaceId~=85211729168715 then
   say('Travelling to First Sea — Upper Sky Shanda')
   if os.clock()>=seaTravelAt then seaTravelAt=os.clock()+30;preferences.save=true;preferences.Flush();remote:InvokeServer('TravelMain') end
   return
  end
  local c,h,r=body();if not r or not h or h.Health<=0 then release();say('Waiting for respawn');return end
  local dodges=tonumber(player:GetAttribute('KenDodgesLeft'))
  if dodges==0 then
   if not retreated then retreated=true;farm.SeaRelease(token);move(r.Position+Vector3.new(0,65,0));if valid() then farm.SeaHold(r.Position,token) end end
   if not config().hakiHop then say('Dodges empty — waiting for recharge') end
   return
  end
  retreated=false
  if hopQueued then return end
  if h.Health<h.MaxHealth*.35 then stop('Low health — training stopped');return end
  if player:GetAttribute('KenActive')~=true then
   if os.clock()>=nextKey then
    nextKey=os.clock()+2
    local setID=setthreadidentity or setidentity;local getID=getthreadidentity or getidentity;local old=getID and getID() or 2
    if setID then setID(8) end
    local input=game:GetService('VirtualInputManager')
    local ok,err=pcall(function() input:SendKeyEvent(true,Enum.KeyCode.E,false,game);task.wait(.08);input:SendKeyEvent(false,Enum.KeyCode.E,false,game) end)
    if setID then setID(old) end
    if not ok then error(err) end
   end
   say('Activating Instinct');return
  end
  if not target or not target.Parent or not target:FindFirstChildOfClass('Humanoid') or target:FindFirstChildOfClass('Humanoid').Health<=0 then target=nearest('Shanda') end
  local p=target and target:FindFirstChild('HumanoidRootPart')
  if not p then
   say('Travelling to Upper Sky — waiting for Shanda')
   local destination=Vector3.new(-5949.067,5467.94,2086.515)
   pcall(function()
    local guide=require(game.ReplicatedStorage.GuideModule)
    for _,n in pairs(guide.Data.NPCList or {}) do
     if n.InternalQuestName=='SkyExp1Quest' and typeof(n.Position)=='Vector3' and n.Position.Y>4000 then destination=n.Position;break end
    end
   end)
   local origin=workspace:FindFirstChild('_WorldOrigin');local spawns=origin and origin:FindFirstChild('EnemySpawns')
   if spawns then for _,v in ipairs(spawns:GetChildren()) do
    if v.Name:find('Shanda',1,true) and v:IsA('BasePart') then destination=v.Position;break end
   end end
   if (r.Position-destination).Magnitude>25 then farm.SeaMove(destination,token) end
   return
  end
  say('Training dodges: '..target.Name)
  if (r.Position-p.Position).Magnitude>9 then
   if not farm.SeaMove(p.Position+Vector3.new(0,0,4),token,function() return valid() and tonumber(player:GetAttribute('KenDodgesLeft'))~=0 end) then return end
  end
  farm.SeaRelease(token);h:MoveTo(p.Position+Vector3.new(0,0,3))
 end
 bindControl(toggle,'Activated',function()
  config().haki=not config().haki
  if not config().haki then release();say('Stopped') else nextCheck=0;stage=nil end
  preferences.Flush()
 end)
 bindControl(hopToggle,'Activated',function() config().hakiHop=not config().hakiHop;preferences.save=true;preferences.Flush() end)
 -- Countdown runs independently of tweening, cooldowns and yielding server checks.
 task.spawn(function()
  while alive do
   local training=preferenceReady and config().haki and xp and xp<5000
   local empty=tonumber(player:GetAttribute('KenDodgesLeft'))==0
   if training and empty then
    exhaustedAt=exhaustedAt or os.clock()
    if config().hakiHop then
     local remaining=math.max(0,(preferences.hopWait or 20)-(os.clock()-exhaustedAt))
     if remaining<=0 and not hopQueued then
      local ok,message=preferences.RequestHop('haki')
      hopQueued=ok
      say(ok and 'Hop requested — finding / loading server' or ('Hop waiting: '..tostring(message)))
     elseif hopQueued then say('Hop requested — finding / loading server')
     else say('Dodges empty — hop in '..math.ceil(remaining)..'s') end
    end
   elseif not hopQueued then exhaustedAt=nil end
   if not config().hakiHop and hopQueued then
    if preferences.CancelHakiHop then preferences.CancelHakiHop() end
    hopQueued=false
   end
   task.wait(.1)
  end
 end)
 local cleanup=beforeCleanup
 beforeCleanup=function() release();if cleanup then cleanup() end end
 task.spawn(function()
  local setID=setthreadidentity or setidentity;if setID then setID(2) end
  while alive do
   toggle.Text=config().haki and 'ON' or 'OFF';hopToggle.Text=config().hakiHop and 'ON' or 'OFF'
   if preferenceReady and config().haki then
    local ok,err=pcall(function()
     if preferences.HasRareItem and preferences.HasRareItem() then stop('Rare item protected — Haki training stopped');return end
     if token and not farm.SeaActive(token) then stop('Stopped: another task took control');return end
     if os.clock()>=nextCheck then
      nextCheck=os.clock()+10
      local reply=remote:InvokeServer('KenTalk','Status')
      xp=tonumber(reply) or type(reply)=='string' and tonumber(reply:match('(%d+)')) or nil
     end
     if xp==nil then say('Instinct EXP unavailable — learn Instinct first');return end
     begin()
     if xp>=5000 then upgrade() else train() end
    end)
    if not ok then stop('Haki stopped: '..tostring(err)) end
   elseif token then release() end
   task.wait(.25)
  end
  release()
 end)
 end
 installHaki()
end

-- Presentation is supplied by nexo test.
-- Player actions: cancel active jobs without clearing user configuration.
do
 local panel=panels.Player
 for _,y in ipairs({46,90,136,180,224,268,312,356,400,444,488,532,576}) do line(panel,y) end
 panel.CanvasSize=UDim2.fromOffset(0,626)
 stackPanel.CanvasSize=UDim2.fromOffset(0,680)
 label(panel,'Stop All',18,3,130,24,14)
 local hint=label(panel,'Stops active tasks; keeps default settings.',18,25,380,18,10)
 local stopButton=control(panel,'OFF',410,10,80,28)
 local busy=false
 preferences.StopAll=function()
  if busy then return end
  busy=true;stopButton.Text='ON'
  local errors={}
  local function run(fn,...)
   if type(fn)=='function' then local ok,err=pcall(fn,...);if not ok then errors[#errors+1]=tostring(err) end end
  end
  for _,key in ipairs({'autoTrial','findFullMoon','v4Training','raceV2','raceV3','autoSpawnIndra','autoSpawnDoughKing','autoSpawnDarkbeard','autoRengoku','eliteHop','fruitHop'}) do preferences[key]=false end
  if preferences.other then preferences.other.haki=false;preferences.other.hakiHop=false end
  if preferences.RaidFruit then run(preferences.RaidFruit.Stop) end
  if preferences.BlueGear then run(preferences.BlueGear.Stop) end
  run(preferences.CancelAllHop)
  run(preferences.StopStyle)
  run(preferences.StopItemShop)
  run(preferences.SetAutoSaber,false)
  run(preferences.SetAutoSoulGuitar,false)
  run(preferences.SetCollectFist,false)
  run(preferences.SetAutoTushita,false)
  for _,key in ipairs({'RaceUpgrades','V4Trial','Leviathan','Volcano'}) do
   local api=preferences[key];if api then run(api.Stop) end
  end
  run(otherFarm.Stop)
  run(preferences.StopPlayerTravel)
  run(travelAPI.Stop)
  run(sea.SetIslandSearch,nil)
  run(sea.SetEnabled,false)
  for key in pairs(farm.stackEvents) do farm.stackEvents[key]=false end
  run(farm.SetStackFruit,false)
  run(farm.SetAutoClick,false)
  run(farm.SetEnabled,false)
  for _,key in ipairs({'Melee','Defense','Sword','Gun','Demon Fruit'}) do run(stats.Select,key,false) end
  -- Keep default aura, water walking, save setting and chosen configuration.
  for _,key in ipairs({'v3','v4','rollFruit','storeFruit'}) do preferences.auto[key]=false end
  farm.autoStore=false
  if preferences.levi then preferences.levi.manual=false end
  for _,key in ipairs({'fog','jump','speed'}) do preferences.movement[key]=false end
  run(preferences.Flush)
  busy=false
  stopButton.Text=#errors==0 and 'OFF' or 'Retry'
  if #errors>0 then warn('NEXO Stop All: '..table.concat(errors,' | ')) end
  task.delay(2,function() if alive and stopButton.Parent then stopButton.Text='OFF' end end)
  return #errors==0
 end
 bindControl(stopButton,'Activated',function()preferences.StopAll()end)
end

-- Player native menus and travel share the existing entrance-aware mover.
do
 local panel=panels.Player
 local message=label(panel,'',18,584,478,36,11);message.TextWrapped=true
 local function row(text,y)
  label(panel,text,18,y,290,28,13)
  return control(panel,'Open',410,y,80,28)
 end
 local function action(b,fn)
  local pending=false
  bindControl(b,'Activated',function()
   if pending then return end;pending=true
   task.spawn(function()
    local ok,err=pcall(fn)
    if not ok then message.Text='Unavailable: '..tostring(err):sub(1,120) end
    pending=false
   end)
  end)
 end
 local function reveal(object)
  local p=object
  while p and p~=player.PlayerGui do
   if p:IsA('ScreenGui') then p.Enabled=true elseif p:IsA('GuiObject') then p.Visible=true end
   p=p.Parent
  end
  local ui=getgenv().NexoFarmUI;if ui then ui.SetOpen(false) end
 end
 for _,entry in ipairs({{'Fruit Dealer',142,'FruitDealer'},{'Mirage Fruit Dealer',186,'AdvancedFruitDealer'}}) do
  local b=row(entry[1],entry[2])
  action(b,function()
   local controller=require(game.ReplicatedStorage.Controllers.UI.FruitShop)
   assert(controller and type(controller.Open)=='function','Fruit shop controller unavailable')
   controller:Open(entry[3])
   local screen=player.PlayerGui:FindFirstChild('FruitShopAndDealer');if screen then reveal(screen) end
  end)
 end
 action(row('Titles Specialist',230),function()
  local screen=player.PlayerGui:FindFirstChild('TitlesMenu');assert(screen,'Titles menu is loading')
  local event=screen:FindFirstChild('Open');assert(event and event:IsA('BindableEvent'),'Titles menu is unavailable')
  reveal(screen);event:Fire()
 end)
 action(row('Awakenings Expert',274),function()
  local available=game.ReplicatedStorage.Remotes.CommF_:InvokeServer('AwakeningChanger','Check')
  if not available then message.Text='No awakened fruit available on this account.';game:GetService('StarterGui'):SetCore('SendNotification',{Title='Awakenings Expert',Text='Equip a fruit with unlocked awakened moves first.',Duration=6});return end
  local popups=player.PlayerGui:FindFirstChild('Popups');local screen=popups and popups:FindFirstChild('AwakeningTogglerUI')
  local frame=screen and screen:FindFirstChild('AwakeningToggler');assert(frame,'Awakening menu is loading');reveal(frame)
 end)
 label(panel,'Change Team',18,362,200,28,13)
 local teamPending=false
 local teamButtons={}
 for i,name in ipairs({'Pirates','Marines'}) do
  local b=control(panel,name,272+(i-1)*112,362,106,28);teamButtons[name]=b
  action(b,function()
   if teamPending then return end
   if player.Team and player.Team.Name==name then message.Text='Already on this team';return end
   teamPending=true
   local started=os.clock()
   task.spawn(function()
    while alive and teamPending do
     for _,button in pairs(teamButtons) do button.Text='Wait '..math.floor(os.clock()-started)..'s' end
     task.wait(.2)
    end
   end)
   local ok,result=pcall(function() return game.ReplicatedStorage.Remotes.CommF_:InvokeServer('SetTeam2',name) end)
   local deadline=os.clock()+5
   while alive and ok and result==0 and (not player.Team or player.Team.Name~=name) and os.clock()<deadline do task.wait(.1) end
   teamPending=false
   for key,button in pairs(teamButtons) do button.Text=key end
   message.Text=player.Team and player.Team.Name==name and ('Team changed: '..name) or 'Team change blocked or not confirmed. Leave combat and retry.'
  end)
 end
 local token;local serial=0
 local mirage=row('Tween to Mirage',494);mirage.Text='OFF'
 local prehistoric=row('Tween to Prehistoric',538);prehistoric.Text='OFF'
 local activeButton
 local function stop()
  serial=serial+1
  if token then farm.SeaEnd(token);token=nil end
  if activeButton then activeButton.Text='OFF';activeButton=nil end
 end
 preferences.StopPlayerTravel=stop
 local function move(name,resolve,button)
  if activeButton==button then stop();return end
  local point=resolve();if not point then message.Text=name..' has not spawned or is not loaded';return end
  stop();travelAPI.Stop();sea.SetEnabled(false);farm.SetEnabled(false);farm.SetStackFruit(false)
  serial=serial+1;local id=serial;token=farm.SeaBegin();local t=token;activeButton=button;button.Text='ON'
  task.spawn(function()
   local ok,result=pcall(function()
    for _=1,5 do
     if id~=serial or not farm.SeaActive(t) then return false end
     local destination=resolve();if not destination then return false end
     if farm.SeaMove(destination,t) then return true end
     task.wait(.2)
    end
    return false
   end)
   if id==serial then stop();message.Text=ok and result and ('Arrived: '..name) or ('Travel stopped: '..name) end
  end)
 end
 local function islandPoint(name,highest)
  local map=workspace:FindFirstChild('Map');local island=map and map:FindFirstChild(name)
  if not island then return nil end
  if highest then
   local best
   for _,p in ipairs(island:GetDescendants()) do
    if p:IsA('BasePart') and p.CanCollide and p.Transparency<1 and (not best or p.Position.Y+p.Size.Y/2>best.Position.Y+best.Size.Y/2) then best=p end
   end
   if best then return best.Position+Vector3.new(0,best.Size.Y/2+3,0) end
  end
  if sea.IslandLanding then local ok,p=pcall(sea.IslandLanding,'Prehistoric Island',island);if ok and typeof(p)=='Vector3' then return p end end
  if island:IsA('Model') then return island:GetPivot().Position+Vector3.new(0,6,0) end
 end
 bindControl(mirage,'Activated',function() move('Mirage Island',function() return islandPoint('MysticIsland',true) end,mirage) end)
 bindControl(prehistoric,'Activated',function() move('Prehistoric Island',function() return islandPoint('PrehistoricIsland',false) end,prehistoric) end)
 local cleanup=beforeCleanup;beforeCleanup=function()stop();if cleanup then cleanup() end end
end

-- Optional visual helpers and emergency retreat; all start disabled.
do
 local c={fruit=false,players=false,berry=false,islands=false,aimPlayer=false,observation=false,hideObservation=false,retreat=false,percent=30,height=800}
 preferences.helpers=c
 local y=734
 local toggleRows={}
 local function row(text,get,set)
  label(settings,text,18,y,345,28,13);local b=control(settings,get() and 'ON' or 'OFF',410,y,80,28)
  toggleRows[#toggleRows+1]={button=b,get=get}
  bindControl(b,'Activated',function()set(not get());b.Text=get() and 'ON' or 'OFF' end)
  line(settings,y+36);y=y+44
 end
 row('Auto Save',function()return preferences.autoSave end,function(v)preferences.autoSave=v;preferences.Flush()end)
 row('Auto Load',function()return preferences.autoLoad end,function(v)preferences.autoLoad=v;preferences.Flush()end)
 label(settings,'Auto Load Team',18,y,280,28,13)
 local loadTeamButton=control(settings,preferences.autoLoadTeam or 'Marines',350,y,140,28)
 bindControl(loadTeamButton,'Activated',function()
  if not preferenceReady then return end
  preferences.autoLoadTeam=preferences.autoLoadTeam=='Pirates' and 'Marines' or 'Pirates'
  loadTeamButton.Text=preferences.autoLoadTeam;preferences.Flush()
 end)
 line(settings,y+36);y=y+44
 for _,v in ipairs({{'fruit','Fruit ESP'},{'players','Player ESP'},{'berry','Berry ESP'},{'islands','Island ESP'},{'aimPlayer','Aim Player'},{'observation','Auto Observation'},{'hideObservation','Remove Observation Effects'},{'retreat','Retreat at Low Health'}}) do
  local key=v[1];row(v[2],function()return c[key]end,function(on)c[key]=on end)
 end
 local function field(name,key,lo,hi)
  label(settings,name,18,y,320,28,13)
  local box=make('TextBox',settings,{Text=tostring(c[key]),Position=UDim2.fromOffset(362,y),Size=UDim2.fromOffset(128,28),BackgroundColor3=Color3.fromRGB(49,46,40),TextColor3=pale,Font=Enum.Font.Gotham,TextSize=14,ClearTextOnFocus=false,ZIndex=4})
  bindControl(box,'FocusLost',function()c[key]=math.clamp(tonumber(box.Text) or c[key],lo,hi);box.Text=tostring(c[key])end)
  line(settings,y+36);y=y+44
 end
 field('Low Health (%)','percent',10,60);field('Retreat Height (studs)','height',50,5000)
 settings.CanvasSize=UDim2.fromOffset(0,y+12)
 -- Compact the old fixed rows, preserving controls within each row.
 local rows={}
 for _,v in ipairs(settings:GetChildren()) do
  if v:IsA('GuiObject') and v.Size.Y.Offset>3 and v.Visible then
   local p=v.Position.Y.Offset;local bucket=math.floor((p+3)/10)
   if not rows[bucket] then rows[bucket]={top=p,objects={}} end
   local r=rows[bucket];r.top=math.min(r.top,p);r.objects[#r.objects+1]=v
  end
 end
 local ordered={};for _,r in pairs(rows)do ordered[#ordered+1]=r end;table.sort(ordered,function(a,b)return a.top<b.top end)
 for _,v in ipairs(settings:GetChildren())do if v:IsA('Frame') and v.Size.Y.Offset==1 then v:Destroy() end end
 local nextY=10
 for _,r in ipairs(ordered)do
  for _,v in ipairs(r.objects)do v.Position=UDim2.fromOffset(v.Position.X.Offset,nextY+v.Position.Y.Offset-r.top)end
  line(settings,nextY+36);nextY=nextY+44
 end
 settings.CanvasSize=UDim2.fromOffset(0,nextY+10)
 local marks={};local retreating=false;local retreatToken;local lastObservation=0;local aimPart;local aimPosition;local observationPending=false
 local function clear()
  for _,v in pairs(marks)do v:Destroy()end;marks={}
 end
 local function anchor(v)
  if v:IsA('BasePart')then return v end
  return v:FindFirstChild('HumanoidRootPart') or v:FindFirstChild('Handle') or v:FindFirstChildWhichIsA('BasePart',true)
 end
 local function mark(v,name,kind,origin,seen)
  local p=anchor(v);if not p then return end;seen[v]=true
  local b=marks[v]
  if not b then
   b=Instance.new('BillboardGui');b.Name='NexoESP';b.Size=UDim2.fromOffset(220,40);b.AlwaysOnTop=true;b.Adornee=p;b.StudsOffset=Vector3.new(0,4,0);b.Parent=gui
   local t=Instance.new('TextLabel');t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.TextColor3=Color3.fromRGB(255,224,146);t.TextStrokeTransparency=.25;t.Font=Enum.Font.Gotham;t.TextSize=14;t.Parent=b;marks[v]=b
  end
  b:FindFirstChildOfClass('TextLabel').Text=name..' | '..math.floor((p.Position-origin).Magnitude+.5)..' studs'
 end
 local function targets()
  local list={}
  if c.aimPlayer then for _,p in ipairs(game.Players:GetPlayers())do if p~=player and p.Character then list[#list+1]=p.Character end end end
  return list
 end
 connect(game:GetService('RunService').RenderStepped,function()
  aimPart=nil;aimPosition=nil
  if retreating or not(c.aimPlayer)then return end
  local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local tool=char and char:FindFirstChildOfClass('Tool');local camera=workspace.CurrentCamera
  if not root or not tool or not camera then return end
  local best,dist
  for _,v in ipairs(targets())do
   local h=v:FindFirstChildOfClass('Humanoid');local p=anchor(v)
   if h and h.Health>0 and p then local d=(p.Position-root.Position).Magnitude;if d<500 and (not dist or d<dist)then best=p;dist=d end end
  end
  aimPart=best;aimPosition=best and best.Position
  if best then local pos=tool:FindFirstChild('MousePos');if pos and pos:IsA('Vector3Value')then pos.Value=best.Position end end
 end)
 -- One reusable hook; scope changes to the equipped tool and native gun shots.
 local aimEnv=getgenv()
 local aimOwner={}
 aimEnv.NexoAimOwner=aimOwner
 local shotRemote=game.ReplicatedStorage.Modules.Net:FindFirstChild('RE/ShootGunEvent')
 aimEnv.NexoAimRewrite=function(remote,args)
  -- No Instance method calls here: they can change the pending namecall method.
  if not alive or retreating or not aimPosition or not aimPart or not(c.aimPlayer)then return end
  if remote==shotRemote and typeof(args[1])=='Vector3' then
   args[1]=aimPosition
   if type(args[2])=='table' then args[2]={aimPart} end
  end
  -- Skill arguments remain untouched. Supported tools aim through MousePos above.
 end
 if not aimEnv.NexoAimHookInstalled and type(hookmetamethod)=='function' and type(getnamecallmethod)=='function' and type(checkcaller)=='function' then
  local previous
  previous=hookmetamethod(game,'__namecall',newcclosure(function(remote,...)
   local args=table.pack(...)
   local method=getnamecallmethod()
   if not checkcaller() and (method=='FireServer' or method=='InvokeServer') and aimEnv.NexoAimRewrite then
    pcall(aimEnv.NexoAimRewrite,remote,args)
   end
   if type(setnamecallmethod)=='function' then setnamecallmethod(method) end
   return previous(remote,table.unpack(args,1,args.n))
  end))
  aimEnv.NexoAimHookInstalled=true
 end
 task.spawn(function()
  while alive do
   task.wait(.5)
   loadTeamButton.Text=preferences.autoLoadTeam or 'Marines'
   for _,r in ipairs(toggleRows)do r.button.Text=r.get() and 'ON' or 'OFF' end
   local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart');local h=char and char:FindFirstChildOfClass('Humanoid')
   if root then
    local seen={}
    if c.players then for _,p in ipairs(game.Players:GetPlayers())do if p~=player and p.Character then mark(p.Character,p.Name,'player',root.Position,seen)end end end
    if c.islands then local origin=workspace:FindFirstChild('_WorldOrigin');local f=origin and origin:FindFirstChild('Locations');if f then for _,v in ipairs(f:GetChildren())do mark(v,v.Name,'island',root.Position,seen)end end end
    if c.fruit then for _,v in ipairs(workspace:GetChildren())do if v.Name:lower():find('fruit',1,true)then mark(v,v.Name,'fruit',root.Position,seen)end end end
    if c.berry then local map=workspace:FindFirstChild('Map');if map then for _,v in ipairs(map:GetDescendants())do if v.Name:lower():find('bush',1,true)then for k,a in pairs(v:GetAttributes())do if type(a)=='string' and a:lower():find('berry',1,true)then mark(v,a,'berry',root.Position,seen);break end end end end end end
    for v,b in pairs(marks)do if not seen[v]then b:Destroy();marks[v]=nil end end
    if c.observation and not observationPending and player:GetAttribute('KenActive')~=true and os.clock()-lastObservation>3 and not game:GetService('UserInputService'):GetFocusedTextBox() then
     lastObservation=os.clock();observationPending=true
     task.spawn(function()
      local setID=setthreadidentity or setidentity;local getID=getthreadidentity or getidentity;local oldID=getID and getID() or 2
      local input=game:GetService('VirtualInputManager')
      local ok,err=pcall(function()
       if setID then setID(8)end
       input:SendKeyEvent(true,Enum.KeyCode.E,false,game);task.wait(.08)
       input:SendKeyEvent(false,Enum.KeyCode.E,false,game)
      end)
      pcall(function()input:SendKeyEvent(false,Enum.KeyCode.E,false,game)end)
      if setID then pcall(setID,oldID)end
      observationPending=false
      if not ok then warn('Nexo observation: '..tostring(err))end
     end)
    end
    if c.retreat and not retreating and h and h.Health>0 and h.Health/h.MaxHealth<=c.percent/100 then
     local destination=root.Position+Vector3.new(0,c.height,0);retreating=true
     task.spawn(function()
      local ok,err=pcall(function()
       preferences.StopAll();c.retreat=true;retreatToken=farm.SeaBegin()
       local t=retreatToken
       if not farm.SeaMove(destination,t,function()return c.retreat end)then return end
       while alive and c.retreat and farm.SeaActive(t) and player.Character==char and h.Parent and h.Health>0 and h.Health/h.MaxHealth<.8 do
        farm.SeaHold(destination,t)
        task.wait(.1)
       end
      end)
      if retreatToken then farm.SeaEnd(retreatToken);retreatToken=nil end
      c.retreat=false;retreating=false
      if not ok then warn('Nexo retreat: '..tostring(err))end
     end)
    end
   end
  end
 end)
 local hiddenObservation={}
 local lighting=game:GetService('Lighting')
 local function restoreObservation()
  for effect,enabled in pairs(hiddenObservation)do
   if effect.Parent then effect.Enabled=player:GetAttribute('KenActive')==true and enabled or false end
  end
  hiddenObservation={}
 end
 local function suppressObservation()
  if not c.hideObservation then restoreObservation();return end
  if player:GetAttribute('KenActive')~=true then restoreObservation();return end
  local blur=lighting:FindFirstChild('Blur')
  local correction=lighting:FindFirstChild('ColorCorrection')
  for _,effect in pairs({blur,correction})do
   if effect and effect:IsA('PostEffect') then
    if hiddenObservation[effect]==nil then hiddenObservation[effect]=effect.Enabled end
    if effect.Enabled then hiddenObservation[effect]=true;effect.Enabled=false end
   end
  end
 end
 connect(game:GetService('RunService').RenderStepped,suppressObservation)
 local previousStop=preferences.StopAll
 preferences.StopAll=function()
  for _,key in ipairs({'fruit','players','berry','islands','aimPlayer','observation','hideObservation','retreat'})do c[key]=false end
  restoreObservation();clear();if retreatToken then farm.SeaEnd(retreatToken);retreatToken=nil end
  return previousStop()
 end
 local previousCleanup=beforeCleanup;beforeCleanup=function()restoreObservation();if aimEnv.NexoAimOwner==aimOwner then aimEnv.NexoAimRewrite=nil;aimEnv.NexoAimOwner=nil end;clear();if retreatToken then farm.SeaEnd(retreatToken)end;if previousCleanup then previousCleanup()end end
end

-- Friends share the boat roster; each account controls only its own character.
do
 local panel=panels['Sea Event'];local shift=246
 for _,child in ipairs(panel:GetChildren()) do
  if child:IsA('GuiObject') and child.Name~='LeviStatus' and child.Position.Y.Offset>=870 then child.Position=child.Position+UDim2.fromOffset(0,68) end
 end
 panel.CanvasSize=panel.CanvasSize+UDim2.fromOffset(0,68)
 for _,child in ipairs(panel:GetChildren()) do
  if child:IsA('GuiObject') and child.Position.Y.Offset>=224 then child.Position=child.Position+UDim2.fromOffset(0,shift) end
 end
 panel.CanvasSize=panel.CanvasSize+UDim2.fromOffset(0,shift)
 local function row(text,y) label(panel,text,16,y,224,28,12);return control(panel,'',244,y,252,28) end
 local start=row('Auto Sea Event with Friends',224)
 local count=row('Players including driver',258)
 local role=row('My role',292)
 local owner=row('Boat owner / Driver',326)
 local members=row('Choose group members',360)
 local refreshList=row('Refresh player list',394);refreshList.Text='REFRESH'
 local note=label(panel,'Use the same roster, owner and events on every account.',16,428,480,36,11);note.TextWrapped=true
 local names,ids={},{}
 local function refreshRoster()
  names={};ids={}
  for _,p in ipairs(game:GetService('Players'):GetPlayers()) do table.insert(names,p.Name);ids[p.Name]=p.UserId end
  table.sort(names)
 end
 refreshRoster()
 local function paint()
  local c=sea.group
  start.Text=c.enabled and sea.enabled and not sea.searchIsland and 'ON' or 'OFF'
  count.Text=tostring(c.count)..'  ▾';role.Text=c.role..'  ↔'
  local p=game:GetService('Players'):GetPlayerByUserId(c.owner);owner.Text=(p and p.Name or tostring(c.owner))..'  ▾'
  local n=0;for _,v in pairs(c.members) do if v then n=n+1 end end
  if n>=2 and n<=5 then c.count=n;count.Text=tostring(n)..'  ▾' end
  members.Text=n..' selected  ▾'
  note.Text=c.enabled and sea.enabled and sea.message or (sea.message~='Off' and sea.message or 'Select 2–5 members. The player count follows your selection.')
 end
 local function edit() if sea.group.enabled and sea.enabled then sea.SetEnabled(false) end end
 bindControl(count,'Activated',function() picker('Select 2–5 group members',names,function(v)return sea.group.members[tostring(ids[v])] end,function(v) edit();local k=tostring(ids[v]);local n=0;for _,on in pairs(sea.group.members) do if on then n=n+1 end end;if not sea.group.members[k] and n>=5 then return end;sea.group.members[k]=not sea.group.members[k] or nil;paint() end,true) end)
 bindControl(role,'Activated',function() edit();sea.group.role=sea.group.role=='Driver' and 'Passenger' or 'Driver';if sea.group.role=='Driver' then sea.group.owner=player.UserId end;paint() end)
 bindControl(owner,'Activated',function() picker('Boat owner / Driver',names,function(v) return sea.group.owner==ids[v] end,function(v) edit();sea.group.owner=ids[v];paint() end,false) end)
 bindControl(members,'Activated',function() picker('Choose all players, including yourself',names,function(v) return sea.group.members[tostring(ids[v])] end,function(v) edit();local k=tostring(ids[v]);local n=0;for _,on in pairs(sea.group.members) do if on then n=n+1 end end;if not sea.group.members[k] and n>=5 then return end;sea.group.members[k]=not sea.group.members[k] or nil;paint() end,true) end)
 bindControl(refreshList,'Activated',function() refreshRoster();paint() end)
 bindControl(start,'Activated',function()
  if sea.group.enabled and sea.enabled then sea.SetEnabled(false);sea.group.enabled=false
  else
   sea.SetEnabled(false)
   if preferences.Leviathan then preferences.Leviathan.Stop() end
   if preferences.Volcano then preferences.Volcano.Stop() end
   local ok=true;if sea.BeforeIslandSearch then ok=sea.BeforeIslandSearch() end
   if ok then sea.searchIsland=nil;sea.group.enabled=true;if not sea.SetEnabled(true) then sea.group.enabled=false end end
  end
  paint()
 end)
 task.spawn(function() while alive do paint();task.wait(.25) end end)
 paint()
end

-- Raid controls use the game's current raid catalogue and native purchase/awakening requests.
do
 local raidSeaByPlace={[4442272183]=2,[79091703265657]=2,[7449423635]=3,[100117331123089]=3}
 local raidSea=raidSeaByPlace[game.PlaceId]
 local panel=panels['Raid + Fruit'];panel.CanvasSize=UDim2.fromOffset(0,350)
 preferences.raid=preferences.raid or {selected='Flame',start=false,unstore=false,awaken=false}
 local rs=game:GetService('ReplicatedStorage');local cfg=preferences.raid
 local function row(text,y) label(panel,text,18,y,285,28,13);line(panel,y+34);return control(panel,'OFF',334,y,156,28) end
 local choose=row('Select Raid',10)
 local start=row('Start Raid',50)
 local unstore=row('Unstore Low Fruit',90)
 local awaken=row('Auto Awaken Fruit',130)
 local status=label(panel,'',18,286,475,58,12);status.TextWrapped=true
 local options={};pcall(function() local data=require(rs.Raids);for _,list in ipairs({data.raids,data.advancedRaids}) do for _,name in ipairs(list) do table.insert(options,name) end end end)
 local raidWaitPosition;local serial=0;local token;local nextBuy=0;local nextUnstore=0;local nextAwaken=0;local nextStart=0;local currencyAttempted=false;local advanced={Phoenix=true,Dough=true}
 local function release() raidWaitPosition=nil;if token then if farm.raidCombatToken==token then farm.raidCombatToken=nil end;farm.SeaEnd(token);token=nil end end
 local function stop() serial=serial+1;cfg.start=false;cfg.unstore=false;cfg.awaken=false;farm.raidFruitReservation=false;release() end
 preferences.RaidFruit={Stop=stop}
 local function paint() choose.Text=cfg.selected..'  ▾';start.Text=cfg.start and 'ON' or 'OFF';unstore.Text=cfg.unstore and 'ON' or 'OFF';awaken.Text=cfg.awaken and 'ON' or 'OFF' end
 bindControl(choose,'Activated',function()picker('Choose Raid',options,function(v)return cfg.selected==v end,function(v)cfg.selected=v;nextBuy=0;currencyAttempted=false;paint();task.defer(preferences.Flush)end,false)end)
 for _,pair in ipairs({{start,'start'},{unstore,'unstore'},{awaken,'awaken'}}) do bindControl(pair[1],'Activated',function()
  serial=serial+1;cfg[pair[2]]=not cfg[pair[2]];release()
  if not cfg.unstore then farm.raidFruitReservation=false end
  paint();task.defer(preferences.Flush)
 end) end
 local function call(id,...)
  local args=table.pack(...);local done=false;local ok,value
  task.spawn(function()ok,value=pcall(rs.Remotes.CommF_.InvokeServer,rs.Remotes.CommF_,table.unpack(args,1,args.n));done=true end)
  local untilTime=os.clock()+10
  repeat task.wait(.1) until done or not alive or id~=serial or os.clock()>untilTime
  if not alive or id~=serial then return nil end
  if not done or not ok then error('Request unconfirmed; toggles stopped to avoid repeated purchases') end
  return value
 end
 local allowed={Common=true,Uncommon=true,Rare=true}
 local function physical()
  local fruits={};local chip
  for _,bag in pairs({player.Character,player:FindFirstChild('Backpack')}) do for _,t in ipairs(bag:GetChildren()) do if t:IsA('Tool') then
   if t.Name=='Special Microchip' then chip=t elseif t.Name:match(' Fruit$') then table.insert(fruits,t) end
  end end end
  return fruits,chip
 end
 local function eligible(t)
  local base=t.Name:gsub(' Fruit$','');local ok,info=pcall(function()return require(rs.FruitInfo).tryGet(base..'-'..base)end)
  return ok and info and info.Rarity and allowed[info.Rarity.Name]==true
 end
 local function candidate()
  local rep=require(rs.ItemReplicationService);local catalog=require(rs.ItemConfig);if not rep.IsInitialized then return end
  local best
  for _,item in pairs(rep:GetItems(rep.KEYS.QUANTITY) or {}) do if type(item.Value)=='number' and item.Value>0 then
   local result=catalog.match(item.ItemId)
   if result:isOk() then local info=result:unwrap();local q=info.Quality
    if info.State and info.State.EquipMethod=='LoadFruit' and q and allowed[q.Rarity] and type(q.MoneyPrice)=='number' and q.MoneyPrice>0 and info.Index and info.Index.StorageKey then
     local price=tonumber(q.MoneyPrice) or math.huge
     if not best or price<best.price then best={key=info.Index.StorageKey,price=price} end
    end
   end
  end end
  return best
 end
 local function inRaid()
  local pg=player:FindFirstChild('PlayerGui');local main=pg and pg:FindFirstChild('Main');local timer=main and main:FindFirstChild('Timer')
  return player:GetAttribute('IslandRaiding')==true or (timer and timer:IsA('GuiObject') and timer.Visible)
 end
 local raidTarget;local raidTargetHP;local raidDamageAt=0;local raidLastSeen
 local function fightRaid(id)
  if not token or not farm.SeaActive(token) then
   if sea.BeforeIslandSearch then local ok,message=sea.BeforeIslandSearch();if not ok then status.Text=message;return end end
   if preferences.Leviathan then preferences.Leviathan.Stop() end
   if preferences.Volcano then preferences.Volcano.Stop() end
   sea.SetEnabled(false);token=farm.SeaBegin()
  end
  farm.raidCombatToken=token
  local char=player.Character;local hum=char and char:FindFirstChildOfClass('Humanoid');local root=char and char:FindFirstChild('HumanoidRootPart')
  if not root or not hum or hum.Health<=0 then release();status.Text='Waiting for respawn';return end
  local world=workspace:FindFirstChild('_WorldOrigin');local locations=world and world:FindFirstChild('Locations')
  local island,index
  if locations then for _,v in ipairs(locations:GetChildren()) do
   local n=tonumber(v.Name:match('^Island (%d+)$'))
   if n and v:IsA('BasePart') and (v.Position-root.Position).Magnitude<14000 and (not index or n>index) then island=v;index=n end
  end end
  if not island then
   raidWaitPosition=raidWaitPosition or root.Position
   status.Text='Waiting for raid island to load';farm.SeaHold(raidWaitPosition,token);return
  end
  raidWaitPosition=nil
  local enemy,enemyRoot,enemyHum,distance;local folder=workspace:FindFirstChild('Enemies')
  if folder then for _,e in ipairs(folder:GetChildren()) do
   local h=e:FindFirstChildOfClass('Humanoid');local r=e:FindFirstChild('HumanoidRootPart')
   if h and h.Health>0 and r and (r.Position-island.Position).Magnitude<1100 then
    local d=(r.Position-root.Position).Magnitude
    if not distance or d<distance then enemy=e;enemyRoot=r;enemyHum=h;distance=d end
   end
  end end
  -- Keep a living target instead of switching every time nearby enemies move.
  if raidTarget and raidTarget.Parent then
   local h=raidTarget:FindFirstChildOfClass('Humanoid');local r=raidTarget:FindFirstChild('HumanoidRootPart')
   if h and h.Health>0 and r and (r.Position-island.Position).Magnitude<1100 then enemy=raidTarget;enemyRoot=r;enemyHum=h end
  end
  if enemy then
   status.Text='Island '..index..' · '..enemy.Name
   if raidTarget~=enemy then raidTarget=enemy;raidTargetHP=enemyHum.Health;raidDamageAt=os.clock() end
   if enemyHum.Health<raidTargetHP then raidDamageAt=os.clock() end;raidTargetHP=enemyHum.Health
   farm.SeaHover(enemyRoot,token,farm.weapon=='Demon Fruit' and 3 or farm.weapon=='Gun' and 30 or 12,false)
   local ok,message=farm.SeaAttack(enemy,token)
   if not ok and message then status.Text='Island '..index..' · '..message end
   if os.clock()-raidDamageAt>12 then status.Text='No damage confirmed; check the selected farming weapon' end
  else
   raidTarget=nil
   local destination=island.Position+Vector3.new(0,30,0)
   if (root.Position-destination).Magnitude>70 then
    status.Text='Moving to raid island '..index
    farm.SeaMove(destination,token,function()return cfg.start and id==serial and inRaid()end)
   else farm.SeaHold(destination,token);status.Text='Island '..index..' · waiting for enemies / next island' end
  end
 end
 local function step(id)
  if not raidSea then release();farm.raidFruitReservation=false;status.Text='Raids require Sea 2 or Sea 3';return end
  if cfg.awaken and os.clock()>=nextAwaken then
   nextAwaken=os.clock()+4;local offer=call(id,'Awakener','Check');if id~=serial then return end
   if type(offer)=='table' and tonumber(offer.Cost) and offer.Awakened~=true then
    release()
    local data=player:FindFirstChild('Data');local fragments=data and data:FindFirstChild('Fragments')
    if fragments and fragments.Value>=tonumber(offer.Cost) then
     nextAwaken=os.clock()+15;local result=call(id,'Awakener','Awaken')
     status.Text=result==1 and ('Awakened '..tostring(offer.Key)) or 'Awakening not confirmed'
    else status.Text='Not enough fragments to awaken' end
    return
   end
  end
  -- The raid already joined always takes priority over the next selected raid.
  if inRaid() then
   raidLastSeen=os.clock();farm.raidFruitReservation=false
   if cfg.start then fightRaid(id) else release();status.Text='Raid active' end
   return
  end
  if raidLastSeen then
   if token then release() end
   if os.clock()-raidLastSeen<5 then status.Text='Waiting for current raid to finish';return end
   raidLastSeen=nil;raidTarget=nil;currencyAttempted=false
  end
  if token then release() end
  if inRaid() then return end
  local fruits,chip=physical()
  if chip then currencyAttempted=false end
  if cfg.unstore and not advanced[cfg.selected] and not chip and #fruits==0 and os.clock()>=nextUnstore and not farm.trevorFruitReservation then
   nextUnstore=os.clock()+30;local item=candidate()
   if item then
    farm.raidFruitReservation=true;status.Text='Unstoring '..item.key
    call(id,'LoadFruit',item.key)
    if not alive or id~=serial then return end
    local deadline=os.clock()+2
    repeat
     fruits,chip=physical()
     if #fruits>0 or chip or inRaid() then break end
     task.wait(.05)
    until not alive or id~=serial or os.clock()>=deadline
    if not alive or id~=serial or inRaid() then return end
    nextBuy=0
    if not chip and #fruits==0 then status.Text='Waiting for unstored fruit to appear';return end
   else status.Text='No Common, Uncommon or Rare fruit in storage' end
  end
  if cfg.start and not chip and not currencyAttempted and #fruits==0 then
   if os.clock()<nextBuy then return end
   local data=player:FindFirstChild('Data');local level=data and data:FindFirstChild('Level')
   if not level or level.Value<1100 then status.Text='Level 1100 required to buy a raid chip';return end
   -- Select with an empty fruit backpack lets the server enforce the paid cooldown.
   status.Text=advanced[cfg.selected] and 'Trying 1,000 fragments for raid chip' or 'Trying $100,000 for raid chip'
   nextBuy=os.clock()+30
   local result=call(id,'RaidsNpc','Select',cfg.selected)
   if id~=serial then return end
   if result==1 then
    status.Text='Paid raid chip requested; waiting for inventory';return
   end
   currencyAttempted=true
   status.Text='Paid purchase unavailable: '..tostring(result)
   if advanced[cfg.selected] then currencyAttempted=false;status.Text='Advanced raid: waiting for paid availability; valuable fruits protected' end
   return
  end
  if not cfg.start then return end
  if not chip then
   if farm.trevorFruitReservation then status.Text='Waiting: fruit reserved for Trevor';return end
   for _,t in ipairs(fruits) do if not eligible(t) then status.Text='Raid purchase paused: protected or unknown fruit in backpack';return end end
   local data=player:FindFirstChild('Data');local level=data and data:FindFirstChild('Level')
   if not level or level.Value<1100 then status.Text='Level 1100 required to buy a raid chip';return end
   if os.clock()<nextBuy then return end
   if #fruits==0 then currencyAttempted=false;return end
   nextBuy=os.clock()+30;farm.raidFruitReservation=cfg.unstore or #fruits>0
   local result=call(id,'RaidsNpc','Select',cfg.selected)
   if id~=serial then return end
   local _,found=physical()
   status.Text=found and 'Raid chip ready' or ('Chip not confirmed: '..tostring(result));return
  end
  farm.raidFruitReservation=false
  if os.clock()<nextStart then return end
  nextStart=os.clock()+8
  local function findButton()
   local map=workspace:FindFirstChild('Map')
   if map then for _,v in ipairs(map:GetDescendants()) do
    if v:IsA('ClickDetector') and v:GetFullName():lower():find('raidsummon',1,true) then return v end
   end end
  end
  local detector=findButton()
  if not detector then
   status.Text='Loading raid button remotely'
   local destination=raidSea==3 and Vector3.new(-5004.12,314.56,-3002.59) or Vector3.new(-6214.01,81.86,-4932.27)
   pcall(function()player:RequestStreamAroundAsync(destination,5)end)
   if not alive or id~=serial or not cfg.start then return end
   detector=findButton()
  end
  if not detector then
   status.Text='Remote button unavailable; travelling to raid area'
   if sea.BeforeIslandSearch then local ok,message=sea.BeforeIslandSearch();if not ok then status.Text=message;return end end
   if preferences.Leviathan then preferences.Leviathan.Stop() end
   if preferences.Volcano then preferences.Volcano.Stop() end
   sea.SetEnabled(false)
   token=farm.SeaBegin()
   local destination=raidSea==3 and Vector3.new(-5004.12,314.56,-3002.59) or Vector3.new(-6214.01,81.86,-4932.27)
   farm.SeaMove(destination,token,function()return alive and id==serial and cfg.start and not inRaid()end)
   if not alive or id~=serial or not cfg.start or inRaid() then return end
   detector=findButton()
  end
  if not detector or not detector.Parent:IsA('BasePart') then status.Text='Waiting for raid button to load';return end
  if type(fireclickdetector)~='function' then status.Text='This executor cannot activate the raid button';return end
  if sea.BeforeIslandSearch then local ok,message=sea.BeforeIslandSearch();if not ok then status.Text=message;return end end
  if preferences.Leviathan then preferences.Leviathan.Stop() end
  if preferences.Volcano then preferences.Volcano.Stop() end
  sea.SetEnabled(false)
  if id==serial and cfg.start and not inRaid() then
   fireclickdetector(detector,0);status.Text='Remote raid start requested; waiting for confirmation'
   local deadline=os.clock()+3
   repeat task.wait(.1) until not alive or id~=serial or inRaid() or os.clock()>=deadline
   if alive and id==serial and cfg.start then
    if inRaid() then status.Text='Raid started'
    elseif detector.Parent then
     status.Text='Remote start unconfirmed; approaching raid button'
     if not token or not farm.SeaActive(token) then token=farm.SeaBegin() end
     farm.SeaMove(detector.Parent.Position+Vector3.new(0,3,0),token,function()return alive and id==serial and cfg.start and not inRaid()end)
     if alive and id==serial and cfg.start and not inRaid() then
      fireclickdetector(detector,0);status.Text='Raid start requested at button'
     end
    end
   end
  end
 end
 local previous=beforeCleanup;beforeCleanup=function()stop();if previous then previous() end end
 task.spawn(function()
  local setID=setthreadidentity or setidentity;if setID then setID(2) end
  while alive do
   if preferenceReady then
    paint()
    if cfg.start or cfg.unstore or cfg.awaken then
     local id=serial;local ok,err=pcall(step,id)
     if not ok then stop();status.Text=tostring(err);paint() end
    end
   end
   task.wait(cfg.start and (inRaid() and .04 or .2) or 1)
  end
 end)
end

-- Collect an already-visible Blue Gear; no moon, race ability, or camera control.
do
 local panel=panels['Sea Event'];local y=mirageToggle.Position.Y.Offset+34
 for _,v in ipairs(panel:GetChildren()) do if v:IsA('GuiObject') and v.Position.Y.Offset>=y then v.Position=v.Position+UDim2.fromOffset(0,66) end end
 panel.CanvasSize=panel.CanvasSize+UDim2.fromOffset(0,66)
 label(panel,'Collect Blue Gear',16,y,224,28,12)
 local toggle=control(panel,'OFF',244,y,252,28)
 local note=label(panel,'',16,y+30,480,30,11);note.TextWrapped=true
 local token
 local function stop()
  preferences.collectBlueGear=false
  if token then farm.SeaEnd(token);token=nil end
 end
 preferences.BlueGear={Stop=stop}
 bindControl(toggle,'Activated',function()
  if preferences.collectBlueGear then stop() else preferences.collectBlueGear=true end
  toggle.Text=preferences.collectBlueGear and 'ON' or 'OFF';task.defer(preferences.Flush)
 end)
 local function findGear()
  local map=workspace:FindFirstChild('Map')
  for _,parent in pairs({map,workspace}) do for _,model in ipairs(parent:GetChildren()) do
   local n=model.Name:lower():gsub('[^%a]','')
   if (n=='mysticisland' or n=='mirageisland') and model:IsA('Model') then
    for _,v in ipairs(model:GetDescendants()) do
     local name=v.Name:lower():gsub('[^%a]','')
     local gearMesh=v:IsA('MeshPart') and v.MeshId:match('%d+')=='10153114969'
     if name=='bluegear' or name=='gear' or gearMesh then
      local p=v:IsA('BasePart') and v or v:FindFirstChildWhichIsA('BasePart',true)
      if p and p.Transparency<1 then return p,model end
     end
    end
   end
  end end
 end
 local function step()
  if game.PlaceId~=7449423635 and game.PlaceId~=100117331123089 then note.Text='Requires Third Sea';return end
  local target,island=findGear()
  if not target then if token then farm.SeaEnd(token);token=nil end;note.Text='Waiting for visible Blue Gear';return end
  if token and not farm.SeaActive(token) then stop();note.Text='Stopped: another task took control';return end
  if not token then
   local ok,message=sea.BeforeIslandSearch();if not ok then note.Text=message;return end
   sea.SetEnabled(false);token=farm.SeaBegin()
  end
  note.Text='Collecting Blue Gear'
  if not farm.SeaMove(target.Position,token,function()return alive and preferences.collectBlueGear and target.Parent~=nil and target.Transparency<1 end) then return end
  local char=player.Character;local root=char and char:FindFirstChild('HumanoidRootPart')
  if not root or not target.Parent or not preferences.collectBlueGear then return end
  if type(firetouchinterest)=='function' then pcall(firetouchinterest,root,target,0);task.wait(.1);pcall(firetouchinterest,root,target,1) end
  farm.SeaHold(root.Position,token);task.wait(.5)
  if island.Parent and (not target.Parent or target.Transparency>=1) then
   stop();note.Text='Gear touched; check your V4 progress';preferences.Flush()
  else note.Text='Gear touch not confirmed; retrying' end
 end
 local oldCleanup=beforeCleanup;beforeCleanup=function()stop();if oldCleanup then oldCleanup() end end
 task.spawn(function()
  while alive do
   toggle.Text=preferences.collectBlueGear and 'ON' or 'OFF'
   if preferenceReady and preferences.collectBlueGear then
    local ok,err=pcall(step);if not ok then stop();note.Text='Stopped: '..tostring(err) end
   end
   task.wait(.5)
  end
 end)
end


-- One reference scale for the entire royal shell, including logo halves.
mobileLayout=function()end
fit=function()
 local v=gui.AbsoluteSize
 scale.Scale=math.max(.1,math.min(v.X/1280,v.Y/720))
 menuHeight=460
end
fit()
root.Position=UDim2.fromOffset(80,220);root.Size=UDim2.fromOffset(960,720)
local function tween(o,t,props)
 local a=TweenService:Create(o,TweenInfo.new(t,Enum.EasingStyle.Cubic,Enum.EasingDirection.InOut),props);tweens[a]=true
 a.Completed:Once(function()tweens[a]=nil end);a:Play();return a
end
top.AnchorPoint=Vector2.new(.5,1);bottom.AnchorPoint=Vector2.new(.5,0)
top.Position=UDim2.fromScale(.5,.5);bottom.Position=UDim2.fromScale(.5,.5)
top.Size=UDim2.fromOffset(80,40);bottom.Size=UDim2.fromOffset(80,40)
for _,b in ipairs({top,bottom})do
 b.ZIndex=30
 local image=b:FindFirstChildOfClass('ImageLabel');image.Size=UDim2.new(1,0,2,0);image.Position=b==top and UDim2.fromScale(0,0)or UDim2.fromScale(0,-1);image.ZIndex=30
end
dock.Size=UDim2.fromOffset(86,86);dock.ZIndex=31
menu.Size=UDim2.fromOffset(576,9);menu.GroupTransparency=1
local closedPosition=root.Position
local function setOpen(value)
 if introRunning or not alive or busy or opened==value then return end
 busy=true;opened=value;dock.Visible=false
 task.spawn(function()
  local ok,err=xpcall(function()
   if value then
    closedPosition=root.Position
    tween(logoScale,.18,{Scale=0});task.wait(.18);if not alive then return end
    root.Position=UDim2.fromScale(.5,.5)
    tween(logoScale,.24,{Scale=1.12});task.wait(.24);if not alive then return end
    tween(logoScale,.12,{Scale=1});task.wait(.12);if not alive then return end
   end
   tween(top,.55,{Position=UDim2.new(.5,0,.5,value and -230 or 0),Size=value and UDim2.fromOffset(280,154)or UDim2.fromOffset(80,40)})
   tween(bottom,.55,{Position=UDim2.new(.5,0,.5,value and 230 or 0),Size=value and UDim2.fromOffset(280,154)or UDim2.fromOffset(80,40)})
   if value then task.wait(.45);if not alive then return end;menu.Visible=true end
   tween(menu,.4,{Size=value and UDim2.fromOffset(960,460)or UDim2.fromOffset(576,9)})
   tween(menu,.3,{GroupTransparency=value and 0 or 1})
   task.wait(value and .4 or .55)
   if not value and alive then
    menu.Visible=false
    tween(logoScale,.18,{Scale=0});task.wait(.18);if not alive then return end
    root.Position=closedPosition
    tween(logoScale,.24,{Scale=1.1});task.wait(.24);if not alive then return end
    tween(logoScale,.12,{Scale=1});task.wait(.12)
   end
  end,debug.traceback)
  if not alive then return end
  menu.Visible=opened;menu.Size=opened and UDim2.fromOffset(960,460)or UDim2.fromOffset(576,9);menu.GroupTransparency=opened and 0 or 1
  top.Position=UDim2.new(.5,0,.5,opened and -230 or 0);bottom.Position=UDim2.new(.5,0,.5,opened and 230 or 0)
  top.Size=opened and UDim2.fromOffset(280,154)or UDim2.fromOffset(80,40);bottom.Size=top.Size
  logoScale.Scale=1;busy=false;dock.Visible=not opened
  if not ok then warn('Nexo Royal animation: '..tostring(err))end
 end)
end

local drag,origin,start,moved,releasedAt=nil,nil,nil,false,0
local function begin(input)
 if busy then return end
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
  drag=input;origin=input.Position;start=root.Position;moved=false
 end
end
connect(dock.InputBegan,begin);connect(header.InputBegan,begin)
connect(Input.InputChanged,function(input)
 if not drag or (input.UserInputType~=Enum.UserInputType.MouseMovement and input~=drag) then return end
 local delta=input.Position-origin;if delta.Magnitude>5 then moved=true end
 if moved then
  local v=gui.AbsoluteSize;local mx=opened and 490*scale.Scale or 44*scale.Scale;local my=opened and 351*scale.Scale or 44*scale.Scale
  root.Position=UDim2.fromOffset(math.clamp(start.X.Scale*v.X+start.X.Offset+delta.X,mx,math.max(mx,v.X-mx)),math.clamp(start.Y.Scale*v.Y+start.Y.Offset+delta.Y,my,math.max(my,v.Y-my)))
 end
end)
connect(Input.InputEnded,function(input) if input==drag then drag=nil;if moved then releasedAt=os.clock() end end end)
bindControl(dock,'Activated',function() if not moved and os.clock()-releasedAt>.15 then setOpen(true) end end)
bindControl(top,'Activated',function() setOpen(false) end);bindControl(bottom,'Activated',function() setOpen(false) end)
connect(Input.InputBegan,function(input,processed) if not processed and not Input:GetFocusedTextBox() and input.KeyCode==Enum.KeyCode.RightShift then setOpen(not opened) end end)
local sound=make('Sound',game:GetService('SoundService'),{Name='NexoStartup',SoundId=env.NexoStartupAsset or 'rbxassetid://119795837423892',Volume=.55,Looped=false})
local function cleanup()
 if not alive then return end;if beforeCleanup then pcall(beforeCleanup) end;alive=false;sea.Destroy();farm.Destroy();stats.Destroy()
 for _,c in ipairs(connections) do c:Disconnect() end
 for a in pairs(tweens) do a:Cancel() end
 sound:Stop();sound:Destroy();gui:Destroy()
end
local shutdown=make('BindableEvent',gui,{Name='NexoShutdown'})
connect(shutdown.Event,cleanup)
connect(host:GetAttributeChangedSignal('NexoFarmRunId'),function() if host:GetAttribute('NexoFarmRunId')~=runId then cleanup() end end)
connect(gui.Destroying,cleanup)
env.NexoFarmUI={Farm=farm,Sea=sea,Stats=stats,Travel=travelAPI,Preferences=preferences,ShowSection=showSection,Destroy=cleanup,SetOpen=setOpen,Status=function() return {alive=alive,busy=busy,opened=opened,soundLoaded=sound.IsLoaded} end}

do
 local function sectionOf(o)
  local cursor=o
  while cursor do
   for name,panel in pairs(panels) do if cursor==panel then return name end end
   local record=bindingObjects[cursor];cursor=record and record.parent or cursor.Parent
  end
 end
 local records={}
 for object,r in pairs(bindingObjects) do
  if object:IsA('TextButton') or object:IsA('TextBox') or object:IsA('TextLabel') then
   local section=sectionOf(object)
   if section then
    local title=r.title or r.text
    records[#records+1]={node=object,section=section,title=title,original=r.text,x=r.x,y=r.y,parent=r.parent.Name,class=object.ClassName}
   end
  end
 end
 table.sort(records,function(a,b)if a.section~=b.section then return a.section<b.section end;if a.y~=b.y then return a.y<b.y end;return a.x<b.x end)
 local function invoke(node,event,...)
  assert(node and node.Parent,'Control no longer exists')
  local events=bindingHandlers[node];local list=events and events[event or 'Activated'];assert(list and #list>0,'Control has no handler')
  for _,fn in ipairs(list) do fn(...) end
 end
 local api=env.NexoFarmUI
 api.MenuBackend={Records=records,Invoke=invoke,Ready=function()return alive and preferenceReady end,Picker=function(node)
  bindingPicker=nil;capturePicker=true
  local ok,err=pcall(invoke,node,'Activated');capturePicker=false
  if not ok then error(err)end
  return bindingPicker
 end}
 api.MenuBackend.CloseOld=function()gui.Enabled=false end
 introRunning=false;root.Visible=false
end
]========]
assert(loadstring(core,'NexoBackend'))()
local backendUI=getgenv().NexoFarmUI
assert(backendUI and backendUI.MenuBackend,'Nexo backend did not finish loading')
local backend=backendUI.MenuBackend
getgenv().NexoMenuSyncError=nil
local f,s,p,t=backendUI.Farm,backendUI.Sea,backendUI.Preferences,backendUI.Travel
local function norm(v)return tostring(v or ''):lower():gsub('[^%w]','')end
local function notice(message)
 warn('Nexo menu: '..tostring(message))
 pcall(function()game:GetService('StarterGui'):SetCore('SendNotification',{Title='NEXO',Text=tostring(message):sub(1,180),Duration=5})end)
end
local function guard(fn,...)
 if not backend.Ready()then notice('Waiting for saved settings to load');return false end
 local ok,result=pcall(fn,...);if not ok then notice(result)end;return ok,result
end
local function find(section,name,class,occurrence,original)
 local list={}
 for _,r in ipairs(backend.Records)do
  if r.section==section and norm(r.title)==norm(name) and r.class==class and (not original or r.original==original)then list[#list+1]=r end
 end
 return list[occurrence or 1],list
end
local function readOn(r)return r and (r.node.Text=='ON' or r.node.Text=='✓'or r.node.Text=='បើក') or false end
local function selectedText(v)return tostring(v):gsub('%s*[▾↔].*$',''):gsub('^Zone%s+','')end
local function binding(get,set)return {get=get,set=set}end
local function flush()task.defer(p.Flush)end
local function direct(owner,key,convert)
 return binding(function()return owner[key]end,function(v)owner[key]=convert and convert(v) or v;flush()end)
end
local feedbackSerial={}
local function actionFeedback(section)
 feedbackSerial[section]=(feedbackSerial[section]or 0)+1;local serial=feedbackSerial[section]
 local labels={};for _,r in ipairs(backend.Records)do if r.section==section and r.class=='TextLabel'and r.original==''then labels[r.node]=r.node.Text end end
 task.spawn(function()
  local untilTime=os.clock()+20;local last
  while backendUI.Status().alive and os.clock()<untilTime and feedbackSerial[section]==serial do
   task.wait(.35)
   for node,old in pairs(labels)do if node.Parent and node.Text~=old then
    labels[node]=node.Text
    if node.Text~=''and node.Text~=last then last=node.Text;notice(node.Text)end
   end end
  end
 end)
end
local function recordBinding(r,kind)
 if kind=='info'then return binding(function()return r.node.Text:gsub('^[^:]+:%s*',''),r.node.TextColor3 end)end
 if kind=='num'then return binding(function()return tonumber(r.node.Text)end,function(v)r.node.Text=tostring(v);backend.Invoke(r.node,'FocusLost',true)end)end
 if kind=='toggle'or kind=='hop'then return binding(function()return readOn(r)end,function(v)if readOn(r)~=v then backend.Invoke(r.node)end end)end
 if kind=='action'then return binding(function()return r.node.Text end,function()actionFeedback(r.section);backend.Invoke(r.node)end)end
 return binding(function()return selectedText(r.node.Text)end,function(value)
  if type(value)~='table'and selectedText(r.node.Text)==tostring(value)then return end
  local picker=backend.Picker(r.node)
  if picker then
   local found=false
   for _,option in ipairs(picker.choices)do
    local key=tostring(option);local plain=key:match('^(%S+)%s+%(')or key
    if picker.multi then
     local want=value[key]==true or value[plain]==true
     if (picker.selected(option)==true)~=want then picker.choose(option)end
     found=true
    elseif key==tostring(value) or plain==tostring(value)then picker.choose(option);found=true;break end
   end
   assert(found,'Selection is unavailable: '..tostring(value))
  elseif selectedText(r.node.Text)~=tostring(value)then backend.Invoke(r.node)end
 end)
end
local bridgeAudit={missing={},bindings={}}
local function resolveBinding(section,spec,kind,occurrence,group)
 local n=spec.n;local key=section..' / '..tostring(n)..' / '..kind..' / '..tostring(occurrence or 1)
 local function done(b)bridgeAudit.bindings[key]=b;return b end
 if kind=='info'then
  for _,r in ipairs(backend.Records)do
   if r.section==section and r.class=='TextLabel'and norm(r.title:match('^[^:]+')or r.title)==norm(n)then return done(recordBinding(r,kind))end
  end
 end
 if section=='Player'and n=='Stop All'then return done(binding(function()return 'Stop'end,p.StopAll))
 elseif section=='Player'and n=='Auto Stats'then
  return done(binding(function()local a={};for k,v in pairs(backendUI.Stats.selected)do a[k=='Demon Fruit'and 'Fruit'or k]=v end;return a end,function(values)for _,k in ipairs({'Melee','Defense','Sword','Gun','Demon Fruit'})do backendUI.Stats.Select(k,values[k=='Demon Fruit'and 'Fruit'or k]==true)end;flush()end))
 elseif section=='Player'and n=='Travel'then
  if kind=='toggle'then return done(binding(function()return t.Snapshot().active end,function(v)if v then t.Start()else t.Stop()end end))end
  return done(binding(function()local snap=t.Snapshot();for _,v in ipairs(t.Options())do if v.key==snap.key then return v.name end end end,function(value)
   local aliases={['kingdomofrosedock']='kingdomofrose',['middlehydra']='hydraisland',['castleonthesea']='castleofthesea',['whirlpool']='whirlpool',['skyland1']='lowersky',['skyland2']='skylands'}
   local wanted=norm(value);local match
   for _,v in ipairs(t.Options())do if norm(v.name)==wanted or norm(v.key)==wanted or norm(v.name)==aliases[wanted]then match=v;break end end
   assert(match,'Island is unavailable in this sea: '..value);t.Select(match.key)
  end))
 elseif section=='Player'and n=='Change Team'then
  return done(binding(function()local team=game.Players.LocalPlayer.Team;return team and team.Name end,function(v)local r=find(section,n,'TextButton',1,v);assert(r,'Team control unavailable');backend.Invoke(r.node)end))
 elseif section=='Farm Setting'and n=='Weapon'then return done(binding(function()return f.weapon end,f.SetWeapon))
 elseif section=='Farm Setting'and n=='Bring Mobs'and kind=='num'then return done(binding(function()return f.mobLimit end,f.SetMobLimit))
 elseif section=='Farm Setting'and n=='Skill Use'then
  return done(binding(function()return table.clone(f.skillUse.Fruit)end,function(v)for _,category in ipairs({'Fruit','Sword','Gun','Melee'})do for _,letter in ipairs({'Z','X','C','V','F'})do f.skillUse[category][letter]=v[letter]==true end end;flush()end))
 elseif section=='Farming'and n=='Farm Material'and kind=='select'then return done(binding(function()return f.material end,f.SelectMaterial))
 elseif section=='Sea Event'and n=='Players including driver'then return done(direct(s.group,'count',tonumber))
 elseif section=='Sea Event'and n=='Events'and kind=='select'then return done(binding(function()return table.clone(s.selected)end,function(v)s.selected=table.clone(v);flush()end))
 elseif section=='Sea Event'and n=='Choose group members'then
  return done(binding(function()local v={};for _,pl in ipairs(game.Players:GetPlayers())do if s.group.members[tostring(pl.UserId)]then v[pl.Name]=true end end;return v end,function(v)
   local count=0;for _,on in pairs(v)do if on then count=count+1 end end;assert(count<=5,'Choose up to five group members')
   if s.group.enabled and s.enabled then s.SetEnabled(false)end;s.group.members={}
   for _,pl in ipairs(game.Players:GetPlayers())do if v[pl.Name]then s.group.members[tostring(pl.UserId)]=true end end
   if count>=2 then s.group.count=count end;flush()
  end))
 elseif section=='Sea Event'and n=='Crack skill tools'then
  return done(binding(function()return p.Volcano.Snapshot().tools end,function(v)p.Volcano.Configure(nil,v)end))
 elseif section=='Sea Event'and n=='Golem weapon'then
  return done(binding(function()return p.Volcano.Snapshot().weapon end,function(v)p.Volcano.Configure(v,nil)end))
 elseif section=='Sea Event'and n=='Return destination'then
  local r=find(section,n,'TextButton');local base=recordBinding(r,kind)
  return done(binding(function()return p.levi and p.levi.returnIsland or 'Tiki' end,base.set))
 end
 local lookup=n;local index=occurrence or 1
 if section=='Sea Event'then
  if n=='My role'then index=group=='Leviathan Hunt'and 2 or 1 end
  if n=='Refresh player list'then index=group=='Leviathan Hunt'and 2 or 1 end
 end
 local class=kind=='num'and 'TextBox'or kind=='info'and 'TextLabel'or 'TextButton'
 local r,list=find(section,lookup,class,index)
 if r and (kind=='toggle'or kind=='hop')then
  local filtered={}
  for _,v in ipairs(list)do if v.original~='+'and v.original~='-'and v.original~='−'and not v.original:find('▾',1,true)then filtered[#filtered+1]=v end end
  if spec.hop then r=filtered[kind=='hop'and 1 or #filtered]else r=filtered[index]end
 end
 if r then return done(recordBinding(r,kind))end
 local reason=section=='Shop'and 'This item is not sold in the current sea.'or 'Control is unavailable: '..tostring(n)
 bridgeAudit.missing[#bridgeAudit.missing+1]={section=section,name=n,kind=kind,reason=reason}
 return done({get=function()return kind=='info'and 'Unavailable'or nil end,set=function()notice(reason)end,unavailable=true})
end
getgenv().NexoMenuBindingAudit=bridgeAudit

--[[
	NEXO MENU — connected to the existing Nexo controllers
	Run the "nexo sounds" script once first (saves the mp3s to workspace/NexoSounds).
]]

---------------------------------------------------------------------
-- SETTINGS (edit these)
---------------------------------------------------------------------
local LOGO_ID = "rbxassetid://140686261014577" -- full logo picture
-- where the logo sits inside that picture (pixels of the original 640x640 image)
local LOGO_IMG_W, LOGO_IMG_H = 640, 640
local LOGO_LEFT, LOGO_RIGHT = 8, 631
local LOGO_TOP, LOGO_SPLIT, LOGO_BOTTOM = 5, 316, 627
local SOUND_VOLUME = 0.6
local LOGO_OPEN_WIDTH = 164   -- logo width when the menu is open
local LOGO_REST_WIDTH = 66    -- small logo width when the menu is closed
local LOGO_REST_X, LOGO_REST_Y = 70, 110 -- where the small logo sits when closed (drag it to move)
local MENU_TRANSPARENCY = 0.2 -- 0 = solid, 1 = invisible
local TITLE_TEXT = "NEXO"

---------------------------------------------------------------------
-- SECTIONS + ROWS
-- t = "toggle" | "drop" | "num" | "choice" | "btn" | "buy" | "info" | "head" | "btns"
-- num = { min, max, start, step }
---------------------------------------------------------------------
local MATERIALS = {
	"Angel Wings", "Leather", "Magma Ore", "Scrap Metal", "Yeti Fur", "Bones", "Ectoplasm", "Fish Tail",
	"Gunpowder", "Mini Tusk", "Mystic Droplet", "Radioactive Material", "Vampire Fang", "Conjured Cocoa",
	"Demonic Wisp", "Dragon Scale",
}

local ISLANDS_BY_SEA = {
	{ "Pirate Starter", "Middle Town", "Jungle", "Colosseum", "Frozen Village", "Whirlpool", "Underwater City",
		"Prison", "Fountain City", "Desert Island", "Pirate Island", "Marine Starter", "Marine Fortress",
		"Magma Village", "Skyland 1", "Skyland 2", "Upper Sky", "Upper Sky 2" },
	{ "Kingdom of Rose Dock", "Cafe", "Green Zone", "Graveyard", "Cursed Ship", "Hot", "Cold", "Forgotten Island",
		"Snow Mountain", "Dark Arena", "Ice Castle", "Small Island" },
	{ "Port Town", "Middle Hydra", "Castle on the Sea", "Mansion", "Floating Turtle", "Tiki", "Submerged Island",
		"Chocolate Island", "Sea of Treats", "Sea of Treats 2", "Sea of Treats 3", "North Pole", "Great Tree",
		"Haunted Castle" },
}
local SEA_OF_PLACE = {
	[2753915549] = 1, [85211729168715] = 1,
	[4442272183] = 2, [79091703265657] = 2,
	[7449423635] = 3, [100117331123089] = 3,
}
local ISLANDS = ISLANDS_BY_SEA[SEA_OF_PLACE[game.PlaceId] or 1]

local RAIDS = { "Flame", "Ice", "Quake", "Light", "Dark", "String", "Rumble", "Magma", "Buddha", "Sand", "Phoenix", "Dough" }

local SECTIONS = {
	{ name = "Info", rows = {
		{ t = "info", n = "Time" },
		{ t = "info", n = "Moon Phase" },
		{ t = "info", n = "Full Moon In" },
		{ t = "info", n = "Tyrant Eyes" },
		{ t = "info", n = "Prehistoric Island" },
		{ t = "info", n = "Mirage Island" },
		{ t = "info", n = "Elite Pirate" },
		{ t = "info", n = "Cake Prince" },
		{ t = "info", n = "Legendary Sword Dealer" },
		{ t = "info", n = "Aura Seller" },
		{ t = "info", n = "Place ID", v = tostring(game.PlaceId) },
		{ t = "btns", list = { "Hop Server", "Hop to Less People" } },
	} },
	{ name = "Shop", rows = {
		{ t = "btn", n = "Redeem All Codes", b = "Redeem" },
		{ t = "head", n = "Abilities" },
		{ t = "buy", n = "Air Jump", price = "$10,000" },
		{ t = "buy", n = "Aura", price = "$25,000" },
		{ t = "buy", n = "Flash Step", price = "$100,000" },
		{ t = "buy", n = "Instinct", price = "$750,000" },
		{ t = "head", n = "Race Shop" },
		{ t = "buy", n = "Cyborg", price = "Fragments 2,500" },
		{ t = "buy", n = "Ghoul", price = "Free" },
		{ t = "buy", n = "Reset Stats", price = "2,500 Fragments" },
		{ t = "buy", n = "Random Race", price = "Fragments 3,000 / roll", b = "Roll" },
		{ t = "head", n = "Fighting Styles" },
		{ t = "buy", n = "Dark Step", price = "$150,000" },
		{ t = "buy", n = "Water Kung Fu", price = "$750,000" },
		{ t = "toggle", n = "Get Water Kung Fu", sub = true },
		{ t = "buy", n = "Electric", price = "$500,000" },
		{ t = "toggle", n = "Get Electric", sub = true },
		{ t = "buy", n = "Dragon Breath", price = "1,500 Fragments" },
		{ t = "buy", n = "Superhuman", price = "$3,000,000" },
		{ t = "buy", n = "Death Step", price = "$2,500,000 + Fragments 5,000" },
		{ t = "toggle", n = "Get Death Step", sub = true },
		{ t = "buy", n = "Sharkman Karate", price = "$2,500,000 + Fragments 5,000" },
		{ t = "toggle", n = "Get Sharkman Karate", sub = true },
		{ t = "buy", n = "Electric Claw", price = "$3,000,000 + Fragments 5,000" },
		{ t = "toggle", n = "Get Electric Claw", sub = true },
		{ t = "buy", n = "Dragon Talon", price = "$3,000,000 + Fragments 5,000" },
		{ t = "toggle", n = "Get Dragon Talon", sub = true },
		{ t = "buy", n = "Godhuman", price = "$5,000,000 + Fragments 5,000" },
		{ t = "toggle", n = "Get Godhuman", sub = true },
		{ t = "buy", n = "Sanguine Art", price = "Previously unlocked" },
		{ t = "head", n = "Items — Sea 1" },
		{ t = "buy", n = "Katana", price = "$1,000" },
		{ t = "buy", n = "Cutlass", price = "$1,000" },
		{ t = "buy", n = "Dual Katana", price = "$12,000" },
		{ t = "buy", n = "Iron Mace", price = "$25,000" },
		{ t = "buy", n = "Triple Katana", price = "$60,000" },
		{ t = "buy", n = "Pipe", price = "$100,000" },
		{ t = "buy", n = "Dual-Headed Blade", price = "$400,000" },
		{ t = "buy", n = "Bisento", price = "$1,000,000" },
		{ t = "buy", n = "Soul Cane", price = "$750,000" },
		{ t = "buy", n = "Slingshot", price = "$5,000" },
		{ t = "buy", n = "Musket", price = "$8,000" },
		{ t = "buy", n = "Flintlock", price = "$10,500" },
		{ t = "buy", n = "Refined Slingshot", price = "$30,000" },
		{ t = "buy", n = "Dual Flintlock", price = "$65,000" },
		{ t = "buy", n = "Cannon", price = "$100,000" },
		{ t = "buy", n = "Black Cape", price = "$50,000" },
		{ t = "buy", n = "Swordsman Hat", price = "$150,000" },
		{ t = "buy", n = "Tomoe Ring", price = "$500,000" },
		{ t = "head", n = "Items — Sea 2" },
		{ t = "buy", n = "Kabucha", price = "1,500 Fragments" },
		{ t = "buy", n = "Bizarre Revolver", price = "25 Ectoplasm" },
		{ t = "toggle", n = "Get Bizarre Revolver", sub = true },
		{ t = "buy", n = "Ghoul Mask", price = "50 Ectoplasm" },
		{ t = "toggle", n = "Get Ghoul Mask", sub = true },
		{ t = "buy", n = "Midnight Blade", price = "100 Ectoplasm" },
		{ t = "toggle", n = "Get Midnight Blade", sub = true },
	} },
	{ name = "Player", rows = {
		{ t = "btn", n = "Stop All", b = "Stop" },
		{ t = "choice", n = "Translate", opts = { "Khmer", "English" }, v = "Khmer" },
		{ t = "btn", n = "Fruit Dealer", b = "Open" },
		{ t = "btn", n = "Mirage Fruit Dealer", b = "Open" },
		{ t = "btn", n = "Titles Specialist", b = "Open" },
		{ t = "btn", n = "Awakenings Expert", b = "Open" },
		{ t = "drop", n = "Auto Stats", opts = { "Melee", "Defense", "Sword", "Gun", "Fruit" }, multi = true },
		{ t = "choice", n = "Change Team", opts = { "Pirates", "Marines" } },
		{ t = "drop", n = "Travel", opts = ISLANDS, toggle = true },
		{ t = "toggle", n = "Tween to Mirage" },
		{ t = "toggle", n = "Tween to Prehistoric" },
	} },
	{ name = "Farm Setting", rows = {
		{ t = "choice", n = "Weapon", opts = { "Melee", "Sword", "Demon Fruit", "Gun" }, v = "Melee", w = 92 },
		{ t = "toggle", n = "Auto Click" },
		{ t = "toggle", n = "Bring Mobs", num = { 2, 6, 4, 1 } },
		{ t = "num", n = "Tween Speed", num = { 40, 350, 120, 10 } },
		{ t = "num", n = "Hop wait (seconds)", num = { 1, 600, 20, 1 } },
		{ t = "toggle", n = "Auto V3" },
		{ t = "toggle", n = "Auto V4" },
		{ t = "toggle", n = "Auto Aura" },
		{ t = "toggle", n = "Retreat to Safety with Rare Items", on = true },
		{ t = "toggle", n = "Remove Fog" },
		{ t = "toggle", n = "Walk on Water", on = true },
		{ t = "toggle", n = "Jump Power", num = { 1, 250, 200, 10 } },
		{ t = "toggle", n = "Walk Speed", num = { 1, 200, 200, 10 } },
		{ t = "drop", n = "Skill Use", opts = { "Z", "X", "C", "V", "F" }, multi = true, v = { "Z", "X", "C", "V", "F" } },
		{ t = "btn", n = "Save Setting", b = "Save" },
		{ t = "toggle", n = "Auto Save", on = true },
		{ t = "toggle", n = "Auto Load", on = true },
		{ t = "choice", n = "Auto Load Team", opts = { "Marines", "Pirates" }, v = "Marines" },
		{ t = "toggle", n = "Fruit ESP" },
		{ t = "toggle", n = "Player ESP" },
		{ t = "toggle", n = "Berry ESP" },
		{ t = "toggle", n = "Island ESP" },
		{ t = "toggle", n = "Aim Player" },
		{ t = "toggle", n = "Auto Observation" },
		{ t = "toggle", n = "Remove Observation Effects" },
		{ t = "toggle", n = "Retreat at Low Health" },
		{ t = "num", n = "Low Health (%)", num = { 10, 60, 30, 5 } },
		{ t = "num", n = "Retreat Height (studs)", num = { 50, 5000, 800, 50 } },
	} },
	{ name = "Farming", rows = {
		{ t = "toggle", n = "Farm Level" },
		{ t = "drop", n = "Farm Material", opts = MATERIALS, v = "Angel Wings", toggle = true },
		{ t = "toggle", n = "Farm Tyrant" },
		{ t = "toggle", n = "Farm Cake Prince" },
	} },
	{ name = "Stack Farm", rows = {
		{ t = "toggle", n = "Collect & Store Fruit" },
		{ t = "toggle", n = "Hop Server", sub = true },
		{ t = "toggle", n = "Auto Elite Pirate" },
		{ t = "toggle", n = "Hop Server", sub = true },
		{ t = "toggle", n = "Kill rip_indra" },
		{ t = "toggle", n = "Auto Spawn Indra" },
		{ t = "toggle", n = "Kill Darkbeard" },
		{ t = "toggle", n = "Auto Spawn Darkbeard" },
		{ t = "toggle", n = "Auto Factory" },
		{ t = "toggle", n = "Auto Pirate Raid" },
		{ t = "toggle", n = "Kill Dough King" },
		{ t = "toggle", n = "Auto Spawn Dough King" },
		{ t = "toggle", n = "Kill Soul Reaper" },
	} },
	{ name = "Farm Other", rows = {
		{ t = "toggle", n = "Pick up berry", hop = true },
		{ t = "toggle", n = "Buy aura / recipe" },
		{ t = "toggle", n = "Buy legendary sword" },
		{ t = "toggle", n = "Collect chest", hop = true },
		{ t = "toggle", n = "Limit chests per server", num = { 1, 200, 20, 1 } },
		{ t = "toggle", n = "Auto V2 Haki" },
		{ t = "toggle", n = "Hop when dodges run out" },
	} },
	{ name = "Get Items", rows = {
		{ t = "toggle", n = "Auto Saber" },
		{ t = "toggle", n = "Collect Fist of Darkness" },
		{ t = "toggle", n = "Auto Tushita" },
		{ t = "toggle", n = "Get Rengoku (Hidden Key)" },
		{ t = "toggle", n = "Auto Soul Guitar" },
	} },
	{ name = "Sea Event", rows = {
		{ t = "drop", n = "Zone", opts = { "1", "2", "3", "4", "5", "6" } },
		{ t = "drop", n = "Events", opts = { "Terrorshark", "Shark", "Sea Beast", "Piranha", "Kill Boats" }, multi = true },
		{ t = "drop", n = "Boat", opts = { "Guardian", "Brigade", "Beast Hunter" }, v = "Guardian" },
		{ t = "num", n = "Boat Speed", num = { 40, 350, 120, 10 } },
		{ t = "toggle", n = "Sail until selected event" },
		{ t = "toggle", n = "Reset beyond 10 km" },
		{ t = "toggle", n = "Auto Sea Event" },
		{ t = "toggle", n = "Find Mirage Island" },
		{ t = "toggle", n = "Find Kitsune Island" },
		{ t = "toggle", n = "Collect Blue Gear" },
		{ t = "toggle", n = "Auto Sea Event with Friends" },
		{ t = "drop", n = "Players including driver", opts = { "2", "3", "4", "5" } },
		{ t = "choice", n = "My role", opts = { "Driver", "Passenger" }, v = "Driver" },
		{ t = "drop", n = "Boat owner / Driver", opts = "players" },
		{ t = "drop", n = "Choose group members", opts = "players", multi = true },
		{ t = "btn", n = "Refresh player list", b = "Refresh" },
		{ t = "head", n = "Leviathan Hunt" },
		{ t = "btn", n = "Spy bribe (1,500 fragments)", b = "Buy" },
		{ t = "drop", n = "Boat owner", opts = "players" },
		{ t = "btn", n = "Refresh player list", b = "Refresh" },
		{ t = "choice", n = "My role", opts = { "Driver", "Passenger" }, v = "Driver" },
		{ t = "toggle", n = "Tween to boat / Ride" },
		{ t = "toggle", n = "Find Frozen Dimension" },
		{ t = "toggle", n = "Auto Attack Leviathan" },
		{ t = "choice", n = "Attack weapon", opts = { "Dragonstorm", "M1 Fruit" }, v = "Dragonstorm", w = 110 },
		{ t = "toggle", n = "Lift boat away from danger", on = true },
		{ t = "toggle", n = "Manual driving speed" },
		{ t = "num", n = "Manual speed value", num = { 40, 350, 120, 10 } },
		{ t = "toggle", n = "Auto Get Leviathan Heart", on = true },
		{ t = "toggle", n = "Auto Return After Heart", on = true },
		{ t = "choice", n = "Return destination", opts = { "Tiki", "Hydra" }, v = "Tiki" },
		{ t = "head", n = "Volcano" },
		{ t = "toggle", n = "Find Prehistoric Island" },
		{ t = "toggle", n = "Auto Volcano Event" },
		{ t = "drop", n = "Golem weapon", opts = { "Gun", "Melee", "Sword", "Fruit" } },
		{ t = "drop", n = "Crack skill tools", opts = { "Fruit", "Gun", "Sword", "Melee" }, multi = true },
	} },
	{ name = "Raid + Fruit", rows = {
		{ t = "drop", n = "Select Raid", opts = RAIDS, v = "Flame" },
		{ t = "toggle", n = "Start Raid" },
		{ t = "toggle", n = "Unstore Low Fruit" },
		{ t = "toggle", n = "Auto Awaken Fruit" },
		{ t = "toggle", n = "Roll Fruit" },
		{ t = "toggle", n = "Store Fruit" },
	} },
	{ name = "V4 Trial", rows = {
		{ t = "btn", n = "Tween to Trial", b = "GO" },
		{ t = "btn", n = "Go to Race Room", b = "GO" },
		{ t = "toggle", n = "Auto Buy Training" },
		{ t = "info", n = "Training" },
		{ t = "toggle", n = "Find Full Moon (within 10 min)" },
		{ t = "info", n = "Race" },
		{ t = "toggle", n = "Auto Trial" },
		{ t = "toggle", n = "Auto Get Race V2" },
		{ t = "toggle", n = "Auto Get Race V3" },
	} },
}

---------------------------------------------------------------------
-- COLORS / FONTS
---------------------------------------------------------------------
local C = {
	Trim = Color3.fromRGB(155, 50, 255),       -- Neon Violet border / glowing accent
	Ivory = Color3.fromRGB(245, 235, 255),      -- Clean light lavender white
	SoftWhite = Color3.fromRGB(230, 215, 250),  -- Soft light purple-white
	LightGrey = Color3.fromRGB(200, 185, 225),  -- Lavender grey text
	MidGrey = Color3.fromRGB(145, 125, 175),    -- Muted purple grey
	MissRed = Color3.fromRGB(180, 85, 255),     -- Bright secondary violet
	DarkLine = Color3.fromRGB(65, 15, 115),     -- Dark purple border
	DeepLine = Color3.fromRGB(45, 10, 80),      -- Deep violet line
	CardLine = Color3.fromRGB(75, 20, 130),     -- Card purple stroke
	Muted = Color3.fromRGB(110, 35, 185),       -- Medium purple
	BarRed = Color3.fromRGB(135, 40, 225),      -- Bar / slider purple
	WindowFill = Color3.fromRGB(16, 8, 28),     -- Very dark purple window background
	PanelFill = Color3.fromRGB(10, 5, 18),      -- Near black-purple panel
	PlateFill = Color3.fromRGB(22, 12, 38),     -- Dark purple card fill
	ActiveFill = Color3.fromRGB(95, 20, 175),   -- Selected tab / active highlight (Neon Purple)
	ReqPanel = Color3.fromRGB(35, 12, 60),      -- Dark purple secondary panel
	HeaderFill = Color3.fromRGB(20, 10, 35),    -- Dark violet header
	NearBlack = Color3.fromRGB(12, 6, 20),      -- Deepest black-purple
	InnerLine = Color3.fromRGB(50, 25, 85),     -- Subtle inner divider
	KnobOff = Color3.fromRGB(95, 85, 120),      -- Toggle off knob
	CoreOff = Color3.fromRGB(35, 22, 50),       -- Toggle off background
	TrackOn = Color3.fromRGB(130, 35, 220),     -- Toggle on track (Purple)
}
local FONT_TITLE = Font.new(Font.fromEnum(Enum.Font.GrenzeGotisch).Family, Enum.FontWeight.Bold)
local FONT_BODY = Font.fromEnum(Enum.Font.Merriweather)
local FONT_BODY_BOLD = Font.new(FONT_BODY.Family, Enum.FontWeight.Bold)
local FONT_SECTION = Font.fromEnum(Enum.Font.BuilderSans)

---------------------------------------------------------------------
-- SERVICES / HELPERS
---------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

pcall(function()
	local list = require(game:GetService("ReplicatedStorage").Raids)
	local names = {}
	for _, group in ipairs({ list.raids or {}, list.advancedRaids or {} }) do
		for _, n in ipairs(group) do table.insert(names, tostring(n)) end
	end
	if #names > 0 then
		RAIDS = names
		for _, sec in ipairs(SECTIONS) do
			for _, r in ipairs(sec.rows) do
				if r.n == "Select Raid" then r.opts = names; r.v = names[1] end
			end
		end
	end
end)

local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			o[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = o
	end
	if props and props.Parent then
		o.Parent = props.Parent
	end
	return o
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function box(parent, props)
	props = props or {}
	props.BorderSizePixel = 0
	props.Parent = parent
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = 1
	end
	return new("Frame", props)
end

-- diamond: "size" = full width tip to tip
local function diamond(parent, size, pos, fill, lineColor, lineThick, z)
	local side = size / math.sqrt(2)
	local d = box(parent, {
		Size = UDim2.fromOffset(side, side),
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = fill or C.Trim,
		BackgroundTransparency = fill and 0 or 1,
		ZIndex = z or 1,
	})
	if lineColor then
		stroke(d, lineColor, lineThick or 1)
	end
	return d
end

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Cubic, dir or Enum.EasingDirection.InOut), props)
	tw:Play()
	return tw
end

---------------------------------------------------------------------
-- SCREEN + SCALING (base 1280 x 720)
---------------------------------------------------------------------
local serviceConnections={}
local pg = player:WaitForChild("PlayerGui")
local oldGui = pg:FindFirstChild("NexoMenu")
if oldGui then oldGui:Destroy() end
local gui = new("ScreenGui", {
	Name = "NexoMenu",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = pg,
})

-- sounds come from workspace/NexoSounds/*.mp3 (saved by the "nexo sounds" script)
local function makeSound(name, file)
	local snd = new("Sound", { Name = name, Volume = SOUND_VOLUME, Parent = gui })
	local path = "NexoSounds/" .. file .. ".mp3"
	if getcustomasset and isfile and isfile(path) then
		local ok, asset = pcall(getcustomasset, path)
		if ok and asset then snd.SoundId = asset end
	end
	return snd
end
local openSound = makeSound("OpenSound", "open")
local closeSound = makeSound("CloseSound", "close")
local clickSound = makeSound("ClickSound", "click")
local toggleSound = makeSound("ToggleSound", "toggle")
local function play(snd)
	snd.TimePosition = 0
	snd:Play()
end

local stage = box(gui, {
	Name = "Stage",
	Size = UDim2.fromOffset(1280, 720),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
})
local uiScale = new("UIScale", { Parent = stage })
local function rescale()
 if not gui.Parent then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local v = cam.ViewportSize
	uiScale.Scale = math.min(v.X / 1280, v.Y / 720)
end
rescale()
table.insert(serviceConnections,workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))

---------------------------------------------------------------------
-- WINDOW GROUP (fades + opens from the middle line)
---------------------------------------------------------------------
local GROUP_W, GROUP_H = 1000, 520
local group = new("CanvasGroup", {
	Name = "WindowGroup",
	Size = UDim2.fromOffset(GROUP_W, GROUP_H),
	Position = UDim2.fromOffset(640, 360),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 2,
	Parent = stage,
})
-- fixed-size content centered in the group (so shrinking the group "closes" it)
local gc = box(group, {
	Name = "Content",
	Size = UDim2.fromOffset(GROUP_W, GROUP_H),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
})

local WX, WY, WW, WH = 20, 30, 960, 460 -- window rect inside group

-- outer ring (6px dark gap + 1px line)
local ring = box(gc, { Size = UDim2.fromOffset(WW + 14, WH + 14), Position = UDim2.fromOffset(WX - 7, WY - 7) })
stroke(ring, C.DarkLine, 1)

-- window
local win = box(gc, {
	Name = "Window",
	Size = UDim2.fromOffset(WW, WH),
	Position = UDim2.fromOffset(WX, WY),
	BackgroundColor3 = C.WindowFill,
	BackgroundTransparency = MENU_TRANSPARENCY,
})
stroke(win, C.Trim, 2)

-- inner border (8px in)
local inner = box(win, {
	Name = "Inner",
	Size = UDim2.new(1, -16, 1, -16),
	Position = UDim2.fromOffset(8, 8),
})
stroke(inner, C.DarkLine, 1)

-- corner brackets
local function line(parent, x, y, w, h, color, ax, ay, z)
	return box(parent, {
		Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(x, y),
		AnchorPoint = Vector2.new(ax or 0, ay or 0),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		ZIndex = z or 1,
	})
end

local function bracket(parent, cx, cy, sx, sy, outerArm, innerArm, outerIn, innerIn, color, thick, withGems)
	local ax = sx == 1 and 0 or 1
	local ay = sy == 1 and 0 or 1
	-- outer L
	line(parent, cx + sx * outerIn, cy + sy * outerIn, outerArm, thick, color, ax, ay, 3)
	line(parent, cx + sx * outerIn, cy + sy * outerIn, thick, outerArm, color, ax, ay, 3)
	if innerArm then
		line(parent, cx + sx * innerIn, cy + sy * innerIn, innerArm, thick, color, ax, ay, 3)
		line(parent, cx + sx * innerIn, cy + sy * innerIn, thick, innerArm, color, ax, ay, 3)
	end
	if withGems then
		diamond(parent, 9, UDim2.fromOffset(cx + sx * (outerIn + outerArm), cy + sy * (outerIn + 1)), color, nil, nil, 3)
		diamond(parent, 9, UDim2.fromOffset(cx + sx * (outerIn + 1), cy + sy * (outerIn + outerArm)), color, nil, nil, 3)
		diamond(parent, 11, UDim2.fromOffset(cx + sx * (innerIn + 1), cy + sy * (innerIn + 1)), C.Ivory, nil, nil, 3)
	end
end

local bx0, by0, bx1, by1 = WX - 10, WY - 10, WX + WW + 10, WY + WH + 10
bracket(gc, bx0, by0, 1, 1, 66, 38, 4, 14, C.Trim, 2, true)
bracket(gc, bx1, by0, -1, 1, 66, 38, 4, 14, C.Trim, 2, true)
bracket(gc, bx0, by1, 1, -1, 66, 38, 4, 14, C.Trim, 2, true)
bracket(gc, bx1, by1, -1, -1, 66, 38, 4, 14, C.Trim, 2, true)

-- logo plates (pointed, on the top and bottom border)
local function plate(cx, cy)
	local p = box(gc, { Size = UDim2.fromOffset(200, 28), Position = UDim2.fromOffset(cx, cy), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4 })
	diamond(p, 28, UDim2.new(0, 20, 0.5, 0), C.NearBlack, C.Trim, 2, 4)
	diamond(p, 28, UDim2.new(1, -20, 0.5, 0), C.NearBlack, C.Trim, 2, 4)
	box(p, { Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(20, 0), BackgroundColor3 = C.NearBlack, BackgroundTransparency = 0, ZIndex = 5 })
	line(p, 20, 0, 160, 2, C.Trim, 0, 0, 6)
	line(p, 20, 28, 160, 2, C.Trim, 0, 1, 6)
end
plate(WX + WW / 2, WY)
plate(WX + WW / 2, WY + WH)

---------------------------------------------------------------------
-- HEADER
---------------------------------------------------------------------
local header = box(inner, {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 80),
	BackgroundColor3 = C.HeaderFill,
	BackgroundTransparency = 0.4,
})
box(header, { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = C.DarkLine, BackgroundTransparency = 0 })

new("TextLabel", { -- shadow
	Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 2),
	BackgroundTransparency = 1, Text = TITLE_TEXT, FontFace = FONT_TITLE, TextSize = 56,
	TextColor3 = Color3.fromRGB(90, 10, 13), Parent = header,
})
local title = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1, Text = TITLE_TEXT, FontFace = FONT_TITLE, TextSize = 56,
	TextColor3 = C.Ivory, ZIndex = 2, Parent = header,
})
new("UIStroke", { Color = C.Trim, Thickness = 2, Transparency = 0.55, Parent = title })

-- divider jewel
local jewel = box(header, { Size = UDim2.fromOffset(120, 18), Position = UDim2.new(0.5, 0, 0, 80), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 })
line(jewel, 0, 9, 44, 1, C.Trim, 0, 0.5, 3)
line(jewel, 120, 9, 44, 1, C.Trim, 1, 0.5, 3)
diamond(jewel, 16, UDim2.fromScale(0.5, 0.5), C.NearBlack, C.Trim, 1, 3)
diamond(jewel, 8, UDim2.fromScale(0.5, 0.5), C.Ivory, nil, nil, 4)

---------------------------------------------------------------------
-- CUSTOM SCROLLBAR
---------------------------------------------------------------------
local function addScrollbar(panel, sf, rightInset, vInset)
	local track = box(panel, {
		Name = "Scrollbar",
		Size = UDim2.new(0, 12, 1, -vInset * 2),
		Position = UDim2.new(1, -rightInset, 0, vInset),
		AnchorPoint = Vector2.new(1, 0),
		ZIndex = 8,
	})
	box(track, { Size = UDim2.new(0, 2, 1, -16), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C.DeepLine, BackgroundTransparency = 0, ZIndex = 8 })
	diamond(track, 12, UDim2.new(0.5, 0, 0, 6), C.NearBlack, C.Trim, 1, 9)
	diamond(track, 12, UDim2.new(0.5, 0, 1, -6), C.NearBlack, C.Trim, 1, 9)
	local area = box(track, { Size = UDim2.new(1, 0, 1, -32), Position = UDim2.fromOffset(0, 16), ZIndex = 9 })
	local thumb = box(area, { Size = UDim2.new(1, 0, 0.3, 0), ZIndex = 9 })
	box(thumb, { Size = UDim2.new(0, 8, 1, -8), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C.Trim, BackgroundTransparency = 0, ZIndex = 9 })
	diamond(thumb, 8, UDim2.new(0.5, 0, 0, 4), C.Trim, nil, nil, 9)
	diamond(thumb, 8, UDim2.new(0.5, 0, 1, -4), C.Trim, nil, nil, 9)

	local function update()
		if not sf.Visible then
			track.Visible = false
			return
		end
		local total = sf.AbsoluteCanvasSize.Y
		local vis = sf.AbsoluteWindowSize.Y
		if total <= vis + 1 then
			track.Visible = false
			return
		end
		track.Visible = true
		local h = math.max(0.14, vis / total)
		local top = (sf.CanvasPosition.Y / math.max(1, (total - vis) / uiScale.Scale)) * (1 - h)
		thumb.Size = UDim2.new(1, 0, h, 0)
		thumb.Position = UDim2.new(0, 0, math.clamp(top, 0, 1 - h), 0)
	end
	sf:GetPropertyChangedSignal("CanvasPosition"):Connect(update)
	sf:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(update)
	sf:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(update)
	sf:GetPropertyChangedSignal("Visible"):Connect(update)
	task.defer(update)
end

local function makeScroller(parent, padT, padB, padL, padR, gap)
	local sf = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 2,
		Parent = parent,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, padT), PaddingBottom = UDim.new(0, padB),
		PaddingLeft = UDim.new(0, padL), PaddingRight = UDim.new(0, padR), Parent = sf,
	})
	new("UIListLayout", {
		Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = sf,
	})
	return sf
end

---------------------------------------------------------------------
-- SIDE SECTION BUTTONS
---------------------------------------------------------------------
local BODY_Y, BODY_H = 80 + 22, 444 - 80 - 22 - 20
local side = box(inner, {
	Name = "Sections",
	Size = UDim2.fromOffset(240, BODY_H),
	Position = UDim2.fromOffset(24, BODY_Y),
	BackgroundColor3 = C.PanelFill,
	BackgroundTransparency = 0.45,
})
stroke(side, C.DeepLine, 1)
local sideList = makeScroller(side, 12, 12, 12, 34, 6)
addScrollbar(side, sideList, 10, 12)

local showSection = function() end
local sectionButtons = {}
local activeSection = 1
local function styleSection(i)
	local s = sectionButtons[i]
	local on = (i == activeSection)
	s.btn.BackgroundColor3 = on and C.ActiveFill or C.PlateFill
	s.btn.BackgroundTransparency = on and 0.4 or 0.45
	s.stroke.Color = on and C.Trim or C.CardLine
	s.innerStroke.Color = on and C.BarRed or C.InnerLine
	s.btn.TextColor3 = on and C.Ivory or C.LightGrey
	for _, d in ipairs(s.gems) do
		d.BackgroundTransparency = on and 0 or 1
		d.BackgroundColor3 = C.Ivory
		d:FindFirstChildOfClass("UIStroke").Color = on and C.Trim or C.Muted
	end
end

for i, sec in ipairs(SECTIONS) do
	local btn = new("TextButton", {
		Name = "Section" .. i,
		Size = UDim2.new(1, 0, 0, 42),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = sec.name,
		TextSize = 17,
		FontFace = FONT_SECTION,
		LayoutOrder = i,
		ZIndex = 3,
		Parent = sideList,
	})
	local st = stroke(btn, C.CardLine, 1)
	local il = box(btn, { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), ZIndex = 3 })
	local ist = stroke(il, C.InnerLine, 1)
	local g1 = diamond(btn, 10, UDim2.new(0, 15, 0.5, 0), C.Ivory, C.Muted, 1, 4)
	local g2 = diamond(btn, 10, UDim2.new(1, -15, 0.5, 0), C.Ivory, C.Muted, 1, 4)
	sectionButtons[i] = { btn = btn, stroke = st, innerStroke = ist, gems = { g1, g2 } }
	btn.MouseButton1Click:Connect(function()
		play(clickSound)
		local old = activeSection
		activeSection = i
		styleSection(old)
		styleSection(i)
		showSection(i)
	end)
end
for i in ipairs(sectionButtons) do
	styleSection(i)
end

---------------------------------------------------------------------
-- CONTENT AREA (one page per section)
---------------------------------------------------------------------
local contentX = 24 + 240 + 22
local cw, ch = 944 - contentX - 24, BODY_H
local content = box(inner, {
	Name = "Pages",
	Size = UDim2.fromOffset(cw, ch),
	Position = UDim2.fromOffset(contentX, BODY_Y),
	BackgroundColor3 = C.PanelFill,
	BackgroundTransparency = 0.45,
})
stroke(content, C.DeepLine, 1)
local cInner = box(content, { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6) })
stroke(cInner, Color3.fromRGB(36, 18, 20), 1)
bracket(content, 0, 0, 1, 1, 22, nil, 10, 0, C.Muted, 1, false)
bracket(content, cw, 0, -1, 1, 22, nil, 10, 0, C.Muted, 1, false)
bracket(content, 0, ch, 1, -1, 22, nil, 10, 0, C.Muted, 1, false)
bracket(content, cw, ch, -1, -1, 22, nil, 10, 0, C.Muted, 1, false)

local Q = Enum.EasingStyle.Quad
local OUT, IN = Enum.EasingDirection.Out, Enum.EasingDirection.In

local function pressFlash(b, rest)
	b.BackgroundColor3 = C.ActiveFill
	tween(b, 0.25, { BackgroundColor3 = rest }, Q, OUT)
end

-- diamond on/off toggle
local liveControls={}
local function change(binding,value,paint)
 if not binding or binding.pending then return end
 binding.pending=true
 task.spawn(function()
  guard(binding.set,value)
  binding.pending=false
  if paint and gui.Parent then paint()end
 end)
end
local function watch(binding,paint)
 if not binding or not binding.get then return end
 liveControls[#liveControls+1]={binding=binding,paint=paint}
 pcall(paint)
end
local function buildToggle(parent, startOn, binding)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(76, 44), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5, Parent = parent,
	})
	local t = box(btn, { Size = UDim2.fromOffset(72, 30), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 })
	local endL = diamond(t, 30, UDim2.new(0.5, -21, 0.5, 0), C.PlateFill, C.CardLine, 1, 5)
	local endR = diamond(t, 30, UDim2.new(0.5, 21, 0.5, 0), C.PlateFill, C.CardLine, 1, 5)
	local mid = box(t, { Size = UDim2.fromOffset(42, 30), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.PlateFill, BackgroundTransparency = 0, ZIndex = 6 })
	local topL = line(mid, 0, 0, 42, 1, C.CardLine, 0, 0, 6)
	local botL = line(mid, 0, 30, 42, 1, C.CardLine, 0, 1, 6)
	local knob = diamond(t, 22, UDim2.new(0.5, -21, 0.5, 0), C.KnobOff, C.NearBlack, 1.5, 8)
	local core = box(knob, { Size = UDim2.fromOffset(7, 7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.CoreOff, BackgroundTransparency = 0, ZIndex = 9 })
	local knobLine = knob:FindFirstChildOfClass("UIStroke")

	local on = startOn == true
	local function apply(animate)
		local tm = animate and 0.18 or 0
		local fill = on and C.TrackOn or C.PlateFill
		local edge = on and C.Trim or C.CardLine
		for _, part in ipairs({ endL, endR, mid }) do
			part.BackgroundColor3 = fill
		end
		endL:FindFirstChildOfClass("UIStroke").Color = edge
		endR:FindFirstChildOfClass("UIStroke").Color = edge
		topL.BackgroundColor3 = edge
		botL.BackgroundColor3 = edge
		core.BackgroundColor3 = on and C.Trim or C.CoreOff
		local goal = { Position = UDim2.new(0.5, on and 21 or -21, 0.5, 0), BackgroundColor3 = on and C.Ivory or C.KnobOff }
		if tm > 0 then
			tween(knob, tm, goal, Q, OUT)
		else
			knob.Position = goal.Position
			knob.BackgroundColor3 = goal.BackgroundColor3
		end
		knobLine.Color = on and C.Trim or C.NearBlack
	end
	local function sync()
  if binding and not binding.pending then local v=binding.get();on=v==true;apply(false)end
 end
 watch(binding,sync)
 apply(false)
 btn.MouseButton1Click:Connect(function()
		play(toggleSound)
		if binding and binding.pending then return end
  on = not on
  apply(true)
  change(binding,on,sync)
	end)
	return btn
end

-- plain action button (Open / Buy / GO ...)
local function buildButton(parent, label, w, binding)
	local b = new("TextButton", {
		Size = UDim2.fromOffset(w or 96, 30), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = C.NearBlack, BackgroundTransparency = 0.2, BorderSizePixel = 0, AutoButtonColor = false,
		Text = label, TextSize = 15, FontFace = FONT_SECTION, TextColor3 = C.Ivory, ZIndex = 5, Parent = parent,
	})
	stroke(b, C.Trim, 1)
	diamond(b, 8, UDim2.new(0, 0, 0.5, 0), C.Trim, nil, nil, 6)
	diamond(b, 8, UDim2.new(1, 0, 0.5, 0), C.Trim, nil, nil, 6)
	b.MouseButton1Click:Connect(function()
		play(clickSound)
		pressFlash(b, C.NearBlack)
  change(binding,true)
	end)
	if binding and (label=="Buy"or label=="Roll")then
  watch(binding,function()
   local value=binding.get()
   if value=="Buy"or value=="Roll"or value=="Equip"or value=="Owned"or value=="Current"or value=="..."then b.Text=value end
  end)
 end
 return b
end

-- number box with - / + diamonds
local function buildStepper(parent, spec, binding)
	local lo, hi, value, step = spec[1], spec[2], spec[3], spec[4] or 1
	local holder = box(parent, { Size = UDim2.fromOffset(132, 30), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 5 })
	local valueBox = new("TextBox", {
		Size = UDim2.fromOffset(66, 26), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.NearBlack, BackgroundTransparency = 0.2, BorderSizePixel = 0,
		Text = tostring(value), TextSize = 15, FontFace = FONT_BODY_BOLD, TextColor3 = C.Ivory,
		ClearTextOnFocus = false, ZIndex = 6, Parent = holder,
	})
	stroke(valueBox, C.CardLine, 1)
	local function set(v, quiet)
		v = tonumber(v) or value
		value = math.clamp(math.floor(v + 0.5), lo, hi)
		valueBox.Text = tostring(value)
  if not quiet then change(binding,value)end
	end
	local function arrow(x, sign)
		local b = new("TextButton", {
			Size = UDim2.fromOffset(28, 28), Position = UDim2.new(x, 0, 0.5, 0), AnchorPoint = Vector2.new(x, 0.5),
			BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 6, Parent = holder,
		})
		local d = diamond(b, 26, UDim2.fromScale(0.5, 0.5), C.PlateFill, C.CardLine, 1, 6)
		line(b, 14, 14, 10, 2, C.Ivory, 0.5, 0.5, 7)
		if sign > 0 then line(b, 14, 14, 2, 10, C.Ivory, 0.5, 0.5, 7) end
		b.MouseEnter:Connect(function() d:FindFirstChildOfClass("UIStroke").Color = C.Trim end)
		b.MouseLeave:Connect(function() d:FindFirstChildOfClass("UIStroke").Color = C.CardLine end)
		b.MouseButton1Click:Connect(function()
			play(clickSound)
			set(value + sign * step)
		end)
	end
	arrow(0, -1)
	arrow(1, 1)
	valueBox.FocusLost:Connect(function() set(valueBox.Text) end)
 watch(binding,function()if not binding.pending and not valueBox:IsFocused()then local v=binding.get();if type(v)=='number'then set(v,true)end end end)
	return holder
end

-- row of choice buttons, one active
local function buildChoice(parent, spec)
	local n, bw = #spec.opts, spec.w or 96
	local holder = box(parent, { Size = UDim2.fromOffset(n * bw + (n - 1) * 6, 30), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 5 })
	local buttons, current = {}, spec.v
	local function paint()
		for o, b in pairs(buttons) do
			local on = (current == o)
			b.BackgroundColor3 = on and C.ActiveFill or C.PlateFill
			b.BackgroundTransparency = on and 0.3 or 0.4
			b.TextColor3 = on and C.Ivory or C.LightGrey
			b:FindFirstChildOfClass("UIStroke").Color = on and C.Trim or C.CardLine
		end
	end
	for i, o in ipairs(spec.opts) do
		local b = new("TextButton", {
			Size = UDim2.fromOffset(bw, 30), Position = UDim2.fromOffset((i - 1) * (bw + 6), 0),
			BorderSizePixel = 0, AutoButtonColor = false, Text = o, TextSize = 15, FontFace = FONT_SECTION,
			ZIndex = 6, Parent = holder,
		})
		stroke(b, C.CardLine, 1)
		buttons[o] = b
		b.MouseButton1Click:Connect(function()
			play(clickSound)
			current = o
			paint()
   change(spec.binding,o)
		end)
	end
	watch(spec.binding,function()if not spec.binding.pending then current=spec.binding.get();paint()end end)
 paint()
 return holder
end

-- dropdown: selector in the row, options open under the row
local openDrop
local function buildDropdown(parent, entry, spec)
	local selector = new("TextButton", {
		Size = UDim2.fromOffset(210, 30), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = C.NearBlack, BackgroundTransparency = 0.2, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "", ZIndex = 5, Parent = parent,
	})
	local st = stroke(selector, C.CardLine, 1)
	local valueLabel = new("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
		TextSize = 14, FontFace = FONT_BODY, TextColor3 = C.Ivory, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6, Parent = selector,
	})
	local chev = box(selector, { Size = UDim2.fromOffset(12, 12), Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 6 })
	line(chev, 4, 6, 7, 2, C.Trim, 0.5, 0.5, 6).Rotation = 45
	line(chev, 8, 6, 7, 2, C.Trim, 0.5, 0.5, 6).Rotation = -45

	local multi = spec.multi
	local chosen
	if multi then
		chosen = {}
		for _, k in ipairs(spec.v or {}) do chosen[k] = true end
	else
		chosen = spec.v
	end
	local function options()
		if spec.opts == "players" then
			local names = {}
			for _, p in ipairs(Players:GetPlayers()) do table.insert(names, p.Name) end
			return names
		end
		return spec.opts
	end
	local function refreshLabel()
		if multi then
			local list = {}
			for _, o in ipairs(options()) do
				if chosen[o] then table.insert(list, o) end
			end
			valueLabel.Text = #list > 0 and table.concat(list, ", ") or "None"
		else
			valueLabel.Text = chosen or "None"
		end
	end

	local panel = box(entry, {
		Size = UDim2.new(1, -24, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2,
		BackgroundColor3 = C.ReqPanel, BackgroundTransparency = 0.45, Visible = false, ZIndex = 3,
	})
	stroke(panel, C.DeepLine, 1)
	new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = panel })
	new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 32), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })

	local isDropOpen = false
	local close
	local function rebuild()
		for _, c in ipairs(panel:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for i, o in ipairs(options()) do
			local on = multi and chosen[o] == true or (not multi and chosen == o)
			local b = new("TextButton", {
				LayoutOrder = i, BorderSizePixel = 0, AutoButtonColor = false,
				BackgroundColor3 = on and C.ActiveFill or C.PlateFill, BackgroundTransparency = on and 0.35 or 0.4,
				Text = o, TextSize = 14, FontFace = FONT_BODY, TextColor3 = on and C.Ivory or C.LightGrey,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 4, Parent = panel,
			})
			stroke(b, on and C.Trim or C.CardLine, 1)
			new("UIPadding", { PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 8), Parent = b })
			diamond(b, 10, UDim2.new(0, -13, 0.5, 0), on and C.Ivory or nil, on and C.Trim or C.Muted, 1, 5)
			b.MouseButton1Click:Connect(function()
				play(clickSound)
				if multi then
					chosen[o] = (not chosen[o]) or nil
					rebuild()
				else
					chosen = o
					close()
				end
				refreshLabel()
    change(spec.binding,multi and table.clone(chosen)or chosen)
			end)
		end
	end
	local function setOpen(v)
		isDropOpen = v
		panel.Visible = v
		st.Color = v and C.Trim or C.CardLine
		tween(chev, 0.2, { Rotation = v and 180 or 0 }, Q, OUT)
	end
	close = function()
		setOpen(false)
		if openDrop == close then openDrop = nil end
	end
	selector.MouseButton1Click:Connect(function()
		play(clickSound)
		if isDropOpen then
			close()
		else
			if openDrop then openDrop() end
			rebuild()
			setOpen(true)
			openDrop = close
		end
	end)
	watch(spec.binding,function()
  if not spec.binding.pending and not isDropOpen then
   local v=spec.binding.get()
   if multi and type(v)=='table'then chosen=table.clone(v)elseif not multi then chosen=v end
   refreshLabel()
  end
 end)
 refreshLabel()
 return selector
end

local function rowText(parent, txt, size, color, align, w)
	return new("TextLabel", {
		Size = UDim2.fromOffset(w or 200, 30), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1,
		Text = txt, TextSize = size, FontFace = FONT_BODY, TextColor3 = color,
		TextXAlignment = align or Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5, Parent = parent,
	})
end

local function buildHeading(entry, name)
	local h = box(entry, { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, ZIndex = 3 })
	local label = new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = name, TextSize = 24,
		FontFace = FONT_TITLE, TextColor3 = C.Ivory, ZIndex = 4, Parent = h,
	})
	new("UIStroke", { Color = C.Trim, Thickness = 1, Transparency = 0.6, Parent = label })
	local left = box(h, { Size = UDim2.new(0.5, -60, 0, 1), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = C.Trim, BackgroundTransparency = 0, ZIndex = 4 })
	local right = box(h, { Size = UDim2.new(0.5, -60, 0, 1), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = C.Trim, BackgroundTransparency = 0, ZIndex = 4 })
	local gl = diamond(h, 10, UDim2.new(0, 10, 0.5, 0), C.NearBlack, C.Trim, 1, 5)
	local gr = diamond(h, 10, UDim2.new(1, -10, 0.5, 0), C.NearBlack, C.Trim, 1, 5)
	local ml = diamond(h, 8, UDim2.new(0.5, -50, 0.5, 0), C.Ivory, nil, nil, 5)
	local mr = diamond(h, 8, UDim2.new(0.5, 50, 0.5, 0), C.Ivory, nil, nil, 5)
	local function fit()
		local half = label.TextBounds.X / 2 + 18
		left.Size = UDim2.new(0.5, -(half + 10), 0, 1)
		right.Size = UDim2.new(0.5, -(half + 10), 0, 1)
		ml.Position = UDim2.new(0.5, -half, 0.5, 0)
		mr.Position = UDim2.new(0.5, half, 0.5, 0)
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	task.defer(fit)
	return gl, gr
end

local function buildRow(page, spec, order)
 local function bind(kind)return resolveBinding(page.Name,spec,kind,spec.occurrence,spec.group)end
	local entry = box(page, { Name = spec.n or spec.t, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = 3 })
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = entry })

	if spec.t == "head" then
		buildHeading(entry, spec.n)
		return
	end

	local plateF = box(entry, { Size = UDim2.new(1, spec.sub and -24 or 0, 0, 50), LayoutOrder = 1, BackgroundColor3 = C.PlateFill, BackgroundTransparency = spec.sub and 0.55 or 0.45, ZIndex = 3 })
	stroke(plateF, C.CardLine, 1)

	if spec.t == "btns" then
		for i, txt in ipairs(spec.list) do
			local b = buildButton(plateF, txt, nil, resolveBinding(page.Name,{n=txt},"action"))
			b.AnchorPoint = Vector2.new(0, 0.5)
			b.Size = UDim2.new(0.5, -22, 0, 32)
			b.Position = UDim2.new(i == 1 and 0 or 0.5, i == 1 and 14 or 8, 0.5, 0)
		end
		return
	end

	local rx = 12
	local function place(obj)
		obj.AnchorPoint = Vector2.new(1, 0.5)
		obj.Position = UDim2.new(1, -rx, 0.5, 0)
		rx = rx + obj.Size.X.Offset + 10
	end

	local t = spec.t
	if t == "toggle" then
		place(buildToggle(plateF, spec.on, bind("toggle")))
		if spec.num then place(buildStepper(plateF, spec.num, bind("num"))) end
		if spec.hop then
			place(buildToggle(plateF, false, bind("hop")))
			place(rowText(plateF, "Hop", 15, C.LightGrey, Enum.TextXAlignment.Right, 36))
		end
	elseif t == "drop" then
		if spec.toggle then place(buildToggle(plateF, spec.on, bind("toggle"))) end
		spec.binding=bind("select");place(buildDropdown(plateF, entry, spec))
	elseif t == "num" then
		place(buildStepper(plateF, spec.num, bind("num")))
	elseif t == "choice" then
		spec.binding=bind("select");place(buildChoice(plateF, spec))
	elseif t == "btn" then
		place(buildButton(plateF, spec.b or "Open", nil, bind("action")))
	elseif t == "buy" then
		place(buildButton(plateF, spec.b or "Buy", nil, bind("action")))
		place(rowText(plateF, spec.price or "", 13, C.MidGrey, Enum.TextXAlignment.Right, 210))
	elseif t == "info" then
		local text=rowText(plateF,spec.v or "—",15,C.LightGrey,Enum.TextXAlignment.Right,330)
  text.TextWrapped=true;place(text)
  local info=bind("info");watch(info,function()local v,color=info.get();text.Text=tostring(v or "—");if color then text.TextColor3=color end end)
	end

	local nameX = 30
	diamond(plateF, 8, UDim2.new(0, 16, 0.5, 0), spec.sub and C.Muted or C.Trim, nil, nil, 4)
	new("TextLabel", {
		Size = UDim2.new(1, -(rx + nameX), 1, 0), Position = UDim2.fromOffset(nameX, 0),
		BackgroundTransparency = 1, Text = spec.n, TextSize = spec.sub and 16 or 18, FontFace = FONT_SECTION,
		TextColor3 = spec.sub and C.LightGrey or C.SoftWhite, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4, Parent = plateF,
	})
end

local pages = {}
for i, sec in ipairs(SECTIONS) do
	local page = makeScroller(content, 16, 16, 20, 40, 8)
	page.Name = sec.name
	page.Visible = (i == activeSection)
	addScrollbar(content, page, 14, 18)
	local occurrences={};local group
 for j,spec in ipairs(sec.rows)do
  if spec.t=="head"then group=spec.n end
  occurrences[spec.n or spec.t]=(occurrences[spec.n or spec.t]or 0)+1
  spec.occurrence=occurrences[spec.n or spec.t];spec.group=group
  local itemSea=group and group:match("Items — Sea (%d)")
  if sec.name~="Shop"or not itemSea or tonumber(itemSea)==SEA_OF_PLACE[game.PlaceId]then buildRow(page,spec,j)end
 end
	pages[i] = page
end

showSection = function(i)
	if openDrop then openDrop() end
	for k, p in ipairs(pages) do
		p.Visible = (k == i)
	end
	pages[i].CanvasPosition = Vector2.new(0, 0)
end

---------------------------------------------------------------------
-- LOGO + OPEN / CLOSE ANIMATION
---------------------------------------------------------------------
local OPEN_TOP = UDim2.fromOffset(640, 130)
local OPEN_BOT = UDim2.fromOffset(640, 590)
local CENTER = UDim2.fromOffset(640, 360)

local function logoHalf(isTop)
	local sc = LOGO_OPEN_WIDTH / (LOGO_RIGHT - LOGO_LEFT)
	local h = isTop and (LOGO_SPLIT - LOGO_TOP) or (LOGO_BOTTOM - LOGO_SPLIT)
	local btn = new("TextButton", {
		Name = isTop and "LogoTop" or "LogoBottom",
		Text = "", BackgroundTransparency = 1, AutoButtonColor = false, ClipsDescendants = true,
		Size = UDim2.fromOffset(LOGO_OPEN_WIDTH, math.floor(h * sc + 0.5)),
		Position = isTop and OPEN_TOP or OPEN_BOT,
		AnchorPoint = Vector2.new(0.5, isTop and 1 or 0),
		ZIndex = 10, Parent = stage,
	})
	new("ImageLabel", {
		Image = LOGO_ID, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(LOGO_IMG_W * sc, LOGO_IMG_H * sc),
		Position = UDim2.fromOffset(-LOGO_LEFT * sc, -(isTop and LOGO_TOP or LOGO_SPLIT) * sc),
		ZIndex = 10, Parent = btn,
	})
	return btn, new("UIScale", { Parent = btn })
end
local logoTop, topScale = logoHalf(true)
local logoBottom, bottomScale = logoHalf(false)
local REST_SCALE = LOGO_REST_WIDTH / LOGO_OPEN_WIDTH


local isOpen = false
local busy = false
local OPEN_SIZE = UDim2.fromOffset(GROUP_W, GROUP_H)
local LINE_SIZE = UDim2.fromOffset(GROUP_W, 2)
local DOT_SIZE = UDim2.fromOffset(4, 2)

-- bright TV flash line
local flash = box(stage, {
	Name = "TVFlash",
	Size = DOT_SIZE,
	Position = UDim2.fromOffset(640, 360),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(255, 235, 235),
	BackgroundTransparency = 1,
	ZIndex = 3,
})

local UIS = game:GetService("UserInputService")
local restPos = Vector2.new(LOGO_REST_X, LOGO_REST_Y)
local function restUDim()
	return UDim2.fromOffset(restPos.X, restPos.Y)
end

-- start closed: only the small logo shows
group.Visible = false
logoTop.Position = restUDim()
logoBottom.Position = restUDim()
topScale.Scale = REST_SCALE
bottomScale.Scale = REST_SCALE

-- logo: shrinks away where it sits -> appears at the middle -> splits as the menu opens
-- TV ON: dot -> line across -> opens up and down
local function openMenu()
	busy = true
	play(openSound)
	-- 1) small logo shrinks away
	tween(topScale, 0.15, { Scale = 0 }, Q, IN)
	tween(bottomScale, 0.15, { Scale = 0 }, Q, IN)
	task.delay(0.15, function()
		-- 2) appears at the middle
		logoTop.Position = CENTER
		logoBottom.Position = CENTER
		tween(topScale, 0.22, { Scale = 1 }, Q, OUT)
		tween(bottomScale, 0.22, { Scale = 1 }, Q, OUT)
		task.delay(0.25, function()
			-- 3) menu opens, logo halves split up and down
			group.Visible = true
			group.GroupTransparency = 0
			group.Size = DOT_SIZE
			flash.Size = DOT_SIZE
			flash.BackgroundTransparency = 0
			tween(logoTop, 0.43, { Position = OPEN_TOP }, Q, OUT)
			tween(logoBottom, 0.43, { Position = OPEN_BOT }, Q, OUT)
			tween(group, 0.18, { Size = LINE_SIZE }, Q, OUT)
			tween(flash, 0.18, { Size = LINE_SIZE }, Q, OUT)
			task.delay(0.18, function()
				tween(group, 0.25, { Size = OPEN_SIZE }, Q, OUT)
				tween(flash, 0.25, { Size = OPEN_SIZE, BackgroundTransparency = 1 }, Q, OUT)
				task.delay(0.25, function()
					isOpen = true
					busy = false
				end)
			end)
		end)
	end)
end

-- TV OFF: squash to a bright line -> shrink to a dot -> fade
-- logo: joins at the middle -> shrinks there -> moves to its resting spot
local function closeMenu()
	busy = true
	isOpen = false
	play(closeSound)
	if openDrop then openDrop() end
	flash.Size = OPEN_SIZE
	flash.BackgroundTransparency = 1
	-- 1) halves close together at the middle with the menu
	tween(logoTop, 0.35, { Position = CENTER }, Q, IN)
	tween(logoBottom, 0.35, { Position = CENTER }, Q, IN)
	tween(group, 0.2, { Size = LINE_SIZE }, Q, IN)
	tween(flash, 0.2, { Size = LINE_SIZE, BackgroundTransparency = 0 }, Q, IN)
	task.delay(0.2, function()
		tween(group, 0.15, { Size = DOT_SIZE }, Q, IN)
		tween(flash, 0.15, { Size = DOT_SIZE }, Q, IN)
		task.delay(0.15, function()
			group.Visible = false
			tween(flash, 0.15, { BackgroundTransparency = 1 })
			-- 2) shrink to small size at the middle
			tween(topScale, 0.22, { Scale = REST_SCALE }, Q, OUT)
			tween(bottomScale, 0.22, { Scale = REST_SCALE }, Q, OUT)
			task.delay(0.25, function()
				-- 3) move to where it was before
				tween(logoTop, 0.35, { Position = restUDim() }, Q, OUT)
				tween(logoBottom, 0.35, { Position = restUDim() }, Q, OUT)
				task.delay(0.35, function()
					busy = false
				end)
			end)
		end)
	end)
end

-- drag the small logo while the menu is closed
local dragging, moved = false, false
local dragStart, startPos
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
local function beginDrag(input)
	if isOpen or busy or not isPress(input) then return end
	dragging, moved = true, false
	dragStart = Vector2.new(input.Position.X, input.Position.Y)
	startPos = restPos
end
logoTop.InputBegan:Connect(beginDrag)
logoBottom.InputBegan:Connect(beginDrag)
table.insert(serviceConnections,UIS.InputChanged:Connect(function(input)
	if not gui.Parent or not dragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
	local d = (Vector2.new(input.Position.X, input.Position.Y) - dragStart) / uiScale.Scale
	if d.Magnitude > 6 then moved = true end
	restPos = Vector2.new(math.clamp(startPos.X + d.X, 30, 1250), math.clamp(startPos.Y + d.Y, 40, 690))
	logoTop.Position = restUDim()
	logoBottom.Position = restUDim()
end))
table.insert(serviceConnections,UIS.InputEnded:Connect(function(input)
	if gui.Parent and dragging and isPress(input) then
		dragging = false
	end
end))

local function onLogo()
	if moved then
		moved = false
		return
	end
	if busy then return end
	if isOpen then closeMenu() else openMenu() end
end
logoTop.MouseButton1Click:Connect(onLogo)
logoBottom.MouseButton1Click:Connect(onLogo)


-- Synchronize with jobs that finish or stop themselves; no world scans here.
local nativeText={}
for _,node in ipairs(gui:GetDescendants())do
 if node:IsA('TextLabel')or node:IsA('TextButton')then nativeText[node]={text=node.Text,size=node.TextSize,font=node.FontFace}end
end
local previousLanguage
local menuAlive=true
gui.Destroying:Connect(function()menuAlive=false;for _,connection in ipairs(serviceConnections)do connection:Disconnect()end end)
backendUI.SetOpen=function(value)
 if not gui.Parent or busy then return end
 if value and not isOpen then openMenu()elseif not value and isOpen then closeMenu()end
end
getgenv().NexoMenuRuntime={Gui=gui,Audit=bridgeAudit,SetOpen=backendUI.SetOpen,ShowSection=function(name)
 for i,sec in ipairs(SECTIONS)do if sec.name==name then showSection(i);return end end
end}
task.spawn(function()
 while menuAlive and gui.Parent and backendUI.Status().alive do
  if previousLanguage~=p.syn then
   previousLanguage=p.syn
   for node,data in pairs(nativeText)do if node.Parent then
    local translated=p.TranslateText(data.text)
    if translated~=data.text then node.Text=translated;node.TextSize=math.max(18,data.size+2);node.FontFace=Font.fromEnum(Enum.Font.SourceSans)
    elseif node.Text~=data.text and data.text~=''and p.TranslateText(data.text)==data.text then node.Text=data.text;node.TextSize=data.size;node.FontFace=data.font end
   end end
  end
  for _,control in ipairs(liveControls)do
   if not control.binding.pending then local ok,err=pcall(control.paint);if not ok then getgenv().NexoMenuSyncError=tostring(err)end end
  end
  task.wait(.4)
 end
 if gui.Parent then gui:Destroy()end
end)
]==========]
local e=getgenv();e.NexoUniversalSource=source
pcall(function()if makefolder and not isfolder('Nexo') then makefolder('Nexo') end;writefile('Nexo/main.lua',source)end)
assert(loadstring(source,'NexoTest'))()
