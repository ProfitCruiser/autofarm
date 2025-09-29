--====================================================--
-- AURORA PANEL — ProfitCruiser (fixed key→panel flow)
-- Full redesign: Compact 2-col layout + sections + gating
-- Aimbot, ESP (Highlight), Crosshair, Profiles
--====================================================--

--// Services
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local GuiService        = game:GetService("GuiService")
local HttpService       = game:GetService("HttpService")
local TextService       = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- forward-declare Root so click handlers can access it before it's created
local Root

pcall(function()
    GuiService.AutoSelectGuiEnabled = false
    GuiService.SelectedObject = nil
end)

--// Gate / links
local KEY_CHECK_URL = "https://pastebin.com/raw/QgqAaumb"
local GET_KEY_URL   = "https://pastebin.com/raw/QgqAaumb"
local DISCORD_URL   = "https://discord.gg/Pgn4NMWDH8"

--// Theme
local T = {
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
    local ok, ui = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
    return (ok and ui) or LocalPlayer:WaitForChild("PlayerGui")
end

--// Utils
local function corner(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=o end
local function stroke(o,col,th,tr) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=th or 1; s.Transparency=tr or 0; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=o end
local function pad(o,p) local x=Instance.new("UIPadding"); x.PaddingTop=UDim.new(0,p); x.PaddingBottom=UDim.new(0,p); x.PaddingLeft=UDim.new(0,p); x.PaddingRight=UDim.new(0,p); x.Parent=o end
local function trim(s) s=tostring(s or ""):gsub("\r",""):gsub("\n",""):gsub("%s+$",""):gsub("^%s+",""); return s end
local function setInteractable(frame, on)
    for _,v in ipairs(frame:GetDescendants()) do
        if v:IsA("TextLabel") or v:IsA("TextButton") then
            v.TextTransparency = on and 0 or 0.45
            if v:IsA("TextButton") then v.AutoButtonColor = on end
        elseif v:IsA("Frame") then
            v.BackgroundColor3 = on and v.BackgroundColor3 or T.Ink
        end
    end
    frame.Active = on
end

--==================== KRILUNI FARM CLIENT STATE ====================--
local AutoFarmRequestRemote = nil
local AutoFarmUpdateRemote = nil
local farmRemotesReady = false
local autoFarmUpdateConn = nil
local remotesFolderRef = nil
local remotesAddedConn = nil
local remotesRemovedConn = nil

local FarmState = {
    Enabled = false,
    TargetName = nil,
    TargetPosition = nil,
    PendingSince = nil,
}

local FarmUI = {
    statusValue = nil,
    targetValue = nil,
    toggleRow = nil,
    toggleButton = nil,
}

local lastTargetText = nil

local function refreshFarmStatus()
    if not FarmUI.statusValue then return end

    local text
    local color
    if not farmRemotesReady then
        text = "Waiting for Kriluni remotes…"
        color = T.Warn
        FarmState.PendingSince = nil
    else
        local pending = FarmState.PendingSince and (os.clock() - FarmState.PendingSince) < 5
        if pending then
            text = "Waiting for server…"
            color = T.Warn
        elseif FarmState.Enabled then
            if FarmState.TargetName then
                text = "Engaging " .. FarmState.TargetName
                color = T.Neon
            else
                text = "Running — scanning for targets"
                color = T.Good
            end
        else
            text = "Idle — press Start"
            color = T.Subtle
        end
        if not pending and FarmState.PendingSince then
            FarmState.PendingSince = nil
        end
    end

    FarmUI.statusValue.Text = text
    FarmUI.statusValue.TextColor3 = color

    if FarmUI.toggleButton then
        local shouldStop = FarmState.Enabled and (FarmState.PendingSince == nil)
        FarmUI.toggleButton.Text = shouldStop and "Stop" or "Start"
    end

    if FarmUI.toggleRow then
        local interactable = farmRemotesReady and not (FarmState.PendingSince and (os.clock() - FarmState.PendingSince) < 5)
        setInteractable(FarmUI.toggleRow, interactable)
    end
end

local function renderFarmTargetLabel()
    if not FarmUI.targetValue then return end

    local text = "(none)"
    local color = T.Subtle

    if not farmRemotesReady then
        text = "Remotes offline"
        color = T.Warn
    elseif FarmState.PendingSince and (os.clock() - FarmState.PendingSince) < 5 then
        text = "Waiting for server…"
        color = T.Warn
    elseif FarmState.TargetName then
        text = FarmState.TargetName
        color = T.Neon
        if FarmState.TargetPosition then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (FarmState.TargetPosition - hrp.Position).Magnitude
                text = string.format("%s (%.0f studs)", FarmState.TargetName, dist)
            end
        end
    elseif FarmState.Enabled then
        text = "Scanning for Kriluni…"
    end

    if lastTargetText ~= text then
        FarmUI.targetValue.Text = text
        lastTargetText = text
    end
    FarmUI.targetValue.TextColor3 = color
end

local function onAutoFarmUpdate(payload)
    if typeof(payload) ~= "table" then return end

    local cmd = payload.cmd
    if cmd == "status" then
        FarmState.PendingSince = nil
        FarmState.Enabled = payload.enabled == true
        if not FarmState.Enabled then
            FarmState.TargetName = nil
            FarmState.TargetPosition = nil
        end
    elseif cmd == "goto" then
        FarmState.TargetName = payload.targetName or "Kriluni"
        if typeof(payload.pos) == "Vector3" then
            FarmState.TargetPosition = payload.pos
        else
            FarmState.TargetPosition = nil
        end
    elseif cmd == "clear" then
        FarmState.TargetName = nil
        FarmState.TargetPosition = nil
    end

    refreshFarmStatus()
    renderFarmTargetLabel()
end

local function attachAutoFarmUpdate(remote)
    if autoFarmUpdateConn then
        autoFarmUpdateConn:Disconnect()
        autoFarmUpdateConn = nil
    end

    if remote and remote:IsA("RemoteEvent") then
        AutoFarmUpdateRemote = remote
        autoFarmUpdateConn = remote.OnClientEvent:Connect(onAutoFarmUpdate)
    else
        AutoFarmUpdateRemote = nil
    end
end

local resolveAutoFarmRemotes

local function watchRemotesFolder(folder)
    if remotesAddedConn then remotesAddedConn:Disconnect() remotesAddedConn = nil end
    if remotesRemovedConn then remotesRemovedConn:Disconnect() remotesRemovedConn = nil end

    remotesFolderRef = folder

    if folder and folder:IsA("Folder") then
        remotesAddedConn = folder.ChildAdded:Connect(function(child)
            if child.Name == "AutoFarmRequest" or child.Name == "AutoFarmUpdate" then
                task.defer(resolveAutoFarmRemotes)
            end
        end)
        remotesRemovedConn = folder.ChildRemoved:Connect(function(child)
            if child == AutoFarmRequestRemote or child == AutoFarmUpdateRemote then
                task.defer(resolveAutoFarmRemotes)
            end
        end)
    end
end

resolveAutoFarmRemotes = function()
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    if folder ~= remotesFolderRef then
        watchRemotesFolder(folder)
    end

    if folder and folder:IsA("Folder") then
        local req = folder:FindFirstChild("AutoFarmRequest")
        if req and req:IsA("RemoteEvent") then
            AutoFarmRequestRemote = req
        else
            AutoFarmRequestRemote = nil
        end

        local upd = folder:FindFirstChild("AutoFarmUpdate")
        if upd and upd:IsA("RemoteEvent") then
            if AutoFarmUpdateRemote ~= upd then
                attachAutoFarmUpdate(upd)
            end
        else
            attachAutoFarmUpdate(nil)
        end
    else
        AutoFarmRequestRemote = nil
        attachAutoFarmUpdate(nil)
    end

    local ready = AutoFarmRequestRemote ~= nil and AutoFarmUpdateRemote ~= nil
    if not ready then
        FarmState.Enabled = false
        FarmState.TargetName = nil
        FarmState.TargetPosition = nil
    end
    if farmRemotesReady ~= ready then
        farmRemotesReady = ready
    end

    refreshFarmStatus()
    renderFarmTargetLabel()
end

ReplicatedStorage.ChildAdded:Connect(function(child)
    if child.Name == "Remotes" then
        task.defer(resolveAutoFarmRemotes)
    end
end)

ReplicatedStorage.ChildRemoved:Connect(function(child)
    if child == remotesFolderRef then
        watchRemotesFolder(nil)
        task.defer(resolveAutoFarmRemotes)
    end
end)

task.defer(resolveAutoFarmRemotes)

--==================== ACCESS OVERLAY ====================--
local Blur = Instance.new("BlurEffect"); Blur.Enabled=false; Blur.Size=0; Blur.Parent=Lighting

local Gate = Instance.new("ScreenGui")
Gate.Name="PC_Gate"; Gate.IgnoreGuiInset=true; Gate.ResetOnSpawn=false; Gate.ZIndexBehavior=Enum.ZIndexBehavior.Global
Gate.DisplayOrder=100; Gate.Parent=safeParent()

local Dim = Instance.new("Frame", Gate)
Dim.BackgroundColor3=Color3.new(0,0,0); Dim.BackgroundTransparency=0.35; Dim.Size=UDim2.fromScale(1,1)

local Card = Instance.new("Frame", Gate)
Card.Size=UDim2.fromOffset(600, 360); Card.AnchorPoint=Vector2.new(0.5,0.5); Card.Position=UDim2.fromScale(0.5,0.5)
Card.BackgroundColor3=T.Card; stroke(Card,T.Stroke,1,0.45); corner(Card,18); pad(Card,22)

local CardLayout = Instance.new("UIListLayout", Card)
CardLayout.SortOrder = Enum.SortOrder.LayoutOrder
CardLayout.Padding   = UDim.new(0, 12)

local Hero = Instance.new("Frame", Card)
Hero.Name = "Hero"; Hero.Size = UDim2.new(1,0,0,128); Hero.LayoutOrder = 1; Hero.BackgroundColor3 = T.Accent; Hero.BackgroundTransparency = 0.7
Hero.ZIndex = 2; Hero.ClipsDescendants = true; corner(Hero,16); stroke(Hero,T.Stroke,1,0.28)

local heroGradient = Instance.new("UIGradient", Hero)
heroGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, T.Accent),
    ColorSequenceKeypoint.new(1, T.Neon)
})
heroGradient.Rotation = 28
heroGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.22),
    NumberSequenceKeypoint.new(1, 0.32)
})

local heroPad = Instance.new("UIPadding", Hero)
heroPad.PaddingTop = UDim.new(0, 18); heroPad.PaddingBottom = UDim.new(0, 18)
heroPad.PaddingLeft = UDim.new(0, 20); heroPad.PaddingRight = UDim.new(0, 20)

local heroLayout = Instance.new("UIListLayout", Hero)
heroLayout.SortOrder = Enum.SortOrder.LayoutOrder; heroLayout.Padding = UDim.new(0, 8)

local Pill = Instance.new("TextLabel", Hero)
Pill.BackgroundTransparency = 0.2; Pill.BackgroundColor3 = T.Ink; Pill.LayoutOrder = 1
Pill.Size = UDim2.new(0, 150, 0, 26); Pill.Font = Enum.Font.GothamBold; Pill.TextSize = 13
Pill.Text = "ACCESS PASS"; Pill.TextColor3 = T.Text; Pill.TextXAlignment = Enum.TextXAlignment.Center
Pill.ZIndex = 3
corner(Pill, 13); stroke(Pill, T.Stroke, 1, 0.5)

local Title = Instance.new("TextLabel", Hero)
Title.BackgroundTransparency=1; Title.Text="ProfitCruiser — Access Portal"; Title.Font=Enum.Font.GothamBlack; Title.TextSize=24; Title.TextColor3=T.Text
Title.Size=UDim2.new(1,0,0,34); Title.TextXAlignment=Enum.TextXAlignment.Left; Title.LayoutOrder = 2; Title.ZIndex = 3

local Hint = Instance.new("TextLabel", Hero)
Hint.BackgroundTransparency=1; Hint.Text="Paste your private key to unlock Aurora. Grab a new key or meet the crew on Discord for instant drops."; Hint.Font=Enum.Font.Gotham
Hint.TextSize=14; Hint.TextColor3=T.Text; Hint.TextWrapped=true; Hint.TextXAlignment=Enum.TextXAlignment.Left; Hint.TextYAlignment=Enum.TextYAlignment.Top
Hint.Size=UDim2.new(1,0,0,44); Hint.LayoutOrder = 3; Hint.ZIndex = 3

local Features = Instance.new("TextLabel", Hero)
Features.BackgroundTransparency = 1; Features.Text = "⚡ Rapid updates    🛡️ Anti-ban shielding    🎯 Elite aim assist"
Features.Font = Enum.Font.Gotham; Features.TextSize = 13; Features.TextColor3 = T.Subtle; Features.TextXAlignment = Enum.TextXAlignment.Left
Features.Size = UDim2.new(1,0,0,22); Features.LayoutOrder = 4; Features.ZIndex = 3

local InputSection = Instance.new("Frame", Card)
InputSection.BackgroundColor3 = T.Panel; InputSection.BackgroundTransparency = 0.05; InputSection.Size = UDim2.new(1,0,0,120)
InputSection.LayoutOrder = 2; corner(InputSection,14); stroke(InputSection,T.Stroke,1,0.28)

local inputPad = Instance.new("UIPadding", InputSection)
inputPad.PaddingTop = UDim.new(0, 14); inputPad.PaddingBottom = UDim.new(0, 14)
inputPad.PaddingLeft = UDim.new(0, 18); inputPad.PaddingRight = UDim.new(0, 18)

local inputLayout = Instance.new("UIListLayout", InputSection)
inputLayout.SortOrder = Enum.SortOrder.LayoutOrder; inputLayout.Padding = UDim.new(0, 8)

local KeyLabel = Instance.new("TextLabel", InputSection)
KeyLabel.BackgroundTransparency = 1; KeyLabel.Text = "Master Key"; KeyLabel.Font = Enum.Font.GothamMedium; KeyLabel.TextSize = 15
KeyLabel.TextColor3 = T.Text; KeyLabel.TextXAlignment = Enum.TextXAlignment.Left; KeyLabel.Size = UDim2.new(1,0,0,22)
KeyLabel.LayoutOrder = 1

local KeyBox = Instance.new("TextBox", InputSection)
KeyBox.Size=UDim2.new(1,0,0,40); KeyBox.Text=""; KeyBox.PlaceholderText="Paste key or drop to auto-fill…"
KeyBox.ClearTextOnFocus=false; KeyBox.Font=Enum.Font.Gotham; KeyBox.TextSize=16; KeyBox.TextColor3=T.Text
KeyBox.BackgroundColor3=T.Ink; stroke(KeyBox,T.Stroke,1,0.35); corner(KeyBox,12); KeyBox.LayoutOrder = 2

local KeyNote = Instance.new("TextLabel", InputSection)
KeyNote.BackgroundTransparency = 1; KeyNote.Text = "Keys rotate fast — confirm before the cycle resets. Discord pings fire instantly."
KeyNote.Font = Enum.Font.Gotham; KeyNote.TextSize = 12; KeyNote.TextColor3 = T.Subtle; KeyNote.TextWrapped = true
KeyNote.TextXAlignment = Enum.TextXAlignment.Left; KeyNote.TextYAlignment = Enum.TextYAlignment.Top
KeyNote.Size = UDim2.new(1,0,0,32); KeyNote.LayoutOrder = 3

local Divider = Instance.new("Frame", Card)
Divider.BackgroundColor3 = T.Stroke; Divider.BackgroundTransparency = 0.55; Divider.Size = UDim2.new(1,0,0,1); Divider.LayoutOrder = 3

local Row = Instance.new("Frame", Card)
Row.BackgroundTransparency=1; Row.Size=UDim2.new(1,0,0,48); Row.LayoutOrder = 4

local rowLayout = Instance.new("UIListLayout", Row)
rowLayout.FillDirection = Enum.FillDirection.Horizontal; rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center; rowLayout.Padding = UDim.new(0, 14)

local function btn(text, style)
    local b=Instance.new("TextButton", Row); b.Text=text; b.Font=Enum.Font.GothamMedium; b.TextSize=15; b.TextColor3=T.Text
    b.AutoButtonColor=false; b.Size=UDim2.new(0,172,0,42); b.LayoutOrder = style == "primary" and 3 or 1
    local isPrimary = style == "primary"
    local baseColor = isPrimary and T.Accent or T.Ink
    local hoverColor = isPrimary and T.Neon or Color3.fromRGB(58, 52, 88)
    b.BackgroundColor3=baseColor; stroke(b,T.Stroke,1,0.35); corner(b,12)
    b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=hoverColor}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=baseColor}):Play() end)
    return b
end

local GetKey = btn("Get Key Link")
local Discord = btn("Join Discord")
local Confirm = btn("Unlock Panel", "primary")

local Status = Instance.new("TextLabel", Card)
Status.BackgroundColor3 = T.Ink; Status.BackgroundTransparency = 0.6; Status.Text=""; Status.Font=Enum.Font.Gotham
Status.TextSize=13; Status.TextColor3=T.Subtle; Status.Size=UDim2.new(1,0,0,28); Status.LayoutOrder = 5
Status.TextXAlignment=Enum.TextXAlignment.Center; Status.TextYAlignment = Enum.TextYAlignment.Center; corner(Status,12)

local function updateStatus(text, color)
    Status.Text = text
    Status.TextColor3 = color or T.Subtle
end

updateStatus("Paste your key to unlock ProfitCruiser.")

-- Success overlay in its own GUI so it survives hiding Gate
local SuccessGui = Instance.new("ScreenGui")
SuccessGui.Name = "PC_Success"; SuccessGui.IgnoreGuiInset = true; SuccessGui.ResetOnSpawn = false
SuccessGui.ZIndexBehavior = Enum.ZIndexBehavior.Global; SuccessGui.DisplayOrder = 110
SuccessGui.Parent = safeParent()

local Success = Instance.new("Frame", SuccessGui)
Success.Visible=false; Success.Size=UDim2.fromScale(1,1); Success.BackgroundTransparency=1
local Center = Instance.new("Frame", Success)
Center.Size=UDim2.fromOffset(420,220); Center.AnchorPoint=Vector2.new(0.5,0.5); Center.Position=UDim2.fromScale(0.5,0.5); Center.BackgroundColor3=T.Card
corner(Center,16); stroke(Center,T.Good,2,0)
local GG = Instance.new("TextLabel", Center)
GG.BackgroundTransparency=1; GG.Size=UDim2.fromScale(1,1); GG.Text="ACCESS GRANTED ✨"; GG.TextColor3=T.Good; GG.Font=Enum.Font.GothamBold; GG.TextSize=28

-- FLAG: only allow reveal of Root after overlay finished
local allowReveal = false

local function fetchRemoteKey()
    local ok,res=pcall(game.HttpGet,game,KEY_CHECK_URL)
    if not ok then return nil,res end
    local cleaned=trim(res); if #cleaned==0 then return nil,"empty" end
    return cleaned
end

GetKey.MouseButton1Click:Connect(function()
    if typeof(setclipboard)=="function" then
        setclipboard(GET_KEY_URL)
        updateStatus("Key link copied to clipboard.", T.Neon)
    else
        updateStatus("Key link: "..GET_KEY_URL)
    end
end)
Discord.MouseButton1Click:Connect(function()
    if typeof(setclipboard)=="function" then setclipboard(DISCORD_URL) end
    updateStatus("Discord invite copied — we'll see you inside!", T.Neon)
    if syn and syn.request then pcall(function() syn.request({Url=DISCORD_URL,Method="GET"}) end) end
end)

-- new showGranted supports callback after hide
local function showGranted(seconds, after)
    Success.Visible = true
    task.delay(seconds or 2.0, function()
        Success.Visible = false
        if after then pcall(after) end
    end)
end

Confirm.MouseButton1Click:Connect(function()
    updateStatus("Checking key…", T.Text)
    local expected,err = fetchRemoteKey()
    if not expected then updateStatus("Fetch failed: "..tostring(err or ""), T.Warn) return end

    if trim(KeyBox.Text) == expected then
        updateStatus("Accepted!", T.Good)

        -- Immediately hide the gate UI so the key box is gone
        Gate.Enabled = false

        -- Ensure Root is hidden while we show the success overlay
        if Root then Root.Visible = false end

        -- Show blur and keep it while overlay is visible
        Blur.Enabled = true
        TweenService:Create(Blur, TweenInfo.new(0.2), {Size = 8}):Play()

        -- Show the granted overlay for 2s, then remove blur and reveal the panel
        showGranted(2.0, function()
            -- animate blur out
            TweenService:Create(Blur, TweenInfo.new(0.2), {Size = 0}):Play()
            task.delay(0.2, function() Blur.Enabled = false end)

            -- mark that reveal is allowed and show Root
            allowReveal = true
            if Root then Root.Visible = true end
        end)

    else
        updateStatus("Wrong key.", T.Warn)
    end
end)

Gate.Enabled=true
Blur.Enabled=true; TweenService:Create(Blur,TweenInfo.new(0.2),{Size=8}):Play()

-- Ensure AA_GUI is disabled when gate is open
Gate:GetPropertyChangedSignal("Enabled"):Connect(function()
    AA_GUI.Enabled = not Gate.Enabled
end)

--==================== MAIN APP ====================--
local App = Instance.new("ScreenGui")
App.Name="AuroraPanel"; App.IgnoreGuiInset=true; App.ResetOnSpawn=false; App.ZIndexBehavior=Enum.ZIndexBehavior.Global
App.DisplayOrder=50; App.Parent=safeParent()

Root = Instance.new("Frame", App)
Root.Size=UDim2.fromOffset(980, 600); Root.AnchorPoint=Vector2.new(0.5,0.5); Root.Position=UDim2.fromScale(0.5,0.5)
Root.BackgroundColor3=T.Card; corner(Root,16); stroke(Root,T.Stroke,1,0.45); pad(Root,12)
Root.Visible=false

local PanelScale = Instance.new("UIScale", Root)
PanelScale.Scale = 1

local Top = Instance.new("Frame", Root)
Top.Size=UDim2.new(1, -16, 0, 46); Top.Position=UDim2.new(0,8,0,8); Top.BackgroundColor3=T.Panel; corner(Top,12); stroke(Top,T.Stroke,1,0.45); pad(Top,10)

local TitleLbl = Instance.new("TextLabel", Top)
TitleLbl.Size=UDim2.new(0.6,0,1,0); TitleLbl.BackgroundTransparency=1; TitleLbl.TextXAlignment=Enum.TextXAlignment.Left
TitleLbl.Text="ProfitCruiser — Aurora Panel"; TitleLbl.Font=Enum.Font.GothamBold; TitleLbl.TextSize=18; TitleLbl.TextColor3=T.Text

-- drag
local draggingEnabled = true
local dragging,rel=false,Vector2.zero
Top.InputBegan:Connect(function(i) if draggingEnabled and i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; rel=Root.AbsolutePosition-UserInputService:GetMouseLocation() end end)
UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
RunService.RenderStepped:Connect(function()
    if dragging then
        local vp=Camera.ViewportSize; local m=UserInputService:GetMouseLocation()
        local nx=math.clamp(m.X+rel.X,8,vp.X-Root.AbsoluteSize.X-8); local ny=math.clamp(m.Y+rel.Y,8,vp.Y-Root.AbsoluteSize.Y-8)
        Root.Position=UDim2.fromOffset(nx,ny)
    end
end)

-- sidebar
local Side = Instance.new("Frame", Root)
Side.Size=UDim2.new(0, 210, 1, -70); Side.Position=UDim2.new(0,8,0,62)
Side.BackgroundColor3=T.Panel; corner(Side,12); stroke(Side,T.Stroke,1,0.45); pad(Side,8)
-- ensure tab buttons stack vertically (fix: only Aimbot showing)
local SideList = Instance.new("UIListLayout", Side)
SideList.SortOrder = Enum.SortOrder.LayoutOrder
SideList.Padding   = UDim.new(0,8)

local Content = Instance.new("Frame", Root)
Content.Size=UDim2.new(1, -234, 1, -70); Content.Position=UDim2.new(0, 226, 0, 62); Content.BackgroundTransparency=1
Content.ClipsDescendants = true

-- two-column grid inside pages
local function newPage(name)
    local p = Instance.new("ScrollingFrame", Content)
    p.Name = name
    p.Size = UDim2.fromScale(1, 1)
    p.Visible = false
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ClipsDescendants = true
    p.Active = true
    p.ScrollingEnabled = true
    p.ScrollBarThickness = 4
    p.ScrollBarImageColor3 = T.Subtle
    p.ScrollBarImageTransparency = 0.15
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.ScrollingDirection = Enum.ScrollingDirection.Y

    local padding = Instance.new("UIPadding", p)
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 8)
    padding.PaddingTop = UDim.new(0, 4)
    padding.PaddingBottom = UDim.new(0, 12)

    local grid = Instance.new("UIGridLayout", p)
    grid.CellPadding = UDim2.new(0, 12, 0, 12)
    grid.CellSize = UDim2.new(0.5, -6, 0, 64)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Left

    local function syncCanvas()
        local contentY = grid.AbsoluteContentSize.Y
        local viewportY = p.AbsoluteSize.Y
        local paddingY = padding.PaddingTop.Offset + padding.PaddingBottom.Offset
        local totalY = math.max(contentY + paddingY, viewportY)
        p.CanvasSize = UDim2.new(0, 0, 0, totalY)

        -- clamp current scroll position so we can always scroll back up
        local maxScroll = math.max(0, totalY - viewportY)
        local current = p.CanvasPosition
        if current.Y > maxScroll or current.Y < 0 then
            p.CanvasPosition = Vector2.new(current.X, math.clamp(current.Y, 0, maxScroll))
        end
    end

    grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)
    p:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncCanvas)
    task.defer(syncCanvas)

    return p
end

local function tabButton(text, page)
    local b=Instance.new("TextButton", Side)
    b.Size=UDim2.new(1,0,0,40); b.Text=text; b.Font=Enum.Font.Gotham; b.TextSize=15; b.TextColor3=T.Text
    b.BackgroundColor3=T.Ink; b.AutoButtonColor=false; corner(b,10); stroke(b,T.Stroke,1,0.35)
    local bar=Instance.new("Frame", b); bar.Size=UDim2.new(0,0,1,0); bar.Position=UDim2.new(0,0,0,0); bar.BackgroundColor3=T.Neon; corner(bar,10)
    b.MouseButton1Click:Connect(function()
        for _,c in ipairs(Content:GetChildren()) do
            if c:IsA("GuiObject") then
                c.Visible = false
            end
        end
        for _,x in ipairs(Side:GetChildren()) do
            if x:IsA("TextButton") then
                TweenService:Create(x,TweenInfo.new(0.12),{BackgroundColor3=T.Ink}):Play()
                local f=x:FindFirstChildOfClass("Frame"); if f then TweenService:Create(f,TweenInfo.new(0.12),{Size=UDim2.new(0,0,1,0)}):Play() end
            end
        end
        page.Visible=true
        if page:IsA("ScrollingFrame") then page.CanvasPosition = Vector2.new(0,0) end
        TweenService:Create(b,TweenInfo.new(0.12),{BackgroundColor3=T.Accent}):Play()
        TweenService:Create(bar,TweenInfo.new(0.12),{Size=UDim2.new(0,4,1,0)}):Play()
    end)
    return b
end

-- floating tooltip bubble for control descriptions
local Tooltip = Instance.new("Frame", App)
Tooltip.Name = "ControlTooltip"
Tooltip.Visible = false
Tooltip.Active = false
Tooltip.ZIndex = 200
Tooltip.BackgroundColor3 = T.Panel
Tooltip.BackgroundTransparency = 0.05
Tooltip.Size = UDim2.fromOffset(220, 64)
Tooltip.ClipsDescendants = false
corner(Tooltip, 10)
stroke(Tooltip, T.Stroke, 1, 0.2)

local tooltipPad = Instance.new("UIPadding", Tooltip)
tooltipPad.PaddingTop = UDim.new(0, 8)
tooltipPad.PaddingBottom = UDim.new(0, 8)
tooltipPad.PaddingLeft = UDim.new(0, 12)
tooltipPad.PaddingRight = UDim.new(0, 12)

local tooltipText = Instance.new("TextLabel", Tooltip)
tooltipText.BackgroundTransparency = 1
tooltipText.Size = UDim2.new(1, 0, 1, 0)
tooltipText.Font = Enum.Font.Gotham
tooltipText.TextSize = 13
tooltipText.TextColor3 = T.Text
tooltipText.TextWrapped = true
tooltipText.TextXAlignment = Enum.TextXAlignment.Left
tooltipText.TextYAlignment = Enum.TextYAlignment.Top
tooltipText.ZIndex = Tooltip.ZIndex + 1

local tooltipOwner = nil
local tooltipBounds = Vector2.new(Tooltip.Size.X.Offset, Tooltip.Size.Y.Offset)

local function updateTooltipPosition(x, y)
    local vp = Camera.ViewportSize
    local width = tooltipBounds.X
    local height = tooltipBounds.Y
    local px = math.clamp(x + 16, 8, vp.X - width - 8)
    local py = math.clamp(y + 20, 8, vp.Y - height - 8)
    Tooltip.Position = UDim2.fromOffset(px, py)
end

local function openTooltip(owner, text)
    tooltipOwner = owner
    tooltipText.Text = text
    local bounds = TextService:GetTextSize(text, tooltipText.TextSize, tooltipText.Font, Vector2.new(280, 800))
    local width = math.clamp(bounds.X + 24, 160, 320)
    local height = math.clamp(bounds.Y + 16, 32, 220)
    tooltipBounds = Vector2.new(width, height)
    Tooltip.Size = UDim2.fromOffset(width, height)
    Tooltip.Visible = true
    local mouse = UserInputService:GetMouseLocation()
    updateTooltipPosition(mouse.X, mouse.Y)
end

local function closeTooltip(owner)
    if tooltipOwner ~= owner then return end
    tooltipOwner = nil
    Tooltip.Visible = false
end

local function trackTooltip(owner, x, y)
    if tooltipOwner ~= owner then return end
    updateTooltipPosition(x, y)
end

Root:GetPropertyChangedSignal("Visible"):Connect(function()
    if not Root.Visible then
        tooltipOwner = nil
        Tooltip.Visible = false
    end
end)

-- Controls factory (compact, reused)
local function rowBase(parent, name, desc)
    local infoText = trim(desc or "")
    local hasDesc = infoText ~= ""
    local r = Instance.new("Frame", parent)
    r.BackgroundColor3 = T.Card
    r.Size = UDim2.new(0.5, -6, 0, 64)
    corner(r, 10)
    stroke(r, T.Stroke, 1, 0.25)

    local labelOffset = hasDesc and 54 or 18
    local labelWidth = hasDesc and -210 or -176

    local l = Instance.new("TextLabel", r)
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, labelOffset, 0, 0)
    l.Size = UDim2.new(1, labelWidth, 1, 0)
    l.Text = name
    l.TextColor3 = T.Text
    l.Font = Enum.Font.Gotham
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextWrapped = true

    if hasDesc then
        local infoButton = Instance.new("TextButton", r)
        infoButton.Name = "Info"
        infoButton.Size = UDim2.fromOffset(26, 26)
        infoButton.Position = UDim2.new(0, 18, 0.5, -13)
        infoButton.BackgroundColor3 = T.Ink
        infoButton.AutoButtonColor = false
        infoButton.Text = "?"
        infoButton.Font = Enum.Font.GothamBold
        infoButton.TextSize = 16
        infoButton.TextColor3 = T.Subtle
        infoButton.ZIndex = 3
        corner(infoButton, 13)
        stroke(infoButton, T.Stroke, 1, 0.45)

        local baseColor = infoButton.BackgroundColor3
        local baseText = infoButton.TextColor3

        infoButton.MouseEnter:Connect(function()
            TweenService:Create(infoButton, TweenInfo.new(0.12), {
                BackgroundColor3 = T.Accent,
                TextColor3 = T.Text,
            }):Play()
            openTooltip(infoButton, infoText)
        end)

        infoButton.MouseLeave:Connect(function()
            TweenService:Create(infoButton, TweenInfo.new(0.12), {
                BackgroundColor3 = baseColor,
                TextColor3 = baseText,
            }):Play()
            closeTooltip(infoButton)
        end)

        infoButton.MouseButton1Click:Connect(function()
            openTooltip(infoButton, infoText)
        end)

        infoButton.MouseMoved:Connect(function(x, y)
            trackTooltip(infoButton, x, y)
        end)
    end

    return r, l
end

local function mkToggle(parent, name, default, cb, desc)
    local r,_=rowBase(parent,name,desc)
    local sw=Instance.new("Frame", r); sw.Size=UDim2.new(0,68,0,28); sw.Position=UDim2.new(1,-84,0.5,-14); sw.BackgroundColor3=T.Ink; corner(sw,16); stroke(sw,T.Stroke,1,0.35)
    local k=Instance.new("Frame", sw); k.Size=UDim2.new(0,24,0,24); k.Position=UDim2.new(0,2,0.5,-12); k.BackgroundColor3=Color3.fromRGB(235,235,245); corner(k,12)
    local state = default
    local function set(v)
        state=v
        TweenService:Create(k,TweenInfo.new(0.12),{Position=v and UDim2.new(1,-26,0.5,-12) or UDim2.new(0,2,0.5,-12)}):Play()
        TweenService:Create(sw,TweenInfo.new(0.12),{BackgroundColor3=v and T.Neon or T.Ink}):Play()
        if cb then cb(v,r) end
    end
    sw.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then set(not state) end end)
    set(state)
    return {Row=r, Set=set, Get=function() return state end}
end

local function mkSlider(parent, name, min, max, default, cb, unit, desc)
    local r,l=rowBase(parent,name,desc)
    local hasDesc = trim(desc or "") ~= ""
    local sliderLeft = hasDesc and 54 or 18
    local valueWidth = 110
    local rightPadding = 28

    l.Position = UDim2.new(0, sliderLeft, 0, 6)
    l.Size = UDim2.new(1, -(sliderLeft + valueWidth + rightPadding), 0, 26)
    l.TextYAlignment = Enum.TextYAlignment.Top

    local v=Instance.new("TextLabel", r); v.BackgroundTransparency=1; v.Size=UDim2.new(0,valueWidth,0,24); v.Position=UDim2.new(1,-valueWidth-18,0,6)
    v.Text=""; v.TextColor3=T.Subtle; v.Font=Enum.Font.Gotham; v.TextSize=14; v.TextXAlignment=Enum.TextXAlignment.Right
    v.TextYAlignment = Enum.TextYAlignment.Top

    local bar=Instance.new("Frame", r); bar.Size=UDim2.new(1, -(sliderLeft + valueWidth + rightPadding), 0, 6); bar.Position=UDim2.new(0,sliderLeft,0,38); bar.BackgroundColor3=T.Ink; corner(bar,4)
    local fill=Instance.new("Frame", bar); fill.Size=UDim2.new(0,0,1,0); fill.BackgroundColor3=T.Neon; corner(fill,4)

    local val=math.clamp(default or min, min, max)
    local function render()
        local a=(val-min)/(max-min)
        fill.Size=UDim2.new(a,0,1,0)
        local u = unit and (" "..unit) or ""
        v.Text = (math.floor(val*100+0.5)/100)..u
    end
    local dragging=false
    bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true end end)
    UserInputService.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
    RunService.RenderStepped:Connect(function()
        if dragging then
            local m=UserInputService:GetMouseLocation().X; local x=bar.AbsolutePosition.X; local w=bar.AbsoluteSize.X
            local a=math.clamp((m-x)/w,0,1); val=min + a*(max-min); render(); if cb then cb(val,r) end
        end
    end)
    render()
    return {Row=r, Set=function(x) val=math.clamp(x,min,max); render(); if cb then cb(val,r) end end, Get=function() return val end}
end

-- simple button control (used for Kill Menu)
local function mkButton(parent, name, onClick, opts, desc)
    local r,_ = rowBase(parent, name, desc)
    -- make the label take full width, then place a button pill on the right
    local btn = Instance.new("TextButton", r)
    btn.Size = UDim2.new(0, 120, 0, 30)
    btn.Position = UDim2.new(1, -132, 0.5, -15)
    opts = opts or {}
    local danger = opts.danger
    local buttonText = opts.buttonText or (danger and "Kill Menu" or "Run")
    local baseColor = opts.backgroundColor or (danger and Color3.fromRGB(170, 60, 70) or T.Ink)
    local hoverColor = opts.hoverColor or (danger and Color3.fromRGB(200, 75, 85) or T.Accent)
    local textColor = opts.textColor or (danger and Color3.fromRGB(255,235,235) or T.Text)
    btn.Text = buttonText
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 14
    btn.TextColor3 = textColor
    btn.BackgroundColor3 = baseColor
    btn.AutoButtonColor = false
    corner(btn, 10)
    stroke(btn, (danger and Color3.fromRGB(200,80,90)) or opts.strokeColor or T.Stroke, 1, 0.35)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = hoverColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = baseColor}):Play()
    end)
    btn.MouseButton1Click:Connect(function()
        if onClick then onClick(r) end
    end)
    return {Row=r, Button=btn}
end

local function mkCycle(parent, name, options, default, cb, desc)
    local r,_ = rowBase(parent, name, desc)
    local btn = Instance.new("TextButton", r)
    btn.Size = UDim2.new(0, 120, 0, 30)
    btn.Position = UDim2.new(1, -132, 0.5, -15)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 14
    btn.TextColor3 = T.Text
    btn.BackgroundColor3 = T.Ink
    btn.AutoButtonColor = false
    corner(btn, 10)
    stroke(btn, T.Stroke, 1, 0.35)

    local normalized = {}
    for i,opt in ipairs(options) do
        if typeof(opt) == "table" then
            normalized[i] = {
                label = opt.label or opt.text or tostring(opt.value),
                value = opt.value,
            }
        else
            normalized[i] = {label = tostring(opt), value = opt}
        end
    end

    local function findIndexByValue(val)
        for i,opt in ipairs(normalized) do
            if opt.value == val then return i end
        end
        return nil
    end

    local idx = 1
    if default ~= nil then
        if typeof(default) == "number" and normalized[default] then
            idx = default
        else
            idx = findIndexByValue(default) or idx
        end
    end

    local function apply(index)
        if #normalized == 0 then return end
        idx = ((index - 1) % #normalized) + 1
        local opt = normalized[idx]
        btn.Text = opt.label
        if cb then cb(opt.value, r) end
    end

    btn.MouseButton1Click:Connect(function()
        apply(idx + 1)
    end)

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = T.Accent}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = T.Ink}):Play()
    end)

    apply(idx)

    return {
        Row = r,
        Set = function(value)
            local targetIndex
            if typeof(value) == "number" and normalized[value] then
                targetIndex = value
            else
                targetIndex = findIndexByValue(value)
            end
            if targetIndex then
                apply(targetIndex)
            end
        end,
        Get = function()
            if normalized[idx] then return normalized[idx].value end
        end,
    }
end

--==================== FEATURE STATE ====================--
local AA={
    Enabled=false,
    Strength=0.15,
    PartName="Head",
    ShowFOV=false,
    FOVRadiusPx=180,
    MaxDistance=250,
    MinDistance=0,
    Deadzone=4,
    RequireRMB=false,
    WallCheck=true,
    DynamicPart=false,
    StickyAim=false,
    StickTime=0.35,
    AdaptiveSmoothing=false,
    CloseRangeBoost=0.2,
    Prediction=0,
    TargetSort="Hybrid",
    DistanceWeight=0.02,
    ReactionDelay=0,
    ReactionJitter=0,
    VerticalOffset=0,
}
local ESP={
    Enabled=false,
    EnemiesOnly=false,
    UseDistance=true,
    MaxDistance=1200,
    EnemyColor=Color3.fromRGB(255,70,70),
    FriendColor=Color3.fromRGB(0,255,140),
    NeutralColor=Color3.fromRGB(255,255,0),
    FillTransparency=0.5,
    OutlineTransparency=0,
    ThroughWalls=true,
    ColorIntensity=1,
}
local Cross={
    Enabled=false,
    Color=Color3.fromRGB(0,255,200),
    Opacity=0.9,
    Size=8,
    Gap=4,
    Thickness=2,
    CenterDot=false,
    DotSize=2,
    DotOpacity=1,
    UseTeamColor=false,
    Rainbow=false,
    RainbowSpeed=1,
    Pulse=false,
    PulseSpeed=2.5,
}

--==================== RUNTIME / DRAW ====================--
-- FOV ring
local AA_GUI=Instance.new("ScreenGui"); AA_GUI.Name="PC_FOV"; AA_GUI.IgnoreGuiInset=true; AA_GUI.ResetOnSpawn=false; AA_GUI.DisplayOrder=45; AA_GUI.Parent=safeParent()
local FOV=Instance.new("Frame", AA_GUI); FOV.AnchorPoint=Vector2.new(0.5,0.5); FOV.Position=UDim2.fromScale(0.5,0.5); FOV.BackgroundTransparency=1; FOV.Visible=false
local FStroke=Instance.new("UIStroke", FOV); FStroke.Thickness=2; FStroke.Transparency=0.15; FStroke.Color=Color3.fromRGB(0,255,140); corner(FOV, math.huge)

-- Crosshair
local CrossGui=Instance.new("ScreenGui"); CrossGui.Name="PC_Crosshair"; CrossGui.IgnoreGuiInset=true; CrossGui.ResetOnSpawn=false; CrossGui.DisplayOrder=44; CrossGui.Parent=safeParent()
local function crossPart() local f=Instance.new("Frame"); f.BorderSizePixel=0; f.Parent=CrossGui; f.Visible=false; return f end
local chL,chR,chU,chD = crossPart(),crossPart(),crossPart(),crossPart()
local dot = crossPart()
local function updCross()
    if not Cross.Enabled then for _,f in ipairs({chL,chR,chU,chD,dot}) do f.Visible=false end return end
    local vp=Camera.ViewportSize; local cx,cy=vp.X*0.5,vp.Y*0.5; local g,s,t=Cross.Gap,Cross.Size,Cross.Thickness

    local color = Cross.Color
    if Cross.Rainbow then
        local h = (os.clock() * math.max(Cross.RainbowSpeed, 0)) % 1
        color = Color3.fromHSV(h, 0.9, 1)
    elseif Cross.UseTeamColor and LocalPlayer.TeamColor then
        color = LocalPlayer.TeamColor.Color
    end

    local pulseFactor = 1
    if Cross.Pulse then
        local wave = math.sin(os.clock() * math.max(Cross.PulseSpeed, 0.01) * math.pi * 2) * 0.5 + 0.5
        pulseFactor = 0.6 + 0.4 * wave
    end

    local baseOpacity = math.clamp(Cross.Opacity * pulseFactor, 0, 1)
    local dotOpacity = math.clamp(Cross.DotOpacity * pulseFactor, 0, 1)

    local function sty(f,opa)
        f.BackgroundColor3=color
        f.BackgroundTransparency=1-math.clamp(opa or baseOpacity,0,1)
    end
    chU.Size=UDim2.fromOffset(t,s); chU.Position=UDim2.fromOffset(cx - t/2, cy - g - s)
    chD.Size=UDim2.fromOffset(t,s); chD.Position=UDim2.fromOffset(cx - t/2, cy + g)
    chL.Size=UDim2.fromOffset(s,t); chL.Position=UDim2.fromOffset(cx - g - s, cy - t/2)
    chR.Size=UDim2.fromOffset(s,t); chR.Position=UDim2.fromOffset(cx + g, cy - t/2)
    for _,f in ipairs({chL,chR,chU,chD}) do sty(f); f.Visible=true end
    dot.Size=UDim2.fromOffset(Cross.DotSize,Cross.DotSize); dot.Position=UDim2.fromOffset(cx - Cross.DotSize/2, cy - Cross.DotSize/2); sty(dot, dotOpacity); dot.Visible=Cross.CenterDot
end
RunService.RenderStepped:Connect(updCross)

-- Targeting helpers
local function isEnemy(p) if p==LocalPlayer then return false end if LocalPlayer.Team and p.Team then return LocalPlayer.Team~=p.Team end return true end
local function aimPart(c)
    if not c then return nil end
    if AA.DynamicPart then
        for _,name in ipairs({"Head","UpperTorso","HumanoidRootPart","Torso"}) do
            local part=c:FindFirstChild(name)
            if part and part:IsA("BasePart") then return part end
        end
    end
    local p=c:FindFirstChild(AA.PartName)
    if not(p and p:IsA("BasePart")) then p=(c:FindFirstChild("UpperTorso") or c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")) end
    return p
end
local function hasLOS(part,char)
    if not AA.WallCheck then return true end
    local origin=Camera.CFrame.Position; local dir=(part.Position-origin)
    local rp=RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances={LocalPlayer.Character, char}; rp.IgnoreWater=true
    return workspace:Raycast(origin, dir, rp)==nil
end
local function buildCandidate(pl, my, cx, cy)
    if not isEnemy(pl) then return nil end
    local char = pl.Character
    if not char then return nil end
    local part = aimPart(char)
    if not part then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local maxDist = math.max(0, AA.MaxDistance or 0)
    local minDist = math.clamp(AA.MinDistance or 0, 0, maxDist)
    local dist = (hrp.Position-my.Position).Magnitude
    if dist > maxDist or dist < minDist then return nil end
    local sp,on = Camera:WorldToViewportPoint(part.Position)
    if not on then return nil end
    local dx,dy = sp.X-cx, sp.Y-cy
    local pd = (dx*dx+dy*dy)^0.5
    if pd>AA.FOVRadiusPx then return nil end
    if not hasLOS(part, char) then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return {
        player = pl,
        character = char,
        part = part,
        hrp = hrp,
        humanoid = hum,
        distance = dist,
        pixelDist = pd,
        screen = Vector2.new(sp.X, sp.Y),
        velocity = (hrp.AssemblyLinearVelocity or part.AssemblyLinearVelocity or Vector3.zero),
    }
end
local function scoreCandidate(info)
    local mode = AA.TargetSort or "Hybrid"
    if mode == "Distance" then
        return info.distance
    elseif mode == "Health" then
        local hum = info.humanoid
        if hum then return hum.Health end
        return math.huge
    elseif mode == "Angle" then
        return info.pixelDist
    else
        local w = math.clamp(AA.DistanceWeight or 0, 0, 0.25)
        return info.pixelDist + info.distance * w
    end
end
local function getTarget()
    local my=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); if not my then return nil end
    local cx,cy=Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2; local best,bScore
    for _,pl in ipairs(Players:GetPlayers()) do
        local info = buildCandidate(pl, my, cx, cy)
        if info then
            local sc = scoreCandidate(info)
            if not bScore or sc < bScore then
                best,bScore = info,sc
            end
        end
    end
    return best
end

local stickyTarget, stickyTimer = nil, 0
local rng = Random.new()
local lastTargetPart, reactionTimer = nil, 0
local function validateTarget(info)
    return info and info.part and info.part:IsDescendantOf(workspace)
end
local function refreshTarget(info)
    if not validateTarget(info) then return nil end
    local player = info.player
    if not player then return nil end
    local char = player.Character
    if not char then return nil end
    info.character = char
    info.part = info.part and info.part.Parent and info.part or aimPart(char)
    if not info.part then return nil end
    info.hrp = char:FindFirstChild("HumanoidRootPart")
    if not info.hrp then return nil end
    info.humanoid = char:FindFirstChildOfClass("Humanoid")
    local my = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not my then return nil end
    local maxDist = math.max(0, AA.MaxDistance or 0)
    local minDist = math.clamp(AA.MinDistance or 0, 0, maxDist)
    info.distance = (info.hrp.Position - my.Position).Magnitude
    if info.distance > maxDist or info.distance < minDist then return nil end
    local sp,on = Camera:WorldToViewportPoint(info.part.Position)
    info.screen = Vector2.new(sp.X, sp.Y)
    local cx,cy = Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2
    local dx,dy = sp.X-cx, sp.Y-cy
    info.pixelDist = (dx*dx+dy*dy)^0.5
    if AA.WallCheck and not hasLOS(info.part, char) then return nil end
    info.onScreen = on
    info.velocity = (info.hrp.AssemblyLinearVelocity or info.part.AssemblyLinearVelocity or Vector3.zero)
    return info
end

-- Main render
RunService.RenderStepped:Connect(function(dt)
    local fovRadius = math.max(0, AA.FOVRadiusPx or 0)
    FOV.Visible = (AA.Enabled and AA.ShowFOV)
    FOV.Size    = UDim2.fromOffset(fovRadius*2, fovRadius*2)

    local aiming = AA.Enabled and (not AA.RequireRMB or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2))
    if aiming then
        local candidate = getTarget()
        if AA.StickyAim then
            if candidate then
                stickyTarget = candidate
                stickyTimer = AA.StickTime
            else
                stickyTimer = math.max(0, stickyTimer - dt)
                if stickyTimer <= 0 then
                    stickyTarget = nil
                end
            end
        else
            stickyTarget = nil
            stickyTimer = 0
        end

        if stickyTarget then
            stickyTarget = refreshTarget(stickyTarget)
            if not stickyTarget then
                stickyTimer = 0
            end
        end

        local targetInfo = stickyTarget or candidate
        if targetInfo and not validateTarget(targetInfo) then
            targetInfo = nil
            if stickyTarget and not validateTarget(stickyTarget) then
                stickyTarget = nil
                stickyTimer = 0
            end
        end

        if targetInfo then
            if targetInfo.part ~= lastTargetPart then
                lastTargetPart = targetInfo.part
                local delay = math.max(0, AA.ReactionDelay or 0)
                local jitter = math.max(0, AA.ReactionJitter or 0)
                if jitter > 0 then
                    delay = delay + rng:NextNumber(0, jitter)
                end
                reactionTimer = delay
            end

            if reactionTimer > 0 then
                reactionTimer = math.max(0, reactionTimer - dt)
            else
                local pos = Camera.CFrame.Position
                local targetPos = targetInfo.part.Position + Vector3.new(0, AA.VerticalOffset or 0, 0)
                if AA.Prediction > 0 then
                    targetPos = targetPos + targetInfo.velocity * math.clamp(AA.Prediction, 0, 1.5)
                end
                local des = CFrame.lookAt(pos, targetPos)
                local alpha = math.clamp(AA.Strength + dt*0.5, 0, 1)
                if AA.AdaptiveSmoothing then
                    local normalized = 1 - math.clamp((targetInfo.distance or 0) / math.max(AA.MaxDistance, 1), 0, 1)
                    alpha = math.clamp(alpha + normalized * AA.CloseRangeBoost, 0, 1)
                end

                local deadzone = math.max(0, AA.Deadzone or 0)
                if deadzone > 0 then
                    local closeness = (targetInfo.pixelDist - deadzone) / math.max(deadzone, 1)
                    if closeness > 0 then
                        local scale = math.clamp(closeness, 0.05, 1)
                        Camera.CFrame = Camera.CFrame:Lerp(des, math.clamp(alpha * scale, 0, 1))
                    end
                else
                    Camera.CFrame = Camera.CFrame:Lerp(des, alpha)
                end
            end
        else
            lastTargetPart = nil
            reactionTimer = 0
        end
    else
        lastTargetPart = nil
        reactionTimer = 0
    end
end)

-- ESP (Highlight)
local function hl(model)
    local h = model:FindFirstChild("_HL_")
    if not h then
        h = Instance.new("Highlight")
        h.Name = "_HL_"
        h.DepthMode = ESP.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        h.FillTransparency = ESP.FillTransparency
        h.OutlineTransparency = ESP.OutlineTransparency
        h.Parent = model
    end
    -- make sure it adorns the whole character even if parent/rig is unusual
    h.Adornee = model
    return h
end
local function isEnemyESP(p) if not LocalPlayer.Team or not p.Team then return nil end return LocalPlayer.Team~=p.Team end
local function distTo(c) local hrp=c and c:FindFirstChild("HumanoidRootPart"); local my=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"); if hrp and my then return (hrp.Position-my.Position).Magnitude end return math.huge end
local function tintESPColor(color)
    local h,s,v = Color3.toHSV(color)
    local intensity = math.clamp(ESP.ColorIntensity or 1, 0, 2)
    v = math.clamp(v * intensity, 0, 1)
    local satScale = math.clamp(0.55 + 0.45 * intensity, 0, 1.5)
    s = math.clamp(s * satScale, 0, 1)
    return Color3.fromHSV(h, s, v)
end
local function espTick(p)
    if p==LocalPlayer then return end
    local c=p.Character; if not c then return end
    local h=hl(c); local show=ESP.Enabled
    if show and ESP.EnemiesOnly then local e=isEnemyESP(p); show=(e==true) end
    if show and ESP.UseDistance then show=distTo(c)<=ESP.MaxDistance end
    h.Enabled=show; if not show then return end
    h.DepthMode = ESP.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
    h.FillTransparency = math.clamp(ESP.FillTransparency, 0, 1)
    h.OutlineTransparency = math.clamp(ESP.OutlineTransparency, 0, 1)
    local e=isEnemyESP(p)
    if e==true then
        local col = tintESPColor(ESP.EnemyColor)
        h.FillColor=col; h.OutlineColor=col
    elseif e==false then
        local col = tintESPColor(ESP.FriendColor)
        h.FillColor=col; h.OutlineColor=col
    else
        local col = tintESPColor(ESP.NeutralColor)
        h.FillColor=col; h.OutlineColor=col
    end
end
RunService.RenderStepped:Connect(function() for _,pl in ipairs(Players:GetPlayers()) do espTick(pl) end end)
Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function() task.wait(0.2); espTick(p) end) end)

--==================== PAGES & CONTROLS ====================--
local FarmP   = newPage("KriluniFarm")
local AimbotP = newPage("Aimbot")
local ESPP    = newPage("ESP")
local VisualP = newPage("Visuals")
local MiscP   = newPage("Misc")
local ConfP   = newPage("Config")

local function requestAutoFarmToggle()
    if not AutoFarmRequestRemote or not farmRemotesReady then
        resolveAutoFarmRemotes()
        refreshFarmStatus()
        return
    end

    if FarmState.PendingSince and (os.clock() - FarmState.PendingSince) < 5 then
        return
    end

    FarmState.PendingSince = os.clock()
    AutoFarmRequestRemote:FireServer("toggle")
    refreshFarmStatus()
    renderFarmTargetLabel()
end

local farmStatusRow,_ = rowBase(FarmP, "Farm Status", "Server-side Kriluni automation status.")
local farmStatusValue = Instance.new("TextLabel", farmStatusRow)
farmStatusValue.AnchorPoint = Vector2.new(1, 0.5)
farmStatusValue.BackgroundTransparency = 1
farmStatusValue.Position = UDim2.new(1, -16, 0.5, 0)
farmStatusValue.Size = UDim2.new(0, 190, 0, 30)
farmStatusValue.Font = Enum.Font.GothamMedium
farmStatusValue.Text = "Waiting for Kriluni remotes…"
farmStatusValue.TextColor3 = T.Warn
farmStatusValue.TextSize = 14
farmStatusValue.TextXAlignment = Enum.TextXAlignment.Right
farmStatusValue.TextYAlignment = Enum.TextYAlignment.Center
farmStatusValue.TextTruncate = Enum.TextTruncate.AtEnd
FarmUI.statusValue = farmStatusValue

local farmTargetRow,_ = rowBase(FarmP, "Current Target", "Nearest Kriluni the server is moving toward or attacking.")
local farmTargetValue = Instance.new("TextLabel", farmTargetRow)
farmTargetValue.AnchorPoint = Vector2.new(1, 0.5)
farmTargetValue.BackgroundTransparency = 1
farmTargetValue.Position = UDim2.new(1, -16, 0.5, 0)
farmTargetValue.Size = UDim2.new(0, 190, 0, 30)
farmTargetValue.Font = Enum.Font.Gotham
farmTargetValue.Text = "(none)"
farmTargetValue.TextColor3 = T.Subtle
farmTargetValue.TextSize = 14
farmTargetValue.TextXAlignment = Enum.TextXAlignment.Right
farmTargetValue.TextYAlignment = Enum.TextYAlignment.Center
farmTargetValue.TextTruncate = Enum.TextTruncate.AtEnd
FarmUI.targetValue = farmTargetValue

local farmToggle = mkButton(FarmP, "Toggle Kriluni Farm", function()
    requestAutoFarmToggle()
end, {
    buttonText = "Start",
    backgroundColor = T.Accent,
    hoverColor = T.Neon,
    textColor = T.Text,
}, "Start or stop the server-authoritative Kriluni farm loop. All targeting and rewards stay server-side.")
FarmUI.toggleRow = farmToggle.Row
FarmUI.toggleButton = farmToggle.Button

refreshFarmStatus()
renderFarmTargetLabel()
resolveAutoFarmRemotes()

local ESPColorPresets = {
    {label = "Crimson Pulse", value = Color3.fromRGB(255, 70, 70)},
    {label = "Solar Gold", value = Color3.fromRGB(255, 255, 0)},
    {label = "Toxic Lime", value = Color3.fromRGB(0, 255, 140)},
    {label = "Electric Azure", value = Color3.fromRGB(90, 190, 255)},
    {label = "Aurora Cyan", value = Color3.fromRGB(70, 255, 255)},
    {label = "Royal Violet", value = Color3.fromRGB(180, 110, 255)},
    {label = "Sunburst", value = Color3.fromRGB(255, 170, 60)},
    {label = "Frostbite", value = Color3.fromRGB(210, 235, 255)},
}

-- create tabs (avoid firing signals programmatically)
tabButton("Kriluni Farm", FarmP)
tabButton("Aimbot", AimbotP)
tabButton("ESP", ESPP)
tabButton("Visuals", VisualP)
tabButton("Misc", MiscP)
tabButton("Config", ConfP)
-- make Aimbot page visible by default
AimbotP.Visible = true

-- Aimbot block
mkToggle(AimbotP,"Enable Aimbot", AA.Enabled, function(v) AA.Enabled=v end, "Turns the aimbot feature on or off.")
mkToggle(AimbotP,"Require Right Mouse (hold)", AA.RequireRMB, function(v) AA.RequireRMB=v end, "Only activates the aimbot while the right mouse button is held down.")
mkToggle(AimbotP,"Wall Check (line of sight)", AA.WallCheck, function(v) AA.WallCheck=v end, "Skips targets that are blocked by walls or other geometry.")
mkToggle(AimbotP,"Show FOV", AA.ShowFOV, function(v) AA.ShowFOV=v end, "Displays the aiming field-of-view circle on your screen.")
mkSlider(AimbotP,"FOV Radius", 40, 500, AA.FOVRadiusPx, function(x) AA.FOVRadiusPx=math.floor(x) end,"px", "Sets the radius of the aim assist field-of-view circle in pixels.")
mkSlider(AimbotP,"Deadzone Padding", 0, 20, AA.Deadzone, function(x) AA.Deadzone=x end,"px", "Defines an inner deadzone where the aimbot will not move the camera.")
mkSlider(AimbotP,"Strength (lower=stronger)", 0.05, 0.40, AA.Strength, function(x) AA.Strength=x end,nil, "Controls how strongly the camera lerps toward the target (lower means snappier).")
mkSlider(AimbotP,"Max Distance", 50, 1000, AA.MaxDistance, function(x) AA.MaxDistance=math.floor(x) end,"studs", "Limits aiming to targets within this distance.")
mkSlider(AimbotP,"Min Distance Gate", 0, 250, AA.MinDistance, function(x) AA.MinDistance=math.floor(x) end,"studs", "Ignores targets that are closer than this distance.")
local targetPriority = mkCycle(AimbotP,"Target Priority", {
    {label="Hybrid (angle+distance)", value="Hybrid"},
    {label="Closest Angle", value="Angle"},
    {label="Closest Distance", value="Distance"},
    {label="Lowest Health", value="Health"},
}, AA.TargetSort, function(val) AA.TargetSort=val end, "Chooses how potential targets are ranked before aiming.")
local distanceWeight = mkSlider(AimbotP,"Hybrid Distance Weight", 0, 0.08, AA.DistanceWeight, function(x) AA.DistanceWeight=x end,nil, "Adjusts how much distance influences the hybrid priority mode.")
local dynamicPartToggle
dynamicPartToggle = mkToggle(AimbotP,"Auto Bone Selection", AA.DynamicPart, function(v) AA.DynamicPart=v end, "Automatically chooses which body part to aim at based on target movement.")
local partCycle = mkCycle(AimbotP,"Manual Target Bone", {"Head","UpperTorso","HumanoidRootPart"}, AA.PartName, function(val) AA.PartName=val end, "Selects the specific body part to aim at when auto selection is disabled.")
local stickyToggle = mkToggle(AimbotP,"Sticky Aim (keep last target)", AA.StickyAim, function(v)
    AA.StickyAim=v
    if not v then stickyTarget=nil; stickyTimer=0 end
end, "Keeps following the most recent target for a short period even if they leave the FOV.")
local stickyDuration = mkSlider(AimbotP,"Sticky Duration", 0.1, 1.5, AA.StickTime, function(x)
    AA.StickTime=x
    stickyTimer = math.min(stickyTimer, AA.StickTime)
end,"s", "How long sticky aim should hold onto the previous target.")
local reactionDelay = mkSlider(AimbotP,"Reaction Delay", 0, 0.35, AA.ReactionDelay, function(x) AA.ReactionDelay=x end,"s", "Adds a delay before the aimbot begins to adjust toward a target.")
local reactionJitter = mkSlider(AimbotP,"Reaction Jitter", 0, 0.3, AA.ReactionJitter, function(x) AA.ReactionJitter=x end,"s", "Adds random variation to the reaction delay for a more human feel.")
local adaptiveToggle = mkToggle(AimbotP,"Adaptive Smoothing Boost", AA.AdaptiveSmoothing, function(v) AA.AdaptiveSmoothing=v end, "Boosts smoothing strength as enemies move closer to you.")
local closeBoost = mkSlider(AimbotP,"Close-range Boost", 0, 0.6, AA.CloseRangeBoost, function(x) AA.CloseRangeBoost=x end,nil, "Amount of extra smoothing applied when targets are nearby.")
local predictionSlider = mkSlider(AimbotP,"Lead Prediction", 0, 0.75, AA.Prediction, function(x) AA.Prediction=x end,"s", "Predicts where moving targets will be after this many seconds.")
local heightOffset = mkSlider(AimbotP,"Aim Height Offset", -2, 2, AA.VerticalOffset, function(x) AA.VerticalOffset=x end,"studs", "Shifts the aim point up or down relative to the target.")

setInteractable(stickyDuration.Row, AA.StickyAim)
setInteractable(closeBoost.Row, AA.AdaptiveSmoothing)
if partCycle and partCycle.Row then setInteractable(partCycle.Row, not AA.DynamicPart) end
if reactionJitter and reactionJitter.Row then setInteractable(reactionJitter.Row, (AA.ReactionDelay or 0) > 0) end
if distanceWeight and distanceWeight.Row then setInteractable(distanceWeight.Row, (AA.TargetSort or "Hybrid") == "Hybrid") end
RunService.RenderStepped:Connect(function()
    setInteractable(stickyDuration.Row, AA.StickyAim)
    setInteractable(closeBoost.Row, AA.AdaptiveSmoothing)
    if partCycle and partCycle.Row then setInteractable(partCycle.Row, not AA.DynamicPart) end
    if reactionJitter and reactionJitter.Row then setInteractable(reactionJitter.Row, (AA.ReactionDelay or 0) > 0) end
    if distanceWeight and distanceWeight.Row then setInteractable(distanceWeight.Row, (AA.TargetSort or "Hybrid") == "Hybrid") end
end)

-- ESP
mkToggle(ESPP,"Enable ESP", ESP.Enabled, function(v) ESP.Enabled=v end, "Turns highlight ESP visuals on or off.")
mkToggle(ESPP,"Enemies Only", ESP.EnemiesOnly, function(v) ESP.EnemiesOnly=v end, "Only shows ESP highlights on enemy players.")
mkToggle(ESPP,"Use Distance Limit", ESP.UseDistance, function(v) ESP.UseDistance=v end, "Restricts ESP to players within the max distance slider.")
mkSlider(ESPP,"Max Distance", 50, 2000, ESP.MaxDistance, function(x) ESP.MaxDistance=math.floor(x) end,"studs", "Sets the farthest distance that ESP highlights will appear.")
mkToggle(ESPP,"Render Through Walls", ESP.ThroughWalls, function(v) ESP.ThroughWalls=v end, "Forces highlight outlines to show even through walls.")
mkSlider(ESPP,"Fill Transparency", 0, 1, ESP.FillTransparency, function(x) ESP.FillTransparency=x end,nil, "Adjusts how solid the ESP highlight fill appears.")
mkSlider(ESPP,"Outline Transparency", 0, 1, ESP.OutlineTransparency, function(x) ESP.OutlineTransparency=x end,nil, "Adjusts how visible the ESP outline is.")
mkSlider(ESPP,"Color Intensity", 0.4, 1.6, ESP.ColorIntensity, function(x) ESP.ColorIntensity=x end,nil, "Boosts or softens highlight brightness for every player type.")
mkCycle(ESPP, "Enemy Highlight", ESPColorPresets, ESP.EnemyColor, function(col) ESP.EnemyColor = col end, "Choose the glow color used when enemies are highlighted.")
mkCycle(ESPP, "Friendly Highlight", ESPColorPresets, ESP.FriendColor, function(col) ESP.FriendColor = col end, "Select the highlight tint for teammates and allies.")
mkCycle(ESPP, "Neutral Highlight", ESPColorPresets, ESP.NeutralColor, function(col) ESP.NeutralColor = col end, "Pick the tone shown for players with no team alignment.")

-- Visuals
local crossT = mkToggle(VisualP,"Crosshair", Cross.Enabled, function(v) Cross.Enabled=v; updCross() end, "Shows or hides the custom crosshair overlay.")
mkSlider(VisualP,"Opacity", 0.1,1, Cross.Opacity, function(x) Cross.Opacity=x; updCross() end,nil, "Sets how transparent the crosshair appears.")
mkSlider(VisualP,"Size", 4,24, Cross.Size, function(x) Cross.Size=math.floor(x); updCross() end,nil, "Controls the overall length of the crosshair lines.")
mkSlider(VisualP,"Gap", 2,20, Cross.Gap, function(x) Cross.Gap=math.floor(x); updCross() end,nil, "Adjusts the gap between the crosshair arms and the center.")
mkSlider(VisualP,"Thickness", 1,6, Cross.Thickness, function(x) Cross.Thickness=math.floor(x); updCross() end,nil, "Changes how thick each crosshair arm is.")
local dotT = mkToggle(VisualP,"Center Dot", Cross.CenterDot, function(v) Cross.CenterDot=v; updCross() end, "Adds a dot to the middle of the crosshair.")
local dotS = mkSlider(VisualP,"Dot Size", 1,6, Cross.DotSize, function(x) Cross.DotSize=math.floor(x); updCross() end,nil, "Sets the size of the center dot.")
local dotO = mkSlider(VisualP,"Dot Opacity", 0.1,1, Cross.DotOpacity, function(x) Cross.DotOpacity=x; updCross() end,nil, "Controls the transparency of the center dot.")
local teamColorToggle
local rainbowToggle
teamColorToggle = mkToggle(VisualP,"Use Team Color", Cross.UseTeamColor, function(v)
    Cross.UseTeamColor=v
    if v and rainbowToggle then
        Cross.Rainbow=false
        rainbowToggle.Set(false)
    end
    updCross()
end, "Applies your current team color to the crosshair.")
rainbowToggle = mkToggle(VisualP,"Rainbow Cycle", Cross.Rainbow, function(v)
    Cross.Rainbow=v
    if v and teamColorToggle then
        Cross.UseTeamColor=false
        teamColorToggle.Set(false)
    end
    updCross()
end, "Cycles crosshair colors through a rainbow gradient.")
local rainbowSpeed = mkSlider(VisualP,"Rainbow Speed", 0.2, 3, Cross.RainbowSpeed, function(x) Cross.RainbowSpeed=x; updCross() end,nil, "Controls how quickly the rainbow effect animates.")
local pulseToggle = mkToggle(VisualP,"Pulse Opacity", Cross.Pulse, function(v) Cross.Pulse=v; updCross() end, "Makes the crosshair fade in and out repeatedly.")
local pulseSpeed = mkSlider(VisualP,"Pulse Speed", 0.5, 5, Cross.PulseSpeed, function(x) Cross.PulseSpeed=x; updCross() end,nil, "Sets the speed of the crosshair opacity pulse.")
RunService.RenderStepped:Connect(function()
    local on=Cross.CenterDot; setInteractable(dotS.Row,on); setInteractable(dotO.Row,on)
    if rainbowSpeed then setInteractable(rainbowSpeed.Row, Cross.Rainbow) end
    if pulseSpeed then setInteractable(pulseSpeed.Row, Cross.Pulse) end
end)

-- Misc
mkToggle(MiscP,"Press K to toggle UI", true, function() end, "Reminder that you can press K to hide or show the panel.")
local dragToggle = mkToggle(MiscP,"Allow Dragging", true, function(v)
    draggingEnabled = v
    if not v then dragging=false end
end, "Enables dragging the window around the screen.")
local centerBtn = mkButton(MiscP, "Center Panel", function()
    Root.Position = UDim2.fromScale(0.5,0.5)
    dragging = false
end, {buttonText="Center"}, "Recenters the panel on your screen.")
local scaleSlider = mkSlider(MiscP,"UI Scale", 0.85, 1.25, PanelScale.Scale, function(x) PanelScale.Scale=x end,"x", "Changes the overall size of the menu UI.")

local creditCard = Instance.new("Frame", MiscP)
creditCard.Name = "CreditsCard"
creditCard.BackgroundColor3 = T.Card
creditCard.Size = UDim2.new(0.5, -6, 0, 64)
corner(creditCard, 10)
stroke(creditCard, T.Stroke, 1, 0.25)

local creditPadding = Instance.new("UIPadding", creditCard)
creditPadding.PaddingLeft = UDim.new(0, 18)
creditPadding.PaddingRight = UDim.new(0, 18)
creditPadding.PaddingTop = UDim.new(0, 12)
creditPadding.PaddingBottom = UDim.new(0, 12)

local creditTitle = Instance.new("TextLabel", creditCard)
creditTitle.BackgroundTransparency = 1
creditTitle.Position = UDim2.new(0, 0, 0, 0)
creditTitle.Size = UDim2.new(1, -140, 0, 22)
creditTitle.Font = Enum.Font.GothamBold
creditTitle.Text = "Made by ProfitCruiser"
creditTitle.TextColor3 = T.Text
creditTitle.TextSize = 15
creditTitle.TextXAlignment = Enum.TextXAlignment.Left
creditTitle.TextYAlignment = Enum.TextYAlignment.Top

local creditSub = Instance.new("TextLabel", creditCard)
creditSub.BackgroundTransparency = 1
creditSub.Position = UDim2.new(0, 0, 0, 24)
creditSub.Size = UDim2.new(1, -140, 1, -28)
creditSub.Font = Enum.Font.Gotham
creditSub.Text = "Made by ProfitCruiser"
creditSub.TextColor3 = T.Subtle
creditSub.TextSize = 12
creditSub.TextWrapped = true
creditSub.TextXAlignment = Enum.TextXAlignment.Left
creditSub.TextYAlignment = Enum.TextYAlignment.Top

local discordBtn = Instance.new("TextButton", creditCard)
discordBtn.Name = "DiscordCopy"
discordBtn.AutoButtonColor = false
discordBtn.Size = UDim2.new(0, 120, 0, 34)
discordBtn.Position = UDim2.new(1, -132, 0.5, -17)
discordBtn.Font = Enum.Font.GothamBold
discordBtn.Text = "Discord"
discordBtn.TextColor3 = T.Text
discordBtn.TextSize = 14
discordBtn.BackgroundColor3 = T.Accent
corner(discordBtn, 12)
stroke(discordBtn, T.Stroke, 1, 0.3)

local discordHover = T.Neon
local discordBase = discordBtn.BackgroundColor3
discordBtn.MouseEnter:Connect(function()
    TweenService:Create(discordBtn, TweenInfo.new(0.12), {BackgroundColor3 = discordHover}):Play()
end)
discordBtn.MouseLeave:Connect(function()
    TweenService:Create(discordBtn, TweenInfo.new(0.12), {BackgroundColor3 = discordBase}):Play()
end)

local defaultSubText = creditSub.Text
local copySignal = 0
discordBtn.MouseButton1Click:Connect(function()
    copySignal += 1
    local ticket = copySignal
    local success = false
    if setclipboard then
        success = pcall(function()
            setclipboard(DISCORD_URL)
        end)
        success = success == true
    end
    if success then
        creditSub.Text = "Discord Link Copyed"
        creditSub.TextColor3 = T.Good
    else
        creditSub.Text = "Kunne ikke kopiere automatisk — bruk lenken: " .. DISCORD_URL
        creditSub.TextColor3 = T.Warn
    end
    TweenService:Create(creditSub, TweenInfo.new(0.12), {TextTransparency = 0}):Play()
    task.delay(1.6, function()
        if copySignal == ticket then
            creditSub.Text = defaultSubText
            creditSub.TextColor3 = T.Subtle
        end
    end)
end)

-- Kill Menu logic
local function killMenu()
    -- hide all UIs
    if Root then Root.Visible = false end
    if Gate then Gate.Enabled = false end
    if SuccessGui then SuccessGui.Enabled = false end
    if AA_GUI then AA_GUI.Enabled = false end
    if CrossGui then CrossGui.Enabled = false end
    -- remove blur
    TweenService:Create(Blur, TweenInfo.new(0.15), {Size = 0}):Play()
    Blur.Enabled = false
    -- disable features so runtime loops render nothing
    AA.Enabled=false; ESP.Enabled=false; Cross.Enabled=false; updCross()
    stickyTarget=nil; stickyTimer=0
    -- clean existing highlights
    for _,pl in ipairs(Players:GetPlayers()) do
        local ch = pl.Character
        if ch then local h = ch:FindFirstChild("_HL_"); if h then pcall(function() h:Destroy() end) end end
    end
end

-- panic key (P) also kills the menu
UserInputService.InputBegan:Connect(function(i)
    if i.KeyCode==Enum.KeyCode.K then Root.Visible = not Root.Visible end
    if i.KeyCode==Enum.KeyCode.P then killMenu() end
end)

-- Button to kill menu
mkButton(MiscP, "Kill Menu (remove UI)", function() killMenu() end, {danger=true, buttonText="Kill Menu"}, "Completely closes the UI and disables every feature until re-executed.")

-- Config / profiles
local BASE="ProfitCruiser"; local PROF=BASE.."/Profiles"; local MODE="memory"; local MEM=rawget(_G,"PC_ProfileStore") or {}; _G.PC_ProfileStore=MEM
local function ensure() if makefolder then local ok1=true if not (isfolder and isfolder(BASE)) then ok1=pcall(function() makefolder(BASE) end) end local ok2=true if not (isfolder and isfolder(PROF)) then ok2=pcall(function() makefolder(PROF) end) end return ok1 and ok2 end return false end
if ensure() and writefile and readfile then MODE="filesystem" end
local function deep(dst,src) for k,v in pairs(src) do if typeof(v)=="table" and typeof(dst[k])=="table" then deep(dst[k],v) else dst[k]=v end end end
local function gather() return {AA=AA, ESP=ESP, Cross=Cross} end
local function apply(s)
    if not s then return end
    deep(AA,s.AA or {})
    deep(ESP,s.ESP or {})
    deep(Cross,s.Cross or {})
    updCross()
end
local function save(name) local ok,data=pcall(function() return HttpService:JSONEncode(gather()) end); if not ok then return false,"encode" end if MODE=="filesystem" then local p=PROF.."/"..name..".json"; local s,err=pcall(function() writefile(p,data) end); return s,(s and nil or tostring(err)) else MEM[name]=data; return true end end
local function load(name) if MODE=="filesystem" then local p=PROF.."/"..name..".json"; if not (isfile and isfile(p)) then return false,"missing" end local ok,raw=pcall(function() return readfile(p) end); if not ok then return false,"read" end local ok2,tbl=pcall(function() return HttpService:JSONDecode(raw) end); if not ok2 then return false,"decode" end apply(tbl); return true else local raw=MEM[name]; if not raw then return false,"missing" end local ok2,tbl=pcall(function() return HttpService:JSONDecode(raw) end); if not ok2 then return false,"decode" end apply(tbl); return true end end

local saveBtn = mkToggle(ConfP,"Save Default (click)", false, function(v,row) if v then local ok,err=save("Default"); (row:FindFirstChildWhichIsA("TextLabel")).Text = ok and "Saved Default ✅" or ("Save failed: "..tostring(err)); task.delay(0.4,function() (row:FindFirstChildWhichIsA("TextLabel")).Text="Save Default (click)" end) end end, "Saves your current settings into the Default profile slot.")
local loadBtn = mkToggle(ConfP,"Load Default (click)", false, function(v,row) if v then local ok,err=load("Default"); (row:FindFirstChildWhichIsA("TextLabel")).Text = ok and "Loaded Default ✅" or ("Load failed: "..tostring(err)); task.delay(0.4,function() (row:FindFirstChildWhichIsA("TextLabel")).Text="Load Default (click)" end) end end, "Loads the Default profile back into all features.")
RunService.RenderStepped:Connect(function()
    if FarmState.PendingSince and (os.clock() - FarmState.PendingSince) >= 5 then
        FarmState.PendingSince = nil
        refreshFarmStatus()
    end
    renderFarmTargetLabel()
end)

-- Show panel when gate closes (only if allowed by flow)
Gate:GetPropertyChangedSignal("Enabled"):Connect(function()
    local on = Gate.Enabled
    TweenService:Create(Blur, TweenInfo.new(0.2), {Size = on and 8 or 0}):Play()
    Blur.Enabled = on or (not on and not allowReveal)
    -- Only reveal Root if gate closed AND the reveal flag was set (set after overlay finishes)
    if (not on) and allowReveal and Root then
        Root.Visible = true
    end
end)
