print("CHAOS BUILD CHECK 319: anti-aim flags in the HUD indicator list")
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
c.manualStatic = control("real", 1, "switch", "Main / Static manual yaw", false)
c.hideNative = control("real", 1, "switch", "Main / Hide native menu", false)
c.style = control("real", 1, "combo", "Real / Style", {"Jitter", "Random", "Spin", "Native"})
c.range = control("real", 1, "slider", "Real / Jitter or random amplitude", 0, 180, 60)
c.hold = control("real", 1, "slider", "Real / Cycles per sample", 1, 8, 1)
c.spin = control("real", 1, "slider", "Real / Spin degrees per sample", 1, 180, 35)
c.pitch = control("real", 1, "combo", "Real / Pitch", {"Native", "Down", "Level", "Up"})
c.hideReal = control("real", 1, "combo", "Real / Hide head", {"Off", "Freestand", "Away from enemy"})
c.hideJitter = control("real", 1, "switch", "Real / Jitter while hidden", false)
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
c.shotFlip = control("fake", 1, "switch", "Fake / Flip on shot while fake walking", false)
c.shotFlipRange = control("fake", 1, "slider", "Fake / Flip amplitude", 0, 180, 90)
c.breaker = control("twist", 1, "switch", "LBY / Vary native decoy", false)
c.breakerRange = control("twist", 1, "slider", "LBY / Random amplitude", 0, 180, 25)
c.flick = control("twist", 1, "switch", "LBY / Alternate decoy offset", false)
c.flickRange = control("twist", 1, "slider", "LBY / Alternating amplitude", 0, 180, 110)
c.breakerHide = control("twist", 1, "combo", "LBY / Hide mode", {"Native", "Expose", "Hide", "Hide flick"})
c.lbyHold = control("twist", 1, "switch", "LBY / Hold real between updates", true)
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
c.lastmoveRepeat = control("real", 2, "switch", "Manual / Repeat last-move side", true)
local keys = {}
for _, direction in ipairs({"back", "left", "right", "forward"}) do
    keys[#keys + 1] = {name = direction, control = control("real", 2, "hotkey", "Direction / " .. direction)}
end
-- Toggling is done by the script on each press; the host key must report the physical hold.
for _, item in ipairs(keys) do item.control:set_mode("hold") end
c.clear = control("real", 2, "hotkey", "Direction / clear")
c.report = control("lag", 2, "button", "Diagnostics / Print status")
c.indicator = control("lag", 2, "switch", "Diagnostics / Indicator", true)
c.flags = control("lag", 2, "switch", "Diagnostics / Anti-aim flags", true)
c.shotLog = control("lag", 2, "switch", "Diagnostics / Log enemy shots", false)
local misc = ui.create("Misc", "Chaos AA", 1)
local logChoices = {"Chat", "Both", "Console"}
c.logOutput = misc and misc:combo("Log destination", logChoices)
    or control("lag", 2, "combo", "Diagnostics / Log destination", logChoices)
c.filterHelp = misc and misc:button("Print console filter commands")
-- Scripts cannot run console commands, so map spam is filtered by the user's con_filter and logs can go to chat instead.
local function chatSafe(text)
    -- Player names can carry invisible multi-byte tags; chat rejects broken or oversized UTF-8.
    return string.sub(string.gsub(text, "[\128-\255]", ""), 1, 240)
end
local function log(text)
    local output = c.logOutput:get()
    local chatted = output ~= 3 and client.in_game() and client.chat_print(chatSafe(text))
    if output ~= 1 or not chatted then print(text) end
end
c.spin:show_if(c.style, 3)
c.fakeRange:show_if(c.fake, 2)
c.shotFlipRange:show_if(c.shotFlip, 2)
c.breakerRange:show_if(c.breaker, 2)
c.flickRange:show_if(c.flick, 2)
c.twistRange:show_if(c.twist, 2)
for _, item in ipairs({c.extendMode, c.extendRange}) do item:show_if(c.extend, 2) end
for _, item in ipairs({c.lagMin, c.lagMax, c.fakewalkSync}) do item:show_if(c.packet, 2) end
c.manualMode:show_if(c.manual, 2)
for _, item in ipairs(keys) do item.control:show_if(c.manual, 2) end
c.clear:show_if(c.manual, 2)
local function tooltip(item, text)
    if item and type(item.set_tooltip) == "function" then item:set_tooltip(text) end
end
local tips = {
    enabled = "Enable Chaos. Requires native AA enabled.",
    manualStatic = "Off: Chaos jitter runs around the manual direction. On: a left, right or forward manual holds a static yaw.",
    hideNative = "Hide the built-in Anti-Aim menu. Off keeps every native feature reachable.",
    style = "Jitter alternates; Random samples; Spin rotates; Native adds no style offset.",
    range = "Yaw offset in degrees. 60 gives jitter offsets of -60 and +60.",
    hold = "Choke cycles to hold each real-angle sample. Higher means slower changes.",
    spin = "Degrees rotated per real-angle sample.",
    pitch = "Choose native pitch, down (+89), level (0), or up (-89).",
    hideReal = "Place the real head itself: Freestand turns it into cover from the closest enemy, Away points it straight away from them. The fake is sent opposite. Manual keys take priority.",
    hideJitter = "Let the real style jitter or spin around the hidden head instead of holding it still.",
    seed = "Change the repeatable random sequence.",
    baseMode = "Direction every angle builds on. Freestanding hides the head from the closest enemy; Edge puts it into a nearby wall. Falls back to native when nothing is found.",
    baseOffset = "Degrees added to the chosen base yaw.",
    profiles = "Use state-specific amplitudes instead of the main amplitude.",
    moving = "Apply Chaos yaw while walking or running.",
    extend = "Add a second yaw offset to the selected real style.",
    extendMode = "Choose a fixed, alternating, random, or rotating extra offset.",
    extendRange = "Extra offset in degrees; Spin uses this as its step.",
    fake = "Alternate a yaw offset on sent commands after choking. Chokes one command per cycle when nothing else chokes.",
    fakeRange = "Fake jitter offset in degrees on each side.",
    shotFlip = "While fake walking, every enemy shot at you flips the fake to the other side. Stacks with Fake jitter.",
    shotFlipRange = "Fake offset in degrees used by the shot flip.",
    breaker = "Randomize the native LBY decoy. Requires the native breaker.",
    breakerRange = "Maximum random offset added to the LBY decoy.",
    flick = "Alternate the native LBY decoy offset at native breaker timing.",
    flickRange = "Alternating LBY decoy offset in degrees.",
    breakerHide = "Native keeps the breaker's choice. Expose records the breaker yaw as real; Hide and Hide flick conceal it.",
    lbyHold = "While standing, real jitter, spin and freestanding change only at each LBY update, so the decoy stays away from the head.",
    twist = "Add an alternating offset when native moving twist runs.",
    twistRange = "Yaw offset added to native moving twist.",
    delay = "Enable native twist movement delay. Can hold back movement.",
    crank = "Enable native twist crank movement. Changes movement behavior.",
    packet = "Choose choke lengths between the limits. Native safety still applies.",
    lagMin = "Lowest requested choke count per cycle, limited by the host.",
    lagMax = "Highest requested choke count per cycle, limited by the host.",
    fakewalkSync = "Run the Chaos choke cadence during fake walk and ask fake walk to follow it.",
    manual = "Enable the script's manual-direction keys. Unbind the native manual keys to avoid both reacting.",
    manualMode = "Toggle: press a direction again to clear it. Hold: release to clear.",
    lastmoveRepeat = "Whether the native last-move side repeats. Off borrows the native setting until unload.",
    clear = "Clear the script's manual direction; base yaw returns to normal.",
    report = "Print angle state, cycle counters, and hook owners to the console.",
    indicator = "Show CHAOS in the HUD indicator list while alive.",
    flags = "Show anti-aim state flags in the HUD indicator list: MANUAL, HIDE, FAKE, CHOKE and FW FLIP. Green means active this moment.",
    shotLog = "Print each enemy shot at you with the anti-aim state and desync.",
    logOutput = "Where Chaos logs go. Chat (local only, never sent) keeps them out of engine console spam; falls back to console when chat is unavailable.",
    filterHelp = "Print the console commands that hide engine spam such as CMaterial::PrecacheVars.",
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
local alive, attached, chosen = false, false, nil
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
-- Each flag returns its text when it applies; active() decides green (working now) or red (armed).
local flagList = {
    {name = "chaos_manual", text = function() return chosen and "MANUAL " .. string.upper(chosen) end},
    {name = "chaos_hide", text = function() return c.hideReal:get() > 1 and "HIDE" end,
        active = function() return s.hidden end},
    {name = "chaos_fake", text = function() return (c.fake:get() or c.shotFlip:get() or s.hidden) and "FAKE" end,
        active = function(command) return s.fakeCommand ~= nil and command - s.fakeCommand < 16 end},
    {name = "chaos_choke", text = function() return c.packet:get() and s.lagTarget and "CHOKE " .. s.lagTarget end},
    {name = "chaos_flip", text = function() return c.shotFlip:get() and s.fakewalking and "FW FLIP" end},
}
if indicator then
    for _, flag in ipairs(flagList) do flag.handle = indicators.add(flag.name, "CHAOS") end
end
local function updateFlags(command, shown)
    for _, flag in ipairs(flagList) do
        local handle = flag.handle
        if handle then
            local text = shown and flag.text() or nil
            handle:set_enabled(text ~= nil and text ~= false)
            if text and text ~= flag.shownText then handle:set_text(text) end
            flag.shownText = text
            if text then handle:set_active(flag.active == nil or flag.active(command) == true) end
        end
    end
end
local function reset()
    s = {cycle = 0, fakeCycle = 0, command = nil, session = nil, previousLag = nil,
        breakerCount = 0, breakerKey = nil, realSamples = 0, fakeSamples = 0, flipSide = 1, lbyCycle = 0}
    parent = nil
end
reset()
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
local manualHead = {back = 180, left = 90, right = -90, forward = 0}
local hideTargets = {
    [2] = function() return rage.antiaim.get_freestanding("fov") end,
    [3] = function()
        local enemy = rage.antiaim.get_target("fov")
        return enemy and wrap(enemy + 180)
    end,
}
local function hiddenYaw(ctx)
    local resolve = hideTargets[c.hideReal:get()]
    if not resolve then return nil end
    -- Standing keeps the head where the last LBY update left it, matching the decoy placed for it.
    local holding = ctx.mode == "stand" and c.lbyHold:get()
    if holding and s.hideCycle == s.lbyCycle then return s.hideYaw end
    local yaw = resolve()
    if holding and yaw then s.hideCycle, s.hideYaw = s.lbyCycle, yaw end
    return yaw
end
local function onView(ctx)
    -- Manual is rotated in onAngles against the native base, so the base must stay native here.
    if chosen or (parent and parent.ctx.manual_direction > 0) then return end
    local holding = ctx.mode == "stand" and c.lbyHold:get()
    if holding and s.viewCycle == s.lbyCycle then ctx.result = {yaw = s.viewYaw}; return end
    local resolve = baseTargets[c.baseMode:get()]
    local yaw = resolve and resolve()
    local offset = c.baseOffset:get()
    if yaw == nil and offset == 0 then return end
    ctx.result = {yaw = wrap((yaw or ctx.native_yaw) + offset)}
    s.viewCycle, s.viewYaw = holding and s.lbyCycle or nil, ctx.result.yaw
end
local hitgroups = {[0] = "generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", [10] = "gear"}
local function onEnemyShot(ctx)
    if c.shotFlip:get() and (s.fakewalking or ctx.state == "fakewalk") then s.flipSide = -s.flipSide end
    if not c.shotLog:get() then return end
    log(string.format("Chaos AA: %s %s (%s, %d dmg, %.0fu) state=%s desync=%.1f real=%.1f fake=%.1f speed=%.0f",
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
    local owned = parent and parent.ctx.angles_allowed and ctx.result == nil
    if owned and (c.breaker:get() or c.flick:get()) then
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
    end
    local base = native(ctx)
    local hide = c.breakerHide:get() - 2
    if not owned or hide < 0 or type(base) ~= "table" then return end
    local result = table.clone(base)
    result.hide = hide
    ctx.result = result
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
local function realOffset(ctx, index, side)
    local amount = c.profiles:get() and profiles[ctx.mode]:get() or c.range:get()
    local style, offset = c.style:get(), 0
    if style == 1 then offset = side * amount
    elseif style == 2 then offset = sample(index, 1, amount)
    elseif style == 3 then offset = wrap(index * c.spin:get()) end
    if c.extend:get() then
        local mode, range = c.extendMode:get(), c.extendRange:get()
        local extra = range
        if mode == 2 then extra = side * range
        elseif mode == 3 then extra = sample(index, 2, range)
        elseif mode == 4 then extra = wrap(index * range) end
        offset = offset + extra
    end
    return offset
end
local function onAngles(ctx)
    prepare(ctx)
    local previous = parent
    parent = {ctx = ctx, manual = c.manualStatic:get() and (chosen ~= nil or ctx.manual_direction > 0)}
    local frame = parent
    -- Restore nesting state even if native dispatch raises an error.
    local ok, base = pcall(native, ctx)
    parent = previous
    if not ok then error(base) end
    if not ctx.angles_allowed or type(base) ~= "table" then return end
    local result = table.clone(base)
    local send = ctx.final_packet
    if s.sendCommand == ctx.command_number then send = s.send end
    local faking = send and ctx.lag > 0
    local flick = ctx.body_update or ctx.body_preupdate
    if flick and not s.inFlick then s.lbyCycle = s.lbyCycle + 1 end
    s.inFlick, s.fakewalking = flick, ctx.fakewalk
    if not flick and not faking then s.nativeReal = base.yaw end
    -- Moving the real must carry the native flick along, or the LBY decoy lands on the head.
    local override = chosen and wrap(ctx.view_yaw + manualHead[chosen]) or hiddenYaw(ctx)
    local anchor = base.yaw
    if override then
        local flickDelta = flick and wrap(base.yaw - (s.nativeReal or base.yaw)) or 0
        anchor = wrap(override + flickDelta)
    end
    result.yaw = anchor
    local pitch = c.pitch:get()
    if pitch == 2 then result.pitch = 89 elseif pitch == 3 then result.pitch = 0 elseif pitch == 4 then result.pitch = -89 end
    ctx.result = result
    if frame.manual or (ctx.mode == "walk" and not c.moving:get()) then return end
    if faking and not flick then
        if s.lastFake ~= ctx.command_number then
            s.lastFake = ctx.command_number
            s.fakeCycle = s.fakeCycle + 1
        end
        local fakeOffset = 0
        if c.fake:get() then fakeOffset = (s.fakeCycle % 2 == 0 and 1 or -1) * c.fakeRange:get() end
        if c.shotFlip:get() and ctx.fakewalk then fakeOffset = fakeOffset + s.flipSide * c.shotFlipRange:get() end
        -- A script-placed real sends its fake opposite; otherwise the fake would sit on the head.
        if override or fakeOffset ~= 0 then
            result.yaw = override and wrap(override + 180 + fakeOffset) or wrap(anchor + fakeOffset)
            s.fakeSamples, s.fakeCommand = s.fakeSamples + 1, ctx.command_number
        end
    else
        -- Standing hold samples once per LBY cycle so the real never drifts onto the decoy between updates.
        local index = (c.lbyHold:get() and ctx.mode == "stand") and s.lbyCycle or s.index
        s.hidden = override ~= nil and not chosen
        local hiddenStill = override and not chosen and not c.hideJitter:get()
        if not hiddenStill then result.yaw = wrap(anchor + realOffset(ctx, index, index % 2 == 0 and -1 or 1)) end
        if ctx.lag == 0 then s.realSamples = s.realSamples + 1 end
    end
    status = string.format("%s cmd=%d cycle=%d lby=%d lag=%d send=%s real=%d fake=%d yaw=%.1f",
        ctx.mode, ctx.command_number, s.cycle, s.lbyCycle, ctx.lag, tostring(send), s.realSamples, s.fakeSamples, result.yaw)
end
local function decidePacket(ctx)
    prepare(ctx)
    local base = native(ctx)
    local syncWalk = ctx.fakewalk and c.fakewalkSync:get()
    if not ctx.angles_allowed or (ctx.fakewalk and not syncWalk) or ctx.shot or ctx.old_shot
        or ctx.fresh_jump or ctx.landing or ctx.body_update or ctx.body_preupdate then return end
    if not c.packet:get() then
        -- Fake jitter needs a sent command after a choke; without fake lag nothing is ever choked.
        if c.fake:get() and base.send and ctx.lag == 0 then
            local result = table.clone(base)
            result.send = false
            ctx.result = result
        end
        return
    end
    -- Flush before the native deadline to allow a fresh animated first command.
    local deadline = ctx.body_update_time - ctx.time
    if ctx.mode == "stand" and deadline >= 0 and deadline <= ctx.tick_interval * 2 then return end
    local result = table.clone(base)
    result.send = ctx.lag >= math.min(s.lagTarget, ctx.max_lag)
    result.fakewalk_sync = syncWalk
    ctx.result = result
end
local function onPacket(ctx)
    decidePacket(ctx)
    -- Angles may run after this; let them read the real send decision instead of guessing.
    local decided = native(ctx)
    if type(decided) == "table" then s.sendCommand, s.send = ctx.command_number, decided.send end
end
local callbacks = {["antiaim.angles"] = onAngles, ["antiaim.packet"] = onPacket,
    ["antiaim.breaker"] = onBreaker, ["antiaim.twist"] = onTwist,
    ["antiaim.view"] = onView, ["antiaim.enemy_shot"] = onEnemyShot}
local function sync()
    local active = c.enabled:get()
    syncNativeMenu(active and c.hideNative:get())
    if active ~= attached then
        reset()
        for stage, callback in pairs(callbacks) do
            if active then hooks.set(stage, callback) else hooks.unset(stage) end
        end
        attached = active
    end
    movement(active and alive and c.moving:get())
    lastmoveRepeat(active)
    if indicator and type(indicator.set_enabled) == "function" then
        indicator:set_enabled(active and alive and c.indicator:get())
    end
end
events.tick:set(function(event)
    alive = event.in_game and event.alive
    sync()
    local useKeys = alive and c.enabled:get() and c.manual:get()
    local holding = c.manualMode:get() == 2
    local nextChoice = useKeys and not holding and chosen or nil
    for _, item in ipairs(keys) do
        local pressed = item.control:pressed()
        if useKeys then
            if holding then
                if item.control:active() then nextChoice = item.name end
            elseif pressed then
                nextChoice = nextChoice ~= item.name and item.name or nil
            end
        end
    end
    if c.clear:pressed() then nextChoice = nil end
    if nextChoice ~= chosen then
        chosen = nextChoice
        log("Chaos AA: manual " .. (chosen or "cleared"))
    end
    if not alive then reset(); status = "waiting for alive player" end
    updateFlags(event.command_number, alive and c.enabled:get() and c.flags:get())
end)
events.ui:set(function(event)
    sync()
    if event.kind == "click" and event.handle == c.report.__handle then
        log("Chaos AA 3.0: " .. status)
        log("Chaos AA manual: " .. (chosen or "none"))
        if type(hooks.owner) == "function" then
            for stage in pairs(callbacks) do log("Chaos AA " .. stage .. " owner: " .. tostring(hooks.owner(stage))) end
        end
    end
    if event.kind == "click" and c.filterHelp and event.handle == c.filterHelp.__handle then
        print("Chaos AA: paste into the console to hide map spam and keep other output:")
        print('con_filter_text ""; con_filter_enable 1; con_filter_text_out "CMaterial::PrecacheVars"')
        print("Chaos AA: or show only script logs:")
        print('con_filter_enable 1; con_filter_text "chaos_aa"')
        print("Chaos AA: undo with con_filter_enable 0")
    end
end)
sync()
print("Chaos AA 3.0: loaded. Controls on native pages, or Anti-Aim > script on older clients. Enable native AA; unload other AA scripts.")

