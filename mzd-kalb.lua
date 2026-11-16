-- =====================================================================
-- MzD KALB script - Ultra-Void v3.3 (Total World Wipe + Exact Weight Equip)
-- =====================================================================

if setfpscap then pcall(setfpscap, 20) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local pGui = player:WaitForChild("PlayerGui")

-- Houd 3D-rendering altijd aan zodat jij, je platform en Beach Gym zichtbaar zijn
pcall(function()
    RunService:Set3dRenderingEnabled(true)
end)

local bonusRemote = nil
local weightEquipRemote = nil
task.spawn(function()
    local shared = ReplicatedStorage:WaitForChild("Shared", 15)
    local packages = shared and shared:WaitForChild("Packages", 15)
    local network = packages and packages:WaitForChild("Network", 15)
    if network then
        bonusRemote = network:FindFirstChild("rev_TaviMishkal") or network:WaitForChild("rev_TaviMishkal", 10)
        weightEquipRemote = network:FindFirstChild("rev_WeightEquip") or network:WaitForChild("rev_WeightEquip", 10)
    end
end)

local uiName = "MzD_KALB_HUD"
local existing = (gethui and gethui():FindFirstChild(uiName)) or CoreGui:FindFirstChild(uiName)
if existing then existing:Destroy() end

-- =====================================================================
-- Officiële Gewichten (gesorteerd van sterkst naar zwakst)
-- =====================================================================
local WEIGHT_PRIORITY = {
    "Black Hole Barbell",
    "Big Jupiter",
    "Planet Barbell",
    "Cosmic Barbell",
    "Neon Pulse",
    "Heaven Plate",
    "Giant Gold Star Barbell",
    "Mega Golden Barbell",
    "Elephant Plate",
    "Lucky Block Barbell",
    "Emerald Barbell",
    "Ice Barbell",
    "Golden Barbell",
    "Donut Barbell",
    "Bone Barbell",
    "Stone Block",
    "Iron Plate",
    "Copper Plate",
    "Wooden Stick"
}

local WEIGHT_LOOKUP = {}
for rank, wName in ipairs(WEIGHT_PRIORITY) do
    WEIGHT_LOOKUP[string.lower(wName)] = rank
end

-- =====================================================================
-- Status & Tellers
-- =====================================================================
local autoLift = true
local autoBonus = true
local autoBeachGym = true
local antiAfkEnabled = true
local autoReconnectEnabled = true

local count2x, count5x, count10x, totalBonusCount = 0, 0, 0, 0
local gymTpCount, lastReactionMs, afkPulses = 0, 0, 0
local lastSeenMultiplier = "x2"
local lastBonusSpawnTick = 0
local activeBeachGym = nil
local activeWeightName = "ZOEKEN..."

local conns = {}
local gymWatchConns = {}

local Val2xLabel, Val5xLabel, Val10xLabel = nil, nil, nil
local ValTotalLabel, ValGymLabel, ValMsLabel, FooterStatsLabel = nil, nil, nil, nil

local function updateDashboard()
    if Val2xLabel then Val2xLabel.Text = tostring(count2x) end
    if Val5xLabel then Val5xLabel.Text = tostring(count5x) end
    if Val10xLabel then Val10xLabel.Text = tostring(count10x) end
    if ValTotalLabel then ValTotalLabel.Text = tostring(totalBonusCount) end
    if ValGymLabel then ValGymLabel.Text = tostring(gymTpCount) end
    if ValMsLabel then ValMsLabel.Text = tostring(lastReactionMs) .. "ms" end
    if FooterStatsLabel then
        FooterStatsLabel.Text = string.format("WEIGHT: %s  |  AFK: %d", string.upper(activeWeightName), afkPulses)
    end
end

-- =====================================================================
-- TRAININGSPLATFORM BEHEER (Altijd grond onder je voeten)
-- =====================================================================
local function removeSafePlatform()
    local existingPad = Workspace:FindFirstChild("MzD_SafePlatform")
    if existingPad then existingPad:Destroy() end
end

local function spawnPlatformUnderPlayer(char)
    local targetChar = char or player.Character
    if not targetChar then return end
    local hrp = targetChar:WaitForChild("HumanoidRootPart", 5)
    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if not hrp then return end

    removeSafePlatform()

    local hipHeight = hum and hum.HipHeight or 2
    local footOffset = hipHeight + (hrp.Size.Y * 0.5)
    local padPos = hrp.Position - Vector3.new(0, footOffset + 1, 0)

    local safePad = Instance.new("Part")
    safePad.Name = "MzD_SafePlatform"
    safePad.Size = Vector3.new(18, 2, 18)
    safePad.Position = padPos
    safePad.Anchored = true
    safePad.CanCollide = true
    safePad.Material = Enum.Material.SmoothPlastic
    safePad.Color = Color3.fromRGB(16, 42, 32)
    safePad.TopSurface = Enum.SurfaceType.Smooth
    safePad.BottomSurface = Enum.SurfaceType.Smooth
    safePad.Parent = Workspace

    local border = Instance.new("SelectionBox")
    border.Adornee = safePad
    border.Color3 = Color3.fromRGB(0, 255, 145)
    border.LineThickness = 0.04
    border.SurfaceTransparency = 1
    border.Parent = safePad

    hrp.AssemblyLinearVelocity = Vector3.zero
    return safePad
end

-- =====================================================================
-- TOTALE WERELD- & UI-SLOOP (Alleen jij, je platform & Beach Gym)
-- =====================================================================
local trackedEffects = setmetatable({}, {__mode = "k"})

local function disableVisualNoise(inst)
    if not inst or not inst.Parent then return end
    if inst:IsDescendantOf(CoreGui) then return end
    pcall(function()
        if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
            or inst:IsA("Sparkles") or inst:IsA("Fire") or inst:IsA("Smoke")
            or inst:IsA("Highlight") or inst:IsA("PointLight")
            or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
            inst.Enabled = false
            if not trackedEffects[inst] then
                trackedEffects[inst] = true
                inst:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if inst.Enabled then inst.Enabled = false end
                end)
            end
        elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
            local gm = Workspace:FindFirstChild("Debris") and Workspace.Debris:FindFirstChild("GymMachine")
            if not (gm and inst:IsDescendantOf(gm)) then
                inst.Enabled = false
            end
        elseif inst:IsA("Sound") then
            inst.Volume = 0
        elseif inst:IsA("Clouds") then
            inst.Enabled = false
            inst.Cover = 0
        end
    end)
end

local function stripAllGameGuis()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
    end)

    for _, gui in ipairs(pGui:GetChildren()) do
        if gui:IsA("LayerCollector") and gui.Name ~= uiName then
            if gui.Name == "KickUpgrades" then
                gui.Enabled = true
                for _, child in ipairs(gui:GetChildren()) do
                    if child:IsA("GuiObject") and child.Name ~= "Bonus" and child.Name ~= "PopBonus" then
                        child.Visible = false
                    end
                end
            else
                gui.Enabled = false
            end
        end
    end
end

local function setupCleanVoidEnvironment()
    pcall(function()
        Workspace.Terrain:Clear()
        for _, c in ipairs(Workspace.Terrain:GetChildren()) do
            c:Destroy()
        end
    end)

    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.ClockTime = 12
        Lighting.Brightness = 1.4
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.Ambient = Color3.fromRGB(165, 175, 170)
        Lighting.OutdoorAmbient = Color3.fromRGB(165, 175, 170)
        Lighting.FogEnd = 9e9

        for _, eff in ipairs(Lighting:GetChildren()) do
            if eff.Name ~= "MzD_VoidSky" then
                eff:Destroy()
            end
        end

        if not Lighting:FindFirstChild("MzD_VoidSky") then
            local sky = Instance.new("Sky")
            sky.Name = "MzD_VoidSky"
            sky.CelestialBodiesShown = false
            sky.StarCount = 0
            sky.SkyboxBk = "rbxassetid://0"
            sky.SkyboxDn = "rbxassetid://0"
            sky.SkyboxFt = "rbxassetid://0"
            sky.SkyboxLf = "rbxassetid://0"
            sky.SkyboxRt = "rbxassetid://0"
            sky.SkyboxUp = "rbxassetid://0"
            sky.Parent = Lighting
        end

        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
end

local function obliterateWorldNow()
    if not activeBeachGym then
        spawnPlatformUnderPlayer(player.Character)
    end

    setupCleanVoidEnvironment()
    stripAllGameGuis()

    local char = player.Character
    local emptyFolders = {
        ["Areas"] = true,
        ["Zones"] = true,
        ["Machine"] = true,
        ["KickUpgrades"] = true
    }
    local protectedRoots = {
        ["Camera"] = true,
        ["Terrain"] = true,
        ["Players"] = true,
        ["Debris"] = true,
        ["MzD_SafePlatform"] = true,
        [player.Name] = true
    }

    for _, obj in ipairs(Workspace:GetChildren()) do
        if emptyFolders[obj.Name] then
            pcall(function() obj:ClearAllChildren() end)
        elseif not protectedRoots[obj.Name] and obj ~= char then
            pcall(function() obj:Destroy() end)
        end
    end

    local playersFolder = Workspace:FindFirstChild("Players")
    if playersFolder then
        for _, pModel in ipairs(playersFolder:GetChildren()) do
            if pModel.Name ~= player.Name then
                pcall(function() pModel:Destroy() end)
            end
        end
    end

    local debrisFolder = Workspace:FindFirstChild("Debris")
    if debrisFolder then
        for _, dChild in ipairs(debrisFolder:GetChildren()) do
            if dChild.Name ~= "GymMachine" then
                pcall(function() dChild:Destroy() end)
            else
                for _, gmChild in ipairs(dChild:GetChildren()) do
                    if string.lower(gmChild.Name) ~= "beach gym" then
                        pcall(function() gmChild:Destroy() end)
                    end
                end
            end
        end
    end

    if char then
        for _, desc in ipairs(char:GetDescendants()) do
            disableVisualNoise(desc)
        end
    end
end

table.insert(conns, Workspace.ChildAdded:Connect(function(obj)
    task.defer(function()
        if not obj or not obj.Parent then return end
        local name = obj.Name
        if name == "MzD_SafePlatform" or name == "Camera" or name == "Terrain"
            or name == "Players" or name == "Debris" or name == player.Name
            or obj == player.Character then
            return
        end
        if name == "Areas" or name == "Zones" or name == "Machine" or name == "KickUpgrades" then
            pcall(function() obj:ClearAllChildren() end)
            return
        end
        pcall(function() obj:Destroy() end)
    end)
end))

table.insert(conns, Workspace.DescendantAdded:Connect(function(desc)
    task.defer(function()
        if not desc or not desc.Parent then return end
        local pf = Workspace:FindFirstChild("Players")
        if pf and desc.Parent == pf and desc.Name ~= player.Name then
            pcall(function() desc:Destroy() end)
            return
        end
        local df = Workspace:FindFirstChild("Debris")
        if df and desc.Parent == df and desc.Name ~= "GymMachine" then
            pcall(function() desc:Destroy() end)
            return
        end
        local gm = df and df:FindFirstChild("GymMachine")
        if gm and desc.Parent == gm and string.lower(desc.Name) ~= "beach gym" then
            pcall(function() desc:Destroy() end)
            return
        end
        disableVisualNoise(desc)
    end)
end))

table.insert(conns, pGui.ChildAdded:Connect(function(gui)
    task.defer(function()
        if gui and gui.Parent and gui:IsA("LayerCollector") and gui.Name ~= uiName then
            if gui.Name == "KickUpgrades" then
                stripAllGameGuis()
            else
                pcall(function() gui.Enabled = false end)
            end
        end
    end)
end))

table.insert(conns, Lighting.ChildAdded:Connect(function(eff)
    task.defer(function()
        if eff and eff.Parent and eff.Name ~= "MzD_VoidSky" then
            pcall(function() eff:Destroy() end)
        end
    end)
end))

-- =====================================================================
-- EXACTE WEIGHT EQUIP (Uit Backpack of WeightUI) & AUTO-LIFT
-- =====================================================================
local function getBestWeightTool()
    local bestTool = nil
    local bestRank = 999
    local isEquipped = false

    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then
                local rank = WEIGHT_LOOKUP[string.lower(item.Name)]
                if rank and rank < bestRank then
                    bestRank = rank
                    bestTool = item
                    isEquipped = true
                end
            end
        end
    end

    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                local rank = WEIGHT_LOOKUP[string.lower(item.Name)]
                if rank and rank < bestRank then
                    bestRank = rank
                    bestTool = item
                    isEquipped = false
                end
            end
        end
    end

    return bestTool, isEquipped
end

local lastInventoryPull = 0
local function pullWeightFromWeightUI()
    if tick() - lastInventoryPull < 2.5 then return end
    lastInventoryPull = tick()

    local frames = pGui:FindFirstChild("Frames")
    local weightUI = frames and frames:FindFirstChild("WeightUI")
    local scroller = weightUI and weightUI:FindFirstChild("ScrollingFrame")

    for _, wName in ipairs(WEIGHT_PRIORITY) do
        local entry = scroller and scroller:FindFirstChild(wName)
        if entry then
            if weightEquipRemote then
                pcall(function() weightEquipRemote:FireServer(wName) end)
            end
            local btns = entry:FindFirstChild("Buttons")
            local eqBtn = btns and btns:FindFirstChild("Equipped")
            if eqBtn and eqBtn:IsA("GuiButton") then
                pcall(function()
                    if getconnections then
                        for _, c in pairs(getconnections(eqBtn.MouseButton1Click)) do c:Fire() end
                        for _, c in pairs(getconnections(eqBtn.Activated)) do c:Fire() end
                    end
                    if firesignal then
                        pcall(firesignal, eqBtn.MouseButton1Click)
                        pcall(firesignal, eqBtn.Activated)
                    end
                end)
            end
            task.wait(0.15)
            local found = getBestWeightTool()
            if found then return end
        end
    end
end

task.spawn(function()
    local clickTick = 0
    while true do
        task.wait(0.08)
        if not CoreGui:FindFirstChild(uiName) and not (gethui and gethui():FindFirstChild(uiName)) then
            break
        end
        if autoLift then
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local tool, isEquipped = getBestWeightTool()
                if not tool then
                    task.spawn(pullWeightFromWeightUI)
                else
                    if activeWeightName ~= tool.Name then
                        activeWeightName = tool.Name
                        updateDashboard()
                    end
                    if not isEquipped then
                        pcall(function() hum:EquipTool(tool) end)
                    else
                        pcall(function() tool:Activate() end)
                    end
                end

                clickTick = clickTick + 1
                if clickTick % 2 == 0 then
                    pcall(function()
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton1(Vector2.new(0, 0))
                    end)
                end
            end
        end
    end
end)

-- =====================================================================
-- 4-LAAGS ANTI-AFK & AUTO-RECONNECT
-- =====================================================================
local function triggerAfkPulse()
    if not antiAfkEnabled then return end
    afkPulses = afkPulses + 1
    updateDashboard()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.RightControl, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.RightControl, false, game)
    end)
end

pcall(function()
    if getconnections then
        for _, conn in pairs(getconnections(player.Idled)) do
            if conn.Disable then conn:Disable() end
        end
    end
end)
table.insert(conns, player.Idled:Connect(triggerAfkPulse))

task.spawn(function()
    local cycle = 0
    while true do
        task.wait(180)
        if not CoreGui:FindFirstChild(uiName) and not (gethui and gethui():FindFirstChild(uiName)) then break end
        if setfpscap then pcall(setfpscap, 20) end
        if antiAfkEnabled then
            cycle = cycle + 1
            triggerAfkPulse()
            if cycle % 2 == 0 then
                pcall(function()
                    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
                end)
            end
        end
    end
end)

local isReconnecting = false
table.insert(conns, GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and msg ~= "" and autoReconnectEnabled and not isReconnecting then
        isReconnecting = true
        task.wait(2)
        pcall(function()
            if #Players:GetPlayers() <= 1 then
                player:Kick("\n[MzD KALB] Auto-Reconnecting...")
                task.wait(0.5)
                TeleportService:Teleport(game.PlaceId, player)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
            end
        end)
    end
end))

-- =====================================================================
-- BEACH GYM TELEPORT + TERUG OP EIGEN PLATFORM NA DESPAWN
-- =====================================================================
local function getBeachCenterSurface(gymObj)
    local floorPart = nil
    local bestArea = 0
    for _, desc in ipairs(gymObj:GetDescendants()) do
        if desc:IsA("BasePart") and desc.CanCollide then
            local area = desc.Size.X * desc.Size.Z
            if area > bestArea then
                bestArea = area
                floorPart = desc
            end
        end
    end
    if not floorPart and gymObj:IsA("BasePart") then floorPart = gymObj end

    local cf, size
    if gymObj:IsA("Model") then
        cf, size = gymObj:GetBoundingBox()
    elseif floorPart then
        cf, size = floorPart.CFrame, floorPart.Size
    else
        return nil
    end

    local cx = floorPart and floorPart.Position.X or cf.Position.X
    local cz = floorPart and floorPart.Position.Z or cf.Position.Z

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {gymObj}

    local origin = Vector3.new(cx, cf.Position.Y + size.Y + 10, cz)
    local hit = Workspace:Raycast(origin, Vector3.new(0, -(size.Y * 2 + 25), 0), params)
    if hit then return hit.Position end

    if floorPart then
        return Vector3.new(cx, floorPart.Position.Y + (floorPart.Size.Y * 0.5), cz)
    end
    return cf.Position
end

local function pulseTouchOnGym(char, gymObj)
    if not firetouchinterest or not char or not gymObj then return end
    for _, desc in ipairs(gymObj:GetDescendants()) do
        if desc:IsA("TouchTransmitter") and desc.Parent and desc.Parent:IsA("BasePart") then
            for _, bodyPart in ipairs(char:GetChildren()) do
                if bodyPart:IsA("BasePart") then
                    pcall(firetouchinterest, bodyPart, desc.Parent, 0)
                end
            end
        end
    end
end

local handledGyms = setmetatable({}, {__mode = "k"})

local function teleportToBeachGym(gymObj)
    if not autoBeachGym or not gymObj or not gymObj.Parent then return end
    if handledGyms[gymObj] then return end
    handledGyms[gymObj] = true

    task.wait(0.15)
    if not gymObj or not gymObj.Parent then return end

    local surfacePos = getBeachCenterSurface(gymObj)
    if not surfacePos then return end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then return end

    removeSafePlatform()
    activeBeachGym = gymObj

    local hipHeight = hum and hum.HipHeight or 2
    local targetPos = surfacePos + Vector3.new(0, hipHeight + (hrp.Size.Y * 0.5) + 0.05, 0)
    hrp.CFrame = CFrame.new(targetPos)
    hrp.AssemblyLinearVelocity = Vector3.new(0, -12, 0)

    pulseTouchOnGym(char, gymObj)

    task.spawn(function()
        task.wait(0.12)
        if activeBeachGym == gymObj and hum and hum.Parent then
            hum.Jump = true
        end
        while activeBeachGym == gymObj and gymObj.Parent and autoBeachGym do
            pulseTouchOnGym(player.Character, gymObj)
            task.wait(2)
        end
    end)

    gymTpCount = gymTpCount + 1
    updateDashboard()

    local despawnConn
    despawnConn = gymObj.AncestryChanged:Connect(function(_, newParent)
        if not newParent or not gymObj:IsDescendantOf(Workspace) then
            if despawnConn then despawnConn:Disconnect() end
            if activeBeachGym == gymObj then activeBeachGym = nil end
            spawnPlatformUnderPlayer(player.Character)
        end
    end)
end

local function setupBeachGymWatcher()
    for _, c in ipairs(gymWatchConns) do pcall(function() c:Disconnect() end) end
    gymWatchConns = {}

    local function hookGymMachine(gmFolder)
        for _, child in ipairs(gmFolder:GetChildren()) do
            if string.lower(child.Name) == "beach gym" then task.spawn(teleportToBeachGym, child) end
        end
        table.insert(gymWatchConns, gmFolder.ChildAdded:Connect(function(child)
            if string.lower(child.Name) == "beach gym" then task.spawn(teleportToBeachGym, child) end
        end))
    end

    local debris = Workspace:WaitForChild("Debris", 15)
    if debris then
        local gm = debris:FindFirstChild("GymMachine")
        if gm then hookGymMachine(gm) end
        table.insert(gymWatchConns, debris.ChildAdded:Connect(function(child)
            if child.Name == "GymMachine" then hookGymMachine(child) end
        end))
    end
end
setupBeachGymWatcher()

table.insert(conns, player.CharacterAdded:Connect(function(newChar)
    task.wait(0.2)
    if activeBeachGym and activeBeachGym:IsDescendantOf(Workspace) and autoBeachGym then
        handledGyms[activeBeachGym] = nil
        teleportToBeachGym(activeBeachGym)
    else
        spawnPlatformUnderPlayer(newChar)
    end
end))

-- =====================================================================
-- COMPACTE STATS HUD
-- =====================================================================
local guiWidth, guiHeight = 356, 254
local NeonGreen    = Color3.fromRGB(0, 255, 145)
local DeepCyberBg  = Color3.fromRGB(7, 13, 11)
local PanelCyberBg = Color3.fromRGB(12, 22, 18)
local CardCyberBg  = Color3.fromRGB(15, 28, 23)
local TextPure     = Color3.fromRGB(255, 255, 255)
local TextMuted    = Color3.fromRGB(145, 205, 178)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = uiName
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = (gethui and gethui()) or CoreGui

local GlowAura = Instance.new("Frame")
GlowAura.Size = UDim2.new(0, guiWidth + 6, 0, guiHeight + 6)
GlowAura.Position = UDim2.new(0.5, -((guiWidth + 6) / 2), 0.14, 0)
GlowAura.BackgroundColor3 = NeonGreen
GlowAura.BackgroundTransparency = 0.85
GlowAura.BorderSizePixel = 0
GlowAura.Parent = ScreenGui
Instance.new("UICorner", GlowAura).CornerRadius = UDim.new(0, 14)

local UiScaler = Instance.new("UIScale", GlowAura)
UiScaler.Scale = 1.0

local AuraStroke = Instance.new("UIStroke", GlowAura)
AuraStroke.Color = NeonGreen
AuraStroke.Thickness = 2
AuraStroke.Transparency = 0.45

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, guiWidth, 0, guiHeight)
MainFrame.Position = UDim2.new(0, 3, 0, 3)
MainFrame.BackgroundColor3 = DeepCyberBg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = GlowAura
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = NeonGreen
MainStroke.Thickness = 1.8
MainStroke.Transparency = 0.1

local TopBar = Instance.new("Frame", MainFrame)
TopBar.Size = UDim2.new(1, 0, 0, 42)
TopBar.BackgroundColor3 = PanelCyberBg
TopBar.BorderSizePixel = 0

local TopDivider = Instance.new("Frame", TopBar)
TopDivider.Size = UDim2.new(1, 0, 0, 2)
TopDivider.Position = UDim2.new(0, 0, 1, -2)
TopDivider.BackgroundColor3 = NeonGreen
TopDivider.BackgroundTransparency = 0.35
TopDivider.BorderSizePixel = 0

local LogoHolder = Instance.new("Frame", TopBar)
LogoHolder.Size = UDim2.new(0, 40, 0, 28)
LogoHolder.Position = UDim2.new(0, 10, 0.5, -14)
LogoHolder.BackgroundColor3 = Color3.fromRGB(10, 32, 24)
LogoHolder.BorderSizePixel = 0
Instance.new("UICorner", LogoHolder).CornerRadius = UDim.new(0, 7)

local LogoStroke = Instance.new("UIStroke", LogoHolder)
LogoStroke.Color = NeonGreen
LogoStroke.Thickness = 1.5

local LogoTextM = Instance.new("TextLabel", LogoHolder)
LogoTextM.Size = UDim2.new(1, 0, 1, 0)
LogoTextM.BackgroundTransparency = 1
LogoTextM.Font = Enum.Font.GothamBlack
LogoTextM.Text = "MzD"
LogoTextM.TextColor3 = NeonGreen
LogoTextM.TextSize = 14

local TitleLabel = Instance.new("TextLabel", TopBar)
TitleLabel.Size = UDim2.new(1, -145, 1, 0)
TitleLabel.Position = UDim2.new(0, 58, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.Text = "MzD KALB // VOID"
TitleLabel.TextColor3 = TextPure
TitleLabel.TextSize = 15
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

local ZoomBtn = Instance.new("TextButton", TopBar)
ZoomBtn.Size = UDim2.new(0, 42, 0, 28)
ZoomBtn.Position = UDim2.new(1, -82, 0.5, -14)
ZoomBtn.BackgroundColor3 = Color3.fromRGB(18, 42, 33)
ZoomBtn.Font = Enum.Font.GothamBlack
ZoomBtn.Text = "1.0x"
ZoomBtn.TextColor3 = NeonGreen
ZoomBtn.TextSize = 12
Instance.new("UICorner", ZoomBtn).CornerRadius = UDim.new(0, 7)

local zoomLevels = {1.0, 1.2, 1.35}
local zoomIdx = 1
ZoomBtn.MouseButton1Click:Connect(function()
    zoomIdx = (zoomIdx % #zoomLevels) + 1
    local newScale = zoomLevels[zoomIdx]
    ZoomBtn.Text = string.format("%.1fx", newScale)
    TweenService:Create(UiScaler, TweenInfo.new(0.15), {Scale = newScale}):Play()
end)

local CloseBtn = Instance.new("TextButton", TopBar)
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0.5, -14)
CloseBtn.BackgroundColor3 = Color3.fromRGB(185, 35, 50)
CloseBtn.Font = Enum.Font.GothamBlack
CloseBtn.Text = "X"
CloseBtn.TextColor3 = TextPure
CloseBtn.TextSize = 13
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 7)

local BoostRow = Instance.new("Frame", MainFrame)
BoostRow.Size = UDim2.new(1, -20, 0, 68)
BoostRow.Position = UDim2.new(0, 10, 0, 50)
BoostRow.BackgroundTransparency = 1

local function createStatCard(parent, xScale, titleText, accentColor, maxNumSize)
    local Card = Instance.new("Frame", parent)
    Card.Size = UDim2.new(0.318, 0, 1, 0)
    Card.Position = UDim2.new(xScale, 0, 0, 0)
    Card.BackgroundColor3 = CardCyberBg
    Card.BorderSizePixel = 0
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 9)

    local CStroke = Instance.new("UIStroke", Card)
    CStroke.Color = accentColor
    CStroke.Thickness = 1.5
    CStroke.Transparency = 0.25

    local BadgeLabel = Instance.new("TextLabel", Card)
    BadgeLabel.Size = UDim2.new(1, 0, 0, 20)
    BadgeLabel.Position = UDim2.new(0, 0, 0, 5)
    BadgeLabel.BackgroundTransparency = 1
    BadgeLabel.Font = Enum.Font.GothamBlack
    BadgeLabel.Text = titleText
    BadgeLabel.TextColor3 = accentColor
    BadgeLabel.TextSize = 12

    local ValueLabel = Instance.new("TextLabel", Card)
    ValueLabel.Size = UDim2.new(1, -8, 1, -28)
    ValueLabel.Position = UDim2.new(0, 4, 0, 24)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Font = Enum.Font.GothamBlack
    ValueLabel.Text = "0"
    ValueLabel.TextColor3 = TextPure
    ValueLabel.TextScaled = true

    local SizeLimit = Instance.new("UITextSizeConstraint", ValueLabel)
    SizeLimit.MaxTextSize = maxNumSize
    SizeLimit.MinTextSize = 13
    return ValueLabel
end

Val2xLabel = createStatCard(BoostRow, 0, "2X BOOST", Color3.fromRGB(195, 110, 255), 25)
Val5xLabel = createStatCard(BoostRow, 0.341, "5X BOOST", Color3.fromRGB(255, 160, 45), 25)
Val10xLabel = createStatCard(BoostRow, 0.682, "10X BOOST", NeonGreen, 25)

local TelemetryRow = Instance.new("Frame", MainFrame)
TelemetryRow.Size = UDim2.new(1, -20, 0, 56)
TelemetryRow.Position = UDim2.new(0, 10, 0, 126)
TelemetryRow.BackgroundTransparency = 1

ValTotalLabel = createStatCard(TelemetryRow, 0, "TOTAAL CLAIMS", TextMuted, 20)
ValGymLabel = createStatCard(TelemetryRow, 0.341, "BEACH GYM", TextMuted, 20)
ValMsLabel = createStatCard(TelemetryRow, 0.682, "REACTIE", TextMuted, 20)
ValMsLabel.Text = "0ms"

local PillsRow = Instance.new("Frame", MainFrame)
PillsRow.Size = UDim2.new(1, -20, 0, 32)
PillsRow.Position = UDim2.new(0, 10, 0, 190)
PillsRow.BackgroundTransparency = 1

local function createStatusPill(xScale, labelPrefix, defaultState, callback)
    local Pill = Instance.new("TextButton", PillsRow)
    Pill.Size = UDim2.new(0.238, 0, 1, 0)
    Pill.Position = UDim2.new(xScale, 0, 0, 0)
    Pill.BackgroundColor3 = defaultState and Color3.fromRGB(14, 120, 74) or Color3.fromRGB(35, 38, 37)
    Pill.Font = Enum.Font.GothamBlack
    Pill.Text = labelPrefix .. (defaultState and "\nAAN" or "\nUIT")
    Pill.TextColor3 = TextPure
    Pill.TextSize = 10
    Instance.new("UICorner", Pill).CornerRadius = UDim.new(0, 7)

    local PStroke = Instance.new("UIStroke", Pill)
    PStroke.Color = defaultState and NeonGreen or Color3.fromRGB(75, 85, 80)
    PStroke.Thickness = 1.2

    local state = defaultState
    Pill.MouseButton1Click:Connect(function()
        state = not state
        Pill.Text = labelPrefix .. (state and "\nAAN" or "\nUIT")
        Pill.BackgroundColor3 = state and Color3.fromRGB(14, 120, 74) or Color3.fromRGB(35, 38, 37)
        PStroke.Color = state and NeonGreen or Color3.fromRGB(75, 85, 80)
        callback(state)
    end)
end

createStatusPill(0, "LIFT", autoLift, function(val) autoLift = val end)
createStatusPill(0.254, "BONUS", autoBonus, function(val) autoBonus = val end)
createStatusPill(0.508, "GYM TP", autoBeachGym, function(val)
    autoBeachGym = val
    if val then
        local debris = Workspace:FindFirstChild("Debris")
        local gm = debris and debris:FindFirstChild("GymMachine")
        local bg = gm and gm:FindFirstChild("beach gym")
        if bg then
            handledGyms[bg] = nil
            task.spawn(teleportToBeachGym, bg)
        end
    end
end)
createStatusPill(0.762, "AFK", antiAfkEnabled, function(val)
    antiAfkEnabled = val
    autoReconnectEnabled = val
    if val then triggerAfkPulse() end
end)

local Footer = Instance.new("Frame", MainFrame)
Footer.Size = UDim2.new(1, 0, 0, 24)
Footer.Position = UDim2.new(0, 0, 1, -24)
Footer.BackgroundColor3 = Color3.fromRGB(10, 20, 16)
Footer.BorderSizePixel = 0

local FooterTopLine = Instance.new("Frame", Footer)
FooterTopLine.Size = UDim2.new(1, 0, 0, 1)
FooterTopLine.BackgroundColor3 = NeonGreen
FooterTopLine.BackgroundTransparency = 0.5
FooterTopLine.BorderSizePixel = 0

FooterStatsLabel = Instance.new("TextLabel", Footer)
FooterStatsLabel.Size = UDim2.new(1, -12, 1, 0)
FooterStatsLabel.Position = UDim2.new(0, 6, 0, 0)
FooterStatsLabel.BackgroundTransparency = 1
FooterStatsLabel.Font = Enum.Font.GothamBold
FooterStatsLabel.Text = "WEIGHT: ZOEKEN...  |  AFK: 0"
FooterStatsLabel.TextColor3 = NeonGreen
FooterStatsLabel.TextSize = 11

CloseBtn.MouseButton1Click:Connect(function()
    autoLift, autoBonus, autoBeachGym, antiAfkEnabled, autoReconnectEnabled = false, false, false, false, false
    if setfpscap then pcall(setfpscap, 60) end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(gymWatchConns) do pcall(function() c:Disconnect() end) end
    ScreenGui:Destroy()
end)

local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = GlowAura.Position
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        GlowAura.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)

-- =====================================================================
-- HYBRID BONUS CLAIMER + POPBONUS VERIFIED COUNTER
-- =====================================================================
local function clickScreenAtButton(btn)
    pcall(function()
        if not btn or not btn.Parent then return end
        local pos, size, inset = btn.AbsolutePosition, btn.AbsoluteSize, GuiService:GetGuiInset()
        local cx, cy = pos.X + (size.X * 0.5), pos.Y + (size.Y * 0.5) + inset.Y
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
end

local function activateBonusButton(btn)
    if not autoBonus or not ScreenGui.Parent or not btn or btn.Name ~= "Bonus" or not btn:IsA("GuiButton") or not btn.Visible then return end
    lastBonusSpawnTick = tick()

    local lbl = btn:FindFirstChildOfClass("TextLabel")
    if lbl and lbl.Text ~= "" then
        lastSeenMultiplier = string.lower(lbl.Text)
    else
        local cConn = btn.ChildAdded:Connect(function(c)
            if c:IsA("TextLabel") and c.Text ~= "" then lastSeenMultiplier = string.lower(c.Text) end
        end)
        task.wait(0.015)
        cConn:Disconnect()
        lbl = btn and btn:FindFirstChildOfClass("TextLabel")
        if lbl and lbl.Text ~= "" then lastSeenMultiplier = string.lower(lbl.Text) end
    end

    pcall(function()
        if btn and btn.Parent then
            if getconnections then
                for _, conn in pairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
                for _, conn in pairs(getconnections(btn.Activated)) do conn:Fire() end
                for _, conn in pairs(getconnections(btn.MouseButton1Down)) do conn:Fire() end
                for _, conn in pairs(getconnections(btn.MouseButton1Up)) do conn:Fire() end
            end
            if firesignal then
                pcall(firesignal, btn.MouseButton1Click)
                pcall(firesignal, btn.Activated)
            end
        end
    end)

    if btn and btn.Parent and btn.Visible then clickScreenAtButton(btn) end
    if bonusRemote then pcall(function() bonusRemote:FireServer() end) end
end

local function onPopBonusConfirmed()
    local now = tick()
    if string.find(lastSeenMultiplier, "10") then count10x = count10x + 1
    elseif string.find(lastSeenMultiplier, "5") then count5x = count5x + 1
    else count2x = count2x + 1 end

    totalBonusCount = totalBonusCount + 1
    if lastBonusSpawnTick > 0 then lastReactionMs = math.floor((now - lastBonusSpawnTick) * 1000) end
    updateDashboard()
end

local function watchKickUpgradesChild(child)
    if child.Name == "PopBonus" then
        onPopBonusConfirmed()
    elseif child.Name == "Bonus" and child:IsA("GuiButton") then
        if child.Visible then task.spawn(activateBonusButton, child) end
        child:GetPropertyChangedSignal("Visible"):Connect(function()
            if child.Visible then task.spawn(activateBonusButton, child) end
        end)
    end
end

task.spawn(function()
    local kickUpgrades = pGui:WaitForChild("KickUpgrades", 15)
    if kickUpgrades then
        for _, child in ipairs(kickUpgrades:GetChildren()) do watchKickUpgradesChild(child) end
        table.insert(conns, kickUpgrades.ChildAdded:Connect(watchKickUpgradesChild))
    end
end)

-- =====================================================================
-- DIRECT UITVOEREN BIJ START
-- =====================================================================
obliterateWorldNow()
triggerAfkPulse()
