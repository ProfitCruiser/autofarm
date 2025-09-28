local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remotes folder (lages om den mangler)
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function ensureRemote(name)
    local r = Remotes:FindFirstChild(name)
    if not r then
        r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = Remotes
    end
    return r
end

local AutoFarmRequest = ensureRemote("AutoFarmRequest")
local AutoFarmUpdate  = ensureRemote("AutoFarmUpdate")

-- === CONFIG (tilpass her) ===
local CONFIG = {
    TARGET_FOLDER_NAME = nil,     -- f.eks. "Enemies" eller nil
    ONLY_KRILUNI = true,
    ATTACK_RANGE = 8,
    DPS = 40,
    SCAN_INTERVAL = 0.5,
    MAX_STEP = 1.0,
    CURRENCY_KEY = "Gold",
    BASE_REWARD_PER_KILL = 20,
    SCALE_REWARD_BY_LEVEL = true,
    LEVEL_ATTRIBUTE = "Level",
    COMBAT_MODE = "HumanoidDamage", -- "HumanoidDamage" eller "Remote"
    REMOTE_NAME = "DealDamage",
    REMOTE_ARGS_STYLE = "TargetOnly",
}

-- === require adapters (forutsetter modulene i samme mappe: ServerScriptService) ===
local ss = script.Parent
local CurrencyAdapter = nil
local CombatAdapter = nil
pcall(function() CurrencyAdapter = require(ss:WaitForChild("CurrencyAdapter")) end)
pcall(function() CombatAdapter = require(ss:WaitForChild("CombatAdapter")) end)

-- Fallback functions hvis modul mangler
local function awardCurrency(player, amount)
    if CurrencyAdapter and CurrencyAdapter.Award then
        return CurrencyAdapter.Award(player, CONFIG.CURRENCY_KEY, amount)
    end
    -- enkel fallback
    local ls = player:FindFirstChild("leaderstats")
    if not ls then ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player end
    local iv = ls:FindFirstChild(CONFIG.CURRENCY_KEY)
    if not iv then iv = Instance.new("IntValue"); iv.Name = CONFIG.CURRENCY_KEY; iv.Parent = ls end
    iv.Value = iv.Value + math.floor(amount or 0)
    return true
end

local function dealDamageTo(model, amount, player)
    if CombatAdapter and CombatAdapter.DealDamage then
        return CombatAdapter.DealDamage(CONFIG, Remotes, model, amount, player)
    end
    -- fallback direct
    local hum = model and model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then hum:TakeDamage(amount) end
end

-- === NPC helpers ===
local function isAlive(model)
    if not model or not model:IsA("Model") then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function isKriluni(model)
    if not model or not model:IsA("Model") then return false end
    if string.find(string.lower(model.Name), "kriluni") then return true end
    local ok, attr = pcall(function() return model:GetAttribute("NPCId") end)
    return ok and attr == "Kriluni"
end

local function getLevel(model)
    if not model then return nil end
    local ok, v = pcall(function() return model:GetAttribute(CONFIG.LEVEL_ATTRIBUTE) end)
    if ok and typeof(v) == "number" then return v end
    local iv = model:FindFirstChild(CONFIG.LEVEL_ATTRIBUTE)
    if iv and iv:IsA("IntValue") then return iv.Value end
    return nil
end

local function iterNPCs()
    if CONFIG.TARGET_FOLDER_NAME then
        local f = workspace:FindFirstChild(CONFIG.TARGET_FOLDER_NAME)
        if f then return f:GetDescendants() end
    end
    return workspace:GetDescendants()
end

local function findNearestKriluni(fromPos)
    local best, bestDist
    for _, inst in ipairs(iterNPCs()) do
        if inst:IsA("Model") and isAlive(inst) and (not CONFIG.ONLY_KRILUNI or isKriluni(inst)) then
            local hrp = inst:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then
                local d = (hrp.Position - fromPos).Magnitude
                if not best or d < bestDist then best, bestDist = inst, d end
            end
        end
    end
    return best, bestDist
end

local function pushGoto(player, targetModel)
    if not player then return end
    if not targetModel then
        AutoFarmUpdate:FireClient(player, { cmd = "clear" })
        return
    end
    local hrp = targetModel:FindFirstChild("HumanoidRootPart")
    if hrp then
        AutoFarmUpdate:FireClient(player, { cmd = "goto", pos = hrp.Position, targetName = targetModel.Name })
    else
        AutoFarmUpdate:FireClient(player, { cmd = "clear" })
    end
end

-- === player state ===
local State = {}
local function initPlayer(p) State[p] = { enabled = false, target = nil, lastScan = 0 } end
local function removePlayer(p) State[p] = nil end
Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(removePlayer)
for _,p in ipairs(Players:GetPlayers()) do initPlayer(p) end

-- === Remote control ===
AutoFarmRequest.OnServerEvent:Connect(function(player, action)
    local st = State[player]
    if not st then return end
    if action == "toggle" then
        st.enabled = not st.enabled
        if not st.enabled then
            st.target = nil
            AutoFarmUpdate:FireClient(player, { cmd = "status", enabled = false })
            AutoFarmUpdate:FireClient(player, { cmd = "clear" })
        else
            AutoFarmUpdate:FireClient(player, { cmd = "status", enabled = true })
        end
    end
end)

-- === on NPC died ===
local function onHumanoidDied(hum)
    local model = hum and hum.Parent
    if not model then return end
    for player, st in pairs(State) do
        if st.enabled and st.target == model then
            local reward = CONFIG.BASE_REWARD_PER_KILL
            if CONFIG.SCALE_REWARD_BY_LEVEL then
                local lv = getLevel(model)
                if lv and lv > 0 then reward = math.floor(reward * (1 + lv * 0.1)) end
            end
            awardCurrency(player, reward)
            st.target = nil
            AutoFarmUpdate:FireClient(player, { cmd = "clear" })
        end
    end
end

local function attachWatcher(model)
    if not model then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and not hum:GetAttribute("AF_W") then
        hum.Died:Connect(function() onHumanoidDied(hum) end)
        hum:SetAttribute("AF_W", true)
    end
end

for _,d in ipairs(iterNPCs()) do if d:IsA("Model") then attachWatcher(d) end end
workspace.DescendantAdded:Connect(function(d) if d:IsA("Model") then task.defer(function() attachWatcher(d) end) end end)

-- === main server tick ===
RunService.Heartbeat:Connect(function(dt)
    local now = os.clock()
    for player, st in pairs(State) do
        if not st.enabled then st.target = nil; goto cont end
        if not player.Character then st.target = nil; goto cont end
        local hrpP = player.Character:FindFirstChild("HumanoidRootPart")
        if not hrpP then st.target = nil; goto cont end

        local needScan = (not st.target) or (not isAlive(st.target)) or ((now - (st.lastScan or 0)) >= CONFIG.SCAN_INTERVAL)
        if needScan then
            st.lastScan = now
            st.target = select(1, findNearestKriluni(hrpP.Position))
            if st.target then pushGoto(player, st.target) else pushGoto(player, nil) end
        end

        local t = st.target
        if t and isAlive(t) then
            local hrpT = t:FindFirstChild("HumanoidRootPart")
            local humT = t:FindFirstChildOfClass("Humanoid")
            if hrpT and humT then
                local dist = (hrpT.Position - hrpP.Position).Magnitude
                if dist <= CONFIG.ATTACK_RANGE and humT.Health > 0 then
                    local step = math.min(dt, CONFIG.MAX_STEP)
                    local dmg = CONFIG.DPS * step
                    dealDamageTo(t, dmg, player)
                else
                    pushGoto(player, t)
                end
            end
        end
        ::cont::
    end
end)

print("[KriluniAutoFarm] server module loaded.")
