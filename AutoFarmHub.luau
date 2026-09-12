--[[
    Auto Farm / Hub — Strength / Wall Simulator
    Framework: Opengame (utils/package.luau)
    Style: AGENT.md (Module / Queue / UI blocks)

    Features:
      - Auto Train   (ClickTrainEvent)
      - Auto Wall    (CaveHitEvent + move/TP)
      - Auto Rebirth (RebirthFunction)
      - Auto Egg     (PetFunction HatchEgg)
      - Auto Chest   (SwordChestFunction BuyChest)
]]

local Module, Settings = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/vita8it/Opengame/main/utils/package.luau"
))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HRP = Character:WaitForChild("HumanoidRootPart")

LocalPlayer.CharacterAdded:Connect(function(Char)
    Character = Char
    Humanoid = Char:WaitForChild("Humanoid")
    HRP = Char:WaitForChild("HumanoidRootPart")
end)

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function Safe(fn, ...)
    local Ok, A, B, C = pcall(fn, ...)
    if Ok then
        return A, B, C
    end
    return nil
end

local function WaitRemote(Name, Timeout)
    return ReplicatedStorage:WaitForChild(Name, Timeout or 10)
end

local function GetStat(Name)
    local Stats = LocalPlayer:FindFirstChild("leaderstats")
    if not Stats then
        return 0
    end
    local V = Stats:FindFirstChild(Name)
    return V and V.Value or 0
end

local function GetPlayerValue(Name)
    local V = LocalPlayer:FindFirstChild(Name)
    return V and V.Value or nil
end

local function GetHRP()
    if HRP and HRP.Parent then
        return HRP
    end
    local Char = LocalPlayer.Character
    return Char and Char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    if Humanoid and Humanoid.Parent then
        return Humanoid
    end
    local Char = LocalPlayer.Character
    return Char and Char:FindFirstChildOfClass("Humanoid")
end

local function TeleportTo(Pos)
    local Root = GetHRP()
    if not Root then
        return false
    end
    if typeof(Pos) == "CFrame" then
        Root.CFrame = Pos
    elseif typeof(Pos) == "Vector3" then
        Root.CFrame = CFrame.new(Pos)
    else
        return false
    end
    return true
end

local function WorldIdFromPosition(Pos)
    if not Pos then
        return 1
    end
    local X = Pos.X
    if X > 9000 then
        return 6
    elseif X > 7000 then
        return 5
    elseif X > 5000 then
        return 4
    elseif X > 3000 then
        return 3
    elseif X > 1000 then
        return 2
    end
    return 1
end

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local Remotes = {
    ClickTrain = WaitRemote("ClickTrainEvent", 15),
    Rebirth = WaitRemote("RebirthFunction", 15),
    Pet = WaitRemote("PetFunction", 15),
    SwordChest = WaitRemote("SwordChestFunction", 30),
    TogglePush = WaitRemote("TogglePush", 15),
    CaveHit = {
        WaitRemote("CaveHitEvent", 10),
        WaitRemote("CaveHitEvent2", 10),
        WaitRemote("CaveHitEvent3", 10),
        WaitRemote("CaveHitEvent4", 10),
    },
}

----------------------------------------------------------------
-- WallConfig (per world)
----------------------------------------------------------------
local WallConfigs = {}

local function LoadWallConfig(WorldId)
    WorldId = WorldId or 1
    if WallConfigs[WorldId] then
        return WallConfigs[WorldId]
    end

    local Name = WorldId <= 1 and "WallConfig" or ("WallConfig" .. WorldId)
    local Mod = ReplicatedStorage:FindFirstChild(Name) or ReplicatedStorage:FindFirstChild("WallConfig")
    if not Mod then
        return nil
    end

    local Ok, Config = pcall(require, Mod)
    if Ok and Config then
        WallConfigs[WorldId] = Config
        return Config
    end
    return nil
end

----------------------------------------------------------------
-- Module
----------------------------------------------------------------
Module:CreateModule("FarmCore", function()
    local FarmCore = {}

    function FarmCore:GetStrength()
        return GetPlayerValue("Strength") or GetStat("Strength") or 0
    end

    function FarmCore:GetWins()
        return GetStat("Wins") or 0
    end

    function FarmCore:GetRebirths()
        return GetStat("Rebirths") or 0
    end

    function FarmCore:GetLevel()
        return GetPlayerValue("Level") or 1
    end

    function FarmCore:GetWorldId()
        local Root = GetHRP()
        return WorldIdFromPosition(Root and Root.Position)
    end

    function FarmCore:FireTrain(PadId)
        local Event = Remotes.ClickTrain
        if not Event then
            return false
        end
        return Safe(function()
            Event:FireServer(PadId)
        end) ~= nil
    end

    function FarmCore:FireCaveHit(WorldId)
        WorldId = WorldId or self:GetWorldId()
        local Index = math.clamp(WorldId, 1, 4)
        local Event = Remotes.CaveHit[Index] or Remotes.CaveHit[1]
        if not Event then
            return false
        end
        return Safe(function()
            Event:FireServer()
        end) ~= nil
    end

    function FarmCore:RequestRebirthState()
        local Fn = Remotes.Rebirth
        if not Fn then
            return nil
        end
        return Safe(function()
            return Fn:InvokeServer("GetState")
        end)
    end

    function FarmCore:DoRebirth()
        local Fn = Remotes.Rebirth
        if not Fn then
            return nil
        end
        return Safe(function()
            return Fn:InvokeServer("Rebirth")
        end)
    end

    function FarmCore:HatchEgg(EggName, Count)
        local Fn = Remotes.Pet
        if not Fn then
            return nil
        end
        return Safe(function()
            return Fn:InvokeServer("HatchEgg", EggName, Count or 1)
        end)
    end

    function FarmCore:BuyChest(Count)
        local Fn = Remotes.SwordChest
        if not Fn then
            return nil
        end
        return Safe(function()
            return Fn:InvokeServer("BuyChest", Count or 1)
        end)
    end

    function FarmCore:FindNearestTrainingPad()
        local Root = GetHRP()
        if not Root then
            return nil
        end

        local Best, BestDist = nil, math.huge
        local Keywords = { "training", "pad", "punch", "bag" }

        local function Scan(Parent)
            if not Parent then
                return
            end
            for _, Obj in Parent:GetDescendants() do
                local Lower = string.lower(Obj.Name)
                local Match = false
                for _, Key in Keywords do
                    if string.find(Lower, Key, 1, true) then
                        Match = true
                        break
                    end
                end
                if Match and (Obj:IsA("BasePart") or Obj:IsA("Model")) then
                    local Part = Obj:IsA("BasePart") and Obj or Obj:FindFirstChildWhichIsA("BasePart", true)
                    if Part then
                        local Dist = (Part.Position - Root.Position).Magnitude
                        if Dist < BestDist then
                            BestDist = Dist
                            Best = Part
                        end
                    end
                end
            end
        end

        Scan(workspace:FindFirstChild("PrototypeTrainingArea"))
        Scan(workspace:FindFirstChild("SIMULATOR MAP"))
        for i = 2, 6 do
            Scan(workspace:FindFirstChild("World" .. i) or workspace:FindFirstChild("SIMULATOR MAP World " .. i))
        end
        Scan(workspace)

        return Best, BestDist
    end

    function FarmCore:FindNearestCaveWall()
        local Root = GetHRP()
        if not Root then
            return nil
        end

        local Best, BestDist = nil, math.huge
        for _, Obj in workspace:GetDescendants() do
            if string.find(Obj.Name, "CaveWall", 1, true) then
                local Part = Obj:IsA("BasePart") and Obj or Obj:FindFirstChildWhichIsA("BasePart", true)
                if Part then
                    local Dist = (Part.Position - Root.Position).Magnitude
                    if Dist < BestDist then
                        BestDist = Dist
                        Best = Part
                    end
                end
            end
        end
        return Best, BestDist
    end

    function FarmCore:MoveToward(TargetPos, StopDistance)
        local Hum = GetHumanoid()
        local Root = GetHRP()
        if not Hum or not Root then
            return false
        end
        StopDistance = StopDistance or 4
        local Delta = Vector3.new(TargetPos.X - Root.Position.X, 0, TargetPos.Z - Root.Position.Z)
        if Delta.Magnitude <= StopDistance then
            Hum:Move(Vector3.zero, false)
            return true
        end
        Hum:Move(Delta.Unit, false)
        return false
    end

    function FarmCore:GoToCaveSpawn(WorldId)
        local Config = LoadWallConfig(WorldId or self:GetWorldId())
        if Config and Config.CAVE_SPAWN then
            return TeleportTo(Config.CAVE_SPAWN + Vector3.new(0, 3, 0))
        end
        if Config and Config.SPAWN_POS then
            return TeleportTo(Config.SPAWN_POS + Vector3.new(0, 3, 0))
        end
        return false
    end

    return FarmCore
end)

----------------------------------------------------------------
-- Configurations
----------------------------------------------------------------
local Configurations = Module.Configurations
local Configurable = Configurations:Create("AutoFarmHub")

Configurable:SetDefault("AutoTrain", false)
Configurable:SetDefault("AutoWall", false)
Configurable:SetDefault("AutoRebirth", false)
Configurable:SetDefault("AutoEgg", false)
Configurable:SetDefault("AutoChest", false)
Configurable:SetDefault("PreferTeleport", true)
Configurable:SetDefault("AntiAFK", true)
Configurable:SetDefault("EggName", "Basic Egg")
Configurable:SetDefault("ChestCount", "1")

Configurable:Load()

----------------------------------------------------------------
-- Queue + Core
----------------------------------------------------------------
local Queue = Module.GoodQueue:Create(false)
local FarmCore = Module.FarmCore
local Connections = Module.Connections
local Plugins = Module.Plugins

----------------------------------------------------------------
-- Threads (Flag ต้องตรงกับ Toggle Flag)
-- CreateOption(Flag, Function, Interval) → Thread
----------------------------------------------------------------

Queue:CreateOption("AutoTrain", function()
    if Settings.PreferTeleport then
        local Pad, Dist = FarmCore:FindNearestTrainingPad()
        if Pad and Dist and Dist > 12 then
            TeleportTo(Pad.Position + Vector3.new(0, 3, 0))
            task.wait(0.12)
        end
    end
    FarmCore:FireTrain(nil)
end, 0.05)

Queue:CreateOption("AutoWall", function()
    local WorldId = FarmCore:GetWorldId()
    local Wall, Dist = FarmCore:FindNearestCaveWall()

    if Wall then
        if Settings.PreferTeleport and Dist and Dist > 25 then
            TeleportTo(Wall.Position + Vector3.new(0, 2, -6))
            task.wait(0.08)
        else
            FarmCore:MoveToward(Wall.Position, 5)
        end
        FarmCore:FireCaveHit(WorldId)
    else
        FarmCore:GoToCaveSpawn(WorldId)
        FarmCore:FireCaveHit(WorldId)
    end
end, 0.1)

Queue:CreateOption("AutoRebirth", function()
    local State = FarmCore:RequestRebirthState()
    if State and State.CanRebirth then
        FarmCore:DoRebirth()
    end
end, 1)

Queue:CreateOption("AutoEgg", function()
    local EggName = Settings.EggName
    if type(EggName) ~= "string" or EggName == "" or EggName == "None" then
        EggName = "Basic Egg"
    end
    FarmCore:HatchEgg(EggName, 1)
end, 0.8)

Queue:CreateOption("AutoChest", function()
    local Count = tonumber(Settings.ChestCount) or 1
    if Count ~= 1 and Count ~= 5 and Count ~= 20 then
        Count = 1
    end
    FarmCore:BuyChest(Count)
end, 1.2)

----------------------------------------------------------------
-- Queue Layers (priority สูง → ต่ำ, return true = stop)
----------------------------------------------------------------

Queue:CreateOption("Priority Rebirth", function()
    if not Settings.AutoRebirth then
        return
    end
    local State = FarmCore:RequestRebirthState()
    if State and State.CanRebirth then
        local Result = FarmCore:DoRebirth()
        if Result then
            return true
        end
    end
end)

Queue:CreateOption("Idle Farm", function()
    -- fallback layer — threads ทำงานหลักอยู่แล้ว
end)

----------------------------------------------------------------
-- Anti AFK
----------------------------------------------------------------
Connections.Connect(LocalPlayer.Idled, function()
    if Settings.AntiAFK then
        Safe(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
do
    Plugins:Window(Queue, {
        "Auto Farm Hub",
        "Train • Wall • Egg • Chest • Rebirth",
    })

    local FarmTab = Plugins:CreateTab({
        "Farm",
        "Main automation",
        10723407389,
    })

    FarmTab:Section("Automation", function(Section)
        Plugins:Toggle(Section, {
            "Auto Train",
            "ClickTrainEvent — farm strength on pads",
        }, "AutoTrain")

        Plugins:Toggle(Section, {
            "Auto Wall",
            "Move/TP to CaveWall + CaveHitEvent",
        }, "AutoWall", function(Value)
            if Value then
                FarmCore:GoToCaveSpawn(FarmCore:GetWorldId())
            end
        end)

        Plugins:Toggle(Section, {
            "Auto Rebirth",
            "RebirthFunction when CanRebirth",
        }, "AutoRebirth")

        Plugins:Toggle(Section, {
            "Auto Egg",
            "PetFunction HatchEgg (ตั้งชื่อไข่ใน Settings)",
        }, "AutoEgg")

        Plugins:Toggle(Section, {
            "Auto Chest / Sword",
            "SwordChestFunction BuyChest",
        }, "AutoChest")
    end)

    FarmTab:Section("Options", function(Section)
        Plugins:Toggle(Section, {
            "Prefer Teleport",
            "TP ไป pad / wall แทนเดิน",
        }, "PreferTeleport")

        Plugins:Toggle(Section, {
            "Anti AFK",
            "กัน idle kick",
        }, "AntiAFK")
    end)

    local SettingsTab = Plugins:CreateTab({
        "Settings",
        "Egg / Chest / Teleport",
        10734950309,
    })

    SettingsTab:Section("Egg & Chest", function(Section)
        Plugins:Textbox(Section, {
            "Egg Name",
            "ชื่อไข่ เช่น Basic Egg, Rainbow Egg",
        }, "EggName")

        Plugins:Dropdown(Section, "Chest Count", { "1", "5", "20" }, "ChestCount")
    end)

    SettingsTab:Section("Actions", function(Section)
        Plugins:Button(Section, {
            "TP Cave Spawn",
            "เทเลพอร์ตไปจุดเริ่มถ้ำของ world ปัจจุบัน",
        }, function()
            FarmCore:GoToCaveSpawn(FarmCore:GetWorldId())
            Plugins:Notify({ "Teleport", "Cave spawn", 10723407389 }, 3)
        end)

        Plugins:Button(Section, {
            "TP Training Pad",
            "เทเลพอร์ตไป training pad ใกล้สุด",
        }, function()
            local Pad = FarmCore:FindNearestTrainingPad()
            if Pad then
                TeleportTo(Pad.Position + Vector3.new(0, 3, 0))
                Plugins:Notify({ "Teleport", "Training pad", 10723407389 }, 3)
            else
                Plugins:Notify({ "Teleport", "ไม่เจอ pad", 10723407389 }, 3)
            end
        end)

        Plugins:Button(Section, {
            "Force Rebirth",
            "เรียก Rebirth ทันที",
        }, function()
            local Result = FarmCore:DoRebirth()
            local Msg = Result and (Result.Message or "OK") or "Failed / not ready"
            Plugins:Notify({ "Rebirth", tostring(Msg), 10723407389 }, 3)
        end)

        Plugins:Button(Section, {
            "Buy Chest x1",
            "ซื้อ chest 1 ครั้งทันที",
        }, function()
            FarmCore:BuyChest(1)
            Plugins:Notify({ "Chest", "BuyChest(1) sent", 10723407389 }, 3)
        end)
    end)

    local StatsTab = Plugins:CreateTab({
        "Stats",
        "Live player stats",
        10734952131,
    })

    StatsTab:Section("Player", function(Section)
        Plugins:Button(Section, {
            "Print Stats",
            "แสดง Strength / Wins / Rebirths / Level / World ใน console",
        }, function()
            local Text = string.format(
                "Strength=%s | Wins=%s | Rebirths=%s | Level=%s | World=%s",
                tostring(FarmCore:GetStrength()),
                tostring(FarmCore:GetWins()),
                tostring(FarmCore:GetRebirths()),
                tostring(FarmCore:GetLevel()),
                tostring(FarmCore:GetWorldId())
            )
            print("[AutoFarmHub]", Text)
            Plugins:Notify({ "Stats", Text, 10723407389 }, 5)
        end)

        Plugins:Button(Section, {
            "Check Rebirth State",
            "Invoke GetState จาก RebirthFunction",
        }, function()
            local State = FarmCore:RequestRebirthState()
            if not State then
                Plugins:Notify({ "Rebirth", "GetState failed", 10723407389 }, 3)
                return
            end
            local Text = string.format(
                "CanRebirth=%s | Rebirths=%s | Level=%s",
                tostring(State.CanRebirth),
                tostring(State.Rebirths),
                tostring(State.CurrentLevel)
            )
            print("[AutoFarmHub]", Text)
            Plugins:Notify({ "Rebirth State", Text, 10723407389 }, 5)
        end)
    end)

    Queue:StartQueue()
end

print("[AutoFarmHub] loaded")
print("  Toggle: AutoTrain | AutoWall | AutoRebirth | AutoEgg | AutoChest")
print("  Settings: EggName, ChestCount (1/5/20)")
