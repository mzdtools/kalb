-- =====================================================================
-- MzD KALB script 
-- =====================================================================

if setfpscap then pcall(setfpscap, 20) end
if not game:IsLoaded() then
    game.Loaded:Wait()
end

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
while not player do
    task.wait()
    player = Players.LocalPlayer
end
local pGui = player:WaitForChild("PlayerGui")

pcall(function()
    RunService:Set3dRenderingEnabled(true)
end)

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 10)
local packagesFolder = sharedFolder and (sharedFolder:FindFirstChild("Packages") or sharedFolder:WaitForChild("Packages", 10))
local networkFolder = packagesFolder and (packagesFolder:FindFirstChild("Network") or packagesFolder:WaitForChild("Network", 10))

local bonusRemote = networkFolder and networkFolder:FindFirstChild("rev_TaviMishkal")
local weightEquipRemote = networkFolder and networkFolder:FindFirstChild("rev_WeightEquip")
local vfxRemote = networkFolder and networkFolder:FindFirstChild("rev_VFX_UPD")

if vfxRemote and getconnections then
    pcall(function()
        for _, conn in pairs(getconnections(vfxRemote.OnClientEvent)) do
            if conn.Disable then conn:Disable() end
        end
    end)
end

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

local VFX_NAME_KEYWORDS = {
    "aura", "glow", "vfx", "effect", "burst",
    "ring", "shock", "muscle", "bicep", "flex",
    "mesh", "part"
}

-- =====================================================================
-- Status & Tellers
-- =====================================================================
local isAlive = true
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
local activeWeightName = "CHECKEN..."
local lastSpawnTick = tick()
local lastEngineInputTick = 0

local conns = {}
local gymWatchConns = {}
local activeGymDespawnConn = nil
local myIdledConn = nil

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
        local afkState = (lastEngineInputTick > 0 and (tick() - lastEngineInputTick) < 90) and "OK" or "..."
        FooterStatsLabel.Text = string.format("WEIGHT: %s  |  AFK: %d [%s]", string.upper(activeWeightName), afkPulses, afkState)
    end
end

local function setActiveWeightLabel(newName)
    if activeWeightName ~= newName then
        activeWeightName = newName
        updateDashboard()
    end
end

local function safeDestroy(inst)
    if not inst or not inst.Parent then return end
    task.defer(function()
        if inst and inst.Parent then
            pcall(inst.Destroy, inst)
        end
    end)
end

-- =====================================================================
-- MEMORY-SAFE PROPERTY-LOCK (MET CLEANUP BIJ SLUITEN)
-- =====================================================================
local instanceLockConns = setmetatable({}, {__mode = "k"})
local INVISIBLE_SEQ = NumberSequence.new(1)
local ZERO_SEQ = NumberSequence.new(0)

local function lockProperty(inst, propName, targetValue)
    if not isAlive or not inst then return end
    local bucket = instanceLockConns[inst]
    if not bucket then
        bucket = {}
        instanceLockConns[inst] = bucket
    end
    if bucket[propName] then return end

    bucket[propName] = inst:GetPropertyChangedSignal(propName):Connect(function()
        if not isAlive then return end
        if inst[propName] ~= targetValue then
            pcall(function() inst[propName] = targetValue end)
        end
    end)
end

-- =====================================================================
-- TRAININGSPLATFORM BEHEER
-- =====================================================================
local function removeSafePlatform()
    local existingPad = Workspace:FindFirstChild("MzD_SafePlatform")
    if existingPad then existingPad:Destroy() end
end

local function spawnPlatformUnderPlayer(char)
    if not isAlive then return end
    local targetChar = char or player.Character
    if not targetChar then return end
    local hrp = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:WaitForChild("HumanoidRootPart", 5)
    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if not hrp or not isAlive then return end

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
    border.Name = "MzD_SafeBorder"
    border.Adornee = safePad
    border.Color3 = Color3.fromRGB(0, 255, 145)
    border.LineThickness = 0.04
    border.SurfaceTransparency = 1
    border.Parent = safePad

    hrp.AssemblyLinearVelocity = Vector3.zero
    return safePad
end

-- =====================================================================
-- TOTALE WERELD-, VFX- & UI-SLOOP
-- =====================================================================
local function isGymBillboard(inst)
    local gm = inst:FindFirstAncestor("GymMachine")
    return gm ~= nil and gm.Parent ~= nil and gm.Parent.Name == "Debris"
end

local function hasVfxKeyword(name)
    local lower = string.lower(name)
    for _, kw in ipairs(VFX_NAME_KEYWORDS) do
        if string.find(lower, kw, 1, true) then
            return true
        end
    end
    return false
end

local function disableVisualNoise(inst)
    if not isAlive or not inst or not inst.Parent then return end
    if inst:IsDescendantOf(CoreGui) then return end
    if inst.Name == "MzD_SafePlatform" or inst.Name == "MzD_SafeBorder" then return end

    pcall(function()
        if inst:IsA("ParticleEmitter") then
            inst.Enabled = false
            inst.Rate = 0
            inst.Transparency = INVISIBLE_SEQ
            inst.Size = ZERO_SEQ
            lockProperty(inst, "Enabled", false)
            lockProperty(inst, "Transparency", INVISIBLE_SEQ)
        elseif inst:IsA("Trail") or inst:IsA("Beam") then
            inst.Enabled = false
            inst.Transparency = INVISIBLE_SEQ
            lockProperty(inst, "Enabled", false)
        elseif inst:IsA("Sparkles") or inst:IsA("Fire") or inst:IsA("Smoke") then
            inst.Enabled = false
            lockProperty(inst, "Enabled", false)
        elseif inst:IsA("Highlight") then
            inst.Enabled = false
            inst.FillTransparency = 1
            inst.OutlineTransparency = 1
            lockProperty(inst, "Enabled", false)
            lockProperty(inst, "FillTransparency", 1)
            lockProperty(inst, "OutlineTransparency", 1)
        elseif inst:IsA("ForceField") then
            inst.Visible = false
            lockProperty(inst, "Visible", false)
        elseif inst:IsA("SelectionBox") or inst:IsA("SelectionSphere") then
            inst.Visible = false
            lockProperty(inst, "Visible", false)
        elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
            inst.Enabled = false
            inst.Brightness = 0
            lockProperty(inst, "Enabled", false)
        elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
            if not isGymBillboard(inst) then
                inst.Enabled = false
                lockProperty(inst, "Enabled", false)
            end
        elseif inst:IsA("Sound") then
            inst.Volume = 0
        elseif inst:IsA("Clouds") then
            inst.Enabled = false
            inst.Cover = 0
        end
    end)

    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam and inst:IsDescendantOf(cam) and inst ~= cam then
            if inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("BillboardGui") or inst:IsA("ParticleEmitter") then
                safeDestroy(inst)
                return
            end
        end

        local char = player.Character
        if char and inst:IsDescendantOf(char) then
            if inst:IsA("BasePart") and inst.Parent == char then
                if inst.Material == Enum.Material.Neon or inst.Material == Enum.Material.ForceField then
                    inst.Material = Enum.Material.SmoothPlastic
                end
                lockProperty(inst, "Material", Enum.Material.SmoothPlastic)
            elseif (inst:IsA("BasePart") or inst:IsA("Model"))
                and not inst:FindFirstAncestorOfClass("Tool")
                and not inst:FindFirstAncestorOfClass("Accessory") then
                if hasVfxKeyword(inst.Name) then
                    safeDestroy(inst)
                end
            end
        end
    end)
end

local function filterMainHud(hudGui)
    if not isAlive or not hudGui then return end
    hudGui.Enabled = true
    for _, child in ipairs(hudGui:GetChildren()) do
        if child:IsA("GuiObject") then
            if child.Name == "BottomLeft" then
                child.Visible = true
                local friendsBoost = child:FindFirstChild("FriendsBoost")
                if friendsBoost and friendsBoost:IsA("GuiObject") then
                    friendsBoost.Visible = false
                    lockProperty(friendsBoost, "Visible", false)
                end
            else
                child.Visible = false
                lockProperty(child, "Visible", false)
            end
        end
    end
end

local hookedHuds = setmetatable({}, {__mode = "k"})
local function hookMainHud(hudGui)
    filterMainHud(hudGui)
    if hookedHuds[hudGui] then return end
    hookedHuds[hudGui] = true
    table.insert(conns, hudGui.ChildAdded:Connect(function()
        if isAlive then filterMainHud(hudGui) end
    end))
end

local function filterKickUpgrades(kuGui)
    if not isAlive or not kuGui then return end
    kuGui.Enabled = true
    for _, child in ipairs(kuGui:GetChildren()) do
        if child:IsA("GuiObject") and child.Name ~= "Bonus" and child.Name ~= "PopBonus" then
            child.Visible = false
            lockProperty(child, "Visible", false)
        end
    end
end

local hookedEffectGuis = setmetatable({}, {__mode = "k"})
local function lockDisabledScreenGui(gui)
    if not isAlive or not gui or not gui:IsA("LayerCollector") then return end
    gui.Enabled = false
    lockProperty(gui, "Enabled", false)
    if (gui.Name == "GUI_Effects" or gui.Name == "FallGUIEffects") and not hookedEffectGuis[gui] then
        hookedEffectGuis[gui] = true
        pcall(function() gui:ClearAllChildren() end)
        table.insert(conns, gui.ChildAdded:Connect(function(c)
            if isAlive then safeDestroy(c) end
        end))
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

-- =====================================================================
-- CHECK-FIRST EQUIP LOGICA & ANDROID AUTO-LIFT
-- =====================================================================
local function getEquippedWeightTool(char)
    if not char then return nil, 999 end
    local bestTool = nil
    local bestRank = 999
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            local rank = WEIGHT_LOOKUP[string.lower(item.Name)]
            if rank and rank < bestRank then
                bestRank = rank
                bestTool = item
            end
        end
    end
    return bestTool, bestRank
end

local function getBackpackWeightTool()
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then return nil, 999 end
    local bestTool = nil
    local bestRank = 999
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") then
            local rank = WEIGHT_LOOKUP[string.lower(item.Name)]
            if rank and rank < bestRank then
                bestRank = rank
                bestTool = item
            end
        end
    end
    return bestTool, bestRank
end

local function isWeightEntryUnlocked(entry)
    local lockObj = entry:FindFirstChild("Lock") or entry:FindFirstChild("Locked")
    if lockObj and lockObj:IsA("GuiObject") and lockObj.Visible then
        return false, nil
    end

    local btns = entry:FindFirstChild("Buttons")
    if btns then
        for _, lockBtnName in ipairs({"Buy", "Purchase", "Unlock", "Lock", "Locked"}) do
            local b = btns:FindFirstChild(lockBtnName)
            if b and b:IsA("GuiObject") and b.Visible then
                return false, nil
            end
        end

        local equipBtn = btns:FindFirstChild("Equip")
        if equipBtn and equipBtn:IsA("GuiButton") and equipBtn.Visible then
            return true, equipBtn
        end

        local eqBtn = btns:FindFirstChild("Equipped")
        if eqBtn and eqBtn:IsA("GuiButton") then
            if eqBtn.Visible then
                return true, eqBtn
            end
            return false, nil
        end
    end

    return true, nil
end

local lastInventoryPull = 0
local function requestWeightFromGame()
    if tick() - lastInventoryPull < 2.5 then return end
    lastInventoryPull = tick()

    local frames = pGui:FindFirstChild("Frames")
    local weightUI = frames and frames:FindFirstChild("WeightUI")
    local scroller = weightUI and weightUI:FindFirstChild("ScrollingFrame")

    if scroller then
        local fallbackName, fallbackBtn = nil, nil

        for _, wName in ipairs(WEIGHT_PRIORITY) do
            local entry = scroller:FindFirstChild(wName)
            if entry then
                local unlocked, btn = isWeightEntryUnlocked(entry)
                if unlocked then
                    if weightEquipRemote then
                        pcall(function() weightEquipRemote:FireServer(wName) end)
                    end
                    if btn and getconnections then
                        pcall(function()
                            for _, c in pairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
                        end)
                    end
                    return
                elseif not fallbackName then
                    local btns = entry:FindFirstChild("Buttons")
                    fallbackName = wName
                    fallbackBtn = btns and (btns:FindFirstChild("Equip") or btns:FindFirstChild("Equipped"))
                end
            end
        end

        if fallbackName then
            if weightEquipRemote then
                pcall(function() weightEquipRemote:FireServer(fallbackName) end)
            end
            if fallbackBtn and fallbackBtn:IsA("GuiButton") and getconnections then
                pcall(function()
                    for _, c in pairs(getconnections(fallbackBtn.MouseButton1Click)) do c:Fire() end
                end)
            end
            return
        end
    end

    if weightEquipRemote then
        pcall(function() weightEquipRemote:FireServer("Black Hole Barbell") end)
    end
end

local function triggerLiftInput(tool)
    if tool then
        pcall(function() tool:Activate() end)
    end
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam then
            local vp = cam.ViewportSize
            local tx, ty = math.max(30, vp.X - 35), math.max(120, vp.Y - 35)
            VirtualInputManager:SendTouchEvent(2, 0, tx, ty)
            task.delay(0.05, function()
                if isAlive then
                    pcall(VirtualInputManager.SendTouchEvent, VirtualInputManager, 2, 2, tx, ty)
                end
            end)
        end
    end)
end

local lastEquipAttempt = 0
local function stepAutoLift(doTap)
    if not isAlive or not autoLift then return end

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local equippedTool, equippedRank = getEquippedWeightTool(char)
    local backpackTool, backpackRank = getBackpackWeightTool()

    -- STAP 1: Check eerst of je al een sterker gewicht in je Backpack hebt dan in je hand
    if backpackTool and backpackRank < equippedRank then
        setActiveWeightLabel(backpackTool.Name .. " (EQUIPPING)")
        if tick() - lastEquipAttempt >= 0.45 then
            lastEquipAttempt = tick()
            pcall(function() hum:EquipTool(backpackTool) end)
            for _, desc in ipairs(backpackTool:GetDescendants()) do
                disableVisualNoise(desc)
            end
        end
        return
    end

    -- STAP 2: Check of je al het sterkste beschikbare gewicht vasthebt -> direct liften
    if equippedTool then
        setActiveWeightLabel(equippedTool.Name)
        if doTap then
            triggerLiftInput(equippedTool)
        else
            pcall(function() equippedTool:Activate() end)
        end
        return
    end

    -- STAP 3: Noch in hand, noch in Backpack -> Wacht kort op server-load en vraag dan op
    setActiveWeightLabel("WACHT OP BARBELL...")
    if tick() - lastSpawnTick >= 1.5 then
        requestWeightFromGame()
    end
end

-- =====================================================================
-- BULLETPROOF MULTI-SUBSYSTEM ANTI-AFK (ANDROID / MUMU / DELTA / PC)
-- =====================================================================
local triggerAfkPulse
local isPulsingAfk = false

table.insert(conns, UserInputService.InputBegan:Connect(function()
    if not isAlive then return end
    local wasOk = (lastEngineInputTick > 0 and (tick() - lastEngineInputTick) < 90)
    lastEngineInputTick = tick()
    if not wasOk then
        updateDashboard()
    end
end))

local function refreshIdledGuard()
    if myIdledConn then
        pcall(function() myIdledConn:Disconnect() end)
        myIdledConn = nil
    end

    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(player.Idled)) do
                if conn.Disable then pcall(conn.Disable, conn) end
                if conn.Disconnect then pcall(conn.Disconnect, conn) end
            end
        end
    end)

    if isAlive then
        myIdledConn = player.Idled:Connect(function()
            if isAlive and antiAfkEnabled and not isPulsingAfk then
                triggerAfkPulse()
            end
        end)
    end
end

local function getSafeViewportPoint()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local inset = GuiService:GetGuiInset()
    local x = math.max(50, vp.X - 35)
    local y = math.max(inset.Y + 80, vp.Y - 35)
    return x, y
end

triggerAfkPulse = function()
    if not isAlive or not antiAfkEnabled or isPulsingAfk then return end
    isPulsingAfk = true

    pcall(function()
        afkPulses = afkPulses + 1
        updateDashboard()
        refreshIdledGuard()

        -- Laag 1: VirtualInputManager Keyboard (F15, 0.12s hold) + Android Touch (finger ID 1, 20px swipe)
        task.spawn(function()
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
                task.wait(0.12)
                if isAlive then
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
                end
            end)
            task.wait(0.08)
            if not isAlive then return end
            pcall(function()
                local tx, ty = getSafeViewportPoint()
                VirtualInputManager:SendTouchEvent(1, 0, tx, ty)
                task.wait(0.10)
                if isAlive then
                    VirtualInputManager:SendTouchEvent(1, 1, tx - 20, ty)
                    task.wait(0.10)
                end
                if isAlive then
                    VirtualInputManager:SendTouchEvent(1, 2, tx - 20, ty)
                end
            end)
        end)

        -- Laag 2: VirtualInputManager MouseMove + Right-Click (Button 1, 0.12s hold -> klikt nooit op UI)
        task.spawn(function()
            pcall(function()
                local mx, my = getSafeViewportPoint()
                VirtualInputManager:SendMouseMoveEvent(mx, my, game)
                task.wait(0.06)
                if not isAlive then return end
                VirtualInputManager:SendMouseMoveEvent(mx - 6, my - 6, game)
                task.wait(0.06)
                if not isAlive then return end
                VirtualInputManager:SendMouseButtonEvent(mx - 6, my - 6, 1, true, game, 0)
                task.wait(0.12)
                if isAlive then
                    VirtualInputManager:SendMouseButtonEvent(mx - 6, my - 6, 1, false, game, 0)
                end
            end)
        end)

        -- Laag 3: VirtualUser (ClickButton2 + 0.40s Button2Down/Up voor >= 8 frames op 20 FPS)
        task.spawn(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
                local cam = Workspace.CurrentCamera
                local cf = cam and cam.CFrame or CFrame.new()
                VirtualUser:Button2Down(Vector2.new(0, 0), cf)
                task.wait(0.40)
                if isAlive then
                    local camNow = Workspace.CurrentCamera
                    VirtualUser:Button2Up(Vector2.new(0, 0), camNow and camNow.CFrame or cf)
                end
            end)
        end)

        -- Laag 4: Camera micro-pulse & Character anti-freeze
        task.spawn(function()
            pcall(function()
                local cam = Workspace.CurrentCamera
                if cam then
                    local orig = cam.CFrame
                    cam.CFrame = orig * CFrame.Angles(0, 0.001, 0)
                    task.wait(0.05)
                    if isAlive and Workspace.CurrentCamera == cam then
                        cam.CFrame = orig
                    end
                end
            end)
            pcall(function()
                local char = player.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    hum:Move(Vector3.new(0.25, 0, 0), false)
                    task.wait(0.08)
                    hum:Move(Vector3.new(-0.25, 0, 0), false)
                    task.wait(0.08)
                    hum:Move(Vector3.zero, false)
                    if hum.FloorMaterial ~= Enum.Material.Air then
                        hum.Jump = true
                    end
                end
            end)
        end)
    end)

    isPulsingAfk = false
end

local isReconnecting = false
local function executeAutoReconnect()
    if not isAlive or not autoReconnectEnabled or isReconnecting then return end
    isReconnecting = true

    task.spawn(function()
        task.wait(2)
        while isAlive and autoReconnectEnabled do
            local ok = pcall(function()
                if #Players:GetPlayers() > 1 and game.JobId and game.JobId ~= "" then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
                else
                    TeleportService:Teleport(game.PlaceId, player)
                end
            end)

            if not ok then
                pcall(function()
                    TeleportService:Teleport(game.PlaceId, player)
                end)
            end

            task.wait(6)
        end
        isReconnecting = false
    end)
end

table.insert(conns, GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and msg ~= "" then
        executeAutoReconnect()
    end
end))

if GuiService:GetErrorMessage() ~= "" then
    executeAutoReconnect()
end

table.insert(conns, TeleportService.TeleportInitFailed:Connect(function(failedPlayer)
    if failedPlayer == player and isAlive and autoReconnectEnabled then
        task.wait(2)
        pcall(function()
            TeleportService:Teleport(game.PlaceId, player)
        end)
    end
end))

task.spawn(function()
    local promptGui = CoreGui:FindFirstChild("RobloxPromptGui") or CoreGui:WaitForChild("RobloxPromptGui", 10)
    local overlay = promptGui and promptGui:FindFirstChild("promptOverlay")
    if overlay and isAlive then
        if overlay:FindFirstChild("ErrorPrompt") then
            executeAutoReconnect()
        end
        table.insert(conns, overlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                executeAutoReconnect()
            end
        end))
    end
end)

-- =====================================================================
-- BEACH GYM TELEPORT
-- =====================================================================
local function findBeachGym()
    local debris = Workspace:FindFirstChild("Debris")
    local gm = debris and debris:FindFirstChild("GymMachine")
    if not gm then return nil end
    for _, child in ipairs(gm:GetChildren()) do
        if string.lower(child.Name) == "beach gym" then
            return child
        end
    end
    return nil
end

local function getBeachGymTargetCFrame(gymObj, char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local sandFloor = nil
    local bestFloorArea = 0
    local hitboxZone = nil
    local bestZoneVol = 0

    for _, desc in ipairs(gymObj:GetDescendants()) do
        if desc:IsA("BasePart") then
            if desc.CanCollide and desc.Size.Y < 5 then
                local area = desc.Size.X * desc.Size.Z
                if area > bestFloorArea then
                    bestFloorArea = area
                    sandFloor = desc
                end
            elseif not desc.CanCollide then
                local vol = desc.Size.X * desc.Size.Y * desc.Size.Z
                if vol > bestZoneVol then
                    bestZoneVol = vol
                    hitboxZone = desc
                end
            end
        end
    end

    local refPart = hitboxZone or sandFloor
    local bboxCf = gymObj:IsA("Model") and gymObj:GetBoundingBox() or nil
    local centerX = refPart and refPart.Position.X or (bboxCf and bboxCf.Position.X)
    local centerZ = refPart and refPart.Position.Z or (bboxCf and bboxCf.Position.Z)
    if not centerX or not centerZ then return nil end

    local floorTopY = sandFloor and (sandFloor.Position.Y + sandFloor.Size.Y * 0.5)
        or (refPart and (refPart.Position.Y - refPart.Size.Y * 0.5) or (bboxCf and bboxCf.Position.Y))

    local hipHeight = hum and hum.HipHeight or 2
    local standY = floorTopY + hipHeight + (hrp.Size.Y * 0.5) + 0.15
    return CFrame.new(centerX + 2, standY, centerZ + 2)
end

local gymTouchPartsCache = setmetatable({}, {__mode = "k"})
local function getGymTouchParts(gymObj)
    local cached = gymTouchPartsCache[gymObj]
    if cached then return cached end

    local parts = {}
    for _, desc in ipairs(gymObj:GetDescendants()) do
        if desc:IsA("TouchTransmitter") and desc.Parent and desc.Parent:IsA("BasePart") then
            table.insert(parts, desc.Parent)
        end
    end
    gymTouchPartsCache[gymObj] = parts
    return parts
end

local function pulseTouchOnGym(char, gymObj)
    if not firetouchinterest or not char or not gymObj or not gymObj.Parent then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    for _, touchPart in ipairs(getGymTouchParts(gymObj)) do
        if touchPart and touchPart.Parent then
            pcall(firetouchinterest, hrp, touchPart, 0)
            pcall(firetouchinterest, hrp, touchPart, 1)
            pcall(firetouchinterest, hrp, touchPart, 0)
        end
    end
end

local handledGyms = setmetatable({}, {__mode = "k"})

local function teleportToBeachGym(gymObj)
    if not isAlive or not autoBeachGym or not gymObj or not gymObj.Parent then return end
    if handledGyms[gymObj] then return end

    task.wait(0.15)
    if not isAlive or not autoBeachGym or not gymObj or not gymObj.Parent then return end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then return end

    local targetCFrame = getBeachGymTargetCFrame(gymObj, char)
    if not targetCFrame then return end

    handledGyms[gymObj] = true
    removeSafePlatform()
    activeBeachGym = gymObj

    hrp.Anchored = true
    hrp.CFrame = targetCFrame
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(0.25)
    if hrp and hrp.Parent then
        hrp.CFrame = targetCFrame
        hrp.Anchored = false
    end

    pulseTouchOnGym(char, gymObj)

    task.spawn(function()
        if activeBeachGym == gymObj and hum and hum.Parent and hrp and hrp.Parent then
            hum:MoveTo(hrp.Position + Vector3.new(1.5, 0, 0))
            task.wait(0.15)
            hum.Jump = true
        end
        while isAlive and activeBeachGym == gymObj and gymObj.Parent and autoBeachGym do
            pulseTouchOnGym(player.Character, gymObj)
            task.wait(2)
        end
    end)

    gymTpCount = gymTpCount + 1
    updateDashboard()

    if activeGymDespawnConn then
        pcall(function() activeGymDespawnConn:Disconnect() end)
        activeGymDespawnConn = nil
    end

    activeGymDespawnConn = gymObj.AncestryChanged:Connect(function(_, newParent)
        if not newParent or not gymObj:IsDescendantOf(Workspace) then
            if activeGymDespawnConn then
                pcall(function() activeGymDespawnConn:Disconnect() end)
                activeGymDespawnConn = nil
            end
            if activeBeachGym == gymObj then activeBeachGym = nil end
            if isAlive then
                spawnPlatformUnderPlayer(player.Character)
            end
        end
    end)
end

local function setupBeachGymWatcher()
    for _, c in ipairs(gymWatchConns) do pcall(function() c:Disconnect() end) end
    gymWatchConns = {}

    local function hookGymMachine(gmFolder)
        for _, child in ipairs(gmFolder:GetChildren()) do
            if string.lower(child.Name) == "beach gym" then
                task.spawn(teleportToBeachGym, child)
            end
        end
        table.insert(gymWatchConns, gmFolder.ChildAdded:Connect(function(child)
            if isAlive and string.lower(child.Name) == "beach gym" then
                task.spawn(teleportToBeachGym, child)
            end
        end))
    end

    local debris = Workspace:FindFirstChild("Debris") or Workspace:WaitForChild("Debris", 15)
    if debris and isAlive then
        local gm = debris:FindFirstChild("GymMachine")
        if gm then hookGymMachine(gm) end
        table.insert(gymWatchConns, debris.ChildAdded:Connect(function(child)
            if isAlive and child.Name == "GymMachine" then
                hookGymMachine(child)
            end
        end))
    end
end
task.spawn(setupBeachGymWatcher)

table.insert(conns, player.CharacterAdded:Connect(function(newChar)
    if not isAlive then return end
    lastSpawnTick = tick()
    lastEquipAttempt = 0
    lastInventoryPull = 0
    task.wait(0.2)
    if not isAlive then return end

    refreshIdledGuard()
    for _, desc in ipairs(newChar:GetDescendants()) do
        disableVisualNoise(desc)
    end
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
    Pill.AutoButtonColor = false
    Instance.new("UICorner", Pill).CornerRadius = UDim.new(0, 7)

    local PStroke = Instance.new("UIStroke", Pill)
    PStroke.Color = defaultState and NeonGreen or Color3.fromRGB(75, 85, 80)
    PStroke.Thickness = 1.2

    local state = defaultState
    local lastToggle = 0
    Pill.MouseButton1Click:Connect(function()
        if tick() - lastToggle < 0.35 then return end
        lastToggle = tick()
        state = not state
        Pill.Text = labelPrefix .. (state and "\nAAN" or "\nUIT")
        Pill.BackgroundColor3 = state and Color3.fromRGB(14, 120, 74) or Color3.fromRGB(35, 38, 37)
        PStroke.Color = state and NeonGreen or Color3.fromRGB(75, 85, 80)
        callback(state)
    end)
end

createStatusPill(0, "LIFT", autoLift, function(val)
    autoLift = val
    if val then
        lastEquipAttempt = 0
        lastInventoryPull = 0
        stepAutoLift(true)
    else
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum and getEquippedWeightTool(char) then
            pcall(function() hum:UnequipTools() end)
        end
    end
end)

createStatusPill(0.254, "BONUS", autoBonus, function(val) autoBonus = val end)

createStatusPill(0.508, "GYM TP", autoBeachGym, function(val)
    autoBeachGym = val
    if val then
        local bg = findBeachGym()
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
FooterStatsLabel.Text = "WEIGHT: CHECKEN...  |  AFK: 0 [...]"
FooterStatsLabel.TextColor3 = NeonGreen
FooterStatsLabel.TextSize = 11
FooterStatsLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Android-veilig draggen (wordt niet onderbroken door Auto-Lift of AFK touch events)
local dragging = false
local activeDragInput = nil
local dragIsMouse = false
local dragStart, startPos

TopBar.InputBegan:Connect(function(input)
    if dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        activeDragInput = input
        dragIsMouse = (input.UserInputType == Enum.UserInputType.MouseButton1)
        dragStart = input.Position
        startPos = GlowAura.Position
    end
end)

table.insert(conns, UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if (dragIsMouse and input.UserInputType == Enum.UserInputType.MouseMovement) or (input == activeDragInput) then
        local delta = input.Position - dragStart
        GlowAura.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end))

table.insert(conns, UserInputService.InputEnded:Connect(function(input)
    if not dragging then return end
    if input == activeDragInput or (dragIsMouse and input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging = false
        activeDragInput = nil
        dragIsMouse = false
    end
end))

CloseBtn.MouseButton1Click:Connect(function()
    isAlive = false
    autoLift, autoBonus, autoBeachGym, antiAfkEnabled, autoReconnectEnabled = false, false, false, false, false

    if setfpscap then pcall(setfpscap, 60) end
    if myIdledConn then pcall(function() myIdledConn:Disconnect() end) end
    if activeGymDespawnConn then pcall(function() activeGymDespawnConn:Disconnect() end) end

    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(gymWatchConns) do pcall(function() c:Disconnect() end) end

    for _, bucket in pairs(instanceLockConns) do
        for _, c in pairs(bucket) do
            pcall(function() c:Disconnect() end)
        end
    end
    table.clear(instanceLockConns)

    removeSafePlatform()

    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
    end)
    pcall(function()
        local touchGui = pGui:FindFirstChild("TouchGui")
        if touchGui and touchGui:IsA("LayerCollector") then
            touchGui.Enabled = true
        end
    end)

    ScreenGui:Destroy()
end)

-- =====================================================================
-- HYBRID BONUS CLAIMER + POPBONUS VERIFIED COUNTER
-- =====================================================================
local function clickScreenAtButton(btn)
    pcall(function()
        if not btn or not btn.Parent then return end
        local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
        local sc = btn:FindFirstAncestorWhichIsA("ScreenGui")
        local insetY = (sc and not sc.IgnoreGuiInset) and GuiService:GetGuiInset().Y or 0
        local cx, cy = pos.X + (size.X * 0.5), pos.Y + (size.Y * 0.5) + insetY
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
end

local claimedBonusBtns = setmetatable({}, {__mode = "k"})
local function activateBonusButton(btn)
    if not isAlive or not autoBonus or not ScreenGui.Parent then return end
    if not btn or btn.Name ~= "Bonus" or not btn:IsA("GuiButton") or not btn.Visible then return end
    if claimedBonusBtns[btn] and (tick() - claimedBonusBtns[btn]) < 0.35 then return end
    claimedBonusBtns[btn] = tick()

    lastBonusSpawnTick = tick()

    local lbl = btn:FindFirstChildOfClass("TextLabel")
    if lbl and lbl.Text ~= "" then
        lastSeenMultiplier = string.lower(lbl.Text)
    else
        local cConn = btn.ChildAdded:Connect(function(c)
            if c:IsA("TextLabel") and c.Text ~= "" then
                lastSeenMultiplier = string.lower(c.Text)
            end
        end)
        task.wait(0.015)
        cConn:Disconnect()
        lbl = btn and btn:FindFirstChildOfClass("TextLabel")
        if lbl and lbl.Text ~= "" then
            lastSeenMultiplier = string.lower(lbl.Text)
        end
    end

    if not isAlive or not autoBonus or not btn or not btn.Parent or not btn.Visible then return end

    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(btn.MouseButton1Click)) do conn:Fire() end
            for _, conn in pairs(getconnections(btn.Activated)) do conn:Fire() end
        end
    end)

    if btn and btn.Parent and btn.Visible then clickScreenAtButton(btn) end
    if bonusRemote and btn and btn.Parent and btn.Visible then
        pcall(function() bonusRemote:FireServer() end)
    end
end

local function onPopBonusConfirmed()
    local now = tick()
    if string.find(lastSeenMultiplier, "10", 1, true) then
        count10x = count10x + 1
    elseif string.find(lastSeenMultiplier, "5", 1, true) then
        count5x = count5x + 1
    else
        count2x = count2x + 1
    end

    totalBonusCount = totalBonusCount + 1
    if lastBonusSpawnTick > 0 then
        lastReactionMs = math.floor((now - lastBonusSpawnTick) * 1000)
    end
    updateDashboard()
end

local hookedBonusButtons = setmetatable({}, {__mode = "k"})
local function watchKickUpgradesChild(child)
    if not isAlive then return end
    if child.Name == "PopBonus" then
        onPopBonusConfirmed()
    elseif child.Name == "Bonus" and child:IsA("GuiButton") then
        if child.Visible then task.spawn(activateBonusButton, child) end
        if not hookedBonusButtons[child] then
            hookedBonusButtons[child] = true
            table.insert(conns, child:GetPropertyChangedSignal("Visible"):Connect(function()
                if isAlive and child.Visible then
                    task.spawn(activateBonusButton, child)
                end
            end))
        end
    else
        filterKickUpgrades(child.Parent)
    end
end

local hookedKickUpgrades = setmetatable({}, {__mode = "k"})
local function hookKickUpgrades(kuGui)
    filterKickUpgrades(kuGui)
    if hookedKickUpgrades[kuGui] then return end
    hookedKickUpgrades[kuGui] = true
    for _, child in ipairs(kuGui:GetChildren()) do
        watchKickUpgradesChild(child)
    end
    table.insert(conns, kuGui.ChildAdded:Connect(watchKickUpgradesChild))
end

-- =====================================================================
-- WORLD, GUI & LIGHTING WATCHERS + OBLITERATE
-- =====================================================================
local function stripAllGameGuis()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
    end)

    for _, gui in ipairs(pGui:GetChildren()) do
        if gui:IsA("LayerCollector") and gui.Name ~= uiName then
            if gui.Name == "KickUpgrades" then
                hookKickUpgrades(gui)
            elseif gui.Name == "HUD" then
                hookMainHud(gui)
            else
                lockDisabledScreenGui(gui)
            end
        end
    end
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

    for _, desc in ipairs(Workspace:GetDescendants()) do
        disableVisualNoise(desc)
    end

    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, desc in ipairs(bp:GetDescendants()) do
            disableVisualNoise(desc)
        end
    end
end

table.insert(conns, Workspace.ChildAdded:Connect(function(obj)
    if not isAlive or not obj then return end
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
    safeDestroy(obj)
end))

table.insert(conns, Workspace.DescendantAdded:Connect(function(desc)
    if not isAlive or not desc then return end
    local parent = desc.Parent
    if parent then
        local pName = parent.Name
        if parent.Parent == Workspace then
            if pName == "Areas" or pName == "Zones" or pName == "Machine" or pName == "KickUpgrades" then
                safeDestroy(desc)
                return
            elseif pName == "Players" and desc.Name ~= player.Name then
                safeDestroy(desc)
                return
            elseif pName == "Debris" and desc.Name ~= "GymMachine" then
                safeDestroy(desc)
                return
            end
        elseif pName == "GymMachine" and parent.Parent and parent.Parent.Name == "Debris" then
            if string.lower(desc.Name) ~= "beach gym" then
                safeDestroy(desc)
                return
            end
        end
    end
    disableVisualNoise(desc)
end))

table.insert(conns, pGui.ChildAdded:Connect(function(gui)
    if not isAlive or not gui then return end
    if gui:IsA("LayerCollector") and gui.Name ~= uiName then
        if gui.Name == "KickUpgrades" then
            hookKickUpgrades(gui)
        elseif gui.Name == "HUD" then
            hookMainHud(gui)
        else
            lockDisabledScreenGui(gui)
        end
    end
end))

table.insert(conns, Lighting.ChildAdded:Connect(function(eff)
    if isAlive and eff and eff.Name ~= "MzD_VoidSky" then
        safeDestroy(eff)
    end
end))

-- =====================================================================
-- BACKGROUND LOOPS & DIRECT STARTEN
-- =====================================================================
task.spawn(function()
    local clickTick = 0
    while isAlive and ScreenGui.Parent do
        task.wait(0.08)
        if not isAlive or not ScreenGui.Parent then break end
        if autoLift then
            clickTick = clickTick + 1
            stepAutoLift(clickTick % 2 == 0)
        end
    end
end)

task.spawn(function()
    while isAlive and ScreenGui.Parent do
        task.wait(45)
        if not isAlive or not ScreenGui.Parent then break end
        if setfpscap then pcall(setfpscap, 20) end
        pcall(function() Workspace.Terrain:Clear() end)
        if antiAfkEnabled then
            triggerAfkPulse()
        end
    end
end)

obliterateWorldNow()
refreshIdledGuard()
triggerAfkPulse()
stepAutoLift(true)
