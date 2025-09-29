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
    TARGET_FOLDER_NAME = nil,     -- f.eks. "Enemies" eller nil (legacy)
    TARGET_FOLDERS = {
        { "Debris", "Monsters" }, -- tilpass til din verden (kan være strenger eller segmenttabeller)
    },
    TARGET_MODEL_NAMES = {},      -- eksakt navneliste (case-insensitive)
    TARGET_NAME_KEYWORDS = { "kriluni" }, -- matcher dersom navnet inneholder (case-insensitive)
    TARGET_NPC_IDS = { "Kriluni" },       -- matcher NPCId-attributt eller verdi
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

local function normalizeList(list)
    local normalized = {}
    if type(list) ~= "table" then
        return normalized
    end
    for _, value in ipairs(list) do
        if typeof(value) == "string" and value ~= "" then
            table.insert(normalized, string.lower(value))
        end
    end
    return normalized
end

local TARGET_MODEL_NAMES = normalizeList(CONFIG.TARGET_MODEL_NAMES)
local TARGET_NAME_KEYWORDS = normalizeList(CONFIG.TARGET_NAME_KEYWORDS)
local TARGET_NPC_IDS = normalizeList(CONFIG.TARGET_NPC_IDS)

local folderFiltersCache = nil
local folderFiltersCount = 0
local lastFolderRefresh = 0
local FOLDER_CACHE_WINDOW = 1.0

local function buildFolderFilters()
    local filters = {}
    local count = 0

    local function addFolder(folder)
        if folder and not filters[folder] then
            filters[folder] = true
            count += 1
        end
    end

    if CONFIG.TARGET_FOLDER_NAME then
        addFolder(workspace:FindFirstChild(CONFIG.TARGET_FOLDER_NAME))
    end

    if type(CONFIG.TARGET_FOLDERS) == "table" then
        for _, pathSpec in ipairs(CONFIG.TARGET_FOLDERS) do
            addFolder(resolveWorkspacePath(pathSpec))
        end
    end

    return filters, count
end

local function getFolderFilters()
    local now = os.clock()
    if folderFiltersCache and (now - lastFolderRefresh) <= FOLDER_CACHE_WINDOW then
        return folderFiltersCache, folderFiltersCount
    end

    local filters, count = buildFolderFilters()
    folderFiltersCache = filters
    folderFiltersCount = count
    lastFolderRefresh = now
    return filters, count
end

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

local function resolveWorkspacePath(pathSpec)
    if typeof(pathSpec) == "Instance" then
        return pathSpec
    end

    if type(pathSpec) == "string" then
        local current = workspace
        for segment in string.gmatch(pathSpec, "[^/]+") do
            current = current and current:FindFirstChild(segment)
        end
        return current
    end

    if type(pathSpec) == "table" then
        local current = workspace
        for _, segment in ipairs(pathSpec) do
            if typeof(segment) ~= "string" or segment == "" then
                return nil
            end
            current = current and current:FindFirstChild(segment)
        end
        return current
    end

    return nil
end

local function isTargetModel(model, requireAlive)
    if not model or not model:IsA("Model") then
        return false
    end

    local folderFilters, filterCount = getFolderFilters()
    if filterCount > 0 then
        local matchesFolder = false
        for folder in pairs(folderFilters) do
            if model:IsDescendantOf(folder) then
                matchesFolder = true
                break
            end
        end
        if not matchesFolder then
            return false
        end
    end

    if requireAlive ~= false and not isAlive(model) then
        return false
    end

    local hasFilters = CONFIG.ONLY_KRILUNI or (#TARGET_MODEL_NAMES > 0) or (#TARGET_NAME_KEYWORDS > 0) or (#TARGET_NPC_IDS > 0)
    if not hasFilters then
        return true
    end

    local nameLower = string.lower(model.Name)
    if CONFIG.ONLY_KRILUNI then
        if string.find(nameLower, "kriluni", 1, true) then
            return true
        end
        local ok, attr = pcall(function()
            return model:GetAttribute("NPCId")
        end)
        if ok and typeof(attr) == "string" and string.lower(attr) == "kriluni" then
            return true
        end
    end

    for _, exact in ipairs(TARGET_MODEL_NAMES) do
        if nameLower == exact then
            return true
        end
    end

    for _, keyword in ipairs(TARGET_NAME_KEYWORDS) do
        if string.find(nameLower, keyword, 1, true) then
            return true
        end
    end

    if #TARGET_NPC_IDS > 0 then
        local okAttr, attrValue = pcall(function()
            return model:GetAttribute("NPCId")
        end)
        if okAttr and typeof(attrValue) == "string" and table.find(TARGET_NPC_IDS, string.lower(attrValue)) then
            return true
        end

        local npcIdInstance = model:FindFirstChild("NPCId")
        if npcIdInstance and npcIdInstance:IsA("StringValue") then
            local lowerValue = string.lower(npcIdInstance.Value)
            if table.find(TARGET_NPC_IDS, lowerValue) then
                return true
            end
        end
    end

    return false
end

local function getLevel(model)
    if not model then return nil end
    local ok, v = pcall(function() return model:GetAttribute(CONFIG.LEVEL_ATTRIBUTE) end)
    if ok and typeof(v) == "number" then return v end
    local iv = model:FindFirstChild(CONFIG.LEVEL_ATTRIBUTE)
    if iv and iv:IsA("IntValue") then return iv.Value end
    return nil
end

local function forEachPotentialTarget(callback)
    local visited = {}

    local function consume(container)
        if not container or visited[container] then
            return
        end
        visited[container] = true
        for _, inst in ipairs(container:GetDescendants()) do
            if inst:IsA("Model") then
                callback(inst)
            end
        end
    end

    local folderFilters, filterCount = getFolderFilters()
    if filterCount > 0 then
        for folder in pairs(folderFilters) do
            consume(folder)
        end
    else
        consume(workspace)
    end
end

local function findNearestTarget(fromPos)
    local best, bestDist
    forEachPotentialTarget(function(inst)
        if isTargetModel(inst) then
            local hrp = inst:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then
                local d = (hrp.Position - fromPos).Magnitude
                if not best or d < bestDist then
                    best, bestDist = inst, d
                end
            end
        end
    end)
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
        AutoFarmUpdate:FireClient(player, {
            cmd = "goto",
            pos = hrp.Position,
            targetName = targetModel.Name,
            range = CONFIG.ATTACK_RANGE,
        })
    else
        AutoFarmUpdate:FireClient(player, { cmd = "clear" })
    end
end

-- === player state ===
local State = {}
local function initPlayer(p)
    State[p] = { enabled = false, target = nil, lastScan = 0 }
    AutoFarmUpdate:FireClient(p, { cmd = "status", enabled = false, range = CONFIG.ATTACK_RANGE })
end
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
            AutoFarmUpdate:FireClient(player, { cmd = "status", enabled = false, range = CONFIG.ATTACK_RANGE })
            AutoFarmUpdate:FireClient(player, { cmd = "clear" })
        else
            AutoFarmUpdate:FireClient(player, { cmd = "status", enabled = true, range = CONFIG.ATTACK_RANGE })
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

forEachPotentialTarget(function(inst)
    if isTargetModel(inst, false) then
        attachWatcher(inst)
    end
end)

workspace.DescendantAdded:Connect(function(d)
    if d:IsA("Folder") then
        folderFiltersCache = nil
    end
    if not d:IsA("Model") then
        return
    end
    task.defer(function()
        if isTargetModel(d, false) then
            attachWatcher(d)
        end
    end)
end)

workspace.DescendantRemoving:Connect(function(d)
    if d:IsA("Folder") then
        folderFiltersCache = nil
    end
end)

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
            st.target = select(1, findNearestTarget(hrpP.Position))
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
