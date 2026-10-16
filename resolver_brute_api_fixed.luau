-- Safe-angle-first resolver with miss-indexed brute force.
-- Uses the documented Divinity hook stage names directly.
-- Note: if this runtime reports hooks=nil, UI controls can appear but
-- resolver behavior cannot be changed until the host exposes the hooks API.

local group = ui.create("Ragebot", "Safe Angle Resolver", nil, "Resolver")
if not group then
    warn("Safe Angle Resolver: ui.create failed; controls were not created.")
    return
end

local function per_weapon(control)
    pcall(function() control:per_weapon() end)
    return control
end

local enabled = group:switch("Enable resolver", true)
local safe_first = group:switch("Safe angle first", true)
local brute = group:switch("Auto brute counter", true)
local reset_on_hit = group:switch("Reset brute on hit", true)
local keep_confident = group:switch("Keep confident native angle", true)
local confident_miss_limit = per_weapon(group:slider("Brute confident after misses (0 = never)", 0, 6, 2))
confident_miss_limit:show_if(keep_confident, 2)
local brute_steps = per_weapon(group:slider("Brute steps", 1, 7, 5))
local start_mode = per_weapon(group:combo("Initial angle", {
    "Body yaw",
    "Freestand if valid",
    "Away yaw",
    "Eye yaw"
}))
local pattern_control = per_weapon(group:combo("Brute pattern", {
    "Balanced",
    "Wide",
    "Classic"
}))
local damage_overrides = group:switch("Min damage overrides", true)
local low_hp = per_weapon(group:slider("Low HP below (0 = off)", 0, 100, 30))
local low_resolve = group:combo("Low resolve trigger", {
    "Off",
    "Very low",
    "Low or worse"
})
local low_resolve_damage = per_weapon(group:slider("Low resolve damage", 1, 100, 15))
low_hp:show_if(damage_overrides, 2)
low_resolve:show_if(damage_overrides, 2)
low_resolve_damage:show_if(damage_overrides, 2)
local debug_console = group:switch("Debug console logs", false)

local registered = {}
local states = {}
local last_override = nil
local hooks_api = hooks

local DEBUG_PREFIX = "[SAR] "

local function sanitize(text)
    return (string.gsub(text, "[^%w %.,:;%-_%+%(%)%[%]#/]", "?"))
end

local function debug_log(message)
    if debug_console:get() then
        print(DEBUG_PREFIX .. sanitize(message))
    end
end

local function norm(yaw)
    if type(yaw) ~= "number" then return 0 end
    yaw = yaw % 360
    if yaw > 180 then yaw = yaw - 360 end
    if yaw < -180 then yaw = yaw + 360 end
    return yaw
end

local function state_key(ctx)
    return tostring(ctx.index) .. ":" .. tostring(ctx.generation)
end

local function get_state(ctx)
    local key = state_key(ctx)
    local s = states[key]
    if not s then
        s = { misses = 0, last_record = nil, last_shot_id = nil, last_step = nil }
        states[key] = s
    end
    return s
end

local patterns = {
    { 58, -58, 90, -90, 120, -120, 180 },
    { 90, -90, 120, -120, 58, -58, 180 },
    { -58, 58, 180, -90, 90, -120, 120 }
}

local function base_yaw(ctx)
    -- Combo values are one-based: 1=Body, 2=Freestand, 3=Away, 4=Eye.
    local mode = start_mode:get()
    if mode == 2 and ctx.freestand_valid == true then
        return norm(ctx.freestand_yaw)
    elseif mode == 3 then
        return norm(ctx.away_yaw)
    elseif mode == 4 then
        return norm(ctx.eye_yaw)
    end
    return norm(ctx.body_yaw)
end

local function build_candidates(ctx)
    local result = ctx.result
    local supplied = result and result.candidates or nil
    local candidates = {}
    local base = base_yaw(ctx)

    if safe_first:get() then
        candidates[#candidates + 1] = { yaw = base, weight = 1.0, hypothesis = 0 }
    end

    -- Combo values are one-based, so do not add one here.
    local offsets = patterns[pattern_control:get()] or patterns[1]
    for i, offset in ipairs(offsets) do
        candidates[#candidates + 1] = {
            yaw = norm(base + offset),
            weight = 1.0 / (i + 1),
            hypothesis = i
        }
    end

    if type(supplied) == "table" then
        for _, c in ipairs(supplied) do
            if type(c) == "table" and type(c.yaw) == "number" then
                local hypothesis = c.hypothesis
                if type(hypothesis) ~= "number" or hypothesis < 1 or hypothesis > 32 then
                    hypothesis = math.min(32, #candidates + 1)
                end
                local weight = type(c.weight) == "number" and c.weight or 0.5
                candidates[#candidates + 1] = {
                    yaw = norm(c.yaw),
                    weight = math.max(0.001, math.min(1, weight)),
                    hypothesis = math.floor(hypothesis)
                }
            end
        end
    end

    return candidates
end

local function result_mode(ctx)
    if ctx.direct_update == true then return 6 end
    if ctx.predicted_update == true then return 7 end
    if ctx.grounded ~= true then return 5 end
    if type(ctx.speed) == "number" and ctx.speed > 5 then return 1 end
    return 2
end

local function on_resolve(ctx)
    if not enabled:get() or type(ctx) ~= "table"
        or ctx.index == nil or ctx.generation == nil then
        return
    end

    -- The native API says overrides are ignored when overridable is false.
    if ctx.overridable ~= true then return end

    local s = get_state(ctx)
    local limit = confident_miss_limit:get()
    if keep_confident:get() and (limit == 0 or s.misses < limit) then
        local native = ctx:original()
        if type(native) == "table" and native.confidence == 2 then
            if s.last_step ~= "native" then
                s.last_step = "native"
                debug_log(string.format("#%s keeping confident native yaw %.0f misses %d",
                    tostring(ctx.index), tonumber(native.yaw) or 0, s.misses))
            end
            return
        end
    end

    local candidates = build_candidates(ctx)
    if #candidates == 0 then return end

    local step = 1
    if brute:get() and s.misses > 0 then
        local window = math.min(brute_steps:get() + 1, #candidates)
        step = (s.misses % window) + 1
    end
    local chosen = candidates[step] or candidates[1]

    ctx.result = ctx.result or {}
    ctx.result.yaw = chosen.yaw
    ctx.result.mode = result_mode(ctx)
    ctx.result.hypothesis = chosen.hypothesis
    -- API requires integer confidence 0..2, not the fractional candidate weight.
    ctx.result.confidence = (chosen.weight >= 0.75) and 2 or 1

    if s.last_step ~= step then
        s.last_step = step
        debug_log(string.format("#%s step %d/%d yaw %.0f hyp %d mode %d misses %d",
            tostring(ctx.index), step, #candidates, chosen.yaw,
            chosen.hypothesis, ctx.result.mode, s.misses))
    end

    s.last_record = ctx.record_id
end

local function on_feedback(ctx)
    if type(ctx) ~= "table" or ctx.index == nil or ctx.generation == nil then return end
    local s = get_state(ctx)

    if s.last_shot_id == ctx.shot_id then return end
    s.last_shot_id = ctx.shot_id

    if ctx.outcome == "resolver_miss" and brute:get() then
        s.misses = s.misses + 1
    elseif ctx.outcome == "hit" and reset_on_hit:get() then
        s.misses = 0
    end
    -- Spread, occlusion and unknown outcomes are not treated as resolver evidence.

    debug_log(string.format("%s: %s (%s) yaw %.0f hyp %s misses %d",
        tostring(ctx.name or ctx.index), tostring(ctx.outcome),
        tostring(ctx.unknown_cause or ctx.reason), tonumber(ctx.yaw) or 0,
        tostring(ctx.hypothesis), s.misses))
end

local function focus_target(targets)
    local best
    for _, target in pairs(targets) do
        if not best or target.fov < best.fov then best = target end
    end
    return best
end

local function override_damage(target)
    local damage
    local threshold = low_hp:get()
    if threshold > 0 and target.health <= threshold then
        damage = target.health
    end
    -- Combo values: 2 = very low (confidence 0), 3 = low or worse (confidence 0 or 1).
    local trigger = low_resolve:get()
    if trigger > 1 and target.resolver_confidence <= trigger - 2 then
        damage = math.min(damage or 200, low_resolve_damage:get())
    end
    return damage
end

local function on_target(ctx)
    if not damage_overrides:get() or type(ctx) ~= "table" or type(ctx.targets) ~= "table" then return end
    local target = focus_target(ctx.targets)
    local damage = target and override_damage(target)
    if not damage or damage >= ctx.damage then
        last_override = nil
        return
    end
    ctx.damage = math.max(1, damage)
    ctx:original()

    local key = tostring(target.index) .. ":" .. tostring(ctx.damage)
    if key ~= last_override then
        last_override = key
        debug_log(string.format("#%s min damage %s (hp %s, confidence %s)",
            tostring(target.index), tostring(ctx.damage), tostring(target.health),
            tostring(target.resolver_confidence)))
    end
end

local function register_stage(stage, callback)
    local ok, err = pcall(function()
        hooks_api.set(stage, callback)
    end)
    if ok then
        registered[stage] = true
        print("Safe Angle Resolver: registered " .. stage)
    else
        warn("Safe Angle Resolver: failed to register " .. stage .. ": " .. tostring(err))
    end
end

local hooks_available = type(hooks_api) == "table"
    and type(hooks_api.set) == "function"
    and type(hooks_api.unset) == "function"

if hooks_available then
    -- These names are explicitly documented by LUAU_API.md.
    register_stage("resolver.resolve", on_resolve)
    register_stage("resolver.feedback", on_feedback)
    register_stage("ragebot.target", on_target)
else
    warn("Safe Angle Resolver: UI loaded, but hooks API is " .. type(hooks_api)
        .. ". The documented resolver stages cannot run in this runtime.")
end

events.shutdown:set(function(event)
    if hooks_available then
        for stage in pairs(registered) do
            pcall(function() hooks_api.unset(stage) end)
        end
    end
    states = {}
end)

if hooks_available and not registered["resolver.resolve"] then
    warn("Safe Angle Resolver: resolver.resolve did not register; see the error above.")
end
if hooks_available and not registered["resolver.feedback"] then
    warn("Safe Angle Resolver: resolver.feedback did not register; brute learning cannot advance.")
end
