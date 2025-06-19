HygieneManager = {}

function HygieneManager.consumeHygieneProduct()
    local player = getPlayer()
    local stats = player:getStats()
    local bodyDamage = player:getBodyDamage()
    local groin = bodyDamage:getBodyPart(BodyPartType.Groin)

    if groin:bandaged() then
        current_bandageLife = groin:getBandageLife()
        print("Bandage life before consuming hygiene product: " .. current_bandageLife)
        groin:setBandageLife(current_bandageLife - 0.1)
    else
        print("Groin is not bandaged, cannot consume hygiene product.")
        return false
    end
    return true
end

return HygieneManager