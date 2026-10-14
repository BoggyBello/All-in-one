-- All-in-One GUI v6
-- Fly / Click TP / No Ragdoll / Noclip / Inf Jump / Godmode / ESP / Speed / Fullbright / Anti-AFK
-- + Waypoint beacons / FOV+zoom / Spectate / Server hop / Death-spot TP / Share spots
-- Saved locations grouped by game, rebindable keys, saved config, Unload
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local TS = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local MarketplaceService = game:GetService("MarketplaceService")
local TeleportService = game:GetService("TeleportService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

-- unload previous copy if this script was already executed
local genv = (getgenv and getgenv()) or _G
if genv.AIO_UNLOAD then pcall(genv.AIO_UNLOAD) end

-- connection tracking (everything tracked here gets disconnected on unload)
local conns = {}
local unloaded = false
local function track(c) conns[#conns + 1] = c return c end

---------------------------------------------------------------- CONFIG
local FILE = "AllInOneGUI.json"
local defaults = {
    ToggleGUI   = Enum.KeyCode.RightShift,
    Fly         = Enum.KeyCode.F,
    FlyUp       = Enum.KeyCode.E,
    FlyDown     = Enum.KeyCode.Q,
    ClickTP     = Enum.KeyCode.LeftControl, -- hold + click
    NoRagdoll   = Enum.KeyCode.N,
    Noclip      = Enum.KeyCode.V,
    InfJump     = Enum.KeyCode.J,
    Godmode     = Enum.KeyCode.G,
    ESP         = Enum.KeyCode.B,
    Speed       = Enum.KeyCode.C,
    Fullbright  = Enum.KeyCode.L,
    AntiAFK     = false,
    Beacons     = Enum.KeyCode.H,
    FovZoom     = Enum.KeyCode.Z,
    QuickSave   = Enum.KeyCode.K,
    DeathBack   = Enum.KeyCode.X,
    StopSpectate= Enum.KeyCode.U,
    Unload      = false,
}
local binds = {}
for k, v in pairs(defaults) do binds[k] = v end

local flySpeed, walkSpeed, fovValue = 60, 50, 90
local reloadUrl = ""
local placeKey = tostring(game.PlaceId)
local allLocations = {}          -- [placeId] = { {name,x,y,z}, ... }
local gameNames = {}             -- [placeId] = "Game name"
local listening = nil
local refreshers, bindBtns = {}, {}
local function refreshAll() for _, f in ipairs(refreshers) do f() end end
local function keyName(k) return k and k.Name or "None" end
local function down(k) return k and UIS:IsKeyDown(k) end

local function save()
    if not writefile then return end
    pcall(function()
        -- only write games that actually have saved spots
        local locs, names = {}, {}
        for k, list in pairs(allLocations) do
            if type(list) == "table" and #list > 0 then
                locs[k] = list
                if gameNames[k] then names[k] = gameNames[k] end
            end
        end
        local t = {
            binds = {}, flySpeed = flySpeed, walkSpeed = walkSpeed, fovValue = fovValue,
            reloadUrl = reloadUrl, locations = locs, gameNames = names,
        }
        for k, v in pairs(binds) do t.binds[k] = v and v.Name or "" end
        writefile(FILE, HttpService:JSONEncode(t))
    end)
end

if isfile and readfile then
    pcall(function()
        if isfile(FILE) then
            local t = HttpService:JSONDecode(readfile(FILE))
            for k, v in pairs(t.binds or {}) do
                if defaults[k] ~= nil then
                    if v == "" then binds[k] = false
                    else
                        local okk, kc = pcall(function() return Enum.KeyCode[v] end)
                        if okk and kc then binds[k] = kc end
                    end
                end
            end
            if tonumber(t.flySpeed) then flySpeed = math.clamp(t.flySpeed, 1, 500) end
            if tonumber(t.walkSpeed) then walkSpeed = math.clamp(t.walkSpeed, 1, 500) end
            if tonumber(t.fovValue) then fovValue = math.clamp(t.fovValue, 30, 120) end
            if type(t.reloadUrl) == "string" then reloadUrl = t.reloadUrl end
            if type(t.locations) == "table" then allLocations = t.locations end
            if type(t.gameNames) == "table" then gameNames = t.gameNames end
        end
    end)
end
allLocations[placeKey] = allLocations[placeKey] or {}

-- which game's spots the Teleport tab is showing
local viewKey, browsing = placeKey, false
local function gameName(key) return gameNames[key] or ("Place " .. key) end

---------------------------------------------------------------- STATE
local flying, clickTPEnabled, noRagdoll, noclip, infJump = false, true, false, false, false
local godmode, espOn, speedOn, fbOn, antiAFK = false, false, false, false, false
local beaconsOn, fovZoom = false, false
local spectating, lastDeath, hopping = nil, nil, false
local espFolder
local rebuildLocList
local refreshBeacons
local setMoreStatus = function() end
local unload

local function getHum() local c = lp.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot() local c = lp.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function teleportTo(pos)       -- drops you slightly above the target
    local c = lp.Character
    if c then c:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0))) end
end
local function teleportExact(pos)
    local c = lp.Character
    if c then c:PivotTo(CFrame.new(pos)) end
end
local function goDeathSpot()
    if lastDeath then teleportExact(lastDeath + Vector3.new(0, 3, 0)) return true end
    return false
end

---------------------------------------------------------------- FLY
local flyBV, flyBG, flyConn
local function stopFly()
    flying = false
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    refreshAll()
end

local function startFly()
    local root, hum = getRoot(), getHum()
    if not root or not hum or hum.Health <= 0 then return end
    if flying then return end
    flying = true
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = root
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    flyBG.P = 9e4
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root
    hum.PlatformStand = true

    flyConn = RS.RenderStepped:Connect(function()
        local cam = workspace.CurrentCamera
        local r, h = getRoot(), getHum()
        if not r or not h or h.Health <= 0 or not cam then return stopFly() end
        local look = cam.CFrame.LookVector
        local flatLook = Vector3.new(look.X, 0, look.Z)
        flatLook = flatLook.Magnitude > 0 and flatLook.Unit or Vector3.new(0, 0, -1)
        local right = cam.CFrame.RightVector
        local flatRight = Vector3.new(right.X, 0, right.Z).Unit
        local m = h.MoveDirection
        local dir = look * m:Dot(flatLook) + right * m:Dot(flatRight)
        if down(binds.FlyUp) then dir += Vector3.new(0, 1, 0) end
        if down(binds.FlyDown) then dir -= Vector3.new(0, 1, 0) end
        flyBV.Velocity = dir * flySpeed
        flyBG.CFrame = CFrame.new(r.Position, r.Position + look)
    end)
    refreshAll()
end
local function setFly(v) if v then startFly() else stopFly() end end

---------------------------------------------------------------- NO RAGDOLL
local ragdollConns = {}
local function clearRagdollConns()
    for _, c in ipairs(ragdollConns) do c:Disconnect() end
    table.clear(ragdollConns)
end

local function applyNoRagdoll(char)
    clearRagdollConns()
    if not noRagdoll or not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    if not hum then return end
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    table.insert(ragdollConns, hum.StateChanged:Connect(function(_, new)
        if not noRagdoll then return end
        if hum.Health <= 0 or new == Enum.HumanoidStateType.Dead then return end
        local bad = new == Enum.HumanoidStateType.Ragdoll
            or new == Enum.HumanoidStateType.FallingDown
            or (new == Enum.HumanoidStateType.PlatformStanding and not flying)
        if bad then
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then root.Anchored = false end
        end
    end))
    table.insert(ragdollConns, hum.Died:Connect(clearRagdollConns))
end

local function setNoRagdoll(v)
    noRagdoll = v
    if v then
        applyNoRagdoll(lp.Character)
    else
        clearRagdollConns()
        local hum = getHum()
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end
    end
    refreshAll()
end

---------------------------------------------------------------- NOCLIP
local noclipOrig = {}
local noclipConn
local function setNoclip(v)
    noclip = v
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if v then
        noclipConn = RS.Stepped:Connect(function()
            local h = getHum()
            if not h or h.Health <= 0 then return end
            local c = lp.Character
            if not c then return end
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then
                    if noclipOrig[p] == nil then noclipOrig[p] = p.CanCollide end
                    p.CanCollide = false
                end
            end
        end)
    else
        for p, orig in pairs(noclipOrig) do
            if p.Parent then p.CanCollide = orig end
        end
        table.clear(noclipOrig)
    end
    refreshAll()
end

---------------------------------------------------------------- INF JUMP
track(UIS.JumpRequest:Connect(function()
    if infJump then
        local hum = getHum()
        if hum and hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))
local function setInfJump(v) infJump = v refreshAll() end

---------------------------------------------------------------- GODMODE (client-side only!)
local godConn
local function applyGod(char)
    if godConn then godConn:Disconnect() godConn = nil end
    if not godmode or not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    if not hum then return end
    godConn = hum.HealthChanged:Connect(function(h)
        if godmode and h > 0 and h < hum.MaxHealth then
            hum.Health = hum.MaxHealth
        end
    end)
    if hum.Health > 0 then hum.Health = hum.MaxHealth end
end
local function setGod(v)
    godmode = v
    if v then
        applyGod(lp.Character)
    elseif godConn then
        godConn:Disconnect() godConn = nil
    end
    refreshAll()
end

---------------------------------------------------------------- SPEED
local speedConn, origSpeed
local function setSpeed(v)
    speedOn = v
    if speedConn then speedConn:Disconnect() speedConn = nil end
    local hum = getHum()
    if v then
        if hum then origSpeed = hum.WalkSpeed end
        speedConn = RS.Heartbeat:Connect(function()
            local h = getHum()
            if h and h.Health > 0 then h.WalkSpeed = walkSpeed end
        end)
    else
        if hum and origSpeed then hum.WalkSpeed = origSpeed end
        origSpeed = nil
    end
    refreshAll()
end

---------------------------------------------------------------- FULLBRIGHT
local fbConn, lightOrig
local function setFullbright(v)
    fbOn = v
    if fbConn then fbConn:Disconnect() fbConn = nil end
    if v then
        lightOrig = {
            Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
            Ambient = Lighting.Ambient,
        }
        fbConn = RS.RenderStepped:Connect(function()
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.FogEnd = 1e6
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        end)
    elseif lightOrig then
        for k, val in pairs(lightOrig) do Lighting[k] = val end
        lightOrig = nil
    end
    refreshAll()
end

---------------------------------------------------------------- ANTI-AFK
track(lp.Idled:Connect(function()
    if antiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end))
local function setAntiAFK(v) antiAFK = v refreshAll() end

---------------------------------------------------------------- FOV + ZOOM
local fovConn, fovOrig
local function setFovZoom(v)
    fovZoom = v
    if fovConn then fovConn:Disconnect() fovConn = nil end
    local cam = workspace.CurrentCamera
    if v then
        fovOrig = {fov = cam and cam.FieldOfView or 70, zoom = lp.CameraMaxZoomDistance}
        fovConn = RS.RenderStepped:Connect(function()
            local c = workspace.CurrentCamera
            if c then c.FieldOfView = fovValue end
            lp.CameraMaxZoomDistance = 1000
        end)
    elseif fovOrig then
        if cam then cam.FieldOfView = fovOrig.fov end
        lp.CameraMaxZoomDistance = fovOrig.zoom
        fovOrig = nil
    end
    refreshAll()
end

---------------------------------------------------------------- ESP
local espObjs = {}
local espConn
local function removeESP(p)
    local o = espObjs[p]
    if o then
        o.hl:Destroy() o.bb:Destroy()
        espObjs[p] = nil
    end
end

local function buildESP(p)
    if p == lp or espObjs[p] or not espFolder then return end
    local ch = p.Character
    local head = ch and ch:FindFirstChild("Head")
    if not head then return end
    local col = (p.Team and p.TeamColor.Color) or Color3.fromRGB(255, 70, 70)

    local hl = Instance.new("Highlight")
    hl.Adornee = ch
    hl.FillColor = col
    hl.FillTransparency = 0.65
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = espFolder

    local bb = Instance.new("BillboardGui")
    bb.Adornee = head
    bb.Size = UDim2.new(0, 170, 0, 34)
    bb.StudsOffset = Vector3.new(0, 2.6, 0)
    bb.AlwaysOnTop = true
    bb.Parent = espFolder

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = col
    lbl.TextStrokeTransparency = 0.3
    lbl.Font = Enum.Font.SourceSansBold
    lbl.TextSize = 15
    lbl.Parent = bb

    espObjs[p] = {hl = hl, bb = bb, lbl = lbl, char = ch}
end

local function updateESP()
    local myRoot = getRoot()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then
            local o = espObjs[p]
            if o and o.char ~= p.Character then removeESP(p) o = nil end
            if not o then buildESP(p) o = espObjs[p] end
            if o then
                local ch = p.Character
                local root = ch and ch:FindFirstChild("HumanoidRootPart")
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                local dist = (root and myRoot) and math.floor((root.Position - myRoot.Position).Magnitude) or 0
                local hp = hum and (" | " .. math.floor(hum.Health) .. " HP") or ""
                o.lbl.Text = ("%s [%dm]%s"):format(p.DisplayName, dist, hp)
            end
        end
    end
end

local function setESP(v)
    espOn = v
    if espConn then espConn:Disconnect() espConn = nil end
    if v then
        local t = 0
        espConn = RS.Heartbeat:Connect(function(dt)
            t += dt
            if t >= 0.2 then t = 0 updateESP() end
        end)
        updateESP()
    else
        for p in pairs(espObjs) do removeESP(p) end
    end
    refreshAll()
end
track(Players.PlayerRemoving:Connect(removeESP))

---------------------------------------------------------------- SPECTATE
local function stopSpectate()
    spectating = nil
    local cam = workspace.CurrentCamera
    local hum = getHum()
    if cam and hum then cam.CameraSubject = hum end
    refreshAll()
end

local function startSpectate(p)
    if not p or p == lp then return end
    if spectating == p then stopSpectate() return end
    spectating = p
    local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    local cam = workspace.CurrentCamera
    if h and cam then cam.CameraSubject = h end
    refreshAll()
end

---------------------------------------------------------------- WAYPOINT BEACONS
local beaconFolder
local beacons = {}

local function clearBeacons()
    table.clear(beacons)
    if beaconFolder then beaconFolder:ClearAllChildren() end
end

local function buildBeacons()
    clearBeacons()
    if not beaconsOn then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    if not beaconFolder then
        beaconFolder = Instance.new("Folder")
        beaconFolder.Name = "AIO_Beacons"
    end
    beaconFolder.Parent = cam
    for i, loc in ipairs(allLocations[placeKey] or {}) do
        local pos = Vector3.new(loc.x, loc.y, loc.z)
        local color = Color3.fromHSV(((i - 1) * 0.13) % 1, 0.6, 1)

        local pillar = Instance.new("Part")
        pillar.Anchored = true
        pillar.CanCollide = false
        pillar.CanQuery = false
        pillar.CanTouch = false
        pillar.CastShadow = false
        pillar.Material = Enum.Material.Neon
        pillar.Color = color
        pillar.Transparency = 0.55
        pillar.Size = Vector3.new(0.5, 80, 0.5)
        pillar.CFrame = CFrame.new(pos + Vector3.new(0, 40, 0))
        pillar.Parent = beaconFolder

        local bb = Instance.new("BillboardGui")
        bb.Adornee = pillar
        bb.Size = UDim2.new(0, 170, 0, 40)
        bb.StudsOffsetWorldSpace = Vector3.new(0, -30, 0)
        bb.AlwaysOnTop = true
        bb.Parent = beaconFolder

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0.3
        lbl.Font = Enum.Font.SourceSansBold
        lbl.TextSize = 15
        lbl.Text = loc.name
        lbl.Parent = bb

        beacons[#beacons + 1] = {pos = pos, name = loc.name, lbl = lbl}
    end
end
refreshBeacons = buildBeacons

local function setBeacons(v)
    beaconsOn = v
    if v then buildBeacons() else clearBeacons() end
    refreshAll()
end

---------------------------------------------------------------- SERVER HOP
local function queueReload()
    local url = tostring(reloadUrl or "")
    if url:sub(1, 8) == "https://" and queue_on_teleport then
        url = url:gsub('["\\\n\r]', "")
        pcall(queue_on_teleport, ('loadstring(game:HttpGet("%s"))()'):format(url))
    end
end

local function fetchServers(cursor)
    for _, host in ipairs({"games.roblox.com", "games.roproxy.com"}) do
        local url = ("https://%s/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s")
            :format(host, game.PlaceId, cursor and ("&cursor=" .. HttpService:UrlEncode(cursor)) or "")
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" then
            local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok2 and type(data) == "table" and type(data.data) == "table" then return data end
        end
    end
    return nil
end

local function hop(mode)
    if hopping then return end
    if game.PrivateServerId ~= "" then setMoreStatus("Can't hop from a private server") return end
    hopping = true
    setMoreStatus("Searching servers...")
    task.spawn(function()
        local servers, cursor, pages = {}, nil, 0
        while pages < 3 and not unloaded do
            local data = fetchServers(cursor)
            if not data then break end
            for _, s in ipairs(data.data) do
                if type(s) == "table" and s.id ~= game.JobId
                    and (s.playing or 0) < (s.maxPlayers or 0) then
                    servers[#servers + 1] = s
                end
            end
            cursor = data.nextPageCursor
            pages += 1
            if not cursor then break end
        end
        if #servers == 0 then
            setMoreStatus("No other servers found (or the request was blocked)")
            hopping = false
            return
        end
        local pick
        if mode == "fewest" then
            table.sort(servers, function(a, b) return (a.playing or 0) < (b.playing or 0) end)
            pick = servers[1]
        elseif mode == "most" then
            table.sort(servers, function(a, b) return (a.playing or 0) > (b.playing or 0) end)
            pick = servers[1]
        else
            pick = servers[math.random(#servers)]
        end
        setMoreStatus(("Joining a server (%d/%d players)..."):format(pick.playing or 0, pick.maxPlayers or 0))
        queueReload()
        local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, lp) end)
        if not ok then setMoreStatus("Teleport failed: " .. tostring(err)) end
        task.wait(6)
        hopping = false
    end)
end

local function rejoin()
    queueReload()
    setMoreStatus("Rejoining...")
    local ok, err
    if #Players:GetPlayers() <= 1 then
        ok, err = pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
    else
        ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp) end)
    end
    if not ok then setMoreStatus("Rejoin failed: " .. tostring(err)) end
end

---------------------------------------------------------------- RESPAWN / DEATH
local function onChar(char)
    if unloaded then return end
    stopFly()
    stopSpectate()
    table.clear(noclipOrig)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        track(hum.Died:Connect(function()
            local r = getRoot()
            if r then lastDeath = r.Position end
            stopFly()
            if noclip then setNoclip(false) end
        end))
    end
    task.wait(0.5)
    if unloaded then return end
    applyNoRagdoll(char)
    applyGod(char)
end
track(lp.CharacterAdded:Connect(onChar))
if lp.Character then task.spawn(onChar, lp.Character) end

---------------------------------------------------------------- LOCATIONS
local function round1(n) return math.floor(n * 10 + 0.5) / 10 end
local function saveLocation(name)
    local root = getRoot()
    if not root then return end
    local list = allLocations[placeKey]
    local p = root.Position
    if not name or name == "" then name = "Spot " .. (#list + 1) end
    table.insert(list, {name = name, x = round1(p.X), y = round1(p.Y), z = round1(p.Z)})
    viewKey, browsing = placeKey, false      -- always jump back to the current game
    if rebuildLocList then rebuildLocList() end
    if refreshBeacons then refreshBeacons() end
    save()
end

---------------------------------------------------------------- GUI BASE
local gui = Instance.new("ScreenGui")
gui.Name = "AllInOneGUI"
gui.ResetOnSpawn = false
local host
do
    local okH, p = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
    host = (okH and p) or lp:WaitForChild("PlayerGui")
    for _, n in ipairs({"AllInOneGUI", "AIO_ESP"}) do
        local old = host:FindFirstChild(n)
        if old then old:Destroy() end
    end
end
local okP = pcall(function() gui.Parent = host end)
if not okP or not gui.Parent then host = lp:WaitForChild("PlayerGui") gui.Parent = host end
espFolder = Instance.new("Folder")
espFolder.Name = "AIO_ESP"
espFolder.Parent = host

---------------------------------------------------------------- UNLOAD
unload = function()
    if unloaded then return end
    unloaded = true
    -- switch every feature off so the game is restored to normal
    pcall(setFly, false)
    pcall(setNoRagdoll, false)
    pcall(setNoclip, false)
    pcall(setGod, false)
    pcall(setESP, false)
    pcall(setSpeed, false)
    pcall(setFullbright, false)
    pcall(setFovZoom, false)
    pcall(stopSpectate)
    pcall(function()
        beaconsOn = false
        clearBeacons()
        if beaconFolder then beaconFolder:Destroy() end
    end)
    infJump, antiAFK, clickTPEnabled = false, false, false
    pcall(save)
    -- disconnect everything the script hooked
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    -- remove all UI / ESP objects
    pcall(function() if espFolder then espFolder:Destroy() end end)
    pcall(function() gui:Destroy() end)
    if genv.AIO_UNLOAD == unload then genv.AIO_UNLOAD = nil end
end
genv.AIO_UNLOAD = unload

local function corner(o, r) local c = Instance.new("UICorner", o) c.CornerRadius = UDim.new(0, r or 8) return c end
local function mkButton(parent, text, size, pos, color)
    local b = Instance.new("TextButton")
    b.Size, b.Position = size, pos or UDim2.new()
    b.BackgroundColor3 = color or Color3.fromRGB(45, 45, 55)
    b.Text, b.TextColor3 = text, Color3.new(1, 1, 1)
    b.Font, b.TextSize = Enum.Font.SourceSansBold, 18
    b.AutoButtonColor = true
    b.Parent = parent
    corner(b, 6)
    return b
end
local function mkLabel(parent, text, size, pos, ts, align)
    local l = Instance.new("TextLabel")
    l.Size, l.Position = size, pos or UDim2.new()
    l.BackgroundTransparency = 1
    l.Text, l.TextColor3 = text, Color3.new(1, 1, 1)
    l.Font, l.TextSize = Enum.Font.SourceSansBold, ts or 17
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Parent = parent
    return l
end
local function mkBox(parent, text, size, pos, placeholder)
    local b = Instance.new("TextBox")
    b.Size, b.Position = size, pos or UDim2.new()
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.PlaceholderColor3 = Color3.fromRGB(130, 130, 130)
    b.PlaceholderText = placeholder or ""
    b.Font, b.TextSize = Enum.Font.SourceSansBold, 16
    b.Text = text or ""
    b.ClearTextOnFocus = false
    b.Parent = parent
    corner(b, 6)
    return b
end

-- Bubble
local bubble = mkButton(gui, "_", UDim2.new(0, 50, 0, 50), UDim2.new(0.92, 0, 0.8, 0), Color3.new(0, 0, 0))
bubble.TextColor3 = Color3.fromRGB(0, 255, 0)
bubble.TextSize = 28
corner(bubble, 25)
TS:Create(bubble, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    {BackgroundColor3 = Color3.fromRGB(0, 60, 0)}):Play()

-- Main frame
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 420, 0, 490)
frame.Position = UDim2.new(0.5, -210, 0.5, -245)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
frame.BackgroundTransparency = 0.05
frame.Active = true
frame.Parent = gui
corner(frame, 10)

local title = mkLabel(frame, "ALL-IN-ONE", UDim2.new(1, -50, 0, 36), UDim2.new(0, 12, 0, 0), 22)
title.Active = true
local closeBtn = mkButton(frame, "X", UDim2.new(0, 28, 0, 28), UDim2.new(1, -34, 0, 4), Color3.fromRGB(200, 40, 40))

do -- drag by title
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, frame.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

local function setVisible(v) frame.Visible = v end
bubble.MouseButton1Click:Connect(function() setVisible(not frame.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setVisible(false) end)

---------------------------------------------------------------- TABS
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -20, 0, 32)
tabBar.Position = UDim2.new(0, 10, 0, 40)
tabBar.BackgroundTransparency = 1
tabBar.Parent = frame
local tl = Instance.new("UIListLayout", tabBar)
tl.FillDirection = Enum.FillDirection.Horizontal
tl.Padding = UDim.new(0, 4)

local pages, tabButtons = {}, {}
local function newPage(name, scrolling)
    local p
    if scrolling then
        p = Instance.new("ScrollingFrame")
        p.ScrollBarThickness = 5
        p.BorderSizePixel = 0
        p.CanvasSize = UDim2.new()
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    else
        p = Instance.new("Frame")
    end
    p.Size = UDim2.new(1, -20, 1, -85)
    p.Position = UDim2.new(0, 10, 0, 78)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.Parent = frame
    pages[name] = p
    local b = mkButton(tabBar, name, UDim2.new(0.2, -3, 1, 0))
    b.TextSize = 16
    tabButtons[name] = b
    b.MouseButton1Click:Connect(function()
        for n, pg in pairs(pages) do
            pg.Visible = (n == name)
            tabButtons[n].BackgroundColor3 = (n == name) and Color3.fromRGB(0, 140, 70) or Color3.fromRGB(45, 45, 55)
        end
    end)
    return p
end
local featPage = newPage("Features", true)
local tpPage = newPage("Teleport")
local playersPage = newPage("Players")
local morePage = newPage("More", true)
local settingsPage = newPage("Settings", true)

---------------------------------------------------------------- KEYBIND BUTTON
local function createBindButton(parent, name, size, pos)
    local btn = mkButton(parent, keyName(binds[name]), size, pos)
    table.insert(bindBtns, {name = name, btn = btn})
    btn.MouseButton1Click:Connect(function()
        listening = name
        btn.Text = "press key..."
        btn.BackgroundColor3 = Color3.fromRGB(160, 120, 0)
    end)
    return btn
end
local function refreshBinds()
    for _, e in ipairs(bindBtns) do
        e.btn.Text = keyName(binds[e.name])
        e.btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end
end

---------------------------------------------------------------- FEATURES PAGE
local fl = Instance.new("UIListLayout", featPage)
fl.Padding = UDim.new(0, 6)

local features = {
    {label = "Fly",            bind = "Fly",        get = function() return flying end,          set = setFly,        toggleKey = true},
    {label = "Click TP (hold key + click)", bind = "ClickTP", get = function() return clickTPEnabled end, set = function(v) clickTPEnabled = v refreshAll() end, toggleKey = false},
    {label = "No Ragdoll",     bind = "NoRagdoll",  get = function() return noRagdoll end,       set = setNoRagdoll,  toggleKey = true},
    {label = "Noclip",         bind = "Noclip",     get = function() return noclip end,          set = setNoclip,     toggleKey = true},
    {label = "Infinite Jump",  bind = "InfJump",    get = function() return infJump end,         set = setInfJump,    toggleKey = true},
    {label = "Godmode (client-side)", bind = "Godmode", get = function() return godmode end,     set = setGod,        toggleKey = true},
    {label = "ESP",            bind = "ESP",        get = function() return espOn end,           set = setESP,        toggleKey = true},
    {label = "Speed boost",    bind = "Speed",      get = function() return speedOn end,         set = setSpeed,      toggleKey = true},
    {label = "Fullbright",     bind = "Fullbright", get = function() return fbOn end,            set = setFullbright, toggleKey = true},
    {label = "Waypoint beacons", bind = "Beacons",  get = function() return beaconsOn end,       set = setBeacons,    toggleKey = true},
    {label = "FOV + unlimited zoom", bind = "FovZoom", get = function() return fovZoom end,      set = setFovZoom,    toggleKey = true},
    {label = "Anti-AFK",       bind = "AntiAFK",    get = function() return antiAFK end,         set = setAntiAFK,    toggleKey = true},
}

for _, f in ipairs(features) do
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 42)
    row.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
    row.Parent = featPage
    corner(row, 8)

    local sw = mkButton(row, "OFF", UDim2.new(0, 56, 0, 30), UDim2.new(0, 6, 0.5, -15))
    mkLabel(row, f.label, UDim2.new(1, -170, 1, 0), UDim2.new(0, 68, 0, 0), 15)
    createBindButton(row, f.bind, UDim2.new(0, 84, 0, 30), UDim2.new(1, -90, 0.5, -15))

    sw.MouseButton1Click:Connect(function() f.set(not f.get()) end)
    table.insert(refreshers, function()
        local on = f.get()
        sw.Text = on and "ON" or "OFF"
        sw.BackgroundColor3 = on and Color3.fromRGB(0, 150, 75) or Color3.fromRGB(110, 45, 45)
    end)
end

local hint = mkLabel(featPage, "", UDim2.new(1, -8, 0, 62), nil, 14)
hint.TextColor3 = Color3.fromRGB(160, 160, 160)
hint.Font = Enum.Font.SourceSans
hint.TextYAlignment = Enum.TextYAlignment.Top
table.insert(refreshers, function()
    hint.Text = ("Click ON/OFF or press the key. Click a key button to rebind (Esc = cancel, Backspace = none). GUI key: %s. Fly/Speed/FOV values are in Settings."):format(keyName(binds.ToggleGUI))
end)

---------------------------------------------------------------- TELEPORT PAGE
local tlay = Instance.new("UIListLayout", tpPage)
tlay.Padding = UDim.new(0, 6)

-- 1) live coords
local coordRow = Instance.new("Frame")
coordRow.Size = UDim2.new(1, 0, 0, 32)
coordRow.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
coordRow.Parent = tpPage
corner(coordRow, 8)
local coordLbl = mkLabel(coordRow, "X: -  Y: -  Z: -", UDim2.new(1, -80, 1, 0), UDim2.new(0, 10, 0, 0), 15)
local copyBtn = mkButton(coordRow, "Copy", UDim2.new(0, 62, 0, 24), UDim2.new(1, -68, 0.5, -12))

local lastCoords = ""
do
    local t = 0
    track(RS.Heartbeat:Connect(function(dt)
        t += dt
        if t < 0.1 then return end
        t = 0
        local r = getRoot()
        if r then
            local p = r.Position
            lastCoords = ("%.1f, %.1f, %.1f"):format(p.X, p.Y, p.Z)
            coordLbl.Text = ("X: %.1f   Y: %.1f   Z: %.1f"):format(p.X, p.Y, p.Z)
        end
    end))
end
copyBtn.MouseButton1Click:Connect(function()
    if setclipboard and lastCoords ~= "" then
        pcall(setclipboard, lastCoords)
        copyBtn.Text = "Copied!"
        task.delay(1, function() copyBtn.Text = "Copy" end)
    else
        copyBtn.Text = "N/A"
        task.delay(1, function() copyBtn.Text = "Copy" end)
    end
end)

-- 2) game header (current game / browse all games)
local headerRow = Instance.new("Frame")
headerRow.Size = UDim2.new(1, 0, 0, 32)
headerRow.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
headerRow.Parent = tpPage
corner(headerRow, 8)
local headerLbl = mkLabel(headerRow, "", UDim2.new(1, -104, 1, 0), UDim2.new(0, 10, 0, 0), 15)
headerLbl.TextWrapped = false
headerLbl.TextTruncate = Enum.TextTruncate.AtEnd
local headerBtn = mkButton(headerRow, "All games", UDim2.new(0, 88, 0, 24), UDim2.new(1, -94, 0.5, -12), Color3.fromRGB(0, 110, 170))
headerBtn.TextSize = 16

-- 3) save current spot
local saveRow = Instance.new("Frame")
saveRow.Size = UDim2.new(1, 0, 0, 32)
saveRow.BackgroundTransparency = 1
saveRow.Parent = tpPage
local nameBox = mkBox(saveRow, "", UDim2.new(1, -110, 1, 0), nil, "Location name")
local saveBtn = mkButton(saveRow, "Save here", UDim2.new(0, 102, 1, 0), UDim2.new(1, -102, 0, 0), Color3.fromRGB(0, 130, 70))
saveBtn.MouseButton1Click:Connect(function()
    saveLocation(nameBox.Text)
    nameBox.Text = ""
end)

-- 4) go to XYZ
local xyzRow = Instance.new("Frame")
xyzRow.Size = UDim2.new(1, 0, 0, 32)
xyzRow.BackgroundTransparency = 1
xyzRow.Parent = tpPage
local bx = mkBox(xyzRow, "", UDim2.new(0.22, -3, 1, 0), UDim2.new(0, 0, 0, 0), "X")
local by = mkBox(xyzRow, "", UDim2.new(0.22, -3, 1, 0), UDim2.new(0.22, 2, 0, 0), "Y")
local bz = mkBox(xyzRow, "", UDim2.new(0.22, -3, 1, 0), UDim2.new(0.44, 4, 0, 0), "Z")
local goBtn = mkButton(xyzRow, "Go to XYZ", UDim2.new(0.34, -4, 1, 0), UDim2.new(0.66, 4, 0, 0), Color3.fromRGB(0, 110, 170))
goBtn.MouseButton1Click:Connect(function()
    local x, y, z = tonumber(bx.Text), tonumber(by.Text), tonumber(bz.Text)
    if x and y and z then teleportExact(Vector3.new(x, y, z)) end
end)

-- 5) death spot + spawn
local extraRow = Instance.new("Frame")
extraRow.Size = UDim2.new(1, 0, 0, 32)
extraRow.BackgroundTransparency = 1
extraRow.Parent = tpPage
local deathBtn = mkButton(extraRow, "Back to death spot [X]", UDim2.new(0.6, -3, 1, 0), nil, Color3.fromRGB(120, 60, 40))
deathBtn.TextSize = 16
local spawnBtn = mkButton(extraRow, "TP to spawn", UDim2.new(0.4, -3, 1, 0), UDim2.new(0.6, 3, 0, 0), Color3.fromRGB(70, 60, 110))
spawnBtn.TextSize = 16
deathBtn.MouseButton1Click:Connect(function()
    if not goDeathSpot() then
        deathBtn.Text = "No death recorded yet"
        task.delay(1.2, function() deathBtn.Text = "Back to death spot [X]" end)
    end
end)
spawnBtn.MouseButton1Click:Connect(function()
    local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    if sp then
        teleportExact(sp.Position + Vector3.new(0, 5, 0))
    else
        spawnBtn.Text = "No spawn found"
        task.delay(1.2, function() spawnBtn.Text = "TP to spawn" end)
    end
end)

-- 6) list (spots of the viewed game, or the list of all games)
local locScroll = Instance.new("ScrollingFrame")
locScroll.Size = UDim2.new(1, 0, 0, 196)
locScroll.BackgroundTransparency = 1
locScroll.BorderSizePixel = 0
locScroll.ScrollBarThickness = 5
locScroll.CanvasSize = UDim2.new()
locScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
locScroll.Parent = tpPage
local ll = Instance.new("UIListLayout", locScroll)
ll.Padding = UDim.new(0, 5)
ll.SortOrder = Enum.SortOrder.LayoutOrder

local function sortedGameKeys()
    local keys = {}
    for k, list in pairs(allLocations) do
        if type(list) == "table" and (#list > 0 or k == placeKey) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
        if a == b then return false end
        if a == placeKey then return true end
        if b == placeKey then return false end
        return gameName(a):lower() < gameName(b):lower()
    end)
    return keys
end

rebuildLocList = function()
    for _, c in ipairs(locScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    local viewList = allLocations[viewKey] or {}
    local isHere = (not browsing) and viewKey == placeKey

    -- header + which rows are visible
    if browsing then
        headerLbl.Text = "All games with saved spots"
    elseif isHere then
        headerLbl.Text = ("%s  (%d)"):format(gameName(placeKey), #viewList)
    else
        headerLbl.Text = ("%s  (%d) - other game"):format(gameName(viewKey), #viewList)
    end
    headerBtn.Text = browsing and "Back" or "All games"
    saveRow.Visible = isHere
    xyzRow.Visible = isHere
    extraRow.Visible = isHere

    -- list of games
    if browsing then
        for i, key in ipairs(sortedGameKeys()) do
            local list = allLocations[key]
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -8, 0, 36)
            card.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            card.LayoutOrder = i
            card.Parent = locScroll
            corner(card, 6)
            local nl = mkLabel(card, ("%s  (%d)%s"):format(gameName(key), #list, key == placeKey and "  - you are here" or ""),
                UDim2.new(1, -70, 1, 0), UDim2.new(0, 8, 0, 0), 14)
            nl.TextWrapped = false
            nl.TextTruncate = Enum.TextTruncate.AtEnd
            local open = mkButton(card, "Open", UDim2.new(0, 54, 0, 26), UDim2.new(1, -60, 0.5, -13), Color3.fromRGB(0, 110, 170))
            open.TextSize = 16
            open.MouseButton1Click:Connect(function()
                viewKey, browsing = key, false
                rebuildLocList()
            end)
        end
        return
    end

    -- spots of the viewed game
    for i, loc in ipairs(viewList) do
        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, -8, 0, 36)
        card.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        card.LayoutOrder = i
        card.Parent = locScroll
        corner(card, 6)
        local nl = mkLabel(card, ("%s  (%.0f, %.0f, %.0f)"):format(loc.name, loc.x, loc.y, loc.z),
            UDim2.new(1, isHere and -100 or -52, 1, 0), UDim2.new(0, 8, 0, 0), 14)
        nl.TextWrapped = false
        nl.TextTruncate = Enum.TextTruncate.AtEnd
        if isHere then -- TP only makes sense inside the same game
            local go = mkButton(card, "TP", UDim2.new(0, 40, 0, 26), UDim2.new(1, -88, 0.5, -13), Color3.fromRGB(0, 150, 75))
            go.MouseButton1Click:Connect(function() teleportExact(Vector3.new(loc.x, loc.y, loc.z)) end)
        end
        local del = mkButton(card, "X", UDim2.new(0, 34, 0, 26), UDim2.new(1, -44, 0.5, -13), Color3.fromRGB(170, 45, 45))
        del.MouseButton1Click:Connect(function()
            local list = allLocations[viewKey]
            if not list then return end
            table.remove(list, i)
            if #list == 0 and viewKey ~= placeKey then
                allLocations[viewKey] = nil
                browsing = true
            end
            rebuildLocList()
            if refreshBeacons then refreshBeacons() end
            save()
        end)
    end
end

headerBtn.MouseButton1Click:Connect(function()
    if browsing then
        browsing, viewKey = false, placeKey
    else
        browsing = true
    end
    rebuildLocList()
end)
rebuildLocList()

---------------------------------------------------------------- PLAYERS PAGE (with spectate)
local specRow = Instance.new("Frame")
specRow.Size = UDim2.new(1, 0, 0, 30)
specRow.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
specRow.Parent = playersPage
corner(specRow, 8)
local specLbl = mkLabel(specRow, "", UDim2.new(1, -90, 1, 0), UDim2.new(0, 10, 0, 0), 14)
specLbl.TextWrapped = false
specLbl.TextTruncate = Enum.TextTruncate.AtEnd
local specStop = mkButton(specRow, "Stop", UDim2.new(0, 70, 0, 24), UDim2.new(1, -76, 0.5, -12), Color3.fromRGB(170, 45, 45))
specStop.TextSize = 16
specStop.MouseButton1Click:Connect(stopSpectate)
table.insert(refreshers, function()
    specLbl.Text = spectating and ("Spectating: " .. spectating.DisplayName) or "Not spectating - press Spec on a player"
end)

local scroll = Instance.new("ScrollingFrame", playersPage)
scroll.Size = UDim2.new(1, 0, 1, -36)
scroll.Position = UDim2.new(0, 0, 0, 36)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
local pl = Instance.new("UIListLayout", scroll)
pl.Padding = UDim.new(0, 5)
pl.SortOrder = Enum.SortOrder.Name

local playerCards = {}
local function addPlayer(p)
    if p == lp or playerCards[p] then return end
    local card = Instance.new("Frame")
    card.Name = p.Name
    card.Size = UDim2.new(1, -8, 0, 38)
    card.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    card.Parent = scroll
    corner(card, 6)
    local nl = mkLabel(card, p.DisplayName .. " (@" .. p.Name .. ")", UDim2.new(0.5, 0, 1, 0), UDim2.new(0, 10, 0, 0), 15)
    nl.TextWrapped = false
    nl.TextTruncate = Enum.TextTruncate.AtEnd
    local spec = mkButton(card, "Spec", UDim2.new(0.2, 0, 0.8, 0), UDim2.new(0.54, 0, 0.1, 0), Color3.fromRGB(0, 110, 170))
    spec.TextSize = 16
    spec.MouseButton1Click:Connect(function() startSpectate(p) end)
    local tp = mkButton(card, "TP", UDim2.new(0.2, 0, 0.8, 0), UDim2.new(0.77, 0, 0.1, 0), Color3.fromRGB(0, 160, 80))
    tp.TextSize = 16
    tp.MouseButton1Click:Connect(function()
        local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if root then teleportTo(root.Position) end
    end)
    playerCards[p] = card
end
for _, p in ipairs(Players:GetPlayers()) do addPlayer(p) end
track(Players.PlayerAdded:Connect(addPlayer))
track(Players.PlayerRemoving:Connect(function(p)
    if playerCards[p] then playerCards[p]:Destroy() playerCards[p] = nil end
    if spectating == p then stopSpectate() end
end))

---------------------------------------------------------------- MORE PAGE (server hop, utilities, share spots)
local ml = Instance.new("UIListLayout", morePage)
ml.Padding = UDim.new(0, 6)

local function sectionLabel(text)
    local l = mkLabel(morePage, text, UDim2.new(1, -8, 0, 22), nil, 15)
    l.TextColor3 = Color3.fromRGB(120, 200, 140)
    return l
end

sectionLabel("SERVER")
local serverInfo = mkLabel(morePage, "", UDim2.new(1, -8, 0, 20), nil, 14)
serverInfo.TextColor3 = Color3.fromRGB(170, 170, 170)
serverInfo.Font = Enum.Font.SourceSans
serverInfo.TextWrapped = false

local hopRow = Instance.new("Frame")
hopRow.Size = UDim2.new(1, -8, 0, 34)
hopRow.BackgroundTransparency = 1
hopRow.Parent = morePage
do
    local modes = {{"Random", "random"}, {"Fewest", "fewest"}, {"Most", "most"}}
    for i, m in ipairs(modes) do
        local b = mkButton(hopRow, "Hop: " .. m[1], UDim2.new(1 / 3, -4, 1, 0), UDim2.new((i - 1) / 3, 2, 0, 0), Color3.fromRGB(0, 110, 170))
        b.TextSize = 15
        b.MouseButton1Click:Connect(function() hop(m[2]) end)
    end
end

local rjRow = Instance.new("Frame")
rjRow.Size = UDim2.new(1, -8, 0, 34)
rjRow.BackgroundTransparency = 1
rjRow.Parent = morePage
local rejoinBtn = mkButton(rjRow, "Rejoin server", UDim2.new(0.5, -3, 1, 0), nil, Color3.fromRGB(120, 85, 20))
rejoinBtn.TextSize = 16
rejoinBtn.MouseButton1Click:Connect(rejoin)
local jobBtn = mkButton(rjRow, "Copy JobId", UDim2.new(0.5, -3, 1, 0), UDim2.new(0.5, 3, 0, 0))
jobBtn.TextSize = 16
jobBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        pcall(setclipboard, game.JobId)
        setMoreStatus("JobId copied")
    else
        setMoreStatus("Clipboard not supported by your executor")
    end
end)

local joinRow = Instance.new("Frame")
joinRow.Size = UDim2.new(1, -8, 0, 32)
joinRow.BackgroundTransparency = 1
joinRow.Parent = morePage
local jobBox = mkBox(joinRow, "", UDim2.new(1, -90, 1, 0), nil, "Paste a JobId to join")
local joinBtn = mkButton(joinRow, "Join", UDim2.new(0, 82, 1, 0), UDim2.new(1, -82, 0, 0), Color3.fromRGB(0, 130, 70))
joinBtn.MouseButton1Click:Connect(function()
    local id = jobBox.Text:gsub("%s", "")
    if id == "" then setMoreStatus("Paste a JobId first") return end
    queueReload()
    setMoreStatus("Joining that server...")
    local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, lp) end)
    if not ok then setMoreStatus("Join failed: " .. tostring(err)) end
end)

local reloadLbl = mkLabel(morePage, "Auto-reload URL after hop/rejoin (raw .lua, https only, optional):", UDim2.new(1, -8, 0, 32), nil, 13)
reloadLbl.TextColor3 = Color3.fromRGB(170, 170, 170)
reloadLbl.Font = Enum.Font.SourceSans
local reloadBox = mkBox(morePage, reloadUrl, UDim2.new(1, -8, 0, 30), nil, "https://raw.githubusercontent.com/...")
reloadBox.FocusLost:Connect(function()
    reloadUrl = reloadBox.Text:gsub("%s", "")
    save()
    if reloadUrl ~= "" and not queue_on_teleport then
        setMoreStatus("Saved, but your executor has no queue_on_teleport")
    else
        setMoreStatus("Reload URL saved")
    end
end)

sectionLabel("SHARE SPOTS (this game)")
local shareRow = Instance.new("Frame")
shareRow.Size = UDim2.new(1, -8, 0, 32)
shareRow.BackgroundTransparency = 1
shareRow.Parent = morePage
local exportBtn = mkButton(shareRow, "Export (copy JSON)", UDim2.new(1, 0, 1, 0), nil, Color3.fromRGB(70, 60, 110))
exportBtn.TextSize = 16
exportBtn.MouseButton1Click:Connect(function()
    local list = allLocations[placeKey] or {}
    if #list == 0 then setMoreStatus("No saved spots in this game to export") return end
    if setclipboard then
        pcall(setclipboard, HttpService:JSONEncode({game = gameName(placeKey), spots = list}))
        setMoreStatus(("Exported %d spots to clipboard"):format(#list))
    else
        setMoreStatus("Clipboard not supported by your executor")
    end
end)

local importRow = Instance.new("Frame")
importRow.Size = UDim2.new(1, -8, 0, 32)
importRow.BackgroundTransparency = 1
importRow.Parent = morePage
local importBox = mkBox(importRow, "", UDim2.new(1, -90, 1, 0), nil, "Paste exported JSON here")
local importBtn = mkButton(importRow, "Import", UDim2.new(0, 82, 1, 0), UDim2.new(1, -82, 0, 0), Color3.fromRGB(0, 130, 70))
importBtn.MouseButton1Click:Connect(function()
    local ok, data = pcall(function() return HttpService:JSONDecode(importBox.Text) end)
    if not ok or type(data) ~= "table" then setMoreStatus("That isn't valid JSON") return end
    local src = data.spots or data
    local mine = allLocations[placeKey]
    local added = 0
    for _, s in ipairs(src) do
        if type(s) == "table" and tonumber(s.x) and tonumber(s.y) and tonumber(s.z) then
            table.insert(mine, {
                name = tostring(s.name or "Imported"),
                x = round1(tonumber(s.x)), y = round1(tonumber(s.y)), z = round1(tonumber(s.z)),
            })
            added += 1
        end
    end
    importBox.Text = ""
    viewKey, browsing = placeKey, false
    rebuildLocList()
    if refreshBeacons then refreshBeacons() end
    save()
    setMoreStatus(("Imported %d spots"):format(added))
end)

local moreStatus = mkLabel(morePage, "", UDim2.new(1, -8, 0, 34), nil, 14)
moreStatus.TextColor3 = Color3.fromRGB(200, 200, 120)
moreStatus.Font = Enum.Font.SourceSans
setMoreStatus = function(t) if moreStatus.Parent then moreStatus.Text = t end end

---------------------------------------------------------------- SETTINGS PAGE
local sl = Instance.new("UIListLayout", settingsPage)
sl.Padding = UDim.new(0, 6)

local function settingsRow(labelText)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 38)
    row.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
    row.Parent = settingsPage
    corner(row, 8)
    mkLabel(row, labelText, UDim2.new(0.55, 0, 1, 0), UDim2.new(0, 10, 0, 0), 16)
    return row
end

for _, e in ipairs({
    {"Show / Hide GUI", "ToggleGUI"},
    {"Fly Up", "FlyUp"},
    {"Fly Down", "FlyDown"},
    {"Quick-save location", "QuickSave"},
    {"Back to death spot", "DeathBack"},
    {"Stop spectating", "StopSpectate"},
    {"Unload script", "Unload"},
}) do
    local row = settingsRow(e[1])
    createBindButton(row, e[2], UDim2.new(0, 120, 0, 28), UDim2.new(1, -128, 0.5, -14))
end

local function numberRow(labelText, get, set, minV, maxV)
    minV, maxV = minV or 1, maxV or 500
    local row = settingsRow(labelText)
    local box = mkBox(row, tostring(get()), UDim2.new(0, 120, 0, 28), UDim2.new(1, -128, 0.5, -14))
    box.TextSize = 18
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then set(math.clamp(n, minV, maxV)) end
        box.Text = tostring(get())
        save()
    end)
end
numberRow("Fly speed (1-500)", function() return flySpeed end, function(n) flySpeed = n end)
numberRow("Walk speed (1-500)", function() return walkSpeed end, function(n) walkSpeed = n end)
numberRow("FOV (30-120)", function() return fovValue end, function(n) fovValue = n end, 30, 120)

local resetBtn = mkButton(settingsPage, "Reset keys to default", UDim2.new(1, -8, 0, 38), nil, Color3.fromRGB(120, 60, 40))
resetBtn.MouseButton1Click:Connect(function()
    for k, v in pairs(defaults) do binds[k] = v end
    listening = nil
    refreshBinds()
    refreshAll()
    save()
end)

local unloadBtn = mkButton(settingsPage, "UNLOAD SCRIPT", UDim2.new(1, -8, 0, 40), nil, Color3.fromRGB(170, 35, 35))
do
    local armed = false
    unloadBtn.MouseButton1Click:Connect(function()
        if armed then
            unload()
            return
        end
        armed = true
        unloadBtn.Text = "Click again to confirm"
        unloadBtn.BackgroundColor3 = Color3.fromRGB(220, 120, 20)
        task.delay(3, function()
            if unloaded then return end
            armed = false
            unloadBtn.Text = "UNLOAD SCRIPT"
            unloadBtn.BackgroundColor3 = Color3.fromRGB(170, 35, 35)
        end)
    end)
end

---------------------------------------------------------------- INPUT
track(UIS.InputBegan:Connect(function(input, gpe)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if listening then -- rebinding mode
            local k = input.KeyCode
            if k == Enum.KeyCode.Escape then
                -- cancel
            elseif k == Enum.KeyCode.Backspace then
                binds[listening] = false
            else
                for name, v in pairs(binds) do
                    if v == k then binds[name] = false end
                end
                binds[listening] = k
            end
            listening = nil
            refreshBinds()
            refreshAll()
            save()
            return
        end
        if gpe then return end

        local k = input.KeyCode
        if binds.Unload and k == binds.Unload then unload() return end
        if binds.ToggleGUI and k == binds.ToggleGUI then setVisible(not frame.Visible) return end
        if binds.QuickSave and k == binds.QuickSave then saveLocation(nil) return end
        if binds.DeathBack and k == binds.DeathBack then goDeathSpot() return end
        if binds.StopSpectate and k == binds.StopSpectate then stopSpectate() return end
        for _, f in ipairs(features) do
            if f.toggleKey and binds[f.bind] and k == binds[f.bind] then
                f.set(not f.get())
            end
        end

    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        if gpe or not clickTPEnabled then return end
        if down(binds.ClickTP) and mouse.Target then
            teleportTo(mouse.Hit.Position)
        end
    end
end))

---------------------------------------------------------------- START
pages.Features.Visible = true
tabButtons.Features.BackgroundColor3 = Color3.fromRGB(0, 140, 70)
refreshBinds()
refreshAll()

-- background loop: beacon labels, spectate enforcement, server info
task.spawn(function()
    while not unloaded do
        local root = getRoot()

        if beaconsOn then
            local cam = workspace.CurrentCamera
            if not beaconFolder or beaconFolder.Parent ~= cam then buildBeacons() end
            if root then
                for _, b in ipairs(beacons) do
                    b.lbl.Text = ("%s\n%.0fm"):format(b.name, (root.Position - b.pos).Magnitude)
                end
            end
        end

        if spectating then
            if not spectating.Parent then
                stopSpectate()
            else
                local h = spectating.Character and spectating.Character:FindFirstChildOfClass("Humanoid")
                local cam = workspace.CurrentCamera
                if h and cam and cam.CameraSubject ~= h then cam.CameraSubject = h end
            end
        end

        serverInfo.Text = ("Players: %d/%d  |  JobId: %s"):format(#Players:GetPlayers(), Players.MaxPlayers, game.JobId:sub(1, 8))
        task.wait(0.25)
    end
end)

-- fetch real game names in the background (current game + every game with saved spots)
task.spawn(function()
    local keys = {}
    for k in pairs(allLocations) do
        local n = tonumber(k)
        if n and n > 0 and not gameNames[k] then keys[#keys + 1] = k end
    end
    local changed = false
    for _, k in ipairs(keys) do
        if unloaded then return end
        local ok, info = pcall(function() return MarketplaceService:GetProductInfo(tonumber(k)) end)
        if ok and type(info) == "table" and info.Name then
            gameNames[k] = info.Name
            changed = true
        end
        task.wait(0.2)
    end
    if changed and not unloaded then
        save()
        if rebuildLocList then rebuildLocList() end
    end
end)
