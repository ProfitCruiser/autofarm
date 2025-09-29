--====================================================--
-- Kriluni Auto-Farm (Executor Edition)
--  * Preserves Aurora key system
--  * Single panel focused on Kriluni farming
--  * Moves to nearest target and applies DPS via remotes
--====================================================--

local RunService            = game:GetService("RunService")
local Players               = game:GetService("Players")
local GuiService            = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

pcall(function()
    GuiService.AutoSelectGuiEnabled = false
    GuiService.SelectedObject = nil
end)

--// Key system endpoints
local KEY_CHECK_URL = "https://pastebin.com/raw/QgqAaumb"
local GET_KEY_URL   = "https://pastebin.com/raw/QgqAaumb"
local DISCORD_URL   = "https://discord.gg/Pgn4NMWDH8"

--// Theme helpers
local Theme = {
    BG      = Color3.fromRGB(10, 9, 18),
    Panel   = Color3.fromRGB(18, 16, 31),
    Card    = Color3.fromRGB(24, 21, 40),
    Ink     = Color3.fromRGB(34, 30, 52),
    Stroke  = Color3.fromRGB(82, 74, 120),
    Neon    = Color3.fromRGB(160, 105, 255),
    Accent  = Color3.fromRGB(116, 92, 220),
    Text    = Color3.fromRGB(240, 240, 252),
    Subtle  = Color3.fromRGB(188, 182, 210),
    Good    = Color3.fromRGB(80, 210, 140),
    Warn    = Color3.fromRGB(255, 183, 77),
    Off     = Color3.fromRGB(100, 94, 130),
}

local function safeParent()
    local ok, ui = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    return (ok and ui) or LocalPlayer:WaitForChild("PlayerGui")
end

local function trim(s)
    s = tostring(s or "")
    s = s:gsub("\r", ""):gsub("\n", "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = o
end

local function stroke(o, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col
    s.Thickness = th or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = o
end

local function padding(o, px)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, px)
    p.PaddingBottom = UDim.new(0, px)
    p.PaddingLeft = UDim.new(0, px)
    p.PaddingRight = UDim.new(0, px)
    p.Parent = o
end

--====================================================--
-- Farming config/state
--====================================================--

local FARM_CONFIG = {
    AttackRange = 10,
    ScanInterval = 0.4,
    AttackCooldown = 0.25,
    DamagePerHit = 65,
    MaxAcquireDistance = 650,
    TargetKeywords = { "kriluni" },
    TargetNPCIds = { Kriluni = true },
    Combat = {
        RemotePaths = {
            { "ReplicatedStorage", "Events", "Damage_Event" },
            { "ReplicatedStorage", "Events", "Player_Damage" },
            { "ReplicatedStorage", "Events", "To_Server" },
            { "ReplicatedStorage", "Events", "API" },
        },
        PayloadStyles = { "TargetOnly", "TargetDamage", "VerbTargetDamage", "VerbTable", "Table" },
    },
}

local FarmState = {
    Enabled = false,
    Status = "Idle",
    CurrentTarget = nil,
    TargetDistance = nil,
    LastScan = 0,
    LastAttack = 0,
}

local Navigator = {
    lastMove = 0,
    lastRootPos = nil,
    stuckTimer = 0,
}

local CombatState = {
    Remote = nil,
    LastStyle = nil,
    LastSearch = -math.huge,
}

local FarmUI = {
    root = nil,
    statusLabel = nil,
    targetLabel = nil,
    toggleButton = nil,
}

--====================================================--
-- Utility helpers
--====================================================--

local function getLocalHumanoid()
    local character = LocalPlayer.Character
    if not character then
        return nil, nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not hrp then
        return nil, nil
    end
    return humanoid, hrp
end

local function resolveInstancePath(path)
    if typeof(path) ~= "table" or #path == 0 then
        return nil
    end

    local node = path[1]
    if typeof(node) == "string" then
        if node:lower() == "workspace" then
            node = workspace
        else
            local ok, svc = pcall(function()
                return game:GetService(node)
            end)
            node = ok and svc or nil
        end
    end

    if typeof(node) ~= "Instance" then
        return nil
    end

    local current = node
    for i = 2, #path do
        if not current then
            return nil
        end
        current = current:FindFirstChild(path[i])
    end
    return current
end

local function tryResolveRemote()
    if CombatState.Remote and CombatState.Remote.Parent then
        return CombatState.Remote
    end
    CombatState.Remote = nil
    for _, path in ipairs(FARM_CONFIG.Combat.RemotePaths) do
        local inst = resolveInstancePath(path)
        if inst and inst:IsA("RemoteEvent") then
            CombatState.Remote = inst
            return inst
        end
    end
    return nil
end

local function tryFireRemote(remote, style, targetModel, damage)
    if not remote then
        return false
    end

    local ok = false
    if style == "TargetOnly" then
        ok = pcall(function()
            remote:FireServer(targetModel)
        end)
    elseif style == "TargetDamage" then
        ok = pcall(function()
            remote:FireServer(targetModel, damage)
        end)
    elseif style == "VerbTargetDamage" then
        ok = pcall(function()
            remote:FireServer("Damage", targetModel, damage)
        end)
    elseif style == "VerbTable" then
        ok = pcall(function()
            remote:FireServer("Damage", { target = targetModel, damage = damage })
        end)
    elseif style == "Table" then
        ok = pcall(function()
            remote:FireServer({ target = targetModel, damage = damage })
        end)
    end

    return ok
end

local function dealDamage(targetModel, damage)
    damage = math.max(0, tonumber(damage) or 0)
    if damage <= 0 then
        return false
    end

    local remote = tryResolveRemote()
    local attempted = {}

    if CombatState.LastStyle then
        attempted[#attempted + 1] = CombatState.LastStyle
    end
    for _, style in ipairs(FARM_CONFIG.Combat.PayloadStyles) do
        if style ~= CombatState.LastStyle then
            attempted[#attempted + 1] = style
        end
    end

    for _, style in ipairs(attempted) do
        if tryFireRemote(remote, style, targetModel, damage) then
            CombatState.LastStyle = style
            return true
        end
    end

    local hum = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        hum:TakeDamage(damage)
        return true
    end
    return false
end

local function isAlive(model)
    if not model or not model:IsA("Model") then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function isKriluni(model)
    if not model or not model:IsA("Model") then
        return false
    end
    local lowerName = string.lower(model.Name)
    for _, key in ipairs(FARM_CONFIG.TargetKeywords) do
        if string.find(lowerName, key) then
            return true
        end
    end
    local ok, attr = pcall(function()
        return model:GetAttribute("NPCId")
    end)
    if ok and attr and FARM_CONFIG.TargetNPCIds[attr] then
        return true
    end
    return false
end

local function getTargetPosition(model)
    if not model then
        return nil
    end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp.Position
    end
    local primary = model.PrimaryPart
    if primary then
        return primary.Position
    end
    return nil
end

local function findNearestTarget(fromPosition)
    local bestModel, bestDistance
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("Model") and isAlive(inst) and isKriluni(inst) then
            local pos = getTargetPosition(inst)
            if pos then
                local dist = (pos - fromPosition).Magnitude
                if dist <= FARM_CONFIG.MaxAcquireDistance then
                    if not bestModel or dist < bestDistance then
                        bestModel = inst
                        bestDistance = dist
                    end
                end
            end
        end
    end
    return bestModel, bestDistance
end

local function updateStatus(text, color)
    if FarmUI.statusLabel then
        FarmUI.statusLabel.Text = text
        FarmUI.statusLabel.TextColor3 = color or Theme.Subtle
    end
    FarmState.Status = text
end

local function updateTargetLabel(name, distance)
    if not FarmUI.targetLabel then
        return
    end
    if not name then
        FarmUI.targetLabel.Text = "Target: none"
    else
        FarmUI.targetLabel.Text = string.format("Target: %s (%.1f studs)", name, distance or 0)
    end
end

local function updateToggleVisual()
    if not FarmUI.toggleButton then
        return
    end
    if FarmState.Enabled then
        FarmUI.toggleButton.Text = "Stop"
        FarmUI.toggleButton.BackgroundColor3 = Theme.Good
    else
        FarmUI.toggleButton.Text = "Start"
        FarmUI.toggleButton.BackgroundColor3 = Theme.Neon
    end
end

--====================================================--
-- Navigation + farm loop
--====================================================--

local function resetNavigator()
    Navigator.lastMove = 0
    Navigator.lastRootPos = nil
    Navigator.stuckTimer = 0
end

local function ensureMoving(humanoid, root, targetPos, dt)
    local now = tick()
    if (now - Navigator.lastMove) >= 0.4 then
        humanoid:MoveTo(targetPos)
        Navigator.lastMove = now
        Navigator.lastRootPos = root.Position
    else
        if Navigator.lastRootPos then
            local traveled = (root.Position - Navigator.lastRootPos).Magnitude
            if traveled < 1 then
                Navigator.stuckTimer = Navigator.stuckTimer + dt
                if Navigator.stuckTimer > 1.5 then
                    humanoid.Jump = true
                    humanoid:MoveTo(targetPos)
                    Navigator.lastMove = now
                    Navigator.lastRootPos = root.Position
                    Navigator.stuckTimer = 0
                end
            else
                Navigator.stuckTimer = 0
                Navigator.lastRootPos = root.Position
            end
        end
    end
end

local function stopMovement(humanoid)
    if humanoid and humanoid.MoveToFinished then
        humanoid:Move(Vector3.new())
    end
end

RunService.Heartbeat:Connect(function(dt)
    if not FarmState.Enabled then
        return
    end

    local humanoid, root = getLocalHumanoid()
    if not humanoid or not root then
        updateStatus("Waiting for character…", Theme.Warn)
        FarmState.CurrentTarget = nil
        updateTargetLabel(nil)
        return
    end

    local now = tick()

    if FarmState.CurrentTarget and (not isAlive(FarmState.CurrentTarget)) then
        FarmState.CurrentTarget = nil
        FarmState.LastScan = 0
    end

    if (not FarmState.CurrentTarget) and ((now - FarmState.LastScan) >= FARM_CONFIG.ScanInterval) then
        FarmState.LastScan = now
        local target, dist = findNearestTarget(root.Position)
        FarmState.CurrentTarget = target
        FarmState.TargetDistance = dist
        if target then
            updateStatus("Moving to target…", Theme.Text)
            updateTargetLabel(target.Name, dist or 0)
            resetNavigator()
        else
            updateStatus("Scanning for Kriluni…", Theme.Subtle)
            updateTargetLabel(nil)
        end
    end

    local target = FarmState.CurrentTarget
    if not target then
        return
    end

    local targetPos = getTargetPosition(target)
    if not targetPos then
        FarmState.CurrentTarget = nil
        updateTargetLabel(nil)
        FarmState.LastScan = 0
        return
    end

    local distance = (targetPos - root.Position).Magnitude
    if distance > FARM_CONFIG.MaxAcquireDistance then
        FarmState.CurrentTarget = nil
        updateTargetLabel(nil)
        updateStatus("Target too far — scanning…", Theme.Warn)
        FarmState.LastScan = 0
        return
    end

    FarmState.TargetDistance = distance
    updateTargetLabel(target.Name, distance)

    if distance > FARM_CONFIG.AttackRange then
        ensureMoving(humanoid, root, targetPos, dt)
        updateStatus("Closing in on " .. target.Name .. "…", Theme.Subtle)
        return
    end

    stopMovement(humanoid)
    updateStatus("Attacking " .. target.Name .. "…", Theme.Good)

    if (now - FarmState.LastAttack) >= FARM_CONFIG.AttackCooldown then
        FarmState.LastAttack = now
        dealDamage(target, FARM_CONFIG.DamagePerHit)
    end
end)

--====================================================--
-- UI construction
--====================================================--

local function buildFarmUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "AuroraFarm"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.DisplayOrder = 100
    gui.Enabled = false
    gui.Parent = safeParent()

    FarmUI.root = gui

    local container = Instance.new("Frame", gui)
    container.Size = UDim2.fromOffset(360, 220)
    container.AnchorPoint = Vector2.new(0, 0)
    container.Position = UDim2.new(0, 24, 0, 24)
    container.BackgroundColor3 = Theme.Card
    container.BackgroundTransparency = 0.05
    corner(container, 14)
    stroke(container, Theme.Stroke, 1.5)

    padding(container, 16)

    local layout = Instance.new("UIListLayout", container)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)

    local title = Instance.new("TextLabel", container)
    title.Text = "Kriluni Farm"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 22
    title.TextColor3 = Theme.Text
    title.BackgroundTransparency = 1
    title.LayoutOrder = 1
    title.Size = UDim2.new(1, 0, 0, 32)

    local status = Instance.new("TextLabel", container)
    status.Text = "Status: Locked"
    status.Font = Enum.Font.Gotham
    status.TextSize = 16
    status.TextColor3 = Theme.Subtle
    status.BackgroundColor3 = Theme.Ink
    status.BackgroundTransparency = 0.3
    status.Size = UDim2.new(1, 0, 0, 40)
    status.LayoutOrder = 2
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Center
    padding(status, 12)
    corner(status, 10)

    local target = Instance.new("TextLabel", container)
    target.Text = "Target: none"
    target.Font = Enum.Font.Gotham
    target.TextSize = 16
    target.TextColor3 = Theme.Subtle
    target.BackgroundColor3 = Theme.Ink
    target.BackgroundTransparency = 0.3
    target.Size = UDim2.new(1, 0, 0, 40)
    target.LayoutOrder = 3
    target.TextXAlignment = Enum.TextXAlignment.Left
    target.TextYAlignment = Enum.TextYAlignment.Center
    padding(target, 12)
    corner(target, 10)

    local toggle = Instance.new("TextButton", container)
    toggle.Text = "Start"
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.TextColor3 = Theme.Text
    toggle.BackgroundColor3 = Theme.Neon
    toggle.AutoButtonColor = false
    toggle.Size = UDim2.new(1, 0, 0, 44)
    toggle.LayoutOrder = 4
    corner(toggle, 12)

    toggle.MouseButton1Click:Connect(function()
        FarmState.Enabled = not FarmState.Enabled
        FarmState.CurrentTarget = nil
        FarmState.LastScan = 0
        FarmState.LastAttack = 0
        if FarmState.Enabled then
            updateStatus("Scanning for Kriluni…", Theme.Subtle)
        else
            updateStatus("Idle", Theme.Subtle)
            updateTargetLabel(nil)
            resetNavigator()
        end
        updateToggleVisual()
    end)

    FarmUI.statusLabel = status
    FarmUI.targetLabel = target
    FarmUI.toggleButton = toggle

    updateToggleVisual()
    updateStatus("Idle", Theme.Subtle)

    return gui
end

--====================================================--
-- Key gate
--====================================================--

local function buildKeyGate(onUnlocked)
    local gui = Instance.new("ScreenGui")
    gui.Name = "AuroraGate"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.DisplayOrder = 90
    gui.Parent = safeParent()

    local blur = Instance.new("BlurEffect")
    blur.Size = 12
    blur.Enabled = true
    blur.Parent = workspace.CurrentCamera

    local root = Instance.new("Frame", gui)
    root.Size = UDim2.fromOffset(420, 260)
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)
    root.BackgroundColor3 = Theme.Card
    corner(root, 16)
    stroke(root, Theme.Stroke, 1.5)
    padding(root, 18)

    local layout = Instance.new("UIListLayout", root)
    layout.Padding = UDim.new(0, 10)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local title = Instance.new("TextLabel", root)
    title.Text = "Aurora Access"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 24
    title.TextColor3 = Theme.Text
    title.BackgroundTransparency = 1
    title.LayoutOrder = 1

    local hint = Instance.new("TextLabel", root)
    hint.Text = "Paste your key to unlock the farm panel."
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 16
    hint.TextColor3 = Theme.Subtle
    hint.BackgroundTransparency = 1
    hint.LayoutOrder = 2

    local keyBox = Instance.new("TextBox", root)
    keyBox.ClearTextOnFocus = false
    keyBox.Text = ""
    keyBox.PlaceholderText = "Paste key here"
    keyBox.Font = Enum.Font.Gotham
    keyBox.TextSize = 16
    keyBox.TextColor3 = Theme.Text
    keyBox.BackgroundColor3 = Theme.Ink
    keyBox.BackgroundTransparency = 0.3
    keyBox.Size = UDim2.new(1, 0, 0, 44)
    keyBox.LayoutOrder = 3
    padding(keyBox, 12)
    corner(keyBox, 10)

    local buttonRow = Instance.new("Frame", root)
    buttonRow.BackgroundTransparency = 1
    buttonRow.Size = UDim2.new(1, 0, 0, 44)
    buttonRow.LayoutOrder = 4

    local hList = Instance.new("UIListLayout", buttonRow)
    hList.FillDirection = Enum.FillDirection.Horizontal
    hList.SortOrder = Enum.SortOrder.LayoutOrder
    hList.Padding = UDim.new(0, 10)

    local function makeButton(text, order)
        local btn = Instance.new("TextButton")
        btn.Text = text
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 16
        btn.TextColor3 = Theme.Text
        btn.BackgroundColor3 = Theme.Neon
        btn.AutoButtonColor = false
        btn.Size = UDim2.new(0.5, -5, 1, 0)
        btn.LayoutOrder = order
        corner(btn, 10)
        btn.Parent = buttonRow
        return btn
    end

    local getKeyBtn = makeButton("Get Key", 1)
    local confirmBtn = makeButton("Unlock", 2)

    local discordBtn = Instance.new("TextButton", root)
    discordBtn.Text = "Copy Discord Invite"
    discordBtn.Font = Enum.Font.Gotham
    discordBtn.TextSize = 16
    discordBtn.TextColor3 = Theme.Text
    discordBtn.BackgroundColor3 = Theme.Ink
    discordBtn.BackgroundTransparency = 0.2
    discordBtn.AutoButtonColor = false
    discordBtn.Size = UDim2.new(1, 0, 0, 40)
    discordBtn.LayoutOrder = 5
    corner(discordBtn, 10)

    local status = Instance.new("TextLabel", root)
    status.Text = "Status: Waiting for key"
    status.Font = Enum.Font.Gotham
    status.TextSize = 16
    status.TextColor3 = Theme.Subtle
    status.BackgroundColor3 = Theme.Ink
    status.BackgroundTransparency = 0.2
    status.Size = UDim2.new(1, 0, 0, 40)
    status.LayoutOrder = 6
    padding(status, 10)
    corner(status, 10)

    local function setStatus(text, color)
        status.Text = text
        status.TextColor3 = color or Theme.Subtle
    end

    local function fetchRemoteKey()
        local ok, res = pcall(function()
            return game:HttpGet(KEY_CHECK_URL)
        end)
        if not ok then
            return nil, res
        end
        local cleaned = trim(res)
        if cleaned == "" then
            return nil, "empty response"
        end
        return cleaned
    end

    getKeyBtn.MouseButton1Click:Connect(function()
        if typeof(setclipboard) == "function" then
            setclipboard(GET_KEY_URL)
            setStatus("Key URL copied to clipboard.", Theme.Neon)
        else
            setStatus("Key URL: " .. GET_KEY_URL, Theme.Neon)
        end
    end)

    discordBtn.MouseButton1Click:Connect(function()
        if typeof(setclipboard) == "function" then
            setclipboard(DISCORD_URL)
        end
        setStatus("Discord invite copied.", Theme.Neon)
        if syn and syn.request then
            pcall(function()
                syn.request({ Url = DISCORD_URL, Method = "GET" })
            end)
        end
    end)

    confirmBtn.MouseButton1Click:Connect(function()
        setStatus("Checking key…", Theme.Text)
        local expected, err = fetchRemoteKey()
        if not expected then
            setStatus("Failed to fetch key: " .. tostring(err), Theme.Warn)
            return
        end
        if trim(keyBox.Text) ~= expected then
            setStatus("Invalid key.", Theme.Warn)
            return
        end

        setStatus("Access granted!", Theme.Good)
        blur.Enabled = false
        blur:Destroy()
        gui.Enabled = false
        task.delay(0.2, function()
            gui:Destroy()
        end)
        if onUnlocked then
            onUnlocked()
        end
    end)

    return gui
end

--====================================================--
-- Bootstrap
--====================================================--

local function bootstrap()
    local farmGui = buildFarmUI()
    buildKeyGate(function()
        farmGui.Enabled = true
        updateStatus("Idle", Theme.Subtle)
        updateTargetLabel(nil)
        updateToggleVisual()
    end)
end

bootstrap()
