-- =====================================================================
-- MzD KALB script - Ultra-Void v5.0 (Mass-Farm Low-CPU / Low-RAM)
-- =====================================================================

local TARGET_FPS          = 12    -- 12 FPS + 1 lift/frame = 12 lifts/sec (> 9/sec server cap, ~40% minder CPU)
local AUTO_REJOIN_MINUTES = 0     -- Optioneel voor public mass-farm: bijv. 180 (3 uur) voor schone RAM-reset
local DISABLE_3D_AT_START = false -- Zet op true om 3D-rendering direct bij opstarten uit te zetten
local DEEP_RAM_STRIP      = true  -- Verwijdert ~25k+ ongebruikte 3D-assets & verborgen menu's (veilig voor base)

if setfpscap then pcall(setfpscap, TARGET_FPS) end
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

local render3dEnabled = not DISABLE_3D_AT_START
pcall(function()
    RunService:Set3dRenderingEnabled(render3dEnabled)
end)

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 10)
local packagesFolder = sharedFolder and (sharedFolder:FindFirstChild("Packages") or sharedFolder:WaitForChild("Packages", 10))
local networkFolder = packagesFolder and (packagesFolder:FindFirstChild("Network") or packagesFolder:WaitForChild("Network", 10))

local bonusRemote = networkFolder and networkFolder:FindFirstChild("rev_TaviMishkal")
local weightEquipRemote = networkFolder and networkFolder:FindFirstChild("rev_WeightEquip")

local COSMETIC_REMOTES = {
    "rev_VFX_UPD",
    "rev_AnimData",
    "rev_WeatherUpdate",
    "rev_AddedWeather",
    "rev_RemovedWeather",
    "rev_LeaderboardUPD",
    "rev_PlayMessage",
    "rev_ChatMessageEvent",
    "rev_NotificationUpdate",
    "rev_TradeBoard_Post",
    "rev_TradeBoard_Remove",
    "rev_TradeBoard_Update",
    "rev_IndexUpdate",
    "rev_FriendsUPD"
}

local function disableCosmeticRemotes()
    if not networkFolder or not getconnections then return end
    for _, rName in ipairs(COSMETIC_REMOTES) do
        local rem = networkFolder:FindFirstChild(rName)
        if rem and rem:IsA("RemoteEvent") then
            pcall(function()
                for _, conn in pairs(getconnections(rem.OnClientEvent)) do
                    if conn.Disable then pcall(conn.Disable, conn) end
                end
            end)
        end
    end
end
disableCosmeticRemotes()

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

local IGNORED_WORKSPACE_FOLDERS = {
    ["Areas"] = true,
    ["Zones"] = true,
    ["Machine"] = true,
    ["KickUpgrades"] = true
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
local idledHookedCount = 0

local conns = {}
local gymWatchConns = {}
local containerWatchConns = {}
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
        local afkState = (lastEngineInputTick > 0 and (tick() - lastEngineInputTick) < 120) and "OK"
            or (idledHookedCount > 0 and "GUARD" or "VU")
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
    safePad.CastShadow = false
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
-- TOTALE WERELD-, VFX-, TOOL-, BEACH GYM- & RAM-SLOOP
-- =====================================================================
local protectedGymFloors = setmetatable({}, {__mode = "k"})

local function isGymDescendant(inst)
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
            if not isGymDescendant(inst) then
                inst.Enabled = false
                lockProperty(inst, "Enabled", false)
            end
        elseif inst:IsA("Sound") then
            inst.Volume = 0
        elseif inst:IsA("Clouds") then
            inst.Enabled = false
            inst.Cover = 0
        elseif inst:IsA("SurfaceAppearance") then
            safeDestroy(inst)
            return
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            inst.Transparency = 1
            lockProperty(inst, "Transparency", 1)
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

        if inst:FindFirstAncestorOfClass("Tool") then
            if inst:IsA("BasePart") then
                inst.Transparency = 1
                inst.CastShadow = false
                inst.Material = Enum.Material.SmoothPlastic
                lockProperty(inst, "Transparency", 1)
                lockProperty(inst, "Material", Enum.Material.SmoothPlastic)
            elseif inst:IsA("SpecialMesh") then
                inst.TextureId = ""
            end
            return
        end

        if isGymDescendant(inst) then
            if inst:IsA("BasePart") then
                inst.CastShadow = false
                inst.Material = Enum.Material.SmoothPlastic
                lockProperty(inst, "Material", Enum.Material.SmoothPlastic)
                if protectedGymFloors[inst] then
                    inst.Color = Color3.fromRGB(16, 42, 32)
                    inst.Transparency = 0.25
                else
                    inst.Transparency = 1
                    lockProperty(inst, "Transparency", 1)
                end
            elseif inst:IsA("SpecialMesh") then
                inst.TextureId = ""
            end
            return
        end

        local char = player.Character
        if char and inst:IsDescendantOf(char) then
            if inst:FindFirstAncestorOfClass("Accessory") then
                if inst:IsA("BasePart") then
                    inst.Transparency = 1
                    inst.CastShadow = false
                    inst.Material = Enum.Material.SmoothPlastic
                    lockProperty(inst, "Transparency", 1)
                elseif inst:IsA("SpecialMesh") then
                    inst.TextureId = ""
                end
                return
            end

            if inst:IsA("BasePart") and inst.Parent == char then
                inst.CastShadow = false
                inst.Material = Enum.Material.SmoothPlastic
                lockProperty(inst, "Material", Enum.Material.SmoothPlastic)
            elseif (inst:IsA("BasePart") or inst:IsA("Model")) then
                if hasVfxKeyword(inst.Name) then
                    safeDestroy(inst)
                end
            end
        end
    end)
end

local function disableUnneededClientExtras()
    pcall(function()
        local ps = player:FindFirstChild("PlayerScripts")
        if not ps then return end
        for _, name in ipairs({"SpookyDecorMotion", "RbxCharacterSounds"}) do
            local s = ps:FindFirstChild(name)
            if s and s:IsA("LocalScript") then
                s.Disabled = true
            end
        end
    end)
    pcall(function()
        UserSettings():GetService("UserGameSettings").MasterVolume = 0
    end)
end

local function stripDeepUnusedAssets()
    if not DEEP_RAM_STRIP then return end

    local rsObjects = ReplicatedStorage:FindFirstChild("Objects")
    if rsObjects then
        for _, name in ipairs({
            "JamesGym", "ShonGym", "MikiGym",
            "SpookyHouseKit", "SpookyHouseKit_v3",
            "BoothSkinPreviews", "SkinTemplates",
            "LuckyBlocks", "VFX", "Event"
        }) do
            local folder = rsObjects:FindFirstChild(name)
            if folder then pcall(function() folder:ClearAllChildren() end) end
        end
    end

    local eraAssets = ReplicatedStorage:FindFirstChild("EraTripAssets")
    if eraAssets then
        pcall(function() eraAssets:ClearAllChildren() end)
    end

    for _, guiName in ipairs({
        "SeasonPass", "FallFrames", "MerchantGui",
        "SkillTree", "MailGui", "FallUpgrades"
    }) do
        local g = pGui:FindFirstChild(guiName)
        if g then pcall(function() g:ClearAllChildren() end) end
    end

    local frames = pGui:FindFirstChild("Frames")
    if frames then
        for _, frameName in ipairs({"KickStylesFrame", "Index", "Store", "RockyStore"}) do
            local f = frames:FindFirstChild(frameName)
            if f then pcall(function() f:ClearAllChildren() end) end
        end
    end
end

local function filterHudChild(child)
    if not isAlive or not child or not child:IsA("GuiObject") then return end
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

local function filterMainHud(hudGui)
    if not isAlive or not hudGui then return end
    hudGui.Enabled = true
    for _, child in ipairs(hudGui:GetChildren()) do
        filterHudChild(child)
    end
end

local hookedHuds = setmetatable({}, {__mode = "k"})
local function hookMainHud(hudGui)
    filterMainHud(hudGui)
    if hookedHuds[hudGui] then return end
    hookedHuds[hudGui] = true
    table.insert(conns, hudGui.ChildAdded:Connect(filterHudChild))
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
        Lighting.Brightness = 1.2
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.Ambient = Color3.fromRGB(165, 175, 170)
        Lighting.OutdoorAmbient = Color3.fromRGB(165, 175, 170)
        Lighting.FogStart = 0
        Lighting.FogEnd = 220
        Lighting.FogColor = Color3.fromRGB(7, 13, 11)

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
            sky.Parent = Lighting
        end

        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
end

-- =====================================================================
-- O(1) GECACHETE EQUIP LOGICA & STILLE AUTO-LIFT
-- =====================================================================
local toolCacheDirty = true
local cachedEquippedTool = nil

local function hookToolContainer(container)
    if not container then return end
    table.insert(containerWatchConns, container.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            toolCacheDirty = true
        end
    end))
    table.insert(containerWatchConns, container.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            toolCacheDirty = true
        end
    end))
end

local function refreshToolWatchers(char)
    for _, c in ipairs(containerWatchConns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(containerWatchConns)

    if char then hookToolContainer(char) end
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        hookToolContainer(bp)
    else
        task.spawn(function()
            local foundBp = player:WaitForChild("Backpack", 5)
            if foundBp and isAlive then
                hookToolContainer(foundBp)
                toolCacheDirty = true
            end
        end)
    end
    cachedEquippedTool = nil
    toolCacheDirty = true
end

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

local lastEquipAttempt = 0
local function stepAutoLift()
    if not isAlive or not autoLift then return end

    local char = player.Character
    if not char then return end

    -- Snelle O(1) cache-hit: geen table/string allocations nodig tijdens normaal liften
    if not toolCacheDirty and cachedEquippedTool and cachedEquippedTool.Parent == char then
        pcall(function() cachedEquippedTool:Activate() end)
        return
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local equippedTool, equippedRank = getEquippedWeightTool(char)
    local backpackTool, backpackRank = getBackpackWeightTool()

    if backpackTool and backpackRank < equippedRank then
        cachedEquippedTool = nil
        toolCacheDirty = true
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

    if equippedTool then
        cachedEquippedTool = equippedTool
        toolCacheDirty = false
        setActiveWeightLabel(equippedTool.Name)
        pcall(function() equippedTool:Activate() end)
        return
    end

    cachedEquippedTool = nil
    toolCacheDirty = true
    setActiveWeightLabel("WACHT OP BARBELL...")
    if tick() - lastSpawnTick >= 1.5 then
        requestWeightFromGame()
    end
end

-- =====================================================================
-- SILENT ANTI-AFK SYSTEEM (ZERO CLICK, ZERO CURSOR STEAL, ZERO TOUCH)
-- =====================================================================
local triggerAfkPulse
local isPulsingAfk = false

table.insert(conns, UserInputService.InputBegan:Connect(function()
    if not isAlive then return end
    local wasOk = (lastEngineInputTick > 0 and (tick() - lastEngineInputTick) < 120)
    lastEngineInputTick = tick()
    if not wasOk then
        updateDashboard()
    end
end))

local function silenceWindowFocusIdle()
    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(UserInputService.WindowFocusReleased)) do
                if conn.Disable then pcall(conn.Disable, conn) end
            end
        end
    end)
end

local function refreshIdledGuard()
    if myIdledConn then
        pcall(function() myIdledConn:Disconnect() end)
        myIdledConn = nil
    end

    local disabled = 0
    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(player.Idled)) do
                if conn.Disable then
                    local ok = pcall(conn.Disable, conn)
                    if ok then disabled = disabled + 1 end
                elseif conn.Disconnect then
                    local ok = pcall(conn.Disconnect, conn)
                    if ok then disabled = disabled + 1 end
                end
            end
        end
    end)
    idledHookedCount = disabled

    if isAlive then
        myIdledConn = player.Idled:Connect(function()
            if isAlive and antiAfkEnabled and not isPulsingAfk then
                triggerAfkPulse()
            end
        end)
    end
end

triggerAfkPulse = function()
    if not isAlive or not antiAfkEnabled or isPulsingAfk then return end
    isPulsingAfk = true

    pcall(function()
        afkPulses = afkPulses + 1
        silenceWindowFocusIdle()
        refreshIdledGuard()

        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)

        task.spawn(function()
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Unknown, false, game)
                task.wait(0.05)
                if isAlive then
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Unknown, false, game)
                end
            end)
        end)

        updateDashboard()
    end)

    isPulsingAfk = false
end

local isReconnecting = false
local function executeAutoReconnect(forceNewServer)
    if not isAlive or isReconnecting then return end
    if not forceNewServer and not autoReconnectEnabled then return end
    isReconnecting = true

    task.spawn(function()
        task.wait(2)
        while isAlive and (forceNewServer or autoReconnectEnabled) do
            local ok = pcall(function()
                if not forceNewServer and #Players:GetPlayers() > 1 and game.JobId and game.JobId ~= "" then
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
        executeAutoReconnect(false)
    end
end))

if GuiService:GetErrorMessage() ~= "" then
    executeAutoReconnect(false)
end

table.insert(conns, TeleportService.TeleportInitFailed:Connect(function(failedPlayer)
    if failedPlayer == player and isAlive and (autoReconnectEnabled or isReconnecting) then
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
            executeAutoReconnect(false)
        end
        table.insert(conns, overlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                executeAutoReconnect(false)
            end
        end))
    end
end)

-- =====================================================================
-- BEACH GYM TELEPORT & VISUAL-STRIP
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
    if not hrp then return nil, nil end

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
    if not centerX or not centerZ then return nil, nil end

    local floorTopY = sandFloor and (sandFloor.Position.Y + sandFloor.Size.Y * 0.5)
        or (refPart and (refPart.Position.Y - refPart.Size.Y * 0.5) or (bboxCf and bboxCf.Position.Y))

    local hipHeight = hum and hum.HipHeight or 2
    local standY = floorTopY + hipHeight + (hrp.Size.Y * 0.5) + 0.15
    return CFrame.new(centerX + 2, standY, centerZ + 2), sandFloor
end

local function stripBeachGymVisuals(gymObj, sandFloor)
    if not gymObj then return end
    if sandFloor then
        protectedGymFloors[sandFloor] = true
    end
    for _, desc in ipairs(gymObj:GetDescendants()) do
        disableVisualNoise(desc)
    end
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

    local targetCFrame, sandFloor = getBeachGymTargetCFrame(gymObj, char)
    if not targetCFrame then return end

    handledGyms[gymObj] = true
    removeSafePlatform()
    activeBeachGym = gymObj

    stripBeachGymVisuals(gymObj, sandFloor)

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
    refreshToolWatchers(newChar)
    task.wait(0.2)
    if not isAlive then return end

    disableCosmeticRemotes()
    disableUnneededClientExtras()
    silenceWindowFocusIdle()
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
TitleLabel.Size = UDim2.new(1, -198, 1, 0)
TitleLabel.Position = UDim2.new(0, 56, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.Text = "MzD KALB // VOID"
TitleLabel.TextColor3 = TextPure
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.TextTruncate = Enum.TextTruncate.AtEnd

local Render3DBtn = Instance.new("TextButton", TopBar)
Render3DBtn.Size = UDim2.new(0, 48, 0, 28)
Render3DBtn.Position = UDim2.new(1, -134, 0.5, -14)
Render3DBtn.BackgroundColor3 = render3dEnabled and Color3.fromRGB(14, 120, 74) or Color3.fromRGB(45, 45, 45)
Render3DBtn.Font = Enum.Font.GothamBlack
Render3DBtn.Text = render3dEnabled and "3D:AAN" or "3D:UIT"
Render3DBtn.TextColor3 = TextPure
Render3DBtn.TextSize = 10
Instance.new("UICorner", Render3DBtn).CornerRadius = UDim.new(0, 7)

Render3DBtn.MouseButton1Click:Connect(function()
    render3dEnabled = not render3dEnabled
    Render3DBtn.Text = render3dEnabled and "3D:AAN" or "3D:UIT"
    Render3DBtn.BackgroundColor3 = render3dEnabled and Color3.fromRGB(14, 120, 74) or Color3.fromRGB(45, 45, 45)
    pcall(function()
        RunService:Set3dRenderingEnabled(render3dEnabled)
    end)
end)

local ZoomBtn = Instance.new("TextButton", TopBar)
ZoomBtn.Size = UDim2.new(0, 40, 0, 28)
ZoomBtn.Position = UDim2.new(1, -82, 0.5, -14)
ZoomBtn.BackgroundColor3 = Color3.fromRGB(18, 42, 33)
ZoomBtn.Font = Enum.Font.GothamBlack
ZoomBtn.Text = "1.0x"
ZoomBtn.TextColor3 = NeonGreen
ZoomBtn.TextSize = 11
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
    toolCacheDirty = true
    if val then
        lastEquipAttempt = 0
        lastInventoryPull = 0
        stepAutoLift()
    else
        cachedEquippedTool = nil
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
    if val then
        triggerAfkPulse()
    else
        updateDashboard()
    end
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

-- Soepel verslepen (muis + touch)
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

-- =====================================================================
-- HYBRID BONUS CLAIMER + MEMORY-SAFE WATCHER (GEEN NIL-LEK!)
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
        if cConn then cConn:Disconnect() end
        lbl = btn and btn:FindFirstChildOfClass("TextLabel")
        if lbl and lbl.Text ~= "" then
            lastSeenMultiplier = string.lower(lbl.Text)
        end
    end

    if not isAlive or not autoBonus or not btn or not btn.Parent or not btn.Visible then return end

    local firedSignal = false
    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(btn.MouseButton1Click)) do
                conn:Fire()
                firedSignal = true
            end
            if not firedSignal then
                for _, conn in pairs(getconnections(btn.Activated)) do
                    conn:Fire()
                    firedSignal = true
                end
            end
        end
    end)

    if bonusRemote then
        pcall(function() bonusRemote:FireServer() end)
    end
    if not firedSignal and btn and btn.Parent and btn.Visible then
        clickScreenAtButton(btn)
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
local bonusWatchConns = setmetatable({}, {__mode = "k"})

local function cleanupBonusWatch(btn)
    local list = bonusWatchConns[btn]
    if list then
        for _, c in ipairs(list) do
            pcall(function() c:Disconnect() end)
        end
        bonusWatchConns[btn] = nil
    end
    hookedBonusButtons[btn] = nil
    claimedBonusBtns[btn] = nil
end

local function watchKickUpgradesChild(child)
    if not isAlive then return end
    if child.Name == "PopBonus" then
        onPopBonusConfirmed()
    elseif child.Name == "Bonus" and child:IsA("GuiButton") then
        if child.Visible then task.spawn(activateBonusButton, child) end
        if not hookedBonusButtons[child] then
            hookedBonusButtons[child] = true
            local visConn = child:GetPropertyChangedSignal("Visible"):Connect(function()
                if isAlive and child.Visible then
                    task.spawn(activateBonusButton, child)
                end
            end)
            local ancConn = child.AncestryChanged:Connect(function(_, newParent)
                if not newParent then
                    cleanupBonusWatch(child)
                end
            end)
            bonusWatchConns[child] = {visConn, ancConn}
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

CloseBtn.MouseButton1Click:Connect(function()
    isAlive = false
    autoLift, autoBonus, autoBeachGym, antiAfkEnabled, autoReconnectEnabled = false, false, false, false, false

    pcall(function()
        RunService:Set3dRenderingEnabled(true)
    end)
    if setfpscap then pcall(setfpscap, 60) end
    if myIdledConn then pcall(function() myIdledConn:Disconnect() end) end
    if activeGymDespawnConn then pcall(function() activeGymDespawnConn:Disconnect() end) end

    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(gymWatchConns) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(containerWatchConns) do pcall(function() c:Disconnect() end) end

    for _, list in pairs(bonusWatchConns) do
        for _, c in ipairs(list) do
            pcall(function() c:Disconnect() end)
        end
    end
    table.clear(bonusWatchConns)

    for _, bucket in pairs(instanceLockConns) do
        for _, c in pairs(bucket) do
            pcall(function() c:Disconnect() end)
        end
    end
    table.clear(instanceLockConns)

    removeSafePlatform()

    pcall(function()
        local ps = player:FindFirstChild("PlayerScripts")
        local rbxSounds = ps and ps:FindFirstChild("RbxCharacterSounds")
        if rbxSounds and rbxSounds:IsA("LocalScript") then
            rbxSounds.Disabled = false
        end
    end)
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
    disableUnneededClientExtras()
    stripAllGameGuis()
    stripDeepUnusedAssets()

    local char = player.Character
    local protectedRoots = {
        ["Camera"] = true,
        ["Terrain"] = true,
        ["Players"] = true,
        ["Debris"] = true,
        ["MzD_SafePlatform"] = true,
        [player.Name] = true
    }

    for _, obj in ipairs(Workspace:GetChildren()) do
        if IGNORED_WORKSPACE_FOLDERS[obj.Name] then
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

    local existingGym = findBeachGym()
    if existingGym then
        local _, sandFloor = getBeachGymTargetCFrame(existingGym, char)
        if sandFloor then protectedGymFloors[sandFloor] = true end
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

local function isInsideIgnoredRoot(desc)
    local cur = desc
    while cur and cur.Parent and cur.Parent ~= Workspace do
        cur = cur.Parent
    end
    if not cur or cur.Parent ~= Workspace then return false end
    local rootName = cur.Name
    if IGNORED_WORKSPACE_FOLDERS[rootName] then
        return true
    elseif rootName == "Players" then
        local pModel = desc
        while pModel and pModel.Parent ~= cur do
            pModel = pModel.Parent
        end
        return pModel ~= nil and pModel.Name ~= player.Name
    elseif rootName == "Debris" then
        local dChild = desc
        while dChild and dChild.Parent ~= cur do
            dChild = dChild.Parent
        end
        if not dChild then return false end
        if dChild.Name ~= "GymMachine" then return true end
        local gmChild = desc
        while gmChild and gmChild.Parent ~= dChild do
            gmChild = gmChild.Parent
        end
        return gmChild ~= nil and string.lower(gmChild.Name) ~= "beach gym"
    end
    return false
end

table.insert(conns, Workspace.ChildAdded:Connect(function(obj)
    if not isAlive or not obj then return end
    local name = obj.Name
    if name == "MzD_SafePlatform" or name == "Camera" or name == "Terrain"
        or name == "Players" or name == "Debris" or name == player.Name
        or obj == player.Character then
        return
    end
    if IGNORED_WORKSPACE_FOLDERS[name] then
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
            if IGNORED_WORKSPACE_FOLDERS[pName] then
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
    if isInsideIgnoredRoot(desc) then return end
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
    local lastLiftTick = 0
    while isAlive and ScreenGui.Parent do
        task.wait()
        if not isAlive or not ScreenGui.Parent then break end
        if autoLift and (tick() - lastLiftTick) >= 0.06 then
            lastLiftTick = tick()
            stepAutoLift()
        end
    end
end)

task.spawn(function()
    while isAlive and ScreenGui.Parent do
        task.wait(55)
        if not isAlive or not ScreenGui.Parent then break end
        if setfpscap then pcall(setfpscap, TARGET_FPS) end
        pcall(function() Workspace.Terrain:Clear() end)
        pcall(collectgarbage, "step", 800)
        if antiAfkEnabled then
            triggerAfkPulse()
        end
    end
end)

if AUTO_REJOIN_MINUTES and AUTO_REJOIN_MINUTES > 0 then
    task.spawn(function()
        task.wait(AUTO_REJOIN_MINUTES * 60)
        if isAlive and ScreenGui.Parent then
            executeAutoReconnect(true)
        end
    end)
end

obliterateWorldNow()
task.delay(4, function()
    if isAlive and ScreenGui.Parent then
        stripDeepUnusedAssets()
    end
end)
refreshToolWatchers(player.Character)
silenceWindowFocusIdle()
refreshIdledGuard()
triggerAfkPulse()
stepAutoLift()
