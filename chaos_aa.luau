print("CHAOS BUILD CHECK 310: native base yaw, last-move repeat, fake walk sync, enemy shot log")
-- Chaos AA 3.0. Divinity LUAU_API.md, March 2018 first-command model.
-- Derived from chaos_aa_extend_jitter_lby: native base, jitter, Extend, LBY, twist.
-- Real samples advance by observed choke cycles, never command parity.
local c = {}
local groups = {}
local placementWarning = false
local function control(page, column, kind, label, ...)
    if type(ui.set) == "function" then
        local ok, item = pcall(ui.set, "Anti-Aim", page, column, kind, "Chaos | " .. label, ...)
        if ok and item ~= nil then return item end
    end
    if not placementWarning then
        placementWarning = true
        warn("Chaos AA: native-page placement unavailable; organized controls are on Anti-Aim > script.")
    end
    local section = string.match(label, "^([^/]+) / ") or page
    local key = section .. ":" .. tostring(column)
    if not groups[key] then
        groups[key] = assert(ui.create("Anti-Aim", "Chaos / " .. section, column), "Cannot create Chaos " .. section)
    end
    local group = groups[key]
    return assert(group[kind](group, label, ...), "Cannot create " .. label)
end
c.enabled = control("real", 1, "switch", "Main / Enable", true)
c.manualRespect = control("real", 1, "switch", "Main / Preserve manual direction", true)
c.style = control("real", 1, "combo", "Real / Style", {"Jitter", "Random", "Spin", "Native"})
c.range = control("real", 1, "slider", "Real / Jitter or random amplitude", 0, 180, 60)
c.hold = control("real", 1, "slider", "Real / Cycles per sample", 1, 8, 1)
c.spin = control("real", 1, "slider", "Real / Spin degrees per sample", 1, 180, 35)
c.pitch = control("real", 1, "combo", "Real / Pitch", {"Native", "Down", "Level", "Up"})
c.seed = control("real", 1, "slider", "Main / Random seed", 1, 10000, 1337)
c.baseMode = control("real", 1, "combo", "Base / Yaw target", {"Native", "At targets (FOV)", "At targets (distance)", "Freestanding", "Edge"})
c.baseOffset = control("real", 1, "slider", "Base / Yaw offset", -180, 180, 0)
c.profiles = control("real", 2, "switch", "Profiles / Separate movement amplitudes", false)
local profiles = {}
for _, entry in ipairs({{"stand", "Standing", 60}, {"walk", "Moving", 35}, {"duck", "Crouching", 45}, {"air", "Air", 75}}) do
    local item = control("real", 2, "slider", "Profiles / " .. entry[2], 0, 180, entry[3])
    item:show_if(c.profiles, 2)
    profiles[entry[1]] = item
end
c.moving = control("real", 2, "switch", "Profiles / Apply while moving", true)
c.extend = control("fake", 2, "switch", "Extend / Enable", false)
c.extendMode = control("fake", 2, "combo", "Extend / Mode", {"Static", "Jitter", "Random", "Spin"})
c.extendRange = control("fake", 2, "slider", "Extend / Amplitude", 0, 180, 30)
c.fake = control("fake", 1, "switch", "Fake / Jitter", false)
c.fakeRange = control("fake", 1, "slider", "Fake / Amplitude", 0, 180, 90)
c.breaker = control("twist", 1, "switch", "LBY / Vary native decoy", false)
c.breakerRange = control("twist", 1, "slider", "LBY / Random amplitude", 0, 180, 25)
c.flick = control("twist", 1, "switch", "LBY / Alternate decoy offset", false)
c.flickRange = control("twist", 1, "slider", "LBY / Alternating amplitude", 0, 180, 110)
c.twist = control("twist", 2, "switch", "Twist / Add yaw offset", false)
c.twistRange = control("twist", 2, "slider", "Twist / Amplitude", 0, 180, 30)
c.delay = control("twist", 2, "switch", "Twist / Delay movement", false)
c.crank = control("twist", 2, "switch", "Twist / Crank movement", false)
c.packet = control("lag", 1, "switch", "Packets / Override native cadence", false)
c.lagMin = control("lag", 1, "slider", "Packets / Minimum choke", 1, 14, 2)
c.lagMax = control("lag", 1, "slider", "Packets / Maximum choke", 1, 14, 6)
c.fakewalkSync = control("lag", 1, "switch", "Packets / Sync fake walk", false)
c.manual = control("real", 2, "switch", "Manual / Script keys", false)
c.manualMode = control("real", 2, "combo", "Manual / Key behavior", {"Toggle", "Hold"})
c.manualRemember = control("real", 2, "switch", "Manual / Remember direction while moving", true)
c.lastmoveRepeat = control("real", 2, "switch", "Manual / Repeat last-move side", true)
local keys = {}
for _, direction in ipairs({"back", "left", "right", "forward"}) do
    keys[#keys + 1] = {name = direction, control = control("real", 2, "hotkey", "Manual / " .. direction)}
end
c.clear = control("real", 2, "hotkey", "Manual / Clear")
c.report = control("lag", 2, "button", "Diagnostics / Print status")
c.indicator = control("lag", 2, "switch", "Diagnostics / Indicator", true)
c.shotLog = control("lag", 2, "switch", "Diagnostics / Log enemy shots", false)
c.spin:show_if(c.style, 3)
c.fakeRange:show_if(c.fake, 2)
c.breakerRange:show_if(c.breaker, 2)
c.flickRange:show_if(c.flick, 2)
c.twistRange:show_if(c.twist, 2)
for _, item in ipairs({c.extendMode, c.extendRange}) do item:show_if(c.extend, 2) end
for _, item in ipairs({c.lagMin, c.lagMax, c.fakewalkSync}) do item:show_if(c.packet, 2) end
c.manualMode:show_if(c.manual, 2)
c.manualRemember:show_if(c.manual, 2)
for _, item in ipairs(keys) do item.control:show_if(c.manual, 2) end
c.clear:show_if(c.manual, 2)
local function tooltip(item, text)
    if type(item.set_tooltip) == "function" then item:set_tooltip(text) end
end
local tips = {
    enabled = "Enable Chaos and hide native AA controls. Requires native AA enabled.",
    manualRespect = "Keep manual yaw; pitch and timed LBY flicks still apply.",
    style = "Jitter alternates; Random samples; Spin rotates; Native adds no style offset.",
    range = "Yaw offset in degrees. 60 gives jitter offsets of -60 and +60.",
    hold = "Choke cycles to hold each real-angle sample. Higher means slower changes.",
    spin = "Degrees rotated per real-angle sample.",
    pitch = "Choose native pitch, down (+89), level (0), or up (-89).",
    seed = "Change the repeatable random sequence.",
    baseMode = "Direction every angle builds on. Freestanding hides the head from the closest enemy; Edge puts it into a nearby wall. Falls back to native when nothing is found.",
    baseOffset = "Degrees added to the chosen base yaw.",
    profiles = "Use state-specific amplitudes instead of the main amplitude.",
    moving = "Apply Chaos yaw while walking or running.",
    extend = "Add a second yaw offset to the selected real style.",
    extendMode = "Choose a fixed, alternating, random, or rotating extra offset.",
    extendRange = "Extra offset in degrees; Spin uses this as its step.",
    fake = "Alternate a yaw offset on sent commands after choking.",
    fakeRange = "Fake jitter offset in degrees on each side.",
    breaker = "Randomize the native LBY decoy. Requires the native breaker.",
    breakerRange = "Maximum random offset added to the LBY decoy.",
    flick = "Alternate the native LBY decoy offset at native breaker timing.",
    flickRange = "Alternating LBY decoy offset in degrees.",
    twist = "Add an alternating offset when native moving twist runs.",
    twistRange = "Yaw offset added to native moving twist.",
    delay = "Enable native twist movement delay. Can hold back movement.",
    crank = "Enable native twist crank movement. Changes movement behavior.",
    packet = "Choose choke lengths between the limits. Native safety still applies.",
    lagMin = "Lowest requested choke count per cycle, limited by the host.",
    lagMax = "Highest requested choke count per cycle, limited by the host.",
    fakewalkSync = "Run the Chaos choke cadence during fake walk and ask fake walk to follow it.",
    manual = "Enable the script's manual-direction keys.",
    manualMode = "Toggle: press again to clear. Hold: release to clear.",
    lastmoveRepeat = "Whether the native last-move side repeats. Off borrows the native setting until unload.",
    manualRemember = "Remember the last manual key pressed while moving for native last-move flicks. Clear resets it.",
    clear = "Clear the script's selected manual direction.",
    report = "Print angle state, cycle counters, and hook owners to the console.",
    indicator = "Show CHAOS in the HUD indicator list while alive.",
    shotLog = "Print each enemy shot at you with the anti-aim state and desync.",
}
for name, text in pairs(tips) do tooltip(c[name], text) end
for state, item in pairs(profiles) do
    tooltip(item, "Jitter/random amplitude for " .. state .. ". Zero adds no style offset.")
end
for _, item in ipairs(keys) do tooltip(item.control, "Select manual " .. item.name .. " using the chosen key behavior.") end

local function wrap(yaw) return 180 - ((180 - yaw) % 360) end
local function sample(index, salt, range)
    local x = bit32.bxor(c.seed:get(), bit32.band(index * 1664525 + salt * 1013904223, 0xffffffff))
    x = bit32.bxor(x, bit32.lshift(x, 13))
    x = bit32.bxor(x, bit32.rshift(x, 17))
    x = bit32.bxor(x, bit32.lshift(x, 5))
    return (x / 4294967295 * 2 - 1) * range
end
local function native(ctx)
    if type(ctx.result) == "table" then return ctx.result end
    return ctx:original()
end
local s, parent = {}, nil
local alive, attached, chosen, ownsManual = false, false, nil, false
local rememberedManual, pendingManualPress, appliedLastmove = nil, nil, nil
local movementState = nil
local lastmoveRepeatState = nil
local nativeMenuHidden = false
local function syncNativeMenu(active)
    if active == nativeMenuHidden then return end
    if type(ui.hide) == "function" then
        if ui.hide("Anti-Aim", active) then nativeMenuHidden = active end
    end
end
local status = "waiting for alive player"
local indicator = type(indicators) == "table" and type(indicators.add) == "function"
    and indicators.add("chaos_aa3", "CHAOS") or nil
local function reset()
    rememberedManual = nil
    s = {cycle = 0, fakeCycle = 0, command = nil, session = nil, previousLag = nil,
        breakerCount = 0, breakerKey = nil, realSamples = 0, fakeSamples = 0}
    parent = nil
end
reset()
local function releaseManual()
    if ownsManual then rage.antiaim.set_manual(nil) end
    ownsManual, chosen = false, nil
    rememberedManual, pendingManualPress, appliedLastmove = nil, nil, nil
end
local function movement(enabled)
    local delay, crank = enabled and c.delay:get(), enabled and c.crank:get()
    local key = tostring(delay) .. ":" .. tostring(crank)
    if key ~= movementState then
        -- Do not borrow movement flags until a movement option is requested.
        if delay or crank or movementState ~= nil then rage.antiaim.set_twist_movement(delay, crank) end
        if delay or crank or movementState ~= nil then movementState = key end
    end
end
local function lastmoveRepeat(active)
    local wanted = not active or c.lastmoveRepeat:get()
    if wanted == lastmoveRepeatState then return end
    -- Same borrowing rule as movement: leave native untouched until asked.
    if wanted and lastmoveRepeatState == nil then return end
    rage.antiaim.set_lastmove_repeat(wanted)
    lastmoveRepeatState = wanted
end
local baseTargets = {
    [2] = function() return rage.antiaim.get_target("fov") end,
    [3] = function() return rage.antiaim.get_target("distance") end,
    [4] = function()
        local cover = rage.antiaim.get_freestanding("fov")
        return cover and wrap(cover + 180)
    end,
    [5] = function()
        local wall = rage.antiaim.edge()
        return wall and wrap(wall + 180)
    end,
}
local function onView(ctx)
    if parent and parent.manual then return end
    local resolve = baseTargets[c.baseMode:get()]
    local yaw = resolve and resolve()
    local offset = c.baseOffset:get()
    if yaw == nil and offset == 0 then return end
    ctx.result = {yaw = wrap((yaw or ctx.native_yaw) + offset)}
end
local hitgroups = {[0] = "generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", [10] = "gear"}
local function onEnemyShot(ctx)
    if not c.shotLog:get() then return end
    print(string.format("Chaos AA: %s %s (%s, %d dmg, %.0fu) state=%s desync=%.1f real=%.1f fake=%.1f speed=%.0f",
        ctx.name, ctx.hit and "hit" or "missed", hitgroups[ctx.hitgroup] or tostring(ctx.hitgroup), ctx.damage,
        ctx.distance, ctx.state, ctx.desync, ctx.real_yaw, ctx.fake_yaw, ctx.speed))
end
local function prepare(ctx)
    if s.session ~= ctx.session_id then reset(); s.session = ctx.session_id end
    if s.command == ctx.command_number then return end
    local fresh = s.command == nil or ctx.lag == 0 or (s.previousLag and ctx.lag < s.previousLag)
    s.command, s.previousLag = ctx.command_number, ctx.lag
    if fresh then
        s.cycle = s.cycle + 1
        s.index = math.floor((s.cycle - 1) / c.hold:get())
        s.side = s.index % 2 == 0 and -1 or 1
        local low = math.min(c.lagMin:get(), c.lagMax:get())
        local high = math.max(c.lagMin:get(), c.lagMax:get())
        s.lagTarget = math.clamp(math.floor((sample(s.cycle, 21, 1) + 1) * 0.5 * (high - low + 1)) + low, low, high)
    end
end
local function onBreaker(ctx)
    if parent then parent.breaker = true end
    -- Manual direction protects the ordinary yaw, but must not disable native LBY flicks.
    if not parent or not parent.ctx.angles_allowed or ctx.result ~= nil
        or (not c.breaker:get() and not c.flick:get()) then native(ctx); return end
    local key = tostring(s.session) .. ":" .. tostring(ctx.body_update_time)
    if s.breakerKey ~= key then
        s.breakerKey = key
        s.breakerCount = s.breakerCount + 1
        -- Capture once: native decoy is stored across calls and must not accumulate offsets.
        s.decoy = wrap(ctx.decoy
            + (c.breaker:get() and sample(s.breakerCount, 7, c.breakerRange:get()) or 0)
            + (c.flick:get() and (s.breakerCount % 2 == 0 and 1 or -1) * c.flickRange:get() or 0))
    end
    ctx.decoy = s.decoy
    ctx:original()
end
local function onTwist(ctx)
    if parent then parent.twist = true end
    local base = native(ctx)
    if not parent or parent.manual or not parent.ctx.angles_allowed or not c.twist:get()
        or not c.moving:get() or type(base) ~= "table" then return end
    local result = table.clone(base)
    result.yaw = wrap(base.yaw + s.side * c.twistRange:get())
    ctx.result = result
end
local function onAngles(ctx)
    prepare(ctx)
    -- tick has keys but no speed; this command's snapshot determines movement.
    if ownsManual then
        if not c.manualRemember:get() then rememberedManual = nil
        elseif pendingManualPress and ctx.grounded and ctx.speed > 0.1 and not ctx.fakewalk then
            rememberedManual = pendingManualPress
        end
        if appliedLastmove ~= rememberedManual then
            if rage.antiaim.set_manual(chosen, rememberedManual) then appliedLastmove = rememberedManual end
        end
    end
    pendingManualPress = nil
    local previous = parent
    parent = {ctx = ctx, manual = c.manualRespect:get() and ctx.manual_direction >= 0}
    local frame = parent
    -- Restore nesting state even if native dispatch raises an error.
    local ok, base = pcall(native, ctx)
    parent = previous
    if not ok then error(base) end
    if not ctx.angles_allowed or type(base) ~= "table" then return end
    local result = table.clone(base)
    local pitch = c.pitch:get()
    if pitch == 2 then result.pitch = 89 elseif pitch == 3 then result.pitch = 0 elseif pitch == 4 then result.pitch = -89 end
    ctx.result = result
    -- Manual direction protects yaw, not the independent pitch selection.
    -- Preserve timed LBY yaw; merely entering breaker/twist is not an LBY update.
    if frame.manual or (ctx.mode == "walk" and not c.moving:get())
        or ctx.body_update or ctx.body_preupdate then return end
    local send = ctx.final_packet
    if send and ctx.lag > 0 then
        if s.lastFake ~= ctx.command_number then
            s.lastFake = ctx.command_number
            s.fakeCycle = s.fakeCycle + 1
        end
        if c.fake:get() then
            result.yaw = wrap(base.yaw + (s.fakeCycle % 2 == 0 and 1 or -1) * c.fakeRange:get())
            s.fakeSamples = s.fakeSamples + 1
        end
    elseif ctx.lag == 0 then
        local amount = c.profiles:get() and profiles[ctx.mode]:get() or c.range:get()
        local style, offset = c.style:get(), 0
        if style == 1 then offset = s.side * amount
        elseif style == 2 then offset = sample(s.index, 1, amount)
        elseif style == 3 then offset = wrap(s.index * c.spin:get()) end
        if c.extend:get() then
            local mode, range = c.extendMode:get(), c.extendRange:get()
            local extra = range
            if mode == 2 then extra = s.side * range
            elseif mode == 3 then extra = sample(s.index, 2, range)
            elseif mode == 4 then extra = wrap(s.index * range) end
            offset = offset + extra
        end
        result.yaw = wrap(base.yaw + offset)
        s.realSamples = s.realSamples + 1
    end
    ctx.result = result
    status = string.format("%s cmd=%d cycle=%d side=%d lag=%d send=%s real=%d fake=%d yaw=%.1f",
        ctx.mode, ctx.command_number, s.cycle, s.side, ctx.lag, tostring(send), s.realSamples, s.fakeSamples, result.yaw)
end
local function onPacket(ctx)
    prepare(ctx)
    local base = native(ctx)
    local syncWalk = ctx.fakewalk and c.fakewalkSync:get()
    if not c.packet:get() or not ctx.angles_allowed or (ctx.fakewalk and not syncWalk) or ctx.shot or ctx.old_shot
        or ctx.fresh_jump or ctx.landing or ctx.body_update or ctx.body_preupdate then return end
    -- Flush before the native deadline to allow a fresh animated first command.
    local deadline = ctx.body_update_time - ctx.time
    if ctx.mode == "stand" and deadline >= 0 and deadline <= ctx.tick_interval * 2 then return end
    local result = table.clone(base)
    result.send = ctx.lag >= math.min(s.lagTarget, ctx.max_lag)
    result.fakewalk_sync = syncWalk
    ctx.result = result
end
local callbacks = {["antiaim.angles"] = onAngles, ["antiaim.packet"] = onPacket,
    ["antiaim.breaker"] = onBreaker, ["antiaim.twist"] = onTwist,
    ["antiaim.view"] = onView, ["antiaim.enemy_shot"] = onEnemyShot}
local function sync()
    local active = c.enabled:get()
    syncNativeMenu(active)
    if active ~= attached then
        reset()
        for stage, callback in pairs(callbacks) do
            if active then hooks.set(stage, callback) else hooks.unset(stage) end
        end
        attached = active
    end
    if not active or not c.manual:get() or not alive then releaseManual() end
    movement(active and alive and c.moving:get())
    lastmoveRepeat(active)
    if indicator and type(indicator.set_enabled) == "function" then
        indicator:set_enabled(active and alive and c.indicator:get())
    end
end
events.tick:set(function(event)
    alive = event.in_game and event.alive
    sync()
    pendingManualPress = nil
    local nextChoice = chosen
    local useKeys = alive and c.enabled:get() and c.manual:get()
    if c.manualMode:get() == 2 or not useKeys then nextChoice = nil end
    for _, item in ipairs(keys) do
        local pressed = item.control:pressed()
        if useKeys then
            if pressed then pendingManualPress = item.name end
            if c.manualMode:get() == 2 then
                if item.control:active() then nextChoice = item.name end
            elseif pressed then
                if nextChoice == item.name then nextChoice = nil else nextChoice = item.name end
            end
        end
    end
    if c.clear:pressed() then nextChoice = nil end
    if nextChoice ~= chosen then
        if nextChoice then
            if rage.antiaim.set_manual(nextChoice, rememberedManual) then
                chosen, ownsManual = nextChoice, true
                appliedLastmove = rememberedManual
            end
        else releaseManual() end
    end
    if not alive then reset(); status = "waiting for alive player" end
end)
events.ui:set(function(event)
    sync()
    if event.kind == "click" and event.handle == c.report.__handle then
        print("Chaos AA 3.0: " .. status)
        print("manual:", chosen or "none", "last moving direction:", rememberedManual or "none")
        if type(hooks.owner) == "function" then
            for stage in pairs(callbacks) do print(stage, "last owner:", hooks.owner(stage)) end
        end
    end
end)
events.shutdown:set(function()
    releaseManual()
    -- The host restores this script's built-in menu hides during release.
end)
sync()
print("Chaos AA 3.0: loaded. Controls on native pages, or Anti-Aim > script on older clients. Enable native AA; unload other AA scripts.")

