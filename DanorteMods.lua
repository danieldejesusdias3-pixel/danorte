--[[
    Danorte Mods v4.0 | Universal | Delta
    Crie a conta com uma key gerada no gerador Danorte Mods.
]]

-- fecha instancia anterior (evita duplicar ao executar de novo)
pcall(function()
    if getgenv and getgenv().DanorteUnload then getgenv().DanorteUnload() end
end)

local cloneref = cloneref or function(x) return x end
local function svc(n) return cloneref(game:GetService(n)) end

local Players      = svc("Players")
local RunService   = svc("RunService")
local UIS          = svc("UserInputService")
local TweenService = svc("TweenService")
local HttpService  = svc("HttpService")
local Workspace    = game:GetService("Workspace") -- sem cloneref (comparacao nos hooks)

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse  = LP:GetMouse()

-- ====================== CONFIGURACAO ======================
local SAVE_FILE = "DanorteMods_login.json"
local CFG_FILE  = "DanorteMods_config.json"

-- Foto opcional no cabecalho do painel (use UMA opcao):
-- 1) DanorteMods_logo.png na pasta workspace do Delta  2) LOGO_URL  3) LOGO_ASSET
local LOGO_FILE  = "DanorteMods_logo.png"
local LOGO_URL   = ""
local LOGO_ASSET = ""

-- Foto de fundo do painel de funcoes (use UMA opcao):
-- 1) DanorteMods_bg.png na pasta workspace do Delta  2) BG_URL  3) BG_ASSET
local BG_FILE  = "DanorteMods_bg.png"
local BG_URL   = ""
local BG_ASSET = ""
local BG_DIM   = 0.45 -- 0 = foto forte | 1 = foto some

-- Controle remoto (gerador > aba Controle Remoto): link RAW do paste com a config.
-- Vazio = desligado. Manutencao, funcoes, abas, fotos e avisos passam a vir do gerador.
local REMOTE_URL  = "https://raw.githubusercontent.com/danieldejesusdias3-pixel/danorte/refs/heads/main/config.json"
local function fixLink(u)
    u = (tostring(u or ""):gsub("^%s+", "")); u = (u:gsub("%s+$", ""))
    if u == "" then return u end
    if not u:find("^https?://") then u = "https://" .. u end
    local code = u:match("^https?://[%w%.]*pastebin%.com/(%w+)$")
    if code and code ~= "raw" then u = "https://pastebin.com/raw/" .. code end
    return u
end
REMOTE_URL = fixLink(REMOTE_URL)
local lastFetchErr = ""
local function fetchRemote() -- tenta com cache-buster; se falhar tenta o link puro
    local sep = REMOTE_URL:find("?", 1, true) and "&" or "?"
    local ok, res = pcall(function() return game:HttpGet(REMOTE_URL .. sep .. "t=" .. os.time()) end)
    if ok and type(res) == "string" and res ~= "" then return res end
    local ok2, res2 = pcall(function() return game:HttpGet(REMOTE_URL) end)
    if ok2 and type(res2) == "string" and res2 ~= "" then return res2 end
    lastFetchErr = ok2 and "resposta vazia" or tostring(res2)
    return nil
end
local REMOTE_POLL = 20 -- segundos entre checagens
local REMOTE_BLOCKED = {} -- keys pausadas/deletadas que vem na config remota
local function setRemoteBlocked(list)
    local t = {}
    if type(list) == "table" then
        for _, k in ipairs(list) do
            if type(k) == "string" then
                local x = (k:upper():gsub("[^A-Z0-9]", ""))
                if x:sub(1, 7) == "DANORTE" then x = x:sub(8) end
                if #x >= 8 then t[x:sub(1, 8)] = true end
            end
        end
    end
    REMOTE_BLOCKED = t
end

-- ====================== ESTADO (tudo desligado por padrao) ======================
local S = {
    -- visual
    ESPLine = false, Skeleton = false, Chams = false,
    IgnoreDead = false, IgnoreTeam = false,
    ShowFOV = false, FOVRadius = 150, FOVOnly = false,
    -- player
    Speed = false, SpeedValue = 32, SpeedCF = false,
    CamFOVOn = false, CamFOV = 90,
    -- armas
    InfAmmo = false, FastReload = false,
    -- aim
    AimZone = 1,
    Aimbot = false, AimSmooth = 100, WallCheck = false,
    AimLegit = false, LegitSmooth = 12,
    SilentAim = false, SilentHit = 100,
    -- troll
    Noclip = false, InfJump = false,
    Fly = false, FlySpeed = 60,
    Spin = false, SpinSpeed = 20,
    Fling = false,
    Orbit = false, Follow = false, Spectate = false,
    Gravity = Workspace.Gravity,
}
local DEFAULT = {}
for k, v in pairs(S) do DEFAULT[k] = v end

local conns = {}
local function connect(sig, fn)
    local c = sig:Connect(fn)
    table.insert(conns, c)
    return c
end

local ORIGINAL_FOV = Camera.FieldOfView
local ORIGINAL_GRAV = Workspace.Gravity
local alive = true
local mainGui, espGui
local uiSet = {}
local toastFn = function() end

local function randName()
    local t = {}
    for i = 1, math.random(10, 16) do t[i] = string.char(math.random(97, 122)) end
    return table.concat(t)
end

-- ====================== HELPERS UI ======================
local C = {
    bg     = Color3.fromRGB(14, 14, 16),
    side   = Color3.fromRGB(12, 12, 14),
    panel  = Color3.fromRGB(24, 24, 28),
    row    = Color3.fromRGB(24, 24, 28),
    off    = Color3.fromRGB(60, 60, 66),
    accent = Color3.fromRGB(220, 30, 45),
    purple = Color3.fromRGB(220, 30, 45),
    gold   = Color3.fromRGB(255, 205, 100),
    text   = Color3.fromRGB(235, 235, 235),
    sub    = Color3.fromRGB(170, 170, 178),
}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(o, r) return new("UICorner", {CornerRadius = UDim.new(0, r)}, o) end
local function circle(o) return new("UICorner", {CornerRadius = UDim.new(1, 0)}, o) end
local function stroke(o, col, tr, th)
    return new("UIStroke", {Color = col, Transparency = tr or 0, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o)
end
local function gradient(o, c1, c2, rot)
    return new("UIGradient", {Color = ColorSequence.new(c1, c2), Rotation = rot or 45}, o)
end

local function tween(o, t, props)
    TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

-- efeito de clique: cor muda ao apertar e volta ao soltar
local function pressFx(btn, normal, pressed)
    btn.MouseButton1Down:Connect(function() tween(btn, .1, {BackgroundColor3 = pressed}) end)
    local function release() tween(btn, .22, {BackgroundColor3 = normal}) end
    btn.MouseButton1Up:Connect(release)
    btn.MouseLeave:Connect(release)
end

-- escala = ajuste a tela * animacao de abrir/fechar
local function makeScale(frame, w, h)
    local sc = new("UIScale", {}, frame)
    local openV = new("NumberValue", {Value = 0.85}, frame)
    local fitS = 1
    local function apply() sc.Scale = fitS * openV.Value end
    local function u()
        local v = Camera.ViewportSize
        fitS = math.clamp(math.min(v.X / (w + 24), v.Y / (h + 24)), 0.5, 1)
        apply()
    end
    u()
    connect(openV.Changed, apply)
    connect(Camera:GetPropertyChangedSignal("ViewportSize"), u)
    return function(target, t) tween(openV, t or .3, {Value = target}) end
end

-- GUI protegida: nome aleatorio + protect_gui/gethui
local function newGui(order)
    local gui = Instance.new("ScreenGui")
    gui.Name = randName()
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = order or 999
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui)
        elseif protect_gui then protect_gui(gui)
        elseif protectgui then protectgui(gui) end
    end)
    pcall(function()
        if gethui then gui.Parent = gethui() else gui.Parent = game:GetService("CoreGui") end
    end)
    if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
    return gui
end

local function fit(frame, w, h)
    local sc = new("UIScale", {}, frame)
    local function u()
        local v = Camera.ViewportSize
        sc.Scale = math.clamp(math.min(v.X / (w + 24), v.Y / (h + 24)), 0.5, 1)
    end
    u()
    connect(Camera:GetPropertyChangedSignal("ViewportSize"), u)
end

local function makeDraggable(handle, target, onClick)
    local dragging, moved, startIn, startPos = false, false, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            startIn, startPos = i.Position, target.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved and onClick then onClick() end
                end
            end)
        end
    end)
    connect(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startIn
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)
end

local function toast(gui, msg)
    if not gui then return end
    local t = new("TextLabel", {
        Size = UDim2.fromOffset(290, 30), AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, -40),
        BackgroundColor3 = C.bg, BackgroundTransparency = .1, Text = msg, TextColor3 = C.text,
        Font = Enum.Font.GothamMedium, TextSize = 13, BorderSizePixel = 0, ZIndex = 50,
    }, gui)
    corner(t, 8); stroke(t, C.accent, .3)
    TweenService:Create(t, TweenInfo.new(.3, Enum.EasingStyle.Quad), {Position = UDim2.new(.5, 0, 0, 24)}):Play()
    task.delay(2.5, function()
        local tw = TweenService:Create(t, TweenInfo.new(.3), {Position = UDim2.new(.5, 0, 0, -40)})
        tw:Play(); tw.Completed:Wait(); t:Destroy()
    end)
end

-- Particulas vermelhas subindo pelo painel
local function createParticles(parent, W, H, n)
    local list, rng = {}, Random.new()
    for i = 1, n do
        local sz = rng:NextInteger(2, 5)
        local f = new("Frame", {
            Size = UDim2.fromOffset(sz, sz), BackgroundColor3 = C.accent, BorderSizePixel = 0,
            BackgroundTransparency = rng:NextNumber(.4, .85),
        }, parent)
        circle(f)
        list[i] = {
            f = f, x = rng:NextNumber(0, W), y = rng:NextNumber(0, H),
            speed = rng:NextNumber(12, 38), drift = rng:NextNumber(4, 14), phase = rng:NextNumber(0, 6.28),
        }
    end
    local c = RunService.RenderStepped:Connect(function(dt)
        local t = os.clock()
        for _, q in ipairs(list) do
            q.y = q.y - q.speed * dt
            if q.y < -6 then q.y = H + 6; q.x = rng:NextNumber(0, W) end
            q.f.Position = UDim2.fromOffset(q.x + math.sin(t + q.phase) * q.drift, q.y)
        end
    end)
    table.insert(conns, c)
    return c
end

-- ====================== LOGO (vetorial, nitida em qualquer tamanho) ======================
local function buildLogo(parent, size)
    local root = new("Frame", {
        Size = UDim2.fromOffset(size, size), BackgroundColor3 = Color3.fromRGB(9, 9, 13), BorderSizePixel = 0,
    }, parent)
    circle(root)

    -- aro girando (vermelho -> dourado)
    local ring = stroke(root, Color3.new(1, 1, 1), 0, math.max(2, size * 0.06))
    local rg = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, C.accent),
            ColorSequenceKeypoint.new(.5, C.gold),
            ColorSequenceKeypoint.new(1, C.accent),
        }),
    }, ring)

    -- miolo com degrade escuro
    local inner = new("Frame", {
        Size = UDim2.fromScale(.84, .84), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, root)
    circle(inner)
    new("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(95, 12, 30), Color3.fromRGB(10, 10, 14)), Rotation = 90,
    }, inner)

    -- brilho superior
    local sheen = new("Frame", {
        Size = UDim2.fromScale(.56, .2), AnchorPoint = Vector2.new(.5, 0), Position = UDim2.fromScale(.5, .1),
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = .86, BorderSizePixel = 0,
    }, root)
    circle(sheen)

    -- letra D
    local h = new("TextLabel", {
        Size = UDim2.fromScale(1, .86), BackgroundTransparency = 1, Text = "D", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBlack, TextSize = math.floor(size * 0.52),
    }, root)
    new("UIStroke", {Color = C.accent, Thickness = math.max(1, size * 0.03), Transparency = .25, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual}, h)

    -- barra dourada
    local bar = new("Frame", {
        Size = UDim2.fromOffset(size * .36, math.max(2, size * .05)), AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.fromScale(.5, .76), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, root)
    corner(bar, 3)
    gradient(bar, C.gold, C.accent, 0)

    local c = RunService.RenderStepped:Connect(function()
        rg.Rotation = (os.clock() * 70) % 360
    end)
    table.insert(conns, c)
    return root
end

-- foto opcional (cabecalho)
local logoAsset, logoTried, pendingLogos = nil, false, {}
local function resolveLogo()
    if LOGO_ASSET ~= "" then return LOGO_ASSET end
    local ok, res = pcall(function()
        if isfile and getcustomasset then
            if isfile(LOGO_FILE) then return getcustomasset(LOGO_FILE) end
            if LOGO_URL ~= "" and writefile then
                writefile(LOGO_FILE, game:HttpGet(LOGO_URL))
                return getcustomasset(LOGO_FILE)
            end
        end
    end)
    if ok then return res end
end
local function registerLogo(img)
    if logoAsset then img.Image = logoAsset
    elseif not logoTried then table.insert(pendingLogos, img) end
end
task.spawn(function()
    logoAsset = resolveLogo()
    logoTried = true
    if logoAsset then
        for _, img in ipairs(pendingLogos) do pcall(function() img.Image = logoAsset end) end
    end
    pendingLogos = {}
end)

-- foto de fundo do painel de funcoes
local function resolveBG()
    if BG_ASSET ~= "" then return BG_ASSET end
    local ok, res = pcall(function()
        if isfile and getcustomasset then
            if isfile(BG_FILE) then return getcustomasset(BG_FILE) end
            if BG_URL ~= "" and writefile then
                writefile(BG_FILE, game:HttpGet(BG_URL))
                return getcustomasset(BG_FILE)
            end
            -- foto embutida no script (usada quando nao ha arquivo/URL/asset)
            if writefile then
                local EMB_FILE = "DanorteMods_bg_embed.jpg"
                if not isfile(EMB_FILE) then
                    local EMB = [==[
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
]==]
                    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
                    local map = {}
                    for i = 1, 64 do map[chars:byte(i)] = i - 1 end
                    local s = (EMB:gsub("[^%w%+/=]", ""))
                    local out = {}
                    for i = 1, #s, 4 do
                        local a, b, c, d = s:byte(i, i + 3)
                        local v = (map[a] or 0) * 262144 + (map[b] or 0) * 4096 + (map[c] or 0) * 64 + (map[d] or 0)
                        local b1, b2, b3 = math.floor(v / 65536), math.floor(v / 256) % 256, v % 256
                        if c == 61 then out[#out + 1] = string.char(b1)
                        elseif d == 61 then out[#out + 1] = string.char(b1, b2)
                        else out[#out + 1] = string.char(b1, b2, b3) end
                    end
                    writefile(EMB_FILE, table.concat(out))
                end
                return getcustomasset(EMB_FILE)
            end
        end
    end)
    if ok then return res end
end

-- ====================== TIME (ignorar amigo - varios metodos) ======================
local TEAM_KEYS = {"Team", "team", "TeamName", "TeamId", "TeamID", "Side", "Squad"}
local teamCache = {}

local function computeSameTeam(p)
    -- 1) objeto Team
    if LP.Team ~= nil and p.Team ~= nil and LP.Team == p.Team then return true end
    -- 2) cor do time
    if not LP.Neutral and not p.Neutral and LP.TeamColor == p.TeamColor then return true end
    -- 3) atributos no jogador / personagem
    local mc, pc = LP.Character, p.Character
    for _, n in ipairs(TEAM_KEYS) do
        local a, b = LP:GetAttribute(n), p:GetAttribute(n)
        if a ~= nil and a == b then return true end
        local ca = mc and mc:GetAttribute(n)
        local cb = pc and pc:GetAttribute(n)
        if ca ~= nil and ca == cb then return true end
    end
    -- 4) valores (StringValue/ObjectValue/IntValue...) dentro do jogador
    for _, n in ipairs(TEAM_KEYS) do
        local a, b = LP:FindFirstChild(n), p:FindFirstChild(n)
        if a and b and a:IsA("ValueBase") and b:IsA("ValueBase") and a.Value ~= nil and a.Value == b.Value then
            return true
        end
    end
    return false
end

local function sameTeam(p)
    local c = teamCache[p]
    local now = os.clock()
    if c and now - c.t < 0.4 then return c.v end
    local v = computeSameTeam(p)
    teamCache[p] = {t = now, v = v}
    return v
end

-- amigos (whitelist manual) salvos por UserId
-- quem esta na lista nao e mirado e nao aparece no ESP
local FRIEND_FILE = "DanorteMods_friends.json"
local friends = {}
pcall(function()
    if isfile and isfile(FRIEND_FILE) then
        for _, id in ipairs(HttpService:JSONDecode(readfile(FRIEND_FILE))) do friends[id] = true end
    end
end)
local function saveFriends()
    pcall(function()
        local t = {}
        for id in pairs(friends) do t[#t + 1] = id end
        writefile(FRIEND_FILE, HttpService:JSONEncode(t))
    end)
end

local function isEnemy(p)
    if p == LP then return false end
    if friends[p.UserId] then return false end
    if S.IgnoreTeam and sameTeam(p) then return false end
    return true
end

-- ====================== ESP (linha / esqueleto / chams) ======================
local R15 = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}
local R6 = {
    {"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"},
}

local objs = {}
local ESP_COLOR = Color3.fromRGB(255, 45, 85)

local function mkLine(th)
    local f = new("Frame", {
        AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = ESP_COLOR, BorderSizePixel = 0,
        Visible = false, Size = UDim2.fromOffset(0, th), ZIndex = 2,
    }, espGui)
    return {f = f, th = th}
end

local function drawLine(l, a, b)
    local d = b - a
    local len = d.Magnitude
    if len < 1 then l.f.Visible = false; return end
    local mid = (a + b) / 2
    l.f.Size = UDim2.fromOffset(len, l.th)
    l.f.Position = UDim2.fromOffset(mid.X, mid.Y)
    l.f.Rotation = math.deg(math.atan2(d.Y, d.X))
    l.f.Visible = true
end

local function removeObj(p)
    local o = objs[p]
    if not o then return end
    if o.line then pcall(function() o.line.f:Destroy() end) end
    for _, l in ipairs(o.bones) do pcall(function() l.f:Destroy() end) end
    if o.hl then pcall(function() o.hl:Destroy() end) end
    objs[p] = nil
    teamCache[p] = nil
end

local fovCircle

local function espStep()
    if not espGui then return end
    Camera = Workspace.CurrentCamera or Camera
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local o = objs[p]
            if not o then o = {bones = {}}; objs[p] = o end

            local char = p.Character
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            local ok = (hum ~= nil and root ~= nil and isEnemy(p))
            if ok and S.IgnoreDead and hum.Health <= 0 then ok = false end

            local pos, on = nil, false
            if ok then
                local v, vis = Camera:WorldToViewportPoint(root.Position)
                pos = Vector2.new(v.X, v.Y)
                on = vis and v.Z > 0
                if S.FOVOnly and not (on and (pos - center).Magnitude <= S.FOVRadius) then ok = false end
            end

            if ok and S.ESPLine and on then
                if not o.line then o.line = mkLine(2) end
                drawLine(o.line, Vector2.new(vp.X / 2, vp.Y - 2), pos)
            elseif o.line then
                o.line.f.Visible = false
            end

            local list = nil
            if ok and S.Skeleton then
                list = (hum.RigType == Enum.HumanoidRigType.R15) and R15 or R6
                for i, pr in ipairs(list) do
                    local l = o.bones[i]
                    if not l then l = mkLine(2); o.bones[i] = l end
                    local a, b = char:FindFirstChild(pr[1]), char:FindFirstChild(pr[2])
                    if a and b then
                        local pa, va = Camera:WorldToViewportPoint(a.Position)
                        local pb, vb = Camera:WorldToViewportPoint(b.Position)
                        if va and vb then
                            drawLine(l, Vector2.new(pa.X, pa.Y), Vector2.new(pb.X, pb.Y))
                        else l.f.Visible = false end
                    else l.f.Visible = false end
                end
            end
            for i = (list and #list + 1 or 1), #o.bones do o.bones[i].f.Visible = false end

            -- Chams (Highlight guardado na GUI protegida, nao no personagem)
            if ok and S.Chams then
                if not o.hl or o.hl.Adornee ~= char then
                    if o.hl then o.hl:Destroy() end
                    o.hl = Instance.new("Highlight")
                    o.hl.Name = randName()
                    o.hl.FillColor = ESP_COLOR
                    o.hl.OutlineColor = Color3.new(1, 1, 1)
                    o.hl.FillTransparency = 0.5
                    o.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    o.hl.Adornee = char
                    o.hl.Parent = espGui
                end
                o.hl.Enabled = true
            elseif o.hl then
                o.hl.Enabled = false
            end
        end
    end
end

connect(Players.PlayerRemoving, removeObj)

-- ====================== PLAYER / TROLL (loops) ======================
local trollTarget = nil
local origWalk = nil
local flyBV = nil
local orbitAngle = 0

local function getChar()
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    return c, h, r
end

local function stopFly()
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
    local _, h = getChar()
    if h then h.PlatformStand = false end
end

local function targetRoot()
    local c = trollTarget and trollTarget.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- antes da fisica: velocidade + noclip
connect(RunService.Stepped, function(_, dt)
    local char, hum, root = getChar()
    if not (char and hum and root) then return end

    if S.Speed then
        if S.SpeedCF then
            local md = hum.MoveDirection
            local extra = math.max(S.SpeedValue - 16, 0)
            if md.Magnitude > 0 and extra > 0 then
                root.CFrame = root.CFrame + md * (extra * dt)
            end
        else
            hum.WalkSpeed = S.SpeedValue
        end
    end

    if S.Noclip then
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d.CanCollide then d.CanCollide = false end
        end
    end
end)

connect(RunService.Heartbeat, function()
    if S.Speed and not S.SpeedCF then
        local _, hum = getChar()
        if hum and hum.WalkSpeed ~= S.SpeedValue then hum.WalkSpeed = S.SpeedValue end
    end
    if S.Fling then
        local _, _, root = getChar()
        if root then root.AssemblyAngularVelocity = Vector3.new(0, 16000, 0) end
    end
end)

connect(UIS.JumpRequest, function()
    if S.InfJump then
        local _, hum = getChar()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

connect(RunService.RenderStepped, function(dt)
    Camera = Workspace.CurrentCamera or Camera
    if S.CamFOVOn then Camera.FieldOfView = S.CamFOV end
    pcall(espStep)

    local _, hum, root = getChar()
    if not (hum and root) then return end

    -- Fly
    if S.Fly then
        if not flyBV or flyBV.Parent ~= root then
            if flyBV then flyBV:Destroy() end
            flyBV = Instance.new("BodyVelocity")
            flyBV.Name = randName()
            flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            flyBV.Velocity = Vector3.zero
            flyBV.Parent = root
        end
        hum.PlatformStand = true
        local cf = Camera.CFrame
        local md = cf:VectorToObjectSpace(hum.MoveDirection)
        flyBV.Velocity = (cf.RightVector * md.X + cf.LookVector * (-md.Z)) * S.FlySpeed
    end

    -- Spin
    if S.Spin then
        root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(S.SpinSpeed), 0)
    end

    -- Orbitar / Grudar no alvo
    local tr = (S.Orbit or S.Follow) and targetRoot()
    if tr then
        if S.Orbit then
            orbitAngle = orbitAngle + dt * 3
            local p = tr.Position + Vector3.new(math.cos(orbitAngle) * 6, 0, math.sin(orbitAngle) * 6)
            root.CFrame = CFrame.new(p, tr.Position)
        elseif S.Follow then
            root.CFrame = tr.CFrame * CFrame.new(0, 0, 3)
        end
    end
end)

-- anti-AFK
pcall(function()
    local vu = game:GetService("VirtualUser")
    connect(LP.Idled, function()
        vu:CaptureController()
        vu:ClickButton2(Vector2.new())
    end)
end)

-- ====================== AIM ======================
local silentPart, silentPos = nil, nil
local rpWall = RaycastParams.new()
rpWall.FilterType = Enum.RaycastFilterType.Exclude

local function wallClear(pos, char)
    local origin = Camera.CFrame.Position
    local ign = {char}
    if LP.Character then table.insert(ign, LP.Character) end
    rpWall.FilterDescendantsInstances = ign
    return Workspace:Raycast(origin, pos - origin, rpWall) == nil
end

local lastTarget = nil -- alvo anterior: evita a mira pular entre inimigos

-- 1 Cabeca | 2 Pescoco | 3 Peito | 4 Ombro
local ZONES = {"Cabeça", "Pescoço", "Peito", "Ombro"}
local ARMS = {"RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm"}

local function zonePoint(char)
    local head = char:FindFirstChild("Head")
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    local z = S.AimZone

    if z == 1 and head then
        return head, head.Position
    elseif z == 2 and head then
        return head, head.Position - head.CFrame.UpVector * (head.Size.Y * 0.5)
    elseif z == 4 then
        local camPos = Camera.CFrame.Position
        local best, bd = nil, math.huge
        for _, n in ipairs(ARMS) do
            local a = char:FindFirstChild(n)
            if a then
                local d = (a.Position - camPos).Magnitude
                if d < bd then best, bd = a, d end
            end
        end
        if best then
            return best, best.Position + best.CFrame.UpVector * (best.Size.Y * 0.3)
        end
    end
    if torso then
        return torso, torso.Position + torso.CFrame.UpVector * (torso.Size.Y * 0.1)
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root then return root, root.Position end
    return nil, nil
end

local function getClosest(radius)
    radius = radius or S.FOVRadius
    local vp = Camera.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local bestPart, bestPos, bestD, bestP, bestR = nil, nil, radius, nil, radius
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p) then
            local char = p.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead then
                local part, pos = zonePoint(char)
                if part then
                    local v, vis = Camera:WorldToViewportPoint(pos)
                    if vis and v.Z > 0 then
                        local d = (Vector2.new(v.X, v.Y) - center).Magnitude
                        local score = (p == lastTarget) and d * 0.6 or d
                        if d <= radius and score < bestD and (not S.WallCheck or wallClear(pos, char)) then
                            bestPart, bestPos, bestD, bestP, bestR = part, pos, score, p, d
                        end
                    end
                end
            end
        end
    end
    lastTarget = bestP
    return bestPart, bestPos, bestR
end

local function aimStep()
    Camera = Workspace.CurrentCamera or Camera
    if not (S.Aimbot or S.AimLegit or S.SilentAim) then
        silentPart, silentPos = nil, nil
        return
    end
    local part, pos = getClosest(S.FOVRadius)
    silentPart = S.SilentAim and part or nil
    silentPos = S.SilentAim and pos or nil
    if not part then return end

    local cf = Camera.CFrame
    if S.Aimbot then
        Camera.CFrame = cf:Lerp(CFrame.new(cf.Position, pos), math.clamp(S.AimSmooth / 100, 0.01, 1))
    elseif S.AimLegit then
        local t = os.clock() * 1.3
        local jitter = Vector3.new(math.noise(t, 0) * .6, math.noise(0, t) * .6, math.noise(t, t) * .6)
        Camera.CFrame = cf:Lerp(CFrame.new(cf.Position, pos + jitter), math.clamp(S.LegitSmooth / 100, 0.01, 1))
    end
end

local aimBindName = randName()
pcall(function()
    RunService:BindToRenderStep(aimBindName, Enum.RenderPriority.Last.Value, function()
        pcall(aimStep)
    end)
end)

-- ====================== PROTECAO (anti-deteccao embutida) ======================
-- * nomes de GUI aleatorios + protect_gui/gethui
-- * Highlights fora do personagem
-- * valores falsos (spoof) para scripts do jogo lerem: WalkSpeed e FieldOfView
-- * bloqueio de Kick pelo cliente
-- * anti-AFK
local hooksOk, hooksTried = false, false
local function ensureHooks()
    if hooksTried then return hooksOk end
    hooksTried = true
    hooksOk = pcall(function()
        assert(hookmetamethod and getnamecallmethod)
        local nc  = newcclosure or function(f) return f end
        local cc  = checkcaller or function() return false end
        local snm = setnamecallmethod
        local function roll() return S.SilentHit >= 100 or math.random(1, 100) <= S.SilentHit end

        local oldIndex
        oldIndex = hookmetamethod(game, "__index", nc(function(self, key)
            if alive and (key == "WalkSpeed" or key == "FieldOfView" or key == "Hit" or key == "Target") and not cc() then
                if key == "Hit" or key == "Target" then
                    if S.SilentAim and silentPart and silentPos and self == Mouse and roll() then
                        if key == "Hit" then return CFrame.new(silentPos) end
                        return silentPart
                    end
                elseif key == "WalkSpeed" then
                    if S.Speed and not S.SpeedCF and typeof(self) == "Instance" and self.ClassName == "Humanoid" then
                        local ch = LP.Character
                        if ch and self:IsDescendantOf(ch) then return origWalk or 16 end
                    end
                elseif key == "FieldOfView" then
                    if S.CamFOVOn and self == Workspace.CurrentCamera then return ORIGINAL_FOV end
                end
            end
            return oldIndex(self, key)
        end))

        local oldNC
        oldNC = hookmetamethod(game, "__namecall", nc(function(self, ...)
            local m = getnamecallmethod()
            if alive and not cc() then
                if (m == "Kick" or m == "kick") and self == LP then
                    return
                end
                if S.SilentAim and silentPos and self == Workspace then
                    if m == "Raycast" then
                        local args = {...}
                        local o, d = args[1], args[2]
                        if typeof(o) == "Vector3" and typeof(d) == "Vector3" and d.Magnitude >= 100 and roll() then
                            args[2] = (silentPos - o).Unit * d.Magnitude
                            if snm then snm(m) end
                            return oldNC(self, unpack(args, 1, select("#", ...)))
                        end
                    elseif m == "FindPartOnRay" or m == "FindPartOnRayWithIgnoreList" or m == "FindPartOnRayWithWhitelist" then
                        local args = {...}
                        local r = args[1]
                        if typeof(r) == "Ray" and r.Direction.Magnitude >= 100 and roll() then
                            args[1] = Ray.new(r.Origin, (silentPos - r.Origin).Unit * r.Direction.Magnitude)
                            if snm then snm(m) end
                            return oldNC(self, unpack(args, 1, select("#", ...)))
                        end
                    end
                end
            end
            return oldNC(self, ...)
        end))
    end)
    return hooksOk
end

-- anti-kick leve (sem hook global)
pcall(function()
    hookfunction(LP.Kick, newcclosure(function() end))
end)

-- ====================== ARMAS ======================
local AMMO_KEYS = {"ammo", "clip", "mag", "bullet", "round"}
local RELOAD_TIME_KEYS = {"time", "delay", "duration", "cooldown", "length"}
local store = setmetatable({}, {__mode = "k"})

local function has(name, list)
    for _, k in ipairs(list) do
        if name:find(k, 1, true) then return true end
    end
    return false
end

local function handleValue(inst, name, val, setter)
    local ln = name:lower()
    local st = store[inst]
    if not st then st = {ammo = {}}; store[inst] = st end

    if S.InfAmmo and has(ln, AMMO_KEYS) and not ln:find("max") then
        local m = st.ammo[name]
        if not m or val > m then st.ammo[name] = val; m = val end
        if val < m then setter(m) end
    end
    if S.FastReload and ln:find("reload") and has(ln, RELOAD_TIME_KEYS) and val > 0.02 then
        setter(0.01)
    end
end

local function processInst(inst)
    if inst:IsA("NumberValue") or inst:IsA("IntValue") then
        handleValue(inst, inst.Name, inst.Value, function(v) inst.Value = v end)
    end
    for name, val in pairs(inst:GetAttributes()) do
        if type(val) == "number" then
            handleValue(inst, name, val, function(v) inst:SetAttribute(name, v) end)
        end
    end
end

local function processTool(tool)
    processInst(tool)
    for _, d in ipairs(tool:GetDescendants()) do processInst(d) end
end

local acc = 0
connect(RunService.Heartbeat, function(dt)
    acc = acc + dt
    if acc < 0.12 then return end
    acc = 0
    if not (S.InfAmmo or S.FastReload) then return end

    local char = LP.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then processTool(t) end
        end
        if S.FastReload then
            local hum = char:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if animator then
                for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
                    if tr.Name:lower():find("reload") then tr:AdjustSpeed(6) end
                end
            end
        end
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then processTool(t) end
        end
    end
end)

-- ====================== TELEPORT ======================
local lastPos, savedPos

local function myRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tpCF(cf)
    local r = myRoot()
    if r then
        lastPos = r.CFrame
        r.CFrame = cf
        return true
    end
    return false
end

local function tpPlayer(p)
    local c = p.Character
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if r then return tpCF(r.CFrame * CFrame.new(0, 0, 3)) end
    return false
end

local function nearestPlayer()
    local me = myRoot()
    if not me then return nil end
    local best, bd = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p) then
            local c = p.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if h and r and h.Health > 0 then
                local d = (r.Position - me.Position).Magnitude
                if d < bd then best, bd = p, d end
            end
        end
    end
    return best
end

-- ====================== CONFIG ======================
local function saveConfig()
    return pcall(function() writefile(CFG_FILE, HttpService:JSONEncode(S)) end)
end

local function loadConfig()
    local ok, data = pcall(function()
        if isfile and isfile(CFG_FILE) then
            return HttpService:JSONDecode(readfile(CFG_FILE))
        end
    end)
    if ok and type(data) == "table" then
        for k, v in pairs(data) do
            if DEFAULT[k] ~= nil and type(v) == type(DEFAULT[k]) and uiSet[k] then
                uiSet[k](v)
            end
        end
        return true
    end
    return false
end

local function resetConfig()
    for k, v in pairs(DEFAULT) do
        if uiSet[k] then uiSet[k](v) end
    end
end

-- ====================== UNLOAD ======================
local function unload()
    alive = false
    pcall(function() RunService:UnbindFromRenderStep(aimBindName) end)
    for k, v in pairs(DEFAULT) do
        if type(v) == "boolean" then S[k] = false end
    end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for p in pairs(objs) do removeObj(p) end
    stopFly()
    pcall(function()
        local _, h, r = getChar()
        if h then Camera.CameraSubject = h end
        if r then r.CustomPhysicalProperties = nil; r.AssemblyAngularVelocity = Vector3.zero end
        Camera.FieldOfView = ORIGINAL_FOV
        Workspace.Gravity = ORIGINAL_GRAV
    end)
    if mainGui then mainGui:Destroy() end
    if espGui then espGui:Destroy() end
end
pcall(function() if getgenv then getgenv().DanorteUnload = unload end end)

-- ====================== PAINEL PRINCIPAL ======================
local function buildMain()
    mainGui = newGui(999)
    espGui  = newGui(998)
    toastFn = function(m) toast(mainGui, m) end

    fovCircle = new("Frame", {
        AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromOffset(S.FOVRadius * 2, S.FOVRadius * 2),
        BackgroundTransparency = 1, Visible = false, BorderSizePixel = 0,
    }, mainGui)
    circle(fovCircle)
    stroke(fovCircle, C.accent, 0, 1.5)

    local PW, PH = 340, 404
    local panel = new("Frame", {
        Size = UDim2.fromOffset(PW, PH), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ClipsDescendants = true,
    }, mainGui)
    corner(panel, 14)
    new("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(40, 8, 14), Color3.fromRGB(12, 12, 14)), Rotation = 90}, panel)
    local pStroke = stroke(panel, C.accent, 0, 1.5)
    local setOpen = makeScale(panel, PW, PH)
    setOpen(1, .4)
    connect(RunService.RenderStepped, function()
        pStroke.Transparency = .2 + .4 * (.5 + .5 * math.sin(os.clock() * 2.4))
    end)

    -- foto de fundo (fica atras de tudo; some se o arquivo nao existir)
    local bgImg = new("ImageLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Crop,
        ImageTransparency = BG_DIM, Visible = false,
    }, panel)
    corner(bgImg, 14)
    task.spawn(function()
        local a = resolveBG()
        if a and alive then bgImg.Image = a; bgImg.Visible = true end
    end)

    createParticles(panel, PW, PH, 26)

    -- cabecalho
    local dragArea = new("Frame", {Size = UDim2.new(1, -54, 0, 50), BackgroundTransparency = 1}, panel)
    makeDraggable(dragArea, panel)
    new("TextLabel", {
        Size = UDim2.fromOffset(220, 22), Position = UDim2.fromOffset(14, 8), BackgroundTransparency = 1,
        Text = "DANORTE MODS", TextColor3 = C.accent, Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
    new("TextLabel", {
        Size = UDim2.fromOffset(260, 12), Position = UDim2.fromOffset(14, 32), BackgroundTransparency = 1,
        Text = "v4.0  •  toque na bolha para abrir ou fechar", TextColor3 = C.sub, Font = Enum.Font.Gotham, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
    local closeBtn = new("TextButton", {
        Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -40, 0, 10), BackgroundColor3 = C.panel,
        Text = "–", TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false,
    }, panel)
    corner(closeBtn, 8)
    pressFx(closeBtn, C.panel, Color3.fromRGB(70, 16, 24))

    -- abas (rolam para o lado)
    local tabBar = new("ScrollingFrame", {
        Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 54), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 0, ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
    }, panel)
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, tabBar)

    local pages, tabs, pageRows = {}, {}, {}

    local function playEntrance(page)
        for i, entry in ipairs(pageRows[page]) do
            local row, tr = entry[1], entry[2]
            row.Position = UDim2.fromOffset(26, 0)
            row.BackgroundTransparency = 1
            task.delay((i - 1) * 0.025, function()
                tween(row, .35, {Position = UDim2.fromOffset(0, 0), BackgroundTransparency = tr})
            end)
        end
    end

    local function selectTab(name)
        for n, pg in pairs(pages) do
            local sel = (n == name)
            pg.Visible = sel
            tween(tabs[n], .25, {BackgroundColor3 = sel and C.accent or C.panel})
        end
        playEntrance(pages[name])
    end

    local function addPage(name)
        local page = new("ScrollingFrame", {
            Size = UDim2.new(1, -24, 1, -106), Position = UDim2.fromOffset(12, 94), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, ScrollBarImageColor3 = C.accent, AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(), Visible = false,
        }, panel)
        new("UIListLayout", {Padding = UDim.new(0, 8)}, page)
        new("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6)}, page)
        pages[name] = page
        pageRows[page] = {}

        local b = new("TextButton", {
            Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.panel,
            Text = name, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false,
        }, tabBar)
        corner(b, 8)
        new("UIPadding", {PaddingLeft = UDim.new(0, 13), PaddingRight = UDim.new(0, 13)}, b)
        tabs[name] = b
        b.Activated:Connect(function() selectTab(name) end)
        return page
    end

    local function newRow(page, height, class, tr)
        local holder = new("Frame", {Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1}, page)
        local props = {Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.panel, BackgroundTransparency = tr or .25, BorderSizePixel = 0}
        if class == "TextButton" then props.Text = ""; props.AutoButtonColor = false end
        local row = new(class or "Frame", props, holder)
        corner(row, 8)
        local list = pageRows[page]
        list[#list + 1] = {row, tr or .25}
        return row
    end

    local function rowTitle(row, text, w)
        return new("TextLabel", {
            Size = w or UDim2.new(1, -70, 0, 20), Position = UDim2.fromOffset(12, 5), BackgroundTransparency = 1, Text = text,
            TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
    end

    local function rowDesc(row, text, y)
        return new("TextLabel", {
            Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(12, y), BackgroundTransparency = 1, Text = text,
            TextColor3 = C.sub, Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        }, row)
    end

    local function section(page, text)
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = text, TextColor3 = C.accent, TextTransparency = .15,
            Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
        }, page)
    end

    local function addToggle(page, title, desc, key, cb)
        local row = newRow(page, 56, "TextButton")
        pressFx(row, C.panel, Color3.fromRGB(40, 40, 46))
        rowTitle(row, title)
        rowDesc(row, desc, 26)
        local track = new("Frame", {
            Size = UDim2.fromOffset(40, 18), Position = UDim2.new(1, -52, 0, 8), BorderSizePixel = 0,
            BackgroundColor3 = S[key] and C.accent or C.off,
        }, row)
        circle(track)
        local knob = new("Frame", {
            Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
            Position = S[key] and UDim2.fromOffset(24, 2) or UDim2.fromOffset(2, 2),
        }, track)
        circle(knob)
        local function setVal(v)
            S[key] = v
            tween(track, .2, {BackgroundColor3 = v and C.accent or C.off})
            tween(knob, .2, {Position = v and UDim2.fromOffset(24, 2) or UDim2.fromOffset(2, 2)})
            if cb then cb(v) end
        end
        uiSet[key] = setVal
        row.Activated:Connect(function() setVal(not S[key]) end)
    end

    local function addSlider(page, title, desc, key, min, max, step, cb)
        local row = newRow(page, 76)
        rowTitle(row, title)
        local vl = new("TextLabel", {
            Size = UDim2.fromOffset(70, 20), Position = UDim2.new(1, -82, 0, 5), BackgroundTransparency = 1,
            Text = tostring(math.floor(S[key] * 10 + .5) / 10), TextColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, row)
        local bar = new("Frame", {Size = UDim2.new(1, -24, 0, 6), Position = UDim2.fromOffset(12, 30), BackgroundColor3 = Color3.fromRGB(50, 50, 56), BorderSizePixel = 0}, row)
        corner(bar, 3)
        local r0 = math.clamp((S[key] - min) / (max - min), 0, 1)
        local fill = new("Frame", {Size = UDim2.new(r0, 0, 1, 0), BackgroundColor3 = C.accent, BorderSizePixel = 0}, bar)
        corner(fill, 3)
        rowDesc(row, desc, 44)
        local hit = new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3}, row)

        local function apply(v)
            v = math.clamp(v, min, max)
            S[key] = v
            tween(fill, .08, {Size = UDim2.new((v - min) / (max - min), 0, 1, 0)})
            vl.Text = tostring(math.floor(v * 10 + .5) / 10)
            if cb then cb(v) end
        end
        uiSet[key] = apply

        local dragging = false
        local function setX(x)
            local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            apply(math.floor((min + (max - min) * rel) / step + .5) * step)
        end
        hit.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                page.ScrollingEnabled = false
                setX(i.Position.X)
                i.Changed:Connect(function()
                    if i.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        page.ScrollingEnabled = true
                    end
                end)
            end
        end)
        connect(UIS.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                setX(i.Position.X)
            end
        end)
    end

    local function addSelector(page, title, desc, key, options)
        local row = newRow(page, 74)
        rowTitle(row, title, UDim2.fromOffset(60, 20))
        rowDesc(row, desc, 38)
        local btns, n = {}, #options
        local function setVal(v)
            S[key] = v
            for i, b in ipairs(btns) do
                tween(b, .2, {BackgroundColor3 = (i == v) and C.accent or Color3.fromRGB(44, 44, 50)})
            end
        end
        for i, name in ipairs(options) do
            local b = new("TextButton", {
                Size = UDim2.fromOffset(56, 24), Position = UDim2.new(1, -12 - (n - i + 1) * 56 - (n - i) * 6, 0, 6),
                BackgroundColor3 = Color3.fromRGB(44, 44, 50), Text = name, TextColor3 = Color3.new(1, 1, 1),
                Font = Enum.Font.GothamBold, TextSize = 11, AutoButtonColor = false,
            }, row)
            corner(b, 6)
            b.Activated:Connect(function() setVal(i) end)
            btns[i] = b
        end
        uiSet[key] = setVal
        setVal(S[key])
    end

    local function addButton(page, text, cb, kind)
        local normal, pressed = C.accent, Color3.fromRGB(150, 18, 30)
        if kind == "gray" then normal, pressed = Color3.fromRGB(40, 40, 46), Color3.fromRGB(62, 62, 70)
        elseif kind == "danger" then normal, pressed = Color3.fromRGB(120, 18, 30), Color3.fromRGB(90, 12, 22) end
        local b = newRow(page, 36, "TextButton", 0)
        b.BackgroundColor3 = normal
        b.Text = text; b.TextColor3 = Color3.new(1, 1, 1); b.Font = Enum.Font.GothamBold; b.TextSize = 12
        pressFx(b, normal, pressed)
        b.Activated:Connect(cb)
        return b
    end

    -- ---- Visual
    local visual = addPage("Visual")
    section(visual, "ESP")
    addToggle(visual, "ESP Linha", "Linha da base da tela até cada inimigo.", "ESPLine")
    addToggle(visual, "ESP Esqueleto", "Desenha os ossos do personagem inimigo.", "Skeleton")
    addToggle(visual, "ESP Chams", "Destaca o inimigo inteiro, até atrás de paredes.", "Chams")
    section(visual, "FILTROS")
    addToggle(visual, "Ignorar inimigo morto", "Não mostra quem está com a vida zerada.", "IgnoreDead")
    addToggle(visual, "Ignorar amigo", "Não mostra jogadores do seu time.", "IgnoreTeam")
    addToggle(visual, "ESP só dentro do FOV", "Mostra apenas quem está dentro do círculo do FOV.", "FOVOnly")

    -- ---- Aim
    local aim = addPage("Aim")
    section(aim, "ONDE ATIRAR")
    addSelector(aim, "Região", "Parte do corpo que o aim, o legit e o silent vão mirar.", "AimZone", ZONES)
    section(aim, "FOV")
    addToggle(aim, "Mostrar FOV", "Círculo na tela com o alcance da mira.", "ShowFOV", function(on) fovCircle.Visible = on end)
    addSlider(aim, "Tamanho do FOV", "Quanto maior, mais longe do centro ele aceita alvos.", "FOVRadius", 40, 400, 5, function(v)
        fovCircle.Size = UDim2.fromOffset(v * 2, v * 2)
    end)
    section(aim, "AIMBOT")
    addToggle(aim, "Aimbot", "Trava a mira no inimigo dentro do FOV.", "Aimbot")
    addSlider(aim, "Força do aimbot (%)", "100 trava na hora. Menos que isso puxa mais devagar.", "AimSmooth", 5, 100, 1)
    addToggle(aim, "Checar parede", "Ignora inimigos que estão atrás de paredes.", "WallCheck")
    section(aim, "AIM LEGIT")
    addToggle(aim, "Aim Legit", "Puxada suave e humana, com leve balanço.", "AimLegit")
    addSlider(aim, "Suavidade legit (%)", "Menor = mais lento e natural.", "LegitSmooth", 2, 40, 1)
    section(aim, "SILENT AIM")
    addToggle(aim, "Silent Aim", "Os tiros vão na região escolhida sem mexer a câmera.", "SilentAim", function(on)
        if on and not ensureHooks() then
            toastFn("Silent Aim indisponível neste executor")
            task.defer(function() uiSet.SilentAim(false) end)
        end
    end)
    addSlider(aim, "Chance de acerto (%)", "Menos que 100 faz alguns tiros saírem normais.", "SilentHit", 10, 100, 1)
    section(aim, "AMIGOS (aim e ESP ignoram)")
    local fList = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, aim)
    new("UIListLayout", {Padding = UDim.new(0, 5)}, fList)

    -- ---- Player
    local player = addPage("Player")
    section(player, "MOVIMENTO")
    addToggle(player, "Velocidade", "Aumenta a velocidade do personagem.", "Speed", function(on)
        local _, h = getChar()
        if on then
            ensureHooks()
            if h and not origWalk then origWalk = h.WalkSpeed end
        else
            if h then h.WalkSpeed = origWalk or 16 end
        end
    end)
    addSlider(player, "Valor da velocidade", "16 é a velocidade normal.", "SpeedValue", 16, 200, 1)
    addToggle(player, "Speed CFrame", "Use se o jogo ficar resetando a velocidade.", "SpeedCF")
    section(player, "CÂMERA")
    addToggle(player, "Barra de FOV", "Muda o campo de visão da câmera.", "CamFOVOn", function(on)
        if on then ensureHooks() end
        if not on then Camera.FieldOfView = ORIGINAL_FOV end
    end)
    addSlider(player, "FOV da câmera", "Maior = vê mais dos lados.", "CamFOV", 30, 120, 1)

    -- ---- Armas
    local guns = addPage("Armas")
    section(guns, "ARMAS")
    addToggle(guns, "Munição infinita", "Mantém a munição da arma cheia.", "InfAmmo")
    addToggle(guns, "Recarga rápida", "Reduz o tempo de recarga.", "FastReload")

    -- ---- Teleport
    local tp = addPage("Teleport")
    section(tp, "ATALHOS")
    addButton(tp, "TP no inimigo mais próximo", function()
        local p = nearestPlayer()
        if p and tpPlayer(p) then toastFn("Teleportado para " .. p.Name) else toastFn("Nenhum inimigo encontrado") end
    end)
    addButton(tp, "Salvar posição atual", function()
        local r = myRoot()
        if r then savedPos = r.CFrame; toastFn("Posição salva") end
    end, "gray")
    addButton(tp, "Ir para a posição salva", function()
        if savedPos then tpCF(savedPos); toastFn("Teleportado") else toastFn("Salve uma posição primeiro") end
    end, "gray")
    addButton(tp, "Voltar (último TP)", function()
        if lastPos then
            local r = myRoot()
            if r then local back = lastPos; lastPos = r.CFrame; r.CFrame = back end
        else toastFn("Sem TP anterior") end
    end, "gray")
    section(tp, "JOGADORES (toque para ir)")
    local listFrame = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, tp)
    new("UIListLayout", {Padding = UDim.new(0, 5)}, listFrame)

    -- ---- Troll
    local troll = addPage("Troll")
    section(troll, "SOLO")
    addToggle(troll, "Noclip", "Atravessa paredes e objetos.", "Noclip")
    addToggle(troll, "Pulo infinito", "Pula no ar quantas vezes quiser.", "InfJump")
    addToggle(troll, "Fly (voar)", "O joystick voa para onde a câmera olha.", "Fly", function(on)
        if not on then stopFly() end
    end)
    addSlider(troll, "Velocidade do fly", "Quanto maior, mais rápido você voa.", "FlySpeed", 10, 200, 1)
    addToggle(troll, "Girar", "O personagem gira sem parar.", "Spin")
    addSlider(troll, "Velocidade do giro", "Graus por quadro.", "SpinSpeed", 3, 60, 1)
    addToggle(troll, "Fling", "Arremessa quem encostar em você.", "Fling", function(on)
        local _, _, r = getChar()
        if r then
            r.CustomPhysicalProperties = on and PhysicalProperties.new(100, 0.3, 0.5) or nil
            if not on then r.AssemblyAngularVelocity = Vector3.zero end
        end
    end)
    addSlider(troll, "Gravidade", "196 é o normal. Menor = pulos mais altos.", "Gravity", 10, 300, 1, function(v) Workspace.Gravity = v end)

    section(troll, "ALVO")
    local targetLabel = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = "Alvo: nenhum", TextColor3 = C.text,
        Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, troll)

    local function needTarget(key, extra)
        return function(on)
            if on and not trollTarget then
                toastFn("Escolha um alvo na lista abaixo")
                task.defer(function() uiSet[key](false) end)
                return
            end
            if extra then extra(on) end
        end
    end
    addToggle(troll, "Orbitar alvo", "Gira em volta do jogador escolhido.", "Orbit", needTarget("Orbit"))
    addToggle(troll, "Grudar no alvo", "Fica colado atrás do jogador.", "Follow", needTarget("Follow"))
    addToggle(troll, "Espectar alvo", "A câmera passa para a visão do jogador.", "Spectate", needTarget("Spectate", function(on)
        local _, h = getChar()
        if on then
            local th = trollTarget.Character and trollTarget.Character:FindFirstChildOfClass("Humanoid")
            if th then Camera.CameraSubject = th end
        elseif h then
            Camera.CameraSubject = h
        end
    end))
    addButton(troll, "Fling no alvo (2s)", function()
        if not trollTarget then toastFn("Escolha um alvo"); return end
        local me = myRoot()
        if not me then return end
        local origin = me.CFrame
        task.spawn(function()
            local t0 = os.clock()
            while os.clock() - t0 < 2 and alive do
                local tr, mr = targetRoot(), myRoot()
                if not (tr and mr) then break end
                mr.CFrame = tr.CFrame
                mr.AssemblyAngularVelocity = Vector3.new(0, 16000, 0)
                RunService.Heartbeat:Wait()
            end
            local mr = myRoot()
            if mr then
                mr.AssemblyAngularVelocity = Vector3.zero
                mr.AssemblyLinearVelocity = Vector3.zero
                mr.CFrame = origin
            end
        end)
    end, "danger")
    local tList = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, troll)
    new("UIListLayout", {Padding = UDim.new(0, 5)}, tList)

    local function listButton(parent, text, selected)
        local b = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = selected and C.accent or C.panel, BackgroundTransparency = .2,
            Text = text, TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 11, AutoButtonColor = false,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, parent)
        corner(b, 8)
        return b
    end

    local function refreshLists()
        for _, c in ipairs(listFrame:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        for _, c in ipairs(tList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        for _, c in ipairs(fList:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then
                local label = p.DisplayName .. "  (@" .. p.Name .. ")"
                local b = listButton(listFrame, label, false)
                pressFx(b, C.panel, Color3.fromRGB(70, 16, 24))
                b.Activated:Connect(function()
                    if tpPlayer(p) then toastFn("Teleportado para " .. p.Name) else toastFn("Jogador sem personagem") end
                end)
                local t = listButton(tList, label, trollTarget == p)
                t.Activated:Connect(function()
                    trollTarget = p
                    targetLabel.Text = "Alvo: " .. p.Name
                    for _, c in ipairs(tList:GetChildren()) do
                        if c:IsA("TextButton") then tween(c, .2, {BackgroundColor3 = C.panel}) end
                    end
                    tween(t, .2, {BackgroundColor3 = C.accent})
                end)

                -- amigo (aim e ESP ignoram)
                local function fLabel() return (friends[p.UserId] and "✔ " or "") .. label end
                local f = listButton(fList, fLabel(), friends[p.UserId] ~= nil)
                f.Activated:Connect(function()
                    friends[p.UserId] = (not friends[p.UserId]) or nil
                    saveFriends()
                    f.Text = fLabel()
                    tween(f, .2, {BackgroundColor3 = friends[p.UserId] and C.accent or C.panel})
                    toastFn(friends[p.UserId] and (p.Name .. " é amigo") or (p.Name .. " removido"))
                end)
            end
        end
        if trollTarget and not trollTarget.Parent then
            trollTarget = nil
            targetLabel.Text = "Alvo: nenhum"
        end
    end
    refreshLists()
    connect(Players.PlayerAdded, function() task.delay(.3, refreshLists) end)
    connect(Players.PlayerRemoving, function() task.delay(.3, refreshLists) end)

    -- ---- Config
    local cfg = addPage("Config")
    section(cfg, "FUNÇÕES")
    addButton(cfg, "Salvar configuração", function()
        if saveConfig() then toastFn("Configuração salva!") else toastFn("Não foi possível salvar") end
    end)
    addButton(cfg, "Carregar configuração", function()
        if loadConfig() then toastFn("Configuração carregada!") else toastFn("Nenhuma config salva") end
    end, "gray")
    addButton(cfg, "Resetar tudo", function()
        resetConfig(); toastFn("Funções resetadas")
    end, "gray")
    section(cfg, "PAINEL")
    addButton(cfg, "Descarregar Danorte Mods", function() unload() end, "danger")

    selectTab("Visual")

    -- ---- bolha flutuante (levita)
    local fab = new("TextButton", {
        Size = UDim2.fromOffset(54, 54), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.new(0, 44, .5, 0),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5,
    }, mainGui)
    local fabIn = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.bg, BorderSizePixel = 0}, fab)
    circle(fabIn)
    local fs = stroke(fabIn, C.accent, 2.5)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "D", TextColor3 = C.accent,
        Font = Enum.Font.GothamBlack, TextSize = 26,
    }, fabIn)
    -- foto redonda na bolha (embutida; se falhar, fica a letra D)
    task.spawn(function(parent)
        pcall(function()
            if not (isfile and writefile and getcustomasset) then return end
            local FAB_FILE = "DanorteMods_fab.jpg"
            if not isfile(FAB_FILE) then
                local EMB = [==[
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
]==]
                local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
                local map = {}
                for i = 1, 64 do map[chars:byte(i)] = i - 1 end
                local s = (EMB:gsub("[^%w%+/=]", ""))
                local out = {}
                for i = 1, #s, 4 do
                    local a, b, c, d = s:byte(i, i + 3)
                    local v = (map[a] or 0) * 262144 + (map[b] or 0) * 4096 + (map[c] or 0) * 64 + (map[d] or 0)
                    local b1, b2, b3 = math.floor(v / 65536), math.floor(v / 256) % 256, v % 256
                    if c == 61 then out[#out + 1] = string.char(b1)
                    elseif d == 61 then out[#out + 1] = string.char(b1, b2)
                    else out[#out + 1] = string.char(b1, b2, b3) end
                end
                writefile(FAB_FILE, table.concat(out))
            end
            local asset = getcustomasset(FAB_FILE)
            if not asset or not alive then return end
            local img = Instance.new("ImageLabel")
            img.Size = UDim2.fromScale(1, 1)
            img.BackgroundTransparency = 1
            img.Image = asset
            img.ScaleType = Enum.ScaleType.Crop
            img.Active = false
            local rc = Instance.new("UICorner")
            rc.CornerRadius = UDim.new(1, 0)
            rc.Parent = img
            img.Parent = parent
            local dLbl = parent:FindFirstChildOfClass("TextLabel")
            if dLbl then dLbl.Visible = false end
        end)
    end, fabIn)
    connect(RunService.RenderStepped, function()
        local t = os.clock()
        fabIn.Position = UDim2.fromOffset(0, math.sin(t * 2.2) * 4)
        fs.Transparency = .15 + .45 * (.5 + .5 * math.sin(t * 2.6))
    end)

    local menuOpen = true
    local function toggleMenu()
        menuOpen = not menuOpen
        if menuOpen then
            panel.Visible = true
            setOpen(1, .3)
        else
            setOpen(.85, .2)
            task.delay(.2, function() if not menuOpen then panel.Visible = false end end)
        end
    end
    makeDraggable(fab, fab, toggleMenu)
    closeBtn.Activated:Connect(function() if menuOpen then toggleMenu() end end)

    local loaded = loadConfig()
    toast(mainGui, loaded and "Danorte Mods carregado! Config restaurada." or "Danorte Mods carregado!")

    -- ---- controle remoto (gerador): manutencao, funcoes, abas, fotos, aviso
    if REMOTE_URL ~= "" then task.spawn(function()
        local lastRaw, lastNotice, inMaint, card, msgLbl = nil, nil, false, nil, nil
        local applied, prevHide, prevOff, origSet = {}, {}, {}, {}
        panel.Visible = false; fab.Visible = false -- escondidos ate a 1a checagem

        local function b64dec(str)
            local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            local map = {}
            for i = 1, 64 do map[chars:byte(i)] = i - 1 end
            local s = (str:gsub("[^%w%+/=]", ""))
            local out = {}
            for i = 1, #s, 4 do
                local a, b, c, d = s:byte(i, i + 3)
                local v = (map[a] or 0) * 262144 + (map[b] or 0) * 4096 + (map[c] or 0) * 64 + (map[d] or 0)
                local b1, b2, b3 = math.floor(v / 65536), math.floor(v / 256) % 256, v % 256
                if c == 61 then out[#out + 1] = string.char(b1)
                elseif d == 61 then out[#out + 1] = string.char(b1, b2)
                else out[#out + 1] = string.char(b1, b2, b3) end
            end
            return table.concat(out)
        end

        local function hashStr(s)
            local h = #s
            for i = 1, #s, 53 do h = (h * 31 + s:byte(i)) % 4294967291 end
            return string.format("%x", h)
        end

        local function mkFabImg()
            local img = Instance.new("ImageLabel")
            img.Size = UDim2.fromScale(1, 1); img.BackgroundTransparency = 1
            img.ScaleType = Enum.ScaleType.Crop; img.Active = false
            local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = img
            img.Parent = fabIn
            return img
        end

        -- troca foto (b64 tem prioridade sobre link); vazio volta pra padrao embutida
        local function setImage(kind, b64, url)
            local key = (b64 ~= "" and b64) or url
            if key == applied[kind] then return end
            applied[kind] = key
            local asset
            if key ~= "" then
                local ok, res = pcall(function()
                    if not (writefile and getcustomasset) then return end
                    local ext = (b64 == "" and url:lower():find("%.png")) and ".png" or ".jpg"
                    local name = "DanorteMods_r_" .. kind .. "_" .. hashStr(key) .. ext
                    if not (isfile and isfile(name)) then
                        writefile(name, b64 ~= "" and b64dec(b64) or game:HttpGet(url))
                    end
                    return getcustomasset(name)
                end)
                if ok then asset = res end
                if not asset then return end -- falhou: mantem a foto atual
            end
            if kind == "bg" then
                if asset then
                    bgImg.Image = asset; bgImg.Visible = true
                else
                    local okd, a = pcall(resolveBG)
                    bgImg.Image = (okd and a) or ""; bgImg.Visible = (okd and a) and true or false
                end
            else
                local lbl = fabIn:FindFirstChildOfClass("TextLabel")
                local img = fabIn:FindFirstChildOfClass("ImageLabel")
                if not asset and isfile and getcustomasset and isfile("DanorteMods_fab.jpg") then
                    local okd, a = pcall(getcustomasset, "DanorteMods_fab.jpg")
                    if okd then asset = a end
                end
                if asset then
                    img = img or mkFabImg()
                    img.Image = asset
                    if lbl then lbl.Visible = false end
                else
                    if img then img:Destroy() end
                    if lbl then lbl.Visible = true end
                end
            end
        end

        local function toSet(t)
            local s = {}
            if type(t) == "table" then for _, v in ipairs(t) do s[v] = true end end
            return s
        end

        -- esconde linhas por titulo, abas inteiras, e trava funcoes desativadas
        local function layout(cfg)
            local hide, off, tabsOff = toSet(cfg.hide), toSet(cfg.off), toSet(cfg.tabs)
            for _, pg in pairs(pages) do
                for _, holder in ipairs(pg:GetChildren()) do
                    if holder:IsA("Frame") then
                        local row = holder:FindFirstChildWhichIsA("GuiObject")
                        if row then
                            local t
                            if row:IsA("TextButton") and row.Text ~= "" then t = row.Text
                            else
                                local lb = row:FindFirstChildOfClass("TextLabel")
                                t = lb and lb.Text
                            end
                            if t then
                                if hide[t] then holder.Visible = false
                                elseif prevHide[t] then holder.Visible = true end
                            end
                        end
                    end
                end
            end
            prevHide = hide

            for k in pairs(off) do
                local d = DEFAULT[k]
                if uiSet[k] and d ~= nil then
                    if not origSet[k] then origSet[k] = uiSet[k] end
                    local o = origSet[k]
                    if type(d) == "boolean" then
                        uiSet[k] = function(v) if v ~= true then o(v) end end
                        if S[k] then o(false) end
                    else
                        uiSet[k] = function() o(d) end
                        if S[k] ~= d then o(d) end
                    end
                end
            end
            for k in pairs(prevOff) do
                if not off[k] and origSet[k] then uiSet[k] = origSet[k]; origSet[k] = nil end
            end
            prevOff = off

            local reselect = false
            for n, b in pairs(tabs) do
                local hid = tabsOff[n] == true
                b.Visible = not hid
                if hid and pages[n].Visible then pages[n].Visible = false; reselect = true end
            end
            if reselect then
                for _, n in ipairs({"Visual", "Aim", "Player", "Armas", "Teleport", "Troll", "Config"}) do
                    if tabs[n] and tabs[n].Visible then selectTab(n); break end
                end
            end
        end

        local function maint(on, msg)
            if on then
                for k, d in pairs(DEFAULT) do
                    if type(d) == "boolean" and S[k] and uiSet[k] then pcall(uiSet[k], false) end
                end
                panel.Visible = false; fab.Visible = false
                if not card then
                    card = new("Frame", {
                        Size = UDim2.fromOffset(280, 130), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
                        BackgroundColor3 = C.bg, BorderSizePixel = 0, ZIndex = 20,
                    }, mainGui)
                    corner(card, 14); stroke(card, C.accent, 0, 1.5)
                    new("TextLabel", {
                        Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 12), BackgroundTransparency = 1,
                        Text = "EM MANUTENÇÃO", TextColor3 = C.accent, Font = Enum.Font.GothamBlack, TextSize = 16, ZIndex = 21,
                    }, card)
                    msgLbl = new("TextLabel", {
                        Size = UDim2.new(1, -24, 1, -52), Position = UDim2.fromOffset(12, 42), BackgroundTransparency = 1,
                        Text = "", TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true,
                        TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 21,
                    }, card)
                end
                msgLbl.Text = msg
                inMaint = true
            elseif inMaint then
                if card then card:Destroy(); card = nil end
                panel.Visible = menuOpen; fab.Visible = true
                inMaint = false
            end
        end

        local function apply(cfg)
            pcall(setRemoteBlocked, cfg.blocked)
            if cfg.kill == true then unload(); return end
            pcall(layout, cfg)
            pcall(function()
                setImage("bg", type(cfg.bgB64) == "string" and cfg.bgB64 or "", type(cfg.bgUrl) == "string" and cfg.bgUrl or "")
                setImage("fab", type(cfg.fabB64) == "string" and cfg.fabB64 or "", type(cfg.fabUrl) == "string" and cfg.fabUrl or "")
                bgImg.ImageTransparency = type(cfg.bgDim) == "number" and math.clamp(cfg.bgDim, 0, 1) or BG_DIM
            end)
            local mOn = cfg.maintenance == true
            pcall(maint, mOn, type(cfg.msg) == "string" and cfg.msg or "Painel em manutenção.")
            local n = cfg.notice
            if not mOn and type(n) == "string" and n ~= "" and n ~= lastNotice then
                lastNotice = n
                toast(mainGui, n)
            end
        end

        local failed = false
        local function fail(m, detail)
            if failed then return end
            failed = true
            toast(mainGui, "Controle remoto: " .. m)
            if detail then task.delay(2.6, function() if alive then toast(mainGui, detail) end end) end
        end
        local function poll()
            local raw = fetchRemote()
            if not raw then
                return fail("não consegui abrir o link", lastFetchErr:sub(1, 42) .. " | " .. REMOTE_URL:sub(1, 30))
            end
            if raw == lastRaw then return end
            local okj, cfg = pcall(function() return HttpService:JSONDecode(raw) end)
            if not okj or type(cfg) ~= "table" then
                return fail("o link abriu mas não é uma config válida", "use o link raw (pastebin.com/raw/...)")
            end
            failed = false
            lastRaw = raw
            apply(cfg)
        end

        task.wait(1) -- deixa o fundo/bolha padrao carregarem antes de aplicar
        pcall(poll)
        if alive and not inMaint then panel.Visible = menuOpen; fab.Visible = true end
        while alive do
            task.wait(math.max(5, REMOTE_POLL))
            if not alive then break end
            pcall(poll)
        end
    end) end
end

-- ====================== CONTA + KEY (painel unico) ======================
local KEY_SECRET    = "DanorteMods-2026" -- igual a "Chave secreta" do gerador
local REQUIRE_BOUND = true -- true = so aceita keys presas ao aparelho (uma key por celular)
local ACC_FILE      = "DanorteMods_acc.json"
local LOG_WEBHOOK   = ""  -- opcional: webhook do Discord que recebe os logs de conta/login
local BLOCKLIST_URL = ""  -- opcional: link raw (Pastebin) com a lista de bloqueio do gerador
BLOCKLIST_URL = fixLink(BLOCKLIST_URL)
local KEY_AL        = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local function round(a, b, c, d, M)
    a = (a + b) % M; d = bit32.lrotate(bit32.bxor(d, a), 16)
    c = (c + d) % M; b = bit32.lrotate(bit32.bxor(b, c), 12)
    a = (a + b) % M; d = bit32.lrotate(bit32.bxor(d, a), 8)
    c = (c + d) % M; b = bit32.lrotate(bit32.bxor(b, c), 7)
    return a, b, c, d
end

local function keySig(p, dev)
    local M = 4294967296
    local a, b, c, d = 0x243F6A88, 0x85A308D3, 0x13198A2E, 0x03707344
    for i = 1, #KEY_SECRET do a = (a + KEY_SECRET:byte(i)) % M; a, b, c, d = round(a, b, c, d, M) end
    a = (a + p % M) % M; a, b, c, d = round(a, b, c, d, M)
    a = (a + math.floor(p / M)) % M; a, b, c, d = round(a, b, c, d, M)
    if dev then a = (a + dev) % M; a, b, c, d = round(a, b, c, d, M) end
    for _ = 1, 4 do a, b, c, d = round(a, b, c, d, M) end
    return bit32.band(bit32.bxor(b, d), 255) * M + bit32.bxor(a, c)
end

local function hashText(str)
    local M = 4294967296
    local a, b, c, d = 0x13198A2E, 0x03707344, 0x243F6A88, 0x85A308D3
    for i = 1, #str do a = (a + str:byte(i)) % M; a, b, c, d = round(a, b, c, d, M) end
    for _ = 1, 8 do a, b, c, d = round(a, b, c, d, M) end
    return string.format("%08x%08x", bit32.bxor(a, c), bit32.bxor(b, d))
end

local DEVICE_NUM
local function getDeviceNum()
    if DEVICE_NUM then return DEVICE_NUM end
    local raw
    pcall(function() if gethwid then raw = gethwid() end end)
    if type(raw) ~= "string" or raw == "" then
        pcall(function() raw = game:GetService("RbxAnalyticsService"):GetClientId() end)
    end
    if type(raw) ~= "string" or raw == "" then -- ultimo caso: id aleatorio salvo neste aparelho
        pcall(function()
            local f = "DanorteMods_dev.txt"
            if isfile and isfile(f) then raw = readfile(f)
            elseif writefile then raw = HttpService:GenerateGUID(false); writefile(f, raw) end
        end)
    end
    DEVICE_NUM = tonumber(hashText("DM|" .. tostring(raw or "x")):sub(1, 8), 16) or 0
    return DEVICE_NUM
end
local function deviceCode()
    local n = string.format("%08X", getDeviceNum())
    return n:sub(1, 4) .. "-" .. n:sub(5)
end

local function keyDec(str)
    local n = 0
    for i = 1, #str do
        local idx = KEY_AL:find(str:sub(i, i), 1, true)
        if not idx then return nil end
        n = n * 32 + (idx - 1)
    end
    return n
end

local function trim(str) return (str:gsub("^%s+", ""):gsub("%s+$", "")) end

local blocked = {}
local function refreshBlocklist()
    if REMOTE_URL ~= "" then
        pcall(function()
            local raw = fetchRemote()
            local cfg = raw and HttpService:JSONDecode(raw)
            if type(cfg) == "table" then setRemoteBlocked(cfg.blocked) end
        end)
    end
    if BLOCKLIST_URL == "" then return true end
    local ok, res = pcall(function() return game:HttpGet(BLOCKLIST_URL) end)
    if not ok or type(res) ~= "string" then return false end
    blocked = {}
    for line in res:gmatch("[^\r\n]+") do
        local k = (line:upper():gsub("[^A-Z0-9]", ""))
        if k:sub(1, 7) == "DANORTE" then k = k:sub(8) end
        if #k >= 8 then blocked[k:sub(1, 8)] = true end
    end
    return true
end

local function keyInfo(k)
    local raw = (string.upper(k or ""):gsub("[^A-Z0-9]", ""))
    if raw:sub(1, 7) == "DANORTE" then raw = raw:sub(8) end
    if #raw ~= 16 then return nil, "Formato de key invalido." end
    local p, sg = keyDec(raw:sub(1, 8)), keyDec(raw:sub(9))
    if not p or not sg then return nil, "Key invalida." end
    local field = math.floor(p / 16777216)
    if field >= 32768 then -- key presa a um aparelho
        if keySig(p, getDeviceNum()) ~= sg then return nil, "Key invalida ou de outro aparelho." end
        return raw:sub(1, 8), field - 32768
    end
    if keySig(p) ~= sg then return nil, "Key invalida." end
    if REQUIRE_BOUND then return nil, "Key sem aparelho. Peça uma nova com o seu ID." end
    return raw:sub(1, 8), field
end

local function checkKey(k)
    local id, exp = keyInfo(k)
    if not id then return false, exp end
    if blocked[id] or REMOTE_BLOCKED[id] then return false, "Key pausada ou desativada." end
    if exp ~= 0 then
        local left = exp - math.floor((os.time() - 1704067200) / 86400)
        if left < 0 then return false, "Key expirada." end
        return true, "Key ativa até " .. os.date("!%d/%m/%Y", 1704067200 + exp * 86400) .. ".", id
    end
    return true, "Key vitalicia.", id
end

local function sendLog(event, acc)
    if LOG_WEBHOOK == "" then return end
    task.spawn(function()
        pcall(function()
            local req = (syn and syn.request) or request or http_request or (http and http.request)
            if not req then return end
            local id = keyInfo(acc.k) or "?"
            local text = ("**Danorte Mods** | %s | conta: %s | Roblox: %s (%d) | key: %s | aparelho: %s | jogo: %d | %s UTC"):format(
                event, acc.u, LP.Name, LP.UserId, id, deviceCode(), game.PlaceId, os.date("!%d/%m/%Y %H:%M"))
            req({
                Url = LOG_WEBHOOK, Method = "POST", Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode({content = text, allowed_mentions = {parse = {}}}),
            })
        end)
    end)
end

local function loadAcc()
    local ok, d = pcall(function()
        if isfile and isfile(ACC_FILE) then return HttpService:JSONDecode(readfile(ACC_FILE)) end
    end)
    if ok and type(d) == "table" and d.u and d.h and d.k then return d end
end

local function enterApp(acc)
    buildMain()
    task.spawn(function()
        local last = os.clock()
        while alive do
            task.wait(5)
            if not alive then return end
            if os.clock() - last >= 60 then last = os.clock(); refreshBlocklist() end
            local ok, text = checkKey(acc.k)
            if not ok then
                toastFn("Acesso encerrado: " .. text)
                task.wait(2.5)
                unload()
                return
            end
        end
    end)
end

local function showAuth()
    local acc = loadAcc()
    local gui = newGui(1000)
    local CW, H_LOGIN, H_CREATE = 300, 324, 376

    local card = new("Frame", {
        Size = UDim2.fromOffset(CW, H_CREATE), AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ClipsDescendants = true,
    }, gui)
    corner(card, 14)
    new("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(40, 8, 14), Color3.fromRGB(12, 12, 14)), Rotation = 90}, card)
    local cs = stroke(card, C.accent, 0, 1.5)
    local setOpen = makeScale(card, CW, H_CREATE)
    setOpen(1, .4)
    local pconn = createParticles(card, CW, H_CREATE, 22)
    connect(RunService.RenderStepped, function()
        cs.Transparency = .2 + .4 * (.5 + .5 * math.sin(os.clock() * 2.4))
    end)
    makeDraggable(card, card)

    new("TextLabel", {
        Size = UDim2.fromOffset(240, 24), Position = UDim2.fromOffset(18, 12), BackgroundTransparency = 1,
        Text = "DANORTE MODS", TextColor3 = C.accent, Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    new("TextLabel", {
        Size = UDim2.fromOffset(260, 12), Position = UDim2.fromOffset(18, 38), BackgroundTransparency = 1,
        Text = LOG_WEBHOOK ~= "" and "Os acessos são registrados pelo administrador" or "Entre ou crie sua conta",
        TextColor3 = C.sub, Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    }, card)

    -- ID do aparelho (toque pra copiar e mandar pro administrador)
    local idBtn = new("TextButton", {
        Size = UDim2.fromOffset(120, 18), Position = UDim2.fromOffset(CW - 138, 16), BackgroundTransparency = 1,
        Text = "ID: " .. deviceCode(), TextColor3 = C.sub, Font = Enum.Font.Code, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right, AutoButtonColor = false,
    }, card)
    idBtn.Activated:Connect(function()
        local ok = pcall(function() (setclipboard or toclipboard)(deviceCode()) end)
        idBtn.Text = ok and "ID copiado!" or ("ID: " .. deviceCode())
        task.delay(1.6, function() if idBtn.Parent then idBtn.Text = "ID: " .. deviceCode() end end)
    end)

    -- abas Entrar / Criar conta com indicador animado
    local seg = new("Frame", {Size = UDim2.fromOffset(CW - 36, 32), Position = UDim2.fromOffset(18, 62), BackgroundColor3 = C.panel, BorderSizePixel = 0}, card)
    corner(seg, 8)
    local ind = new("Frame", {Size = UDim2.new(.5, -4, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = C.accent, BorderSizePixel = 0}, seg)
    corner(ind, 6)
    local function segBtn(text, x)
        return new("TextButton", {
            Size = UDim2.new(.5, 0, 1, 0), Position = UDim2.new(x, 0, 0, 0), BackgroundTransparency = 1, Text = text,
            TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false,
        }, seg)
    end
    local tLogin, tCreate = segBtn("Entrar", 0), segBtn("Criar conta", .5)

    local function field(text, y, ph)
        local l = new("TextLabel", {
            Size = UDim2.fromOffset(220, 12), Position = UDim2.fromOffset(18, y), BackgroundTransparency = 1,
            Text = text, TextColor3 = C.sub, Font = Enum.Font.GothamMedium, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
        }, card)
        local box = new("TextBox", {
            Size = UDim2.fromOffset(CW - 36, 30), Position = UDim2.fromOffset(18, y + 15), BackgroundColor3 = C.panel,
            Text = "", PlaceholderText = ph, PlaceholderColor3 = Color3.fromRGB(110, 110, 118), TextColor3 = C.text,
            Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0,
        }, card)
        corner(box, 8)
        new("UIPadding", {PaddingLeft = UDim.new(0, 10)}, box)
        local st = stroke(box, Color3.fromRGB(60, 60, 66), 0, 1)
        box.Focused:Connect(function() tween(st, .2, {Color = C.accent}) end)
        box.FocusLost:Connect(function() tween(st, .2, {Color = Color3.fromRGB(60, 60, 66)}) end)
        return l, box
    end
    local _, userBox = field("Usuário", 108, "seu usuário")
    local _, passBox = field("Senha", 158, "sua senha")
    local keyLbl, keyBox = field("Key (do administrador)", 208, "DANORTE-XXXX-XXXX-XXXX-XXXX")
    keyBox.Font = Enum.Font.Code

    local btn = new("TextButton", {
        Size = UDim2.fromOffset(CW - 36, 36), Position = UDim2.fromOffset(18, 284), BackgroundColor3 = C.accent,
        Text = "Entrar", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = false,
    }, card)
    corner(btn, 8)
    pressFx(btn, C.accent, Color3.fromRGB(150, 18, 30))
    local msg = new("TextLabel", {
        Size = UDim2.fromOffset(CW - 36, 30), Position = UDim2.fromOffset(18, 328), BackgroundTransparency = 1, TextWrapped = true,
        Text = "", TextColor3 = Color3.fromRGB(255, 110, 120), Font = Enum.Font.GothamMedium, TextSize = 10,
    }, card)

    -- salvar login (lembra usuario e senha neste aparelho)
    local remember = false
    local chk = new("TextButton", {
        Size = UDim2.fromOffset(160, 18), Position = UDim2.fromOffset(18, 260), BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false,
    }, card)
    local chkBox = new("Frame", {Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.panel, BorderSizePixel = 0}, chk)
    corner(chkBox, 4); stroke(chkBox, C.off, 0, 1)
    local chkMark = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "✓", TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold, TextSize = 12, Visible = false,
    }, chkBox)
    new("TextLabel", {
        Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(24, 0), BackgroundTransparency = 1, Text = "Salvar login",
        TextColor3 = C.sub, Font = Enum.Font.GothamMedium, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    }, chk)
    local function setRemember(v)
        remember = v
        chkMark.Visible = v
        tween(chkBox, .15, {BackgroundColor3 = v and C.accent or C.panel})
    end
    chk.Activated:Connect(function() setRemember(not remember) end)

    local mode = "login"
    local function setMode(m)
        mode = m
        local create = (m == "create")
        tween(ind, .3, {Position = create and UDim2.new(.5, 1, 0, 3) or UDim2.fromOffset(3, 3)})
        tween(tLogin, .25, {TextColor3 = create and C.sub or Color3.new(1, 1, 1)})
        tween(tCreate, .25, {TextColor3 = create and Color3.new(1, 1, 1) or C.sub})
        keyLbl.Visible = create; keyBox.Visible = create
        if create then
            keyBox.BackgroundTransparency = 1
            tween(keyBox, .35, {BackgroundTransparency = 0})
        end
        btn.Text = create and "Criar conta" or "Entrar"
        tween(chk, .3, {Position = UDim2.fromOffset(18, create and 260 or 208)})
        tween(btn, .3, {Position = UDim2.fromOffset(18, create and 284 or 232)})
        tween(msg, .3, {Position = UDim2.fromOffset(18, create and 328 or 276)})
        tween(card, .3, {Size = UDim2.fromOffset(CW, create and H_CREATE or H_LOGIN)})
        msg.Text = ""
        if not create and acc then userBox.Text = acc.u end
    end
    tLogin.Activated:Connect(function() setMode("login") end)
    tCreate.Activated:Connect(function() setMode("create") end)
    setMode(acc and "login" or "create")

    -- carrega login salvo
    pcall(function()
        if isfile and isfile(SAVE_FILE) then
            local sv = HttpService:JSONDecode(readfile(SAVE_FILE))
            if type(sv) == "table" and sv.u and sv.p then
                userBox.Text = sv.u; passBox.Text = sv.p; setRemember(true)
            end
        end
    end)
    local function persistLogin(u, p)
        pcall(function()
            if remember then
                writefile(SAVE_FILE, HttpService:JSONEncode({u = u, p = p}))
            elseif isfile and isfile(SAVE_FILE) then
                if delfile then delfile(SAVE_FILE) else writefile(SAVE_FILE, "{}") end
            end
        end)
    end

    local busy = false
    local function submit()
        if busy then return end
        local function fail(t)
            msg.TextColor3 = Color3.fromRGB(255, 110, 120); msg.Text = t
            local base = card.Position
            for _ = 1, 3 do
                card.Position = base + UDim2.fromOffset(-7, 0); task.wait(.04)
                card.Position = base + UDim2.fromOffset(7, 0); task.wait(.04)
            end
            card.Position = base
        end
        local function success(t)
            busy = true
            msg.TextColor3 = Color3.fromRGB(120, 255, 170); msg.Text = t
            task.wait(.7)
            setOpen(.8, .25)
            task.wait(.3)
            pconn:Disconnect()
            gui:Destroy()
            enterApp(acc)
        end
        local u, p = trim(userBox.Text), passBox.Text
        if mode == "create" then
            if #u < 3 or #u > 20 or not u:match("^[%w_]+$") then return fail("Usuário: 3 a 20 letras, números ou _.") end
            if #p < 4 then return fail("Senha: mínimo de 4 caracteres.") end
            refreshBlocklist()
            local ok, text = checkKey(keyBox.Text)
            if not ok then return fail(text) end
            acc = {u = u, h = hashText(u:lower() .. "|" .. p), k = string.upper(trim(keyBox.Text))}
            pcall(function() if writefile then writefile(ACC_FILE, HttpService:JSONEncode(acc)) end end)
            sendLog("conta criada", acc)
            persistLogin(u, p)
            success("Conta criada! " .. text)
        else
            if not acc then return fail("Nenhuma conta neste aparelho. Toque em Criar conta.") end
            if u:lower() ~= acc.u:lower() or hashText(u:lower() .. "|" .. p) ~= acc.h then
                return fail("Usuário ou senha incorretos.")
            end
            refreshBlocklist()
            local ok, text = checkKey(acc.k)
            if not ok then return fail(text) end
            sendLog("login", acc)
            persistLogin(u, p)
            success(text)
        end
    end
    btn.Activated:Connect(submit)
    passBox.FocusLost:Connect(function(enter) if enter and mode == "login" then submit() end end)
    keyBox.FocusLost:Connect(function(enter) if enter then submit() end end)
end

showAuth()
