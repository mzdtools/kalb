-- =====================================================================
-- MzD KALB script - Ultra-Void v2 (Zero-Particle & GitHub Ready)
-- =====================================================================

if setfpscap then
    pcall(setfpscap, 20)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local pGui = player:WaitForChild("PlayerGui")

-- Directe referentie naar de Bonus Remote
local bonusRemote = nil
task.spawn(function()
    local shared = ReplicatedStorage:WaitForChild("Shared", 15)
    local packages = shared and shared:WaitForChild("Packages", 15)
    local network = packages and packages:WaitForChild("Network", 15)
    bonusRemote = network and network:WaitForChild("rev_TaviMishkal", 15)
end)

-- Verwijder oude instantie van deze HUD indien opnieuw uitgevoerd
local uiName = "MzD_KALB_HUD"
local existing = (gethui and gethui():FindFirstChild(uiName)) or CoreGui:FindFirstChild(uiName)
if existing then existing:Destroy() end

-- =====================================================================
-- Status & Tellers
-- =====================================================================
local autoBonus = true
local autoBeachGym = true
local antiAfkEnabled = true
local autoReconnectEnabled = true
local fpsCapEnabled = true
local worldWiped = false

local count2x = 0
local count5x = 0
local count10x = 0
local totalBonusCount = 0
local gymTpCount = 0
local lastReactionMs = 0
local afkPulses = 0
local isMinimized = false

local lastSeenMultiplier = "x2"
local lastBonusSpawnTick = 0
local activeBeachGym = nil

local afkConnection = nil
local errorConnection = nil
local bonusConn = nil
local popCleanerConn = nil
local playerCleanerConn = nil
local debrisCleanerConn = nil
local respawnConn = nil
local worldEffectConn = nil
local charEffectConn = nil
local gymWatchConns = {}

local Val2xLabel, Val5xLabel, Val10xLabel, FooterStatsLabel = nil, nil, nil, nil

-- =====================================================================
-- Event-Driven Dashboard Update
-- =====================================================================
local function updateDashboard()
    if Val2xLabel then Val2xLabel.Text = tostring(count2x) end
    if Val5xLabel then Val5xLabel.Text = tostring(count5x) end
    if Val10xLabel then Val10xLabel.Text = tostring(count10x) end
    if FooterStatsLabel then
        FooterStatsLabel.Text = string.format("TOT: %d  |  GYM: %d  |  %dms  |  AFK: %d  |  20 FPS", totalBonusCount, gymTpCount, lastReactionMs, afkPulses)
    end
end

-- =====================================================================
-- 4-LAAGS BULLETPROOF ANTI-AFK & AUTO-RECONNECT
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

local function setupBulletproofAfk()
    if afkConnection then
        afkConnection:Disconnect()
        afkConnection = nil
    end

    pcall(function()
        if getconnections then
            for _, conn in pairs(getconnections(player.Idled)) do
                if conn.Disable then conn:Disable() end
            end
        end
    end)

    afkConnection = player.Idled:Connect(function()
        triggerAfkPulse()
    end)
end

setupBulletproofAfk()

task.spawn(function()
    local cycle = 0
    while true do
        task.wait(180)
        if not CoreGui:FindFirstChild(uiName) and not (gethui and gethui():FindFirstChild(uiName)) then
            break
        end
        if fpsCapEnabled and setfpscap then
            pcall(setfpscap, 20)
        end
        if antiAfkEnabled then
            cycle = cycle + 1
            triggerAfkPulse()

            if cycle % 2 == 0 then
                pcall(function()
                    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.FloorMaterial ~= Enum.Material.Air then
                        hum.Jump = true
                    end
                end)
            end
        end
    end
end)

local isReconnecting = false
local function attemptReconnect()
    if isReconnecting or not autoReconnectEnabled then return end
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

errorConnection = GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and msg ~= "" and autoReconnectEnabled then
        attemptReconnect()
    end
end)

-- =====================================================================
-- PLATFORM BEHEER & DIRECTE BEACH ISLAND LANDING + DESPAWN CATCH
-- =====================================================================
local function removeSafePlatform()
    local existingPad = Workspace:FindFirstChild("MzD_SafePlatform")
    if existingPad then
        existingPad:Destroy()
    end
end

local function spawnPlatformAtPosition(pos, padName)
    local nameToUse = padName or "MzD_SafePlatform"
    local existingPad = Workspace:FindFirstChild(nameToUse)
    if existingPad then existingPad:Destroy() end

    local safePad = Instance.new("Part")
    safePad.Name = nameToUse
    safePad.Size = Vector3.new(22, 2, 22)
    safePad.Position = pos
    safePad.Anchored = true
    safePad.CanCollide = true
    safePad.Material = Enum.Material.SmoothPlastic
    safePad.Color = Color3.fromRGB(10, 22, 18)
    safePad.Parent = Workspace
    return safePad
end

local function spawnPlatformUnderPlayer(char)
    local targetChar = char or player.Character
    if not targetChar then return end

    local hrp = targetChar:WaitForChild("HumanoidRootPart", 5)
    local hum = targetChar:FindFirstChildOfClass("Humanoid")
    if not hrp then return end

    local hipHeight = hum and hum.HipHeight or 2
    local rootHalfHeight = hrp.Size.Y * 0.5
    local footOffset = hipHeight + rootHalfHeight
    local platformThickness = 2

    local padPos = hrp.Position - Vector3.new(0, footOffset + (platformThickness * 0.5), 0)
    spawnPlatformAtPosition(padPos, "MzD_SafePlatform")
end

local function findBeachFloorPart(gymObj)
    if gymObj:IsA("BasePart") then
        return gymObj
    end

    local bestPart = nil
    local bestArea = 0
    for _, desc in ipairs(gymObj:GetDescendants()) do
        if desc:IsA("BasePart") and desc.CanCollide then
            local area = desc.Size.X * desc.Size.Z
            if area > bestArea then
                bestArea = area
                bestPart = desc
            end
        end
    end

    if not bestPart then
        bestPart = gymObj:FindFirstChildWhichIsA("BasePart", true)
    end
    return bestPart
end

local handledGyms = setmetatable({}, {__mode = "k"})

local function teleportToBeachGym(gymObj)
    if not autoBeachGym or not gymObj or not gymObj.Parent then return end
    if handledGyms[gymObj] then return end
    handledGyms[gymObj] = true

    task.wait(0.15)
    if not gymObj or not gymObj.Parent then return end

    local floorPart = findBeachFloorPart(gymObj)
    if not floorPart then return end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then return end

    removeSafePlatform()
    activeBeachGym = gymObj

    local floorTop = floorPart.Position + Vector3.new(0, floorPart.Size.Y * 0.5, 0)
    local hipHeight = hum and hum.HipHeight or 2
    local rootHalfHeight = hrp.Size.Y * 0.5
    local targetPlayerPos = floorTop + Vector3.new(0, hipHeight + rootHalfHeight + 0.25, 0)

    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = CFrame.new(targetPlayerPos)

    if firetouchinterest then
        for _, desc in ipairs(gymObj:GetDescendants()) do
            if desc:IsA("TouchTransmitter") and desc.Parent and desc.Parent:IsA("BasePart") then
                pcall(function()
                    firetouchinterest(hrp, desc.Parent, 0)
                    task.wait()
                    firetouchinterest(hrp, desc.Parent, 1)
                end)
            end
        end
    end

    gymTpCount = gymTpCount + 1
    updateDashboard()

    local despawnConn
    despawnConn = gymObj.AncestryChanged:Connect(function(_, newParent)
        if not newParent or not gymObj:IsDescendantOf(Workspace) then
            if despawnConn then despawnConn:Disconnect() end
            if activeBeachGym == gymObj then
                activeBeachGym = nil
            end
            local currentChar = player.Character
            local currentHrp = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
            if currentHrp then
                currentHrp.AssemblyLinearVelocity = Vector3.zero
            end
            spawnPlatformUnderPlayer(currentChar)
        end
    end)
end

local function setupBeachGymWatcher()
    for _, c in ipairs(gymWatchConns) do
        pcall(function() c:Disconnect() end)
    end
    gymWatchConns = {}

    local function hookGymMachine(gmFolder)
        for _, child in ipairs(gmFolder:GetChildren()) do
            if string.lower(child.Name) == "beach gym" then
                task.spawn(teleportToBeachGym, child)
            end
        end
        local c = gmFolder.ChildAdded:Connect(function(child)
            if string.lower(child.Name) == "beach gym" then
                task.spawn(teleportToBeachGym, child)
            end
        end)
        table.insert(gymWatchConns, c)
    end

    local debris = Workspace:WaitForChild("Debris", 15)
    if debris then
        local gm = debris:FindFirstChild("GymMachine")
        if gm then
            hookGymMachine(gm)
        end
        local cDebris = debris.ChildAdded:Connect(function(child)
            if child.Name == "GymMachine" then
                hookGymMachine(child)
            end
        end)
        table.insert(gymWatchConns, cDebris)
    end
end

setupBeachGymWatcher()

-- =====================================================================
-- ULTRA-VOID 3D & CHARACTER EFFECT DESTROYER (0% Render Overhead)
-- =====================================================================
local function stripVisualInstance(inst)
    if not inst or not inst.Parent then return end
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Sparkles") or inst:IsA("Fire") or inst:IsA("Smoke")
        or inst:IsA("Explosion") or inst:IsA("Highlight")
        or inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight")
        or inst:IsA("BillboardGui") or inst:IsA("SurfaceGui")
        or inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("Sound") then
        pcall(function() inst:Destroy() end)
    elseif inst:IsA("BasePart") and inst.Name ~= "MzD_SafePlatform" then
        inst.Transparency = 1
        inst.CastShadow = false
    end
end

local function stripCharacterVisuals(char)
    if not char then return end
    for _, desc in ipairs(char:GetDescendants()) do
        stripVisualInstance(desc)
    end
    if charEffectConn then
        charEffectConn:Disconnect()
        charEffectConn = nil
    end
    charEffectConn = char.DescendantAdded:Connect(function(desc)
        if worldWiped then
            stripVisualInstance(desc)
        end
    end)
end

local function enableVoidMode()
    if not activeBeachGym then
        spawnPlatformUnderPlayer(player.Character)
    end

    stripCharacterVisuals(player.Character)

    if worldWiped then return end
    worldWiped = true

    local char = player.Character

    respawnConn = player.CharacterAdded:Connect(function(newChar)
        if worldWiped then
            task.wait(0.15)
            stripCharacterVisuals(newChar)
            if activeBeachGym and activeBeachGym:IsDescendantOf(Workspace) then
                handledGyms[activeBeachGym] = nil
                teleportToBeachGym(activeBeachGym)
            else
                spawnPlatformUnderPlayer(newChar)
            end
        end
    end)

    local keepWorkspace = {
        ["Areas"] = true,
        ["Zones"] = true,
        ["Machine"] = true,
        ["KickUpgrades"] = true,
        ["Players"] = true,
        ["Camera"] = true,
        ["Terrain"] = true,
        ["Debris"] = true,
        ["MzD_SafePlatform"] = true,
        [player.Name] = true
    }

    for _, obj in ipairs(Workspace:GetChildren()) do
        if not keepWorkspace[obj.Name] and obj ~= char then
            pcall(function()
                obj:Destroy()
            end)
        elseif keepWorkspace[obj.Name] and obj.Name ~= "Players" and obj.Name ~= "MzD_SafePlatform" and obj.Name ~= "Debris" and obj.Name ~= "Camera" and obj.Name ~= "Terrain" and obj ~= char then
            for _, p in ipairs(obj:GetDescendants()) do
                stripVisualInstance(p)
            end
        end
    end

    -- Live filter: blokkeert elke nieuwe particle, aura, beam of geluid in de hele wereld
    worldEffectConn = Workspace.DescendantAdded:Connect(function(desc)
        if not worldWiped then return end
        if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam")
            or desc:IsA("Sparkles") or desc:IsA("Fire") or desc:IsA("Smoke")
            or desc:IsA("BillboardGui") or desc:IsA("Highlight") or desc:IsA("Sound") then
            pcall(function() desc:Destroy() end)
        end
    end)

    local debrisFolder = Workspace:FindFirstChild("Debris")
    if debrisFolder then
        for _, dChild in ipairs(debrisFolder:GetChildren()) do
            if dChild.Name ~= "GymMachine" then
                pcall(function() dChild:Destroy() end)
            end
        end
        debrisCleanerConn = debrisFolder.ChildAdded:Connect(function(c)
            if c.Name ~= "GymMachine" then
                task.wait()
                if c and c.Parent and c.Name ~= "GymMachine" then
                    pcall(function() c:Destroy() end)
                end
            end
        end)
    end

    local playersFolder = Workspace:FindFirstChild("Players")
    if playersFolder then
        for _, pModel in ipairs(playersFolder:GetChildren()) do
            if pModel.Name ~= player.Name then
                pcall(function() pModel:Destroy() end)
            end
        end
        playerCleanerConn = playersFolder.ChildAdded:Connect(function(pModel)
            if worldWiped and pModel.Name ~= player.Name then
                task.wait()
                pcall(function() pModel:Destroy() end)
            end
        end)
    end

    -- Verwijder lucht, wolken, schaduwen en post-processing volledig
    pcall(function()
        Workspace.Terrain:Clear()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 0
        Lighting.Ambient = Color3.fromRGB(0, 0, 0)
        Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
        for _, eff in ipairs(Lighting:GetChildren()) do
            eff:Destroy()
        end
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)

    -- Verberg standaard Roblox HUD-onderdelen (PlayerList, Chat, Emotes)
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)

    local kickUpgrades = pGui:FindFirstChild("KickUpgrades")
    if kickUpgrades then
        local popFolder = kickUpgrades:FindFirstChild("Pop")
        if popFolder then
            popFolder:ClearAllChildren()
            popCleanerConn = popFolder.ChildAdded:Connect(function(c)
                c:Destroy()
            end)
        end
    end
end

-- =====================================================================
-- FUTURISTISCHE CYBER-GROENE HUD & CUSTOM MzD LOGO
-- =====================================================================
local fullHeight = 452
local guiWidth = 332

local NeonGreen      = Color3.fromRGB(0, 255, 145)
local EmeraldGlow    = Color3.fromRGB(16, 210, 120)
local DeepCyberBg    = Color3.fromRGB(7, 13, 11)
local PanelCyberBg   = Color3.fromRGB(11, 20, 17)
local CardCyberBg    = Color3.fromRGB(13, 24, 20)
local TextPrimary    = Color3.fromRGB(238, 255, 247)
local TextMuted      = Color3.fromRGB(115, 175, 148)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = uiName
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = (gethui and gethui()) or CoreGui

local GlowAura = Instance.new("Frame")
GlowAura.Name = "GlowAura"
GlowAura.Size = UDim2.new(0, guiWidth + 6, 0, fullHeight + 6)
GlowAura.Position = UDim2.new(0.5, -((guiWidth + 6) / 2), 0.21, 0)
GlowAura.BackgroundColor3 = NeonGreen
GlowAura.BackgroundTransparency = 0.88
GlowAura.BorderSizePixel = 0
GlowAura.Parent = ScreenGui

local AuraCorner = Instance.new("UICorner")
AuraCorner.CornerRadius = UDim.new(0, 16)
AuraCorner.Parent = GlowAura

local AuraStroke = Instance.new("UIStroke")
AuraStroke.Color = NeonGreen
AuraStroke.Thickness = 2
AuraStroke.Transparency = 0.65
AuraStroke.Parent = GlowAura

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, guiWidth, 0, fullHeight)
MainFrame.Position = UDim2.new(0, 3, 0, 3)
MainFrame.BackgroundColor3 = DeepCyberBg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = GlowAura

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = NeonGreen
MainStroke.Thickness = 1.6
MainStroke.Transparency = 0.15
MainStroke.Parent = MainFrame

local UIGradient = Instance.new("UIGradient")
UIGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 28, 22)),
    ColorSequenceKeypoint.new(0.45, Color3.fromRGB(8, 15, 13)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 10, 9))
})
UIGradient.Rotation = 55
UIGradient.Parent = MainFrame

local TopGlowBar = Instance.new("Frame")
TopGlowBar.Size = UDim2.new(1, 0, 0, 2)
TopGlowBar.Position = UDim2.new(0, 0, 0, 0)
TopGlowBar.BackgroundColor3 = NeonGreen
TopGlowBar.BorderSizePixel = 0
TopGlowBar.Parent = MainFrame

local TopBarGrad = Instance.new("UIGradient")
TopBarGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.85),
    NumberSequenceKeypoint.new(0.5, 0),
    NumberSequenceKeypoint.new(1, 0.85)
})
TopBarGrad.Parent = TopGlowBar

local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 54)
TopBar.BackgroundColor3 = PanelCyberBg
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopDivider = Instance.new("Frame")
TopDivider.Size = UDim2.new(1, 0, 0, 1)
TopDivider.Position = UDim2.new(0, 0, 1, -1)
TopDivider.BackgroundColor3 = NeonGreen
TopDivider.BackgroundTransparency = 0.45
TopDivider.BorderSizePixel = 0
TopDivider.Parent = TopBar

local LogoHolder = Instance.new("Frame")
LogoHolder.Name = "MzDLogo"
LogoHolder.Size = UDim2.new(0, 38, 0, 38)
LogoHolder.Position = UDim2.new(0, 12, 0.5, -19)
LogoHolder.BackgroundColor3 = Color3.fromRGB(10, 26, 20)
LogoHolder.BorderSizePixel = 0
LogoHolder.Parent = TopBar

local LogoCorner = Instance.new("UICorner")
LogoCorner.CornerRadius = UDim.new(0, 9)
LogoCorner.Parent = LogoHolder

local LogoStroke = Instance.new("UIStroke")
LogoStroke.Color = NeonGreen
LogoStroke.Thickness = 1.6
LogoStroke.Parent = LogoHolder

local LogoGrad = Instance.new("UIGradient")
LogoGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 145)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 35, 25))
})
LogoGrad.Rotation = 135
LogoGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.65),
    NumberSequenceKeypoint.new(1, 0.1)
})
LogoGrad.Parent = LogoHolder

local CornerTL = Instance.new("Frame")
CornerTL.Size = UDim2.new(0, 8, 0, 2)
CornerTL.Position = UDim2.new(0, 3, 0, 3)
CornerTL.BackgroundColor3 = Color3.fromRGB(190, 255, 225)
CornerTL.BorderSizePixel = 0
CornerTL.Parent = LogoHolder

local CornerBR = Instance.new("Frame")
CornerBR.Size = UDim2.new(0, 8, 0, 2)
CornerBR.Position = UDim2.new(1, -11, 1, -5)
CornerBR.BackgroundColor3 = Color3.fromRGB(190, 255, 225)
CornerBR.BorderSizePixel = 0
CornerBR.Parent = LogoHolder

local LogoTextM = Instance.new("TextLabel")
LogoTextM.Size = UDim2.new(1, 0, 0, 22)
LogoTextM.Position = UDim2.new(0, 0, 0, 4)
LogoTextM.BackgroundTransparency = 1
LogoTextM.Font = Enum.Font.GothamBlack
LogoTextM.Text = "MzD"
LogoTextM.TextColor3 = Color3.fromRGB(245, 255, 250)
LogoTextM.TextSize = 13
LogoTextM.Parent = LogoHolder

local LogoSubTag = Instance.new("TextLabel")
LogoSubTag.Size = UDim2.new(1, 0, 0, 10)
LogoSubTag.Position = UDim2.new(0, 0, 0, 23)
LogoSubTag.BackgroundTransparency = 1
LogoSubTag.Font = Enum.Font.Code
LogoSubTag.Text = "CORE"
LogoSubTag.TextColor3 = NeonGreen
LogoSubTag.TextSize = 8
LogoSubTag.Parent = LogoHolder

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -128, 0, 20)
TitleLabel.Position = UDim2.new(0, 58, 0, 9)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.Text = "MzD KALB // SYSTEM"
TitleLabel.TextColor3 = TextPrimary
TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local SubTitleLabel = Instance.new("TextLabel")
SubTitleLabel.Size = UDim2.new(1, -128, 0, 14)
SubTitleLabel.Position = UDim2.new(0, 58, 0, 29)
SubTitleLabel.BackgroundTransparency = 1
SubTitleLabel.Font = Enum.Font.Code
SubTitleLabel.Text = "ULTRA-VOID • 20 FPS LOCK"
SubTitleLabel.TextColor3 = EmeraldGlow
SubTitleLabel.TextSize = 10
SubTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubTitleLabel.Parent = TopBar

task.spawn(function()
    while GlowAura and GlowAura.Parent do
        TweenService:Create(AuraStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.25}):Play()
        TweenService:Create(LogoStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.45}):Play()
        task.wait(1.4)
        if not GlowAura or not GlowAura.Parent then break end
        TweenService:Create(AuraStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.78}):Play()
        TweenService:Create(LogoStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.05}):Play()
        task.wait(1.4)
    end
end)

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -68, 0.5, -14)
MinBtn.BackgroundColor3 = Color3.fromRGB(16, 34, 27)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Text = "-"
MinBtn.TextColor3 = NeonGreen
MinBtn.TextSize = 16
MinBtn.Parent = TopBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 7)
MinCorner.Parent = MinBtn

local MinStroke = Instance.new("UIStroke")
MinStroke.Color = EmeraldGlow
MinStroke.Thickness = 1
MinStroke.Transparency = 0.5
MinStroke.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -14)
CloseBtn.BackgroundColor3 = Color3.fromRGB(165, 35, 48)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 12
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 7)
CloseCorner.Parent = CloseBtn

local Section1Title = Instance.new("TextLabel")
Section1Title.Size = UDim2.new(1, -28, 0, 16)
Section1Title.Position = UDim2.new(0, 14, 0, 62)
Section1Title.BackgroundTransparency = 1
Section1Title.Font = Enum.Font.Code
Section1Title.Text = "> MULTIPLIER TELEMETRIE [VERIFIED]"
Section1Title.TextColor3 = TextMuted
Section1Title.TextSize = 10
Section1Title.TextXAlignment = Enum.TextXAlignment.Left
Section1Title.Parent = MainFrame

local CardsContainer = Instance.new("Frame")
CardsContainer.Size = UDim2.new(1, -28, 0, 70)
CardsContainer.Position = UDim2.new(0, 14, 0, 82)
CardsContainer.BackgroundTransparency = 1
CardsContainer.Parent = MainFrame

local function createStatCard(xScale, xOffset, badgeText, accentColor)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(0.315, 0, 1, 0)
    Card.Position = UDim2.new(xScale, xOffset, 0, 0)
    Card.BackgroundColor3 = CardCyberBg
    Card.BorderSizePixel = 0
    Card.Parent = CardsContainer

    local CCorner = Instance.new("UICorner")
    CCorner.CornerRadius = UDim.new(0, 10)
    CCorner.Parent = Card

    local CStroke = Instance.new("UIStroke")
    CStroke.Color = accentColor
    CStroke.Thickness = 1.3
    CStroke.Transparency = 0.35
    CStroke.Parent = Card

    local TopAccent = Instance.new("Frame")
    TopAccent.Size = UDim2.new(0.65, 0, 0, 2)
    TopAccent.Position = UDim2.new(0.175, 0, 0, 0)
    TopAccent.BackgroundColor3 = accentColor
    TopAccent.BorderSizePixel = 0
    TopAccent.Parent = Card

    local BadgeLabel = Instance.new("TextLabel")
    BadgeLabel.Size = UDim2.new(1, 0, 0, 20)
    BadgeLabel.Position = UDim2.new(0, 0, 0, 8)
    BadgeLabel.BackgroundTransparency = 1
    BadgeLabel.Font = Enum.Font.GothamBold
    BadgeLabel.Text = badgeText
    BadgeLabel.TextColor3 = accentColor
    BadgeLabel.TextSize = 12
    BadgeLabel.Parent = Card

    local ValueLabel = Instance.new("TextLabel")
    ValueLabel.Size = UDim2.new(1, -8, 0, 28)
    ValueLabel.Position = UDim2.new(0, 4, 0, 31)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Font = Enum.Font.GothamBlack
    ValueLabel.Text = "0"
    ValueLabel.TextColor3 = TextPrimary
    ValueLabel.TextScaled = true
    ValueLabel.Parent = Card

    local SizeLimit = Instance.new("UITextSizeConstraint")
    SizeLimit.MaxTextSize = 21
    SizeLimit.MinTextSize = 11
    SizeLimit.Parent = ValueLabel

    return ValueLabel
end

Val2xLabel = createStatCard(0, 0, "2X BOOST", Color3.fromRGB(185, 95, 255))
Val5xLabel = createStatCard(0.3425, 0, "5X BOOST", Color3.fromRGB(255, 145, 35))
Val10xLabel = createStatCard(0.685, 0, "10X BOOST", NeonGreen)

local Section2Title = Instance.new("TextLabel")
Section2Title.Size = UDim2.new(1, -28, 0, 16)
Section2Title.Position = UDim2.new(0, 14, 0, 162)
Section2Title.BackgroundTransparency = 1
Section2Title.Font = Enum.Font.Code
Section2Title.Text = "> SYSTEEM MODULES"
Section2Title.TextColor3 = TextMuted
Section2Title.TextSize = 10
Section2Title.TextXAlignment = Enum.TextXAlignment.Left
Section2Title.Parent = MainFrame

local function createToggleRow(labelText, subText, yPos, defaultState, callback)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, -28, 0, 44)
    Row.Position = UDim2.new(0, 14, 0, yPos)
    Row.BackgroundColor3 = CardCyberBg
    Row.BorderSizePixel = 0
    Row.Parent = MainFrame

    local RowCorner = Instance.new("UICorner")
    RowCorner.CornerRadius = UDim.new(0, 9)
    RowCorner.Parent = Row

    local RowStroke = Instance.new("UIStroke")
    RowStroke.Color = defaultState and Color3.fromRGB(22, 75, 54) or Color3.fromRGB(28, 45, 38)
    RowStroke.Thickness = 1
    RowStroke.Parent = Row

    local Indicator = Instance.new("Frame")
    Indicator.Size = UDim2.new(0, 3, 0, 24)
    Indicator.Position = UDim2.new(0, 0, 0.5, -12)
    Indicator.BackgroundColor3 = defaultState and NeonGreen or Color3.fromRGB(45, 70, 60)
    Indicator.BorderSizePixel = 0
    Indicator.Parent = Row

    local IndCorner = Instance.new("UICorner")
    IndCorner.CornerRadius = UDim.new(0, 2)
    IndCorner.Parent = Indicator

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -74, 0, 18)
    Label.Position = UDim2.new(0, 12, 0, 6)
    Label.BackgroundTransparency = 1
    Label.Font = Enum.Font.GothamSemibold
    Label.Text = labelText
    Label.TextColor3 = TextPrimary
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Row

    local SubLabel = Instance.new("TextLabel")
    SubLabel.Size = UDim2.new(1, -74, 0, 14)
    SubLabel.Position = UDim2.new(0, 12, 0, 24)
    SubLabel.BackgroundTransparency = 1
    SubLabel.Font = Enum.Font.Gotham
    SubLabel.Text = subText
    SubLabel.TextColor3 = TextMuted
    SubLabel.TextSize = 10
    SubLabel.TextXAlignment = Enum.TextXAlignment.Left
    SubLabel.Parent = Row

    local SwitchBg = Instance.new("TextButton")
    SwitchBg.Size = UDim2.new(0, 44, 0, 22)
    SwitchBg.Position = UDim2.new(1, -54, 0.5, -11)
    SwitchBg.BackgroundColor3 = defaultState and EmeraldGlow or Color3.fromRGB(24, 42, 35)
    SwitchBg.AutoButtonColor = false
    SwitchBg.Text = ""
    SwitchBg.Parent = Row

    local SwCorner = Instance.new("UICorner")
    SwCorner.CornerRadius = UDim.new(1, 0)
    SwCorner.Parent = SwitchBg

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 16, 0, 16)
    Knob.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    Knob.BackgroundColor3 = Color3.fromRGB(245, 255, 250)
    Knob.BorderSizePixel = 0
    Knob.Parent = SwitchBg

    local KnobCorner = Instance.new("UICorner")
    KnobCorner.CornerRadius = UDim.new(1, 0)
    KnobCorner.Parent = Knob

    local state = defaultState
    SwitchBg.MouseButton1Click:Connect(function()
        state = not state
        local targetPos = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        local targetCol = state and EmeraldGlow or Color3.fromRGB(24, 42, 35)
        local targetInd = state and NeonGreen or Color3.fromRGB(45, 70, 60)
        TweenService:Create(Knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Position = targetPos}):Play()
        TweenService:Create(SwitchBg, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {BackgroundColor3 = targetCol}):Play()
        TweenService:Create(Indicator, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {BackgroundColor3 = targetInd}):Play()
        callback(state)
    end)
end

createToggleRow("Smart Bonus Claimer", "Echte klik + remote + PopBonus check", 182, autoBonus, function(val)
    autoBonus = val
end)

createToggleRow("Auto-TP Beach Island + Catch", "Landt op eiland & vangt op bij despawn", 232, autoBeachGym, function(val)
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

createToggleRow("20 FPS Power Saver Lock", "Beperkt framerate tot 20 FPS (AFK)", 282, fpsCapEnabled, function(val)
    fpsCapEnabled = val
    if setfpscap then
        pcall(setfpscap, val and 20 or 60)
    end
end)

createToggleRow("Bulletproof Anti-AFK + Reconnect", "4-laags beveiliging & auto-herstel", 332, antiAfkEnabled, function(val)
    antiAfkEnabled = val
    autoReconnectEnabled = val
    if val then triggerAfkPulse() end
end)

local VoidBtn = Instance.new("TextButton")
VoidBtn.Size = UDim2.new(1, -28, 0, 38)
VoidBtn.Position = UDim2.new(0, 14, 0, 386)
VoidBtn.BackgroundColor3 = Color3.fromRGB(14, 135, 82)
VoidBtn.Font = Enum.Font.GothamBold
VoidBtn.Text = "Sloop 3D Wereld + Alle Effecten"
VoidBtn.TextColor3 = Color3.fromRGB(245, 255, 250)
VoidBtn.TextSize = 12
VoidBtn.Parent = MainFrame

local VoidCorner = Instance.new("UICorner")
VoidCorner.CornerRadius = UDim.new(0, 9)
VoidCorner.Parent = VoidBtn

local VoidStroke = Instance.new("UIStroke")
VoidStroke.Color = NeonGreen
VoidStroke.Thickness = 1.2
VoidStroke.Transparency = 0.25
VoidStroke.Parent = VoidBtn

VoidBtn.MouseButton1Click:Connect(function()
    enableVoidMode()
    VoidBtn.Text = "ULTRA-VOID ACTIEF (0% Render)"
    VoidBtn.BackgroundColor3 = Color3.fromRGB(18, 170, 102)
end)

local Footer = Instance.new("Frame")
Footer.Size = UDim2.new(1, 0, 0, 18)
Footer.Position = UDim2.new(0, 0, 1, -18)
Footer.BackgroundColor3 = Color3.fromRGB(9, 18, 15)
Footer.BorderSizePixel = 0
Footer.Parent = MainFrame

local FooterLine = Instance.new("Frame")
FooterLine.Size = UDim2.new(1, 0, 0, 1)
FooterLine.Position = UDim2.new(0, 0, 0, 0)
FooterLine.BackgroundColor3 = NeonGreen
FooterLine.BackgroundTransparency = 0.65
FooterLine.BorderSizePixel = 0
FooterLine.Parent = Footer

FooterStatsLabel = Instance.new("TextLabel")
FooterStatsLabel.Size = UDim2.new(1, -20, 1, 0)
FooterStatsLabel.Position = UDim2.new(0, 10, 0, 0)
FooterStatsLabel.BackgroundTransparency = 1
FooterStatsLabel.Font = Enum.Font.Code
FooterStatsLabel.Text = "TOT: 0  |  GYM: 0  |  0ms  |  AFK: 0  |  20 FPS"
FooterStatsLabel.TextColor3 = EmeraldGlow
FooterStatsLabel.TextSize = 10
FooterStatsLabel.Parent = Footer

MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    local targetMain = isMinimized and UDim2.new(0, guiWidth, 0, 54) or UDim2.new(0, guiWidth, 0, fullHeight)
    local targetAura = isMinimized and UDim2.new(0, guiWidth + 6, 0, 60) or UDim2.new(0, guiWidth + 6, 0, fullHeight + 6)
    MinBtn.Text = isMinimized and "+" or "-"
    TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = targetMain}):Play()
    TweenService:Create(GlowAura, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = targetAura}):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    autoBonus = false
    autoBeachGym = false
    antiAfkEnabled = false
    autoReconnectEnabled = false
    if setfpscap then pcall(setfpscap, 60) end
    if afkConnection then afkConnection:Disconnect() end
    if errorConnection then errorConnection:Disconnect() end
    if bonusConn then bonusConn:Disconnect() end
    if popCleanerConn then popCleanerConn:Disconnect() end
    if playerCleanerConn then playerCleanerConn:Disconnect() end
    if debrisCleanerConn then debrisCleanerConn:Disconnect() end
    if respawnConn then respawnConn:Disconnect() end
    if worldEffectConn then worldEffectConn:Disconnect() end
    if charEffectConn then charEffectConn:Disconnect() end
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
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        GlowAura.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local function clickScreenAtButton(btn)
    pcall(function()
        if not btn or not btn.Parent then return end
        local pos = btn.AbsolutePosition
        local size = btn.AbsoluteSize
        local inset = GuiService:GetGuiInset()
        local cx = pos.X + (size.X * 0.5)
        local cy = pos.Y + (size.Y * 0.5) + inset.Y

        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
end

local function activateBonusButton(btn)
    if not autoBonus or not ScreenGui.Parent then return end
    if not btn or btn.Name ~= "Bonus" or not btn:IsA("GuiButton") then return end
    if not btn.Visible then return end

    lastBonusSpawnTick = tick()

    local lbl = btn:FindFirstChildOfClass("TextLabel")
    if lbl and lbl.Text ~= "" then
        lastSeenMultiplier = string.lower(lbl.Text)
    else
        local cConn
        cConn = btn.ChildAdded:Connect(function(c)
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

    if btn and btn.Parent and btn.Visible then
        clickScreenAtButton(btn)
    end

    if bonusRemote then
        pcall(function()
            bonusRemote:FireServer()
        end)
    end
end

local function onPopBonusConfirmed()
    local now = tick()
    if string.find(lastSeenMultiplier, "10") then
        count10x = count10x + 1
    elseif string.find(lastSeenMultiplier, "5") then
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

local function watchKickUpgradesChild(child)
    if child.Name == "PopBonus" then
        onPopBonusConfirmed()
    elseif child.Name == "Bonus" and child:IsA("GuiButton") then
        if child.Visible then
            task.spawn(activateBonusButton, child)
        end
        child:GetPropertyChangedSignal("Visible"):Connect(function()
            if child.Visible then
                task.spawn(activateBonusButton, child)
            end
        end)
    end
end

task.spawn(function()
    local kickUpgrades = pGui:WaitForChild("KickUpgrades", 15)
    if kickUpgrades then
        for _, child in ipairs(kickUpgrades:GetChildren()) do
            watchKickUpgradesChild(child)
        end

        bonusConn = kickUpgrades.ChildAdded:Connect(function(child)
            watchKickUpgradesChild(child)
        end)
    end
end)

triggerAfkPulse()
