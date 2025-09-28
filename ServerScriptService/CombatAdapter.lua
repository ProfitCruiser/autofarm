local CombatAdapter = {}

-- mode = "HumanoidDamage" eller "Remote"
-- remoteApi: { remotesFolder, name, argStyle }
function CombatAdapter.DealDamage(config, remotesFolder, targetModel, amount, player)
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return end

    if (config.COMBAT_MODE or "HumanoidDamage") == "HumanoidDamage" then
        local hum = targetModel and targetModel:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            hum:TakeDamage(amount)
        end
        return
    end

    if config.COMBAT_MODE == "Remote" then
        local name = config.REMOTE_NAME or "DealDamage"
        local remote = remotesFolder and remotesFolder:FindFirstChild(name)
        if not remote or not remote:IsA("RemoteEvent") then return end

        local style = config.REMOTE_ARGS_STYLE or "TargetOnly"
        if style == "TargetOnly" then
            -- FireServer(targetModel) — tilpass hvis server forventer andre param
            remote:FireServer(targetModel)
        elseif style == "WithAmount" then
            remote:FireServer(targetModel, amount)
        else
            -- Custom: send tabell; kompisen må tilpasse til sin server-API
            remote:FireServer({ target = targetModel, dmg = amount, player = player })
        end
    end
end

return CombatAdapter
