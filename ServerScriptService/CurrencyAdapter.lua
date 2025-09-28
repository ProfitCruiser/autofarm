local CurrencyAdapter = {}

local function getOrCreateInt(container, key)
    if not container then return nil end
    local v = container:FindFirstChild(key)
    if not v then
        v = Instance.new("IntValue")
        v.Name = key
        v.Value = 0
        v.Parent = container
    end
    return v
end

-- Award: prøver flere vanlige steder, returnerer true hvis ok
function CurrencyAdapter.Award(player, key, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return false end
    -- 1) leaderstats
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        local iv = ls:FindFirstChild(key)
        if iv and iv:IsA("IntValue") then iv.Value += amount; return true end
    end
    -- 2) Stats
    local stats = player:FindFirstChild("Stats")
    if stats then
        local iv = stats:FindFirstChild(key)
        if iv and iv:IsA("IntValue") then iv.Value += amount; return true end
    end
    -- 3) PlayerData / Data
    local pd = player:FindFirstChild("PlayerData") or player:FindFirstChild("Data")
    if pd and pd:IsA("Folder") then
        local iv = pd:FindFirstChild(key)
        if iv and iv:IsA("IntValue") then iv.Value += amount; return true end
    end
    -- 4) fallback: lag leaderstats og betal der
    if not ls then
        ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = player
    end
    local iv = ls:FindFirstChild(key)
    if not iv then iv = Instance.new("IntValue"); iv.Name = key; iv.Value = 0; iv.Parent = ls end
    iv.Value += amount
    return true
end

return CurrencyAdapter
