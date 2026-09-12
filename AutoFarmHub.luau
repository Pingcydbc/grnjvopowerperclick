--[[
    Auto Farm / Hub — Strength / Wall Simulator
    STANDALONE (ไม่พึ่ง Opengame / GitHub ภายนอก)

    Features:
      Auto Train  → ClickTrainEvent
      Auto Wall   → CaveHitEvent + move/TP
      Auto Rebirth → RebirthFunction
      Auto Egg    → PetFunction HatchEgg
      Auto Chest  → SwordChestFunction BuyChest
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Character, Humanoid, HRP

local function BindCharacter(Char)
    Character = Char
    Humanoid = Char:WaitForChild("Humanoid")
    HRP = Char:WaitForChild("HumanoidRootPart")
end

if LocalPlayer.Character then
    BindCharacter(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(BindCharacter)

----------------------------------------------------------------
-- Settings (in-memory + optional writefile)
----------------------------------------------------------------
local Settings = {
    AutoTrain = false,
    AutoWall = false,
    AutoRebirth = false,
    AutoEgg = false,
    AutoChest = false,
    PreferTeleport = true,
    AntiAFK = true,
    EggName = "Basic Egg",
    ChestCount = 1,
}

do
    local Ok, Data = pcall(function()
        if isfile and isfile("AutoFarmHub.json") then
            return HttpService:JSONDecode(readfile("AutoFarmHub.json"))
        end
        return nil
    end)
    if Ok and type(Data) == "table" then
        for K, V in pairs(Data) do
            if Settings[K] ~= nil then
                Settings[K] = V
            end
        end
    end
end

local function SaveSettings()
    pcall(function()
        if writefile then
            writefile("AutoFarmHub.json", HttpService:JSONEncode(Settings))
        end
    end)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function Safe(Fn, ...)
    local Ok, A, B, C = pcall(Fn, ...)
    if Ok then
        return A, B, C
    end
    return nil
end

local function WaitRemote(Name, Timeout)
    return ReplicatedStorage:FindFirstChild(Name) or ReplicatedStorage:WaitForChild(Name, Timeout or 8)
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
    ClickTrain = WaitRemote("ClickTrainEvent", 10),
    Rebirth = WaitRemote("RebirthFunction", 10),
    Pet = WaitRemote("PetFunction", 10),
    SwordChest = WaitRemote("SwordChestFunction", 15),
    CaveHit = {
        WaitRemote("CaveHitEvent", 8),
        WaitRemote("CaveHitEvent2", 8),
        WaitRemote("CaveHitEvent3", 8),
        WaitRemote("CaveHitEvent4", 8),
    },
}

----------------------------------------------------------------
-- WallConfig
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
-- Farm Core
----------------------------------------------------------------
local Farm = {}

function Farm.GetStrength()
    return GetPlayerValue("Strength") or GetStat("Strength") or 0
end

function Farm.GetWins()
    return GetStat("Wins") or 0
end

function Farm.GetRebirths()
    return GetStat("Rebirths") or 0
end

function Farm.GetLevel()
    return GetPlayerValue("Level") or 1
end

function Farm.GetWorldId()
    local Root = GetHRP()
    return WorldIdFromPosition(Root and Root.Position)
end

function Farm.FireTrain(PadId)
    local Event = Remotes.ClickTrain
    if not Event then
        return false
    end
    return Safe(function()
        Event:FireServer(PadId)
    end) ~= nil
end

function Farm.FireCaveHit(WorldId)
    WorldId = WorldId or Farm.GetWorldId()
    local Event = Remotes.CaveHit[math.clamp(WorldId, 1, 4)] or Remotes.CaveHit[1]
    if not Event then
        return false
    end
    return Safe(function()
        Event:FireServer()
    end) ~= nil
end

function Farm.RequestRebirthState()
    local Fn = Remotes.Rebirth
    if not Fn then
        return nil
    end
    return Safe(function()
        return Fn:InvokeServer("GetState")
    end)
end

function Farm.DoRebirth()
    local Fn = Remotes.Rebirth
    if not Fn then
        return nil
    end
    return Safe(function()
        return Fn:InvokeServer("Rebirth")
    end)
end

function Farm.HatchEgg(EggName, Count)
    local Fn = Remotes.Pet
    if not Fn then
        return nil
    end
    return Safe(function()
        return Fn:InvokeServer("HatchEgg", EggName, Count or 1)
    end)
end

function Farm.BuyChest(Count)
    local Fn = Remotes.SwordChest
    if not Fn then
        return nil
    end
    return Safe(function()
        return Fn:InvokeServer("BuyChest", Count or 1)
    end)
end

function Farm.FindNearestTrainingPad()
    local Root = GetHRP()
    if not Root then
        return nil
    end
    local Best, BestDist = nil, math.huge
    local Keys = { "training", "pad", "punch", "bag" }

    local function Scan(Parent)
        if not Parent then
            return
        end
        for _, Obj in Parent:GetDescendants() do
            local Lower = string.lower(Obj.Name)
            local Match = false
            for _, Key in Keys do
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
        Scan(workspace:FindFirstChild("World" .. i))
        Scan(workspace:FindFirstChild("SIMULATOR MAP World " .. i))
    end
    Scan(workspace)
    return Best, BestDist
end

function Farm.FindNearestCaveWall()
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

function Farm.MoveToward(TargetPos, StopDistance)
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

function Farm.GoToCaveSpawn(WorldId)
    local Config = LoadWallConfig(WorldId or Farm.GetWorldId())
    if Config and Config.CAVE_SPAWN then
        return TeleportTo(Config.CAVE_SPAWN + Vector3.new(0, 3, 0))
    end
    if Config and Config.SPAWN_POS then
        return TeleportTo(Config.SPAWN_POS + Vector3.new(0, 3, 0))
    end
    return false
end

----------------------------------------------------------------
-- Auto loops
----------------------------------------------------------------
local Running = true

task.spawn(function()
    while Running do
        if Settings.AutoTrain then
            if Settings.PreferTeleport then
                local Pad, Dist = Farm.FindNearestTrainingPad()
                if Pad and Dist and Dist > 12 then
                    TeleportTo(Pad.Position + Vector3.new(0, 3, 0))
                    task.wait(0.1)
                end
            end
            Farm.FireTrain(nil)
        end
        task.wait(0.05)
    end
end)

task.spawn(function()
    while Running do
        if Settings.AutoWall then
            local WorldId = Farm.GetWorldId()
            local Wall, Dist = Farm.FindNearestCaveWall()
            if Wall then
                if Settings.PreferTeleport and Dist and Dist > 25 then
                    TeleportTo(Wall.Position + Vector3.new(0, 2, -6))
                    task.wait(0.08)
                else
                    Farm.MoveToward(Wall.Position, 5)
                end
                Farm.FireCaveHit(WorldId)
            else
                Farm.GoToCaveSpawn(WorldId)
                Farm.FireCaveHit(WorldId)
            end
        end
        task.wait(0.1)
    end
end)

task.spawn(function()
    while Running do
        if Settings.AutoRebirth then
            local State = Farm.RequestRebirthState()
            if State and State.CanRebirth then
                Farm.DoRebirth()
            end
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while Running do
        if Settings.AutoEgg then
            local Name = Settings.EggName
            if type(Name) ~= "string" or Name == "" then
                Name = "Basic Egg"
            end
            Farm.HatchEgg(Name, 1)
        end
        task.wait(0.8)
    end
end)

task.spawn(function()
    while Running do
        if Settings.AutoChest then
            local Count = tonumber(Settings.ChestCount) or 1
            if Count ~= 1 and Count ~= 5 and Count ~= 20 then
                Count = 1
            end
            Farm.BuyChest(Count)
        end
        task.wait(1.2)
    end
end)

-- Anti AFK
LocalPlayer.Idled:Connect(function()
    if Settings.AntiAFK then
        Safe(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

----------------------------------------------------------------
-- Simple UI (ScreenGui — ไม่พึ่ง library ภายนอก)
----------------------------------------------------------------
local function MakeCorner(Parent, Radius)
    local C = Instance.new("UICorner")
    C.CornerRadius = UDim.new(0, Radius or 8)
    C.Parent = Parent
    return C
end

local function MakeStroke(Parent, Color, Thickness)
    local S = Instance.new("UIStroke")
    S.Color = Color or Color3.fromRGB(60, 60, 80)
    S.Thickness = Thickness or 1
    S.Parent = Parent
    return S
end

local Old = PlayerGui:FindFirstChild("AutoFarmHubUI")
if Old then
    Old:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AutoFarmHubUI"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(320, 420)
Main.Position = UDim2.new(0.5, -160, 0.5, -210)
Main.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = Gui
MakeCorner(Main, 12)
MakeStroke(Main, Color3.fromRGB(80, 80, 120), 1)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 0, 36)
Title.Position = UDim2.fromOffset(12, 8)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextColor3 = Color3.fromRGB(240, 240, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "Auto Farm Hub"
Title.Parent = Main

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(28, 28)
CloseBtn.Position = UDim2.new(1, -36, 0, 10)
CloseBtn.BackgroundColor3 = Color3.fromRGB(50, 30, 40)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
CloseBtn.Parent = Main
MakeCorner(CloseBtn, 6)

CloseBtn.MouseButton1Click:Connect(function()
    Running = false
    Gui:Destroy()
end)

local List = Instance.new("ScrollingFrame")
List.Size = UDim2.new(1, -24, 1, -56)
List.Position = UDim2.fromOffset(12, 48)
List.BackgroundTransparency = 1
List.BorderSizePixel = 0
List.ScrollBarThickness = 4
List.CanvasSize = UDim2.fromOffset(0, 0)
List.AutomaticCanvasSize = Enum.AutomaticSize.Y
List.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 8)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Parent = List

local function AddToggle(Key, Label, Order)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 36)
    Row.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
    Row.BorderSizePixel = 0
    Row.LayoutOrder = Order
    Row.Parent = List
    MakeCorner(Row, 8)

    local Name = Instance.new("TextLabel")
    Name.Size = UDim2.new(1, -70, 1, 0)
    Name.Position = UDim2.fromOffset(12, 0)
    Name.BackgroundTransparency = 1
    Name.Font = Enum.Font.Gotham
    Name.TextSize = 13
    Name.TextColor3 = Color3.fromRGB(220, 220, 235)
    Name.TextXAlignment = Enum.TextXAlignment.Left
    Name.Text = Label
    Name.Parent = Row

    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.fromOffset(52, 24)
    Btn.Position = UDim2.new(1, -60, 0.5, -12)
    Btn.Font = Enum.Font.GothamBold
    Btn.TextSize = 12
    Btn.Parent = Row
    MakeCorner(Btn, 6)

    local function Paint()
        if Settings[Key] then
            Btn.BackgroundColor3 = Color3.fromRGB(40, 160, 90)
            Btn.Text = "ON"
            Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            Btn.BackgroundColor3 = Color3.fromRGB(70, 40, 50)
            Btn.Text = "OFF"
            Btn.TextColor3 = Color3.fromRGB(255, 180, 180)
        end
    end
    Paint()

    Btn.MouseButton1Click:Connect(function()
        Settings[Key] = not Settings[Key]
        Paint()
        SaveSettings()
        if Key == "AutoWall" and Settings.AutoWall then
            Farm.GoToCaveSpawn(Farm.GetWorldId())
        end
    end)
end

local function AddButton(Label, Order, Callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 34)
    Btn.BackgroundColor3 = Color3.fromRGB(45, 45, 70)
    Btn.Font = Enum.Font.Gotham
    Btn.TextSize = 13
    Btn.TextColor3 = Color3.fromRGB(230, 230, 255)
    Btn.Text = Label
    Btn.LayoutOrder = Order
    Btn.Parent = List
    MakeCorner(Btn, 8)
    Btn.MouseButton1Click:Connect(function()
        Safe(Callback)
    end)
end

local function AddTextBox(Key, Placeholder, Order)
    local Box = Instance.new("TextBox")
    Box.Size = UDim2.new(1, 0, 0, 34)
    Box.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
    Box.Font = Enum.Font.Gotham
    Box.TextSize = 13
    Box.TextColor3 = Color3.fromRGB(230, 230, 255)
    Box.PlaceholderText = Placeholder
    Box.Text = tostring(Settings[Key] or "")
    Box.ClearTextOnFocus = false
    Box.LayoutOrder = Order
    Box.Parent = List
    MakeCorner(Box, 8)
    Box.FocusLost:Connect(function()
        Settings[Key] = Box.Text
        SaveSettings()
    end)
end

-- Toggles
AddToggle("AutoTrain", "Auto Train", 1)
AddToggle("AutoWall", "Auto Wall", 2)
AddToggle("AutoRebirth", "Auto Rebirth", 3)
AddToggle("AutoEgg", "Auto Egg", 4)
AddToggle("AutoChest", "Auto Chest / Sword", 5)
AddToggle("PreferTeleport", "Prefer Teleport", 6)
AddToggle("AntiAFK", "Anti AFK", 7)

-- Egg name + chest count
AddTextBox("EggName", "Egg Name (e.g. Basic Egg)", 8)

local ChestRow = Instance.new("Frame")
ChestRow.Size = UDim2.new(1, 0, 0, 34)
ChestRow.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
ChestRow.BorderSizePixel = 0
ChestRow.LayoutOrder = 9
ChestRow.Parent = List
MakeCorner(ChestRow, 8)

local ChestLabel = Instance.new("TextLabel")
ChestLabel.Size = UDim2.new(0.45, 0, 1, 0)
ChestLabel.Position = UDim2.fromOffset(12, 0)
ChestLabel.BackgroundTransparency = 1
ChestLabel.Font = Enum.Font.Gotham
ChestLabel.TextSize = 13
ChestLabel.TextColor3 = Color3.fromRGB(220, 220, 235)
ChestLabel.TextXAlignment = Enum.TextXAlignment.Left
ChestLabel.Text = "Chest Count"
ChestLabel.Parent = ChestRow

local Counts = { 1, 5, 20 }
local CountIdx = 1
for i, C in ipairs(Counts) do
    if C == (tonumber(Settings.ChestCount) or 1) then
        CountIdx = i
    end
end

local CountBtn = Instance.new("TextButton")
CountBtn.Size = UDim2.fromOffset(64, 24)
CountBtn.Position = UDim2.new(1, -72, 0.5, -12)
CountBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 90)
CountBtn.Font = Enum.Font.GothamBold
CountBtn.TextSize = 12
CountBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CountBtn.Text = "x" .. tostring(Counts[CountIdx])
CountBtn.Parent = ChestRow
MakeCorner(CountBtn, 6)

CountBtn.MouseButton1Click:Connect(function()
    CountIdx = CountIdx % #Counts + 1
    Settings.ChestCount = Counts[CountIdx]
    CountBtn.Text = "x" .. tostring(Counts[CountIdx])
    SaveSettings()
end)

-- Action buttons
AddButton("TP Cave Spawn", 10, function()
    Farm.GoToCaveSpawn(Farm.GetWorldId())
end)

AddButton("TP Training Pad", 11, function()
    local Pad = Farm.FindNearestTrainingPad()
    if Pad then
        TeleportTo(Pad.Position + Vector3.new(0, 3, 0))
    end
end)

AddButton("Force Rebirth Now", 12, function()
    local Result = Farm.DoRebirth()
    print("[AutoFarmHub] Rebirth:", Result and (Result.Message or "ok") or "failed")
end)

AddButton("Buy Chest x1 Now", 13, function()
    Farm.BuyChest(1)
end)

AddButton("Print Stats", 14, function()
    print(string.format(
        "[AutoFarmHub] Strength=%s Wins=%s Rebirths=%s Level=%s World=%s",
        tostring(Farm.GetStrength()),
        tostring(Farm.GetWins()),
        tostring(Farm.GetRebirths()),
        tostring(Farm.GetLevel()),
        tostring(Farm.GetWorldId())
    ))
end)

print("[AutoFarmHub] STANDALONE loaded — ไม่พึ่ง GitHub / Opengame")
print("  Remotes: ClickTrain=", tostring(Remotes.ClickTrain ~= nil),
    " Rebirth=", tostring(Remotes.Rebirth ~= nil),
    " Pet=", tostring(Remotes.Pet ~= nil),
    " SwordChest=", tostring(Remotes.SwordChest ~= nil))
