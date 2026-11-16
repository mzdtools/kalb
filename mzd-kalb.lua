-- =====================================================================
-- MzD KALB script - Ultra-Void v2.2 (Center Island Landing + Catch)
-- =====================================================================

if setfpscap then pcall(setfpscap, 20) end

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

local bonusRemote = nil
task.spawn(function()
    local shared = ReplicatedStorage:WaitForChild("Shared", 15)
    local packages = shared and shared:WaitForChild("Packages", 15)
    local network = packages and packages:WaitForChild("Network", 15)
    bonusRemote = network and network:WaitForChild("rev_TaviMishkal", 15)
end)

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

local count2x, count5x, count10x, totalBonusCount = 0, 0, 0, 0
local gymTpCount, lastReactionMs, afkPulses = 0, 0, 0
local isMinimized = false
local lastSeenMultiplier = "x2"
local lastBonusSpawnTick = 0
local activeBeachGym = nil

local afkConnection, errorConnection, bonusConn, popCleanerConn = nil, nil, nil, nil
local playerCleanerConn, debrisCleanerConn, respawnConn, worldEffectConn, charEffectConn = nil, nil, nil, nil, nil
local gymWatchConns = {}
local Val2xLabel, Val5xLabel, Val10xLabel, FooterStatsLabel = nil, nil, nil, nil

local function updateDashboard()
    if Val2xLabel then Val2xLabel.Text = tostring(count2x) end
    if Val5xLabel then Val5xLabel.Text = tostring(count5x) end
    if Val10xLabel then Val10xLabel.Text = tostring(count10x) end
    if FooterStatsLabel then
        FooterStatsLabel.Text = string.format("TOT: %d  |  GYM: %d  |  %dms  |  AFK: %d  |  20 FPS", totalBonusCount, gymTpCount, lastReactionMs, afkPulses)
    end
end

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
afkConnection = player.Idled:Connect(triggerAfkPulse)

task.spawn(function()
    local cycle = 0
    while true do
        task.wait(180)
        if not CoreGui:FindFirstChild(uiName) and not (gethui and gethui():FindFirstChild(uiName)) then break end
        if fpsCapEnabled and setfpscap then pcall(setfpscap, 20) end
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
errorConnection = GuiService.ErrorMessageChanged:Connect(function(msg)
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
end)

-- =====================================================================
-- PLATFORM BEHEER & MIDDEN-EILAND LANDING + DESPAWN CATCH
-- =====================================================================
local function removeSafePlatform()
    local existingPad = Workspace:FindFirstChild("MzD_SafePlatform")
    if existingPad then existingPad:Destroy() end
end

local function spawnPlatformAtPosition(pos)
    removeSafePlatform()
    local safePad = Instance.new("Part")
    safePad.Name = "MzD_SafePlatform"
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
    local footOffset = hipHeight + (hrp.Size.Y * 0.5)
    spawnPlatformAtPosition(hrp.Position - Vector3.new(0, footOffset + 1, 0))
end

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

    -- Raycast exact naar het midden van de eilandvloer
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

    -- Zet je karakter strak op het midden van het eiland en druk direct op de vloer
    local hipHeight = hum and hum.HipHeight or 2
    local targetPos = surfacePos + Vector3.new(0, hipHeight + (hrp.Size.Y * 0.5) + 0.05, 0)
    hrp.CFrame = CFrame.new(targetPos)
    hrp.AssemblyLinearVelocity = Vector3.new(0, -12, 0)

    pulseTouchOnGym(char, gymObj)

    -- Korte micro-landing zodat native physics direct registreert dat je op het eiland staat
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
            local cChar = player.Character
            local cHrp = cChar and cChar:FindFirstChild("HumanoidRootPart")
            if cHrp then cHrp.AssemblyLinearVelocity = Vector3.zero end
            spawnPlatformUnderPlayer(cChar)
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

-- =====================================================================
-- ULTRA-VOID 3D & CHARACTER EFFECT DESTROYER
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
    for _, desc in ipairs(char:GetDescendants()) do stripVisualInstance(desc) end
    if charEffectConn then charEffectConn:Disconnect() end
    charEffectConn = char.DescendantAdded:Connect(function(desc)
        if worldWiped then stripVisualInstance(desc) end
    end)
end

local function enableVoidMode()
    if not activeBeachGym then spawnPlatformUnderPlayer(player.Character) end
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
        ["Areas"] = true, ["Zones"] = true, ["Machine"] = true, ["KickUpgrades"] = true,
        ["Players"] = true, ["Camera"] = true, ["Terrain"] = true, ["Debris"] = true,
        ["MzD_SafePlatform"] = true, [player.Name] = true
    }

    for _, obj in ipairs(Workspace:GetChildren()) do
        if not keepWorkspace[obj.Name] and obj ~= char then
            pcall(function() obj:Destroy() end)
        elseif keepWorkspace[obj.Name] and obj.Name ~= "Players" and obj.Name ~= "MzD_SafePlatform" and obj.Name ~= "Debris" and obj.Name ~= "Camera" and obj.Name ~= "Terrain" and obj ~= char then
            for _, p in ipairs(obj:GetDescendants()) do stripVisualInstance(p) end
        end
    end

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
            if dChild.Name ~= "GymMachine" then pcall(function() dChild:Destroy() end) end
        end
        debrisCleanerConn = debrisFolder.ChildAdded:Connect(function(c)
            if c.Name ~= "GymMachine" then
                task.wait()
                if c and c.Parent and c.Name ~= "GymMachine" then pcall(function() c:Destroy() end) end
            end
        end)
    end

    local playersFolder = Workspace:FindFirstChild("Players")
    if playersFolder then
        for _, pModel in ipairs(playersFolder:GetChildren()) do
            if pModel.Name ~= player.Name then pcall(function() pModel:Destroy() end) end
        end
        playerCleanerConn = playersFolder.ChildAdded:Connect(function(pModel)
            if worldWiped and pModel.Name ~= player.Name then
                task.wait()
                pcall(function() pModel:Destroy() end)
            end
        end)
    end

    pcall(function()
        Workspace.Terrain:Clear()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 0
        Lighting.Ambient = Color3.new(0, 0, 0)
        Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
        for _, eff in ipairs(Lighting:GetChildren()) do eff:Destroy() end
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)

    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)

    local kickUpgrades = pGui:FindFirstChild("KickUpgrades")
    local popFolder = kickUpgrades and kickUpgrades:FindFirstChild("Pop")
    if popFolder then
        popFolder:ClearAllChildren()
        popCleanerConn = popFolder.ChildAdded:Connect(function(c) c:Destroy() end)
    end
end

-- =====================================================================
-- FUTURISTISCHE CYBER-GROENE HUD & CUSTOM MzD LOGO
-- =====================================================================
local fullHeight, guiWidth = 452, 332
local NeonGreen    = Color3.fromRGB(0, 255, 145)
local EmeraldGlow  = Color3.fromRGB(16, 210, 120)
local DeepCyberBg  = Color3.fromRGB(7, 13, 11)
local PanelCyberBg = Color3.fromRGB(11, 20, 17)
local CardCyberBg  = Color3.fromRGB(13, 24, 20)
local TextPrimary  = Color3.fromRGB(238, 255, 247)
local TextMuted    = Color3.fromRGB(115, 175, 148)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = uiName
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = (gethui and gethui()) or CoreGui

local GlowAura = Instance.new("Frame")
GlowAura.Size = UDim2.new(0, guiWidth + 6, 0, fullHeight + 6)
GlowAura.Position = UDim2.new(0.5, -((guiWidth + 6) / 2), 0.21, 0)
GlowAura.BackgroundColor3 = NeonGreen
GlowAura.BackgroundTransparency = 0.88
GlowAura.BorderSizePixel = 0
GlowAura.Parent = ScreenGui
Instance.new("UICorner", GlowAura).CornerRadius = UDim.new(0, 16)

local AuraStroke = Instance.new("UIStroke", GlowAura)
AuraStroke.Color = NeonGreen
AuraStroke.Thickness = 2
AuraStroke.Transparency = 0.65

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, guiWidth, 0, fullHeight)
MainFrame.Position = UDim2.new(0, 3, 0, 3)
MainFrame.BackgroundColor3 = DeepCyberBg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = GlowAura
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 14)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = NeonGreen
MainStroke.Thickness = 1.6
MainStroke.Transparency = 0.15

local UIGradient = Instance.new("UIGradient", MainFrame)
UIGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 28, 22)),
    ColorSequenceKeypoint.new(0.45, Color3.fromRGB(8, 15, 13)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 10, 9))
})
UIGradient.Rotation = 55

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 54)
TopBar.BackgroundColor3 = PanelCyberBg
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopDivider = Instance.new("Frame", TopBar)
TopDivider.Size = UDim2.new(1, 0, 0, 1)
TopDivider.Position = UDim2.new(0, 0, 1, -1)
TopDivider.BackgroundColor3 = NeonGreen
TopDivider.BackgroundTransparency = 0.45
TopDivider.BorderSizePixel = 0

local LogoHolder = Instance.new("Frame", TopBar)
LogoHolder.Size = UDim2.new(0, 38, 0, 38)
LogoHolder.Position = UDim2.new(0, 12, 0.5, -19)
LogoHolder.BackgroundColor3 = Color3.fromRGB(10, 26, 20)
LogoHolder.BorderSizePixel = 0
Instance.new("UICorner", LogoHolder).CornerRadius = UDim.new(0, 9)

local LogoStroke = Instance.new("UIStroke", LogoHolder)
LogoStroke.Color = NeonGreen
LogoStroke.Thickness = 1.6

local LogoTextM = Instance.new("TextLabel", LogoHolder)
LogoTextM.Size = UDim2.new(1, 0, 0, 22)
LogoTextM.Position = UDim2.new(0, 0, 0, 4)
LogoTextM.BackgroundTransparency = 1
LogoTextM.Font = Enum.Font.GothamBlack
LogoTextM.Text = "MzD"
LogoTextM.TextColor3 = Color3.fromRGB(245, 255, 250)
LogoTextM.TextSize = 13

local LogoSubTag = Instance.new("TextLabel", LogoHolder)
LogoSubTag.Size = UDim2.new(1, 0, 0, 10)
LogoSubTag.Position = UDim2.new(0, 0, 0, 23)
LogoSubTag.BackgroundTransparency = 1
LogoSubTag.Font = Enum.Font.Code
LogoSubTag.Text = "CORE"
LogoSubTag.TextColor3 = NeonGreen
LogoSubTag.TextSize = 8

local TitleLabel = Instance.new("TextLabel", TopBar)
TitleLabel.Size = UDim2.new(1, -128, 0, 20)
TitleLabel.Position = UDim2.new(0, 58, 0, 9)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.Text = "MzD KALB // SYSTEM"
TitleLabel.TextColor3 = TextPrimary
TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left

local SubTitleLabel = Instance.new("TextLabel", TopBar)
SubTitleLabel.Size = UDim2.new(1, -128, 0, 14)
SubTitleLabel.Position = UDim2.new(0, 58, 0, 29)
SubTitleLabel.BackgroundTransparency = 1
SubTitleLabel.Font = Enum.Font.Code
SubTitleLabel.Text = "ULTRA-VOID • 20 FPS LOCK"
SubTitleLabel.TextColor3 = EmeraldGlow
SubTitleLabel.TextSize = 10
SubTitleLabel.TextXAlignment = Enum.TextXAlignment.Left

task.spawn(function()
    while GlowAura and GlowAura.Parent do
        TweenService:Create(AuraStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine), {Transparency = 0.25}):Play()
        TweenService:Create(LogoStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine), {Transparency = 0.45}):Play()
        task.wait(1.4)
        if not GlowAura or not GlowAura.Parent then break end
        TweenService:Create(AuraStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine), {Transparency = 0.78}):Play()
        TweenService:Create(LogoStroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine), {Transparency = 0.05}):Play()
        task.wait(1.4)
    end
end)

local MinBtn = Instance.new("TextButton", TopBar)
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -68, 0.5, -14)
MinBtn.BackgroundColor3 = Color3.fromRGB(16, 34, 27)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Text = "-"
MinBtn.TextColor3 = NeonGreen
MinBtn.TextSize = 16
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 7)

local CloseBtn = Instance.new("TextButton", TopBar)
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -14)
CloseBtn.BackgroundColor3 = Color3.fromRGB(165, 35, 48)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.TextSize = 12
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 7)

local Section1Title = Instance.new("TextLabel", MainFrame)
Section1Title.Size = UDim2.new(1, -28, 0, 16)
Section1Title.Position = UDim2.new(0, 14, 0, 62)
Section1Title.BackgroundTransparency = 1
Section1Title.Font = Enum.Font.Code
Section1Title.Text = "> MULTIPLIER TELEMETRIE [VERIFIED]"
Section1Title.TextColor3 = TextMuted
Section1Title.TextSize = 10
Section1Title.TextXAlignment = Enum.TextXAlignment.Left

local CardsContainer = Instance.new("Frame", MainFrame)
CardsContainer.Size = UDim2.new(1, -28, 0, 70)
CardsContainer.Position = UDim2.new(0, 14, 0, 82)
CardsContainer.BackgroundTransparency = 1

local function createStatCard(xScale, badgeText, accentColor)
    local Card = Instance.new("Frame", CardsContainer)
    Card.Size = UDim2.new(0.315, 0, 1, 0)
    Card.Position = UDim2.new(xScale, 0, 0, 0)
    Card.BackgroundColor3 = CardCyberBg
    Card.BorderSizePixel = 0
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 10)

    local CStroke = Instance.new("UIStroke", Card)
    CStroke.Color = accentColor
    CStroke.Thickness = 1.3
    CStroke.Transparency = 0.35

    local TopAccent = Instance.new("Frame", Card)
    TopAccent.Size = UDim2.new(0.65, 0, 0, 2)
    TopAccent.Position = UDim2.new(0.175, 0, 0, 0)
    TopAccent.BackgroundColor3 = accentColor
    TopAccent.BorderSizePixel = 0

    local BadgeLabel = Instance.new("TextLabel", Card)
    BadgeLabel.Size = UDim2.new(1, 0, 0, 20)
    BadgeLabel.Position = UDim2.new(0, 0, 0, 8)
    BadgeLabel.BackgroundTransparency = 1
    BadgeLabel.Font = Enum.Font.GothamBold
    BadgeLabel.Text = badgeText
    BadgeLabel.TextColor3 = accentColor
    BadgeLabel.TextSize = 12

    local ValueLabel = Instance.new("TextLabel", Card)
    ValueLabel.Size = UDim2.new(1, -8, 0, 28)
    ValueLabel.Position = UDim2.new(0, 4, 0, 31)
    ValueLabel.BackgroundTransparency = 1
    ValueLabel.Font = Enum.Font.GothamBlack
    ValueLabel.Text = "0"
    ValueLabel.TextColor3 = TextPrimary
    ValueLabel.TextScaled = true

    local SizeLimit = Instance.new("UITextSizeConstraint", ValueLabel)
    SizeLimit.MaxTextSize = 21
    SizeLimit.MinTextSize = 11
    return ValueLabel
end

Val2xLabel = createStatCard(0, "2X BOOST", Color3.fromRGB(185, 95, 255))
Val5xLabel = createStatCard(0.3425, "5X BOOST", Color3.fromRGB(255, 145, 35))
Val10xLabel = createStatCard(0.685, "10X BOOST", NeonGreen)

local Section2Title = Instance.new("TextLabel", MainFrame)
Section2Title.Size = UDim2.new(1, -28, 0, 16)
Section2Title.Position = UDim2.new(0, 14, 0, 162)
Section2Title.BackgroundTransparency = 1
Section2Title.Font = Enum.Font.Code
Section2Title.Text = "> SYSTEEM MODULES"
Section2Title.TextColor3 = TextMuted
Section2Title.TextSize = 10
Section2Title.TextXAlignment = Enum.TextXAlignment.Left

local function createToggleRow(labelText, subText, yPos, defaultState, callback)
    local Row = Instance.new("Frame", MainFrame)
    Row.Size = UDim2.new(1, -28, 0, 44)
    Row.Position = UDim2.new(0, 14, 0, yPos)
    Row.BackgroundColor3 = CardCyberBg
    Row.BorderSizePixel = 0
    Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 9)

    local RowStroke = Instance.new("UIStroke", Row)
    RowStroke.Color = defaultState and Color3.fromRGB(22, 75, 54) or Color3.fromRGB(28, 45, 38)
    RowStroke.Thickness = 1

    local Indicator = Instance.new("Frame", Row)
    Indicator.Size = UDim2.new(0, 3, 0, 24)
    Indicator.Position = UDim2.new(0, 0, 0.5, -12)
    Indicator.BackgroundColor3 = defaultState and NeonGreen or Color3.fromRGB(45, 70, 60)
    Indicator.BorderSizePixel = 0

    local Label = Instance.new("TextLabel", Row)
    Label.Size = UDim2.new(1, -74, 0, 18)
    Label.Position = UDim2.new(0, 12, 0, 6)
    Label.BackgroundTransparency = 1
    Label.Font = Enum.Font.GothamSemibold
    Label.Text = labelText
    Label.TextColor3 = TextPrimary
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left

    local SubLabel = Instance.new("TextLabel", Row)
    SubLabel.Size = UDim2.new(1, -74, 0, 14)
    SubLabel.Position = UDim2.new(0, 12, 0, 24)
    SubLabel.BackgroundTransparency = 1
    SubLabel.Font = Enum.Font.Gotham
    SubLabel.Text = subText
    SubLabel.TextColor3 = TextMuted
    SubLabel.TextSize = 10
    SubLabel.TextXAlignment = Enum.TextXAlignment.Left

    local SwitchBg = Instance.new("TextButton", Row)
    SwitchBg.Size = UDim2.new(0, 44, 0, 22)
    SwitchBg.Position = UDim2.new(1, -54, 0.5, -11)
    SwitchBg.BackgroundColor3 = defaultState and EmeraldGlow or Color3.fromRGB(24, 42, 35)
    SwitchBg.AutoButtonColor = false
    SwitchBg.Text = ""
    Instance.new("UICorner", SwitchBg).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame", SwitchBg)
    Knob.Size = UDim2.new(0, 16, 0, 16)
    Knob.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    Knob.BackgroundColor3 = Color3.fromRGB(245, 255, 250)
    Knob.BorderSizePixel = 0
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local state = defaultState
    SwitchBg.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(Knob, TweenInfo.new(0.18), {Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)}):Play()
        TweenService:Create(SwitchBg, TweenInfo.new(0.18), {BackgroundColor3 = state and EmeraldGlow or Color3.fromRGB(24, 42, 35)}):Play()
        TweenService:Create(Indicator, TweenInfo.new(0.18), {BackgroundColor3 = state and NeonGreen or Color3.fromRGB(45, 70, 60)}):Play()
        callback(state)
    end)
end

createToggleRow("Smart Bonus Claimer", "Echte klik + remote + PopBonus check", 182, autoBonus, function(val) autoBonus = val end)
createToggleRow("Auto-TP Beach Island + Catch", "Landt midden op eiland & vangt op", 232, autoBeachGym, function(val)
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
    if setfpscap then pcall(setfpscap, val and 20 or 60) end
end)
createToggleRow("Bulletproof Anti-AFK + Reconnect", "4-laags beveiliging & auto-herstel", 332, antiAfkEnabled, function(val)
    antiAfkEnabled = val
    autoReconnectEnabled = val
    if val then triggerAfkPulse() end
end)

local VoidBtn = Instance.new("TextButton", MainFrame)
VoidBtn.Size = UDim2.new(1, -28, 0, 38)
VoidBtn.Position = UDim2.new(0, 14, 0, 386)
VoidBtn.BackgroundColor3 = Color3.fromRGB(14, 135, 82)
VoidBtn.Font = Enum.Font.GothamBold
VoidBtn.Text = "Sloop 3D Wereld + Alle Effecten"
VoidBtn.TextColor3 = Color3.fromRGB(245, 255, 250)
VoidBtn.TextSize = 12
Instance.new("UICorner", VoidBtn).CornerRadius = UDim.new(0, 9)

local VoidStroke = Instance.new("UIStroke", VoidBtn)
VoidStroke.Color = NeonGreen
VoidStroke.Thickness = 1.2
VoidStroke.Transparency = 0.25

VoidBtn.MouseButton1Click:Connect(function()
    enableVoidMode()
    VoidBtn.Text = "ULTRA-VOID ACTIEF (0% Render)"
    VoidBtn.BackgroundColor3 = Color3.fromRGB(18, 170, 102)
end)

local Footer = Instance.new("Frame", MainFrame)
Footer.Size = UDim2.new(1, 0, 0, 18)
Footer.Position = UDim2.new(0, 0, 1, -18)
Footer.BackgroundColor3 = Color3.fromRGB(9, 18, 15)
Footer.BorderSizePixel = 0

FooterStatsLabel = Instance.new("TextLabel", Footer)
FooterStatsLabel.Size = UDim2.new(1, -20, 1, 0)
FooterStatsLabel.Position = UDim2.new(0, 10, 0, 0)
FooterStatsLabel.BackgroundTransparency = 1
FooterStatsLabel.Font = Enum.Font.Code
FooterStatsLabel.Text = "TOT: 0  |  GYM: 0  |  0ms  |  AFK: 0  |  20 FPS"
FooterStatsLabel.TextColor3 = EmeraldGlow
FooterStatsLabel.TextSize = 10

MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    MinBtn.Text = isMinimized and "+" or "-"
    TweenService:Create(MainFrame, TweenInfo.new(0.2), {Size = isMinimized and UDim2.new(0, guiWidth, 0, 54) or UDim2.new(0, guiWidth, 0, fullHeight)}):Play()
    TweenService:Create(GlowAura, TweenInfo.new(0.2), {Size = isMinimized and UDim2.new(0, guiWidth + 6, 0, 60) or UDim2.new(0, guiWidth + 6, 0, fullHeight + 6)}):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    autoBonus, autoBeachGym, antiAfkEnabled, autoReconnectEnabled = false, false, false, false
    if setfpscap then pcall(setfpscap, 60) end
    for _, c in pairs({afkConnection, errorConnection, bonusConn, popCleanerConn, playerCleanerConn, debrisCleanerConn, respawnConn, worldEffectConn, charEffectConn}) do
        if c then pcall(function() c:Disconnect() end) end
    end
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
        bonusConn = kickUpgrades.ChildAdded:Connect(watchKickUpgradesChild)
    end
end)

triggerAfkPulse()
