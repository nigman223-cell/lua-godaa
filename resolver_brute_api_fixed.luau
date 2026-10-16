-- Safe-angle-first resolver with miss-indexed brute force.
-- Uses the documented Divinity hook stage names directly.
-- Note: if this runtime reports hooks=nil, UI controls can appear but
-- resolver behavior cannot be changed until the host exposes the hooks API.

local group = ui.create("Ragebot", "Safe Angle Resolver", nil, "Resolver")
if not group then
    warn("Safe Angle Resolver: ui.create failed; controls were not created.")
    return
end

local enabled = group:switch("Enable resolver", true)
local safe_first = group:switch("Safe angle first", true)
local brute = group:switch("Auto brute counter", true)
local reset_on_hit = group:switch("Reset brute on hit", true)
local brute_steps = group:slider("Brute steps", 1, 7, 5)
local start_mode = group:combo("Initial angle", {
    "Body yaw",
    "Freestand if valid",
    "Away yaw",
    "Eye yaw"
})
local pattern_control = group:combo("Brute pattern", {
    "Balanced",
    "Wide",
    "Classic"
})
local debug_output = group:combo("Debug logs", {
    "Off",
    "Chat",
    "Console",
    "Chat + console"
})

local resolve_stages = {}
local feedback_stages = {}
local states = {}
local hooks_api = hooks

local DEBUG_PREFIX = "[SAR] "
local CHAT_LIMIT = 240
local CHAT_QUEUE_MAX = 16
local CHAT_LINES_PER_TICK = 1
local chat_queue = {}

local function sanitize(text)
    return (string.gsub(text, "[^%w %.,:;%-_%+%(%)%[%]#/]", "?"))
end

local function debug_log(message)
    local mode = debug_output:get()
    if mode == 1 then return end
    local line = DEBUG_PREFIX .. sanitize(message)
    if (mode == 2 or mode == 4) and #chat_queue < CHAT_QUEUE_MAX then
        chat_queue[#chat_queue + 1] = string.sub(line, 1, CHAT_LIMIT)
    end
    if mode == 3 or mode == 4 then
        print(line)
    end
end

local function flush_chat(event)
    if #chat_queue == 0 then return end
    if not event.in_game then
        chat_queue = {}
        return
    end
    for _ = 1, math.min(CHAT_LINES_PER_TICK, #chat_queue) do
        pcall(client.chat_print, table.remove(chat_queue, 1))
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

local function register_stage(stage, callback, bucket)
    local ok, err = pcall(function()
        hooks_api.set(stage, callback)
    end)
    if ok then
        bucket[#bucket + 1] = stage
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
    register_stage("resolver.resolve", on_resolve, resolve_stages)
    register_stage("resolver.feedback", on_feedback, feedback_stages)
else
    warn("Safe Angle Resolver: UI loaded, but hooks API is " .. type(hooks_api)
        .. ". The documented resolver stages cannot run in this runtime.")
end

events.tick:set(flush_chat)

events.shutdown:set(function(event)
    if hooks_available then
        for _, stage in ipairs(resolve_stages) do
            pcall(function() hooks_api.unset(stage) end)
        end
        for _, stage in ipairs(feedback_stages) do
            pcall(function() hooks_api.unset(stage) end)
        end
    end
    states = {}
    chat_queue = {}
end)

if hooks_available and #resolve_stages == 0 then
    warn("Safe Angle Resolver: resolver.resolve did not register; see the error above.")
end
if hooks_available and #feedback_stages == 0 then
    warn("Safe Angle Resolver: resolver.feedback did not register; brute learning cannot advance.")
end
