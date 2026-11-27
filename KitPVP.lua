-- KIT PVP | Delta + Mobile | v2.0
-- Loadstring host this raw on GitHub/Pastebin

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local UserInputService= game:GetService("UserInputService")
local Camera          = workspace.CurrentCamera
local LocalPlayer     = Players.LocalPlayer
local IsMobile        = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    -- COMBAT
    AimAssist = {
        Enabled    = false,
        FOV        = 120,
        Smoothness = 0.25,
        TargetPart = "Head",
        TeamCheck  = true,
    },
    AutoClicker = {
        Enabled    = false,
        CPS        = 12,       -- clicks per second
        LookCheck  = true,     -- only clicks when looking at a player
        LookFOV    = 150,      -- px from center to count as "looking"
        TeamCheck  = true,
    },
    KillAura = {
        Enabled   = false,
        Radius    = 8,
        TeamCheck = true,
    },

    -- VISUALS
    ESP = {
        Enabled     = false,
        Boxes       = true,
        Names       = true,
        Distance    = true,
        Health      = true,
        MaxDistance = 1000,
        BoxColor    = Color3.fromRGB(255,255,255),
        TextColor   = Color3.fromRGB(255,255,255),
    },
    Tracers = {
        Enabled   = false,
        Origin    = "Bottom",
        Thickness = 1,
        Color     = Color3.fromRGB(255,255,255),
    },
    Crosshair = {
        Enabled = false,
        Size    = 10,
        Color   = Color3.fromRGB(255,255,255),
    },
    FOVCircle = {
        Enabled = false,
        Color   = Color3.fromRGB(255,255,255),
    },

    -- MOVEMENT
    AutoSprint = {
        Enabled = false,
    },
    NoBoundary = {
        Enabled = false,
    },
}

-- ============================================================
-- UTILITY
-- ============================================================
local function getChar(p)  return p.Character end
local function getRoot(p)  local c=getChar(p) return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum(p)   local c=getChar(p) return c and c:FindFirstChildOfClass("Humanoid") end
local function getHead(p)  local c=getChar(p) return c and c:FindFirstChild("Head") end
local function isAlive(p)  local h=getHum(p)  return h and h.Health > 0 end
local function isMate(p)   return p.Team == LocalPlayer.Team end

local function toScreen(pos)
    local s, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), on, s.Z
end

local function getClosestOnScreen(fovPx)
    local best, bestD = nil, fovPx
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if Config.AimAssist.TeamCheck and isMate(p) then continue end
        if not isAlive(p) then continue end
        local part = p.Character and p.Character:FindFirstChild(Config.AimAssist.TargetPart)
        if not part then continue end
        local sp, on = toScreen(part.Position)
        if not on then continue end
        local d = (center - sp).Magnitude
        if d < bestD then bestD=d best=p end
    end
    return best
end

local function isLookingAtPlayer()
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if Config.AutoClicker.TeamCheck and isMate(p) then continue end
        if not isAlive(p) then continue end
        local head = getHead(p)
        if not head then continue end
        local sp, on = toScreen(head.Position)
        if not on then continue end
        if (center - sp).Magnitude <= Config.AutoClicker.LookFOV then
            return true
        end
    end
    return false
end

-- ============================================================
-- DRAWING LAYER — safe wrapper
-- ============================================================
local function newDraw(t, props)
    local ok, obj = pcall(Drawing.new, t)
    if not ok then return nil end
    for k,v in pairs(props) do
        pcall(function() obj[k]=v end)
    end
    return obj
end

local function setDraw(obj, props)
    if not obj then return end
    for k,v in pairs(props) do
        pcall(function() obj[k]=v end)
    end
end

local function hideDraw(obj)
    if obj then pcall(function() obj.Visible=false end) end
end

-- ============================================================
-- ESP
-- ============================================================
local ESPObjects = {}

local function createESP(player)
    ESPObjects[player] = {
        Box      = newDraw("Square",{Visible=false,Thickness=1,Color=Config.ESP.BoxColor,Filled=false}),
        Name     = newDraw("Text",  {Visible=false,Size=13,Color=Config.ESP.TextColor,Center=true,Outline=true,OutlineColor=Color3.fromRGB(0,0,0)}),
        Health   = newDraw("Text",  {Visible=false,Size=12,Color=Color3.fromRGB(80,255,80),Center=true,Outline=true,OutlineColor=Color3.fromRGB(0,0,0)}),
        Distance = newDraw("Text",  {Visible=false,Size=11,Color=Config.ESP.TextColor,Center=true,Outline=true,OutlineColor=Color3.fromRGB(0,0,0)}),
        Tracer   = newDraw("Line",  {Visible=false,Thickness=Config.Tracers.Thickness,Color=Config.Tracers.Color}),
    }
end

local function removeESP(player)
    if not ESPObjects[player] then return end
    for _,o in pairs(ESPObjects[player]) do
        pcall(function() o:Remove() end)
    end
    ESPObjects[player] = nil
end

local function updateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local esp = ESPObjects[player]
        if not esp then continue end

        local char = getChar(player)
        local root = getRoot(player)
        local hum  = getHum(player)

        local function hideAll()
            for _,o in pairs(esp) do hideDraw(o) end
        end

        if not char or not root or not hum or hum.Health <= 0 then
            hideAll() continue
        end

        local dist = (Camera.CFrame.Position - root.Position).Magnitude
        if dist > Config.ESP.MaxDistance then hideAll() continue end

        -- Bounding box from character parts
        local minX,minY,maxX,maxY = math.huge,math.huge,-math.huge,-math.huge
        local hits = 0
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local hx,hy,hz = part.Size.X/2, part.Size.Y/2, part.Size.Z/2
                for _,cf in ipairs({
                    part.CFrame*CFrame.new( hx, hy, hz),
                    part.CFrame*CFrame.new(-hx, hy,-hz),
                    part.CFrame*CFrame.new( hx,-hy, hz),
                    part.CFrame*CFrame.new(-hx,-hy,-hz),
                }) do
                    local sp, on = toScreen(cf.Position)
                    if on then
                        hits=hits+1
                        minX=math.min(minX,sp.X) minY=math.min(minY,sp.Y)
                        maxX=math.max(maxX,sp.X) maxY=math.max(maxY,sp.Y)
                    end
                end
            end
        end

        if hits == 0 then hideAll() continue end

        local bW = maxX-minX
        local bH = maxY-minY
        local cx  = minX+bW/2

        -- Box
        if Config.ESP.Enabled and Config.ESP.Boxes then
            setDraw(esp.Box,{Visible=true,Position=Vector2.new(minX,minY),Size=Vector2.new(bW,bH)})
        else hideDraw(esp.Box) end

        -- Name
        if Config.ESP.Enabled and Config.ESP.Names then
            setDraw(esp.Name,{Visible=true,Text=player.Name,Position=Vector2.new(cx,minY-16)})
        else hideDraw(esp.Name) end

        -- Health
        if Config.ESP.Enabled and Config.ESP.Health then
            setDraw(esp.Health,{
                Visible=true,
                Text=math.floor(hum.Health).."/"..math.floor(hum.MaxHealth).." HP",
                Position=Vector2.new(cx,minY+bH+2)
            })
        else hideDraw(esp.Health) end

        -- Distance
        if Config.ESP.Enabled and Config.ESP.Distance then
            setDraw(esp.Distance,{
                Visible=true,
                Text=math.floor(dist).." studs",
                Position=Vector2.new(cx,minY+bH+14)
            })
        else hideDraw(esp.Distance) end

        -- Tracer
        if Config.Tracers.Enabled then
            local origin = Config.Tracers.Origin == "Bottom"
                and Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
                or  Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
            local tp, on = toScreen(root.Position)
            if on then
                setDraw(esp.Tracer,{Visible=true,From=origin,To=tp})
            else hideDraw(esp.Tracer) end
        else hideDraw(esp.Tracer) end
    end
end

-- ============================================================
-- CROSSHAIR
-- ============================================================
local CH = {
    L = newDraw("Line",{Visible=false,Thickness=1,Color=Config.Crosshair.Color}),
    R = newDraw("Line",{Visible=false,Thickness=1,Color=Config.Crosshair.Color}),
    U = newDraw("Line",{Visible=false,Thickness=1,Color=Config.Crosshair.Color}),
    D = newDraw("Line",{Visible=false,Thickness=1,Color=Config.Crosshair.Color}),
}
local FOVC = newDraw("Circle",{Visible=false,Thickness=1,
    Color=Config.FOVCircle.Color,Filled=false,NumSides=64})

local function updateVisuals()
    local cv = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local s  = Config.Crosshair.Size
    local on = Config.Crosshair.Enabled
    setDraw(CH.L,{Visible=on,From=cv-Vector2.new(s,0),To=cv-Vector2.new(3,0)})
    setDraw(CH.R,{Visible=on,From=cv+Vector2.new(3,0),To=cv+Vector2.new(s,0)})
    setDraw(CH.U,{Visible=on,From=cv-Vector2.new(0,s),To=cv-Vector2.new(0,3)})
    setDraw(CH.D,{Visible=on,From=cv+Vector2.new(0,3),To=cv+Vector2.new(0,s)})
    setDraw(FOVC,{
        Visible  = Config.FOVCircle.Enabled and Config.AimAssist.Enabled,
        Position = cv,
        Radius   = Config.AimAssist.FOV,
    })
end

-- ============================================================
-- AIM ASSIST
-- ============================================================
local touchActive = false
UserInputService.TouchStarted:Connect(function() touchActive=true  end)
UserInputService.TouchEnded:Connect(function()   touchActive=false end)

local function runAimAssist()
    if not Config.AimAssist.Enabled then return end
    local fire = IsMobile and touchActive
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or UserInputService:IsKeyDown(Enum.KeyCode.Q)
    if not fire then return end
    local target = getClosestOnScreen(Config.AimAssist.FOV)
    if not target then return end
    local part = target.Character and target.Character:FindFirstChild(Config.AimAssist.TargetPart)
    if not part then return end
    local sp, on = toScreen(part.Position)
    if not on then return end
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local delta  = sp - center
    mousemoverel(delta.X*(1-Config.AimAssist.Smoothness), delta.Y*(1-Config.AimAssist.Smoothness))
end

-- ============================================================
-- AUTOCLICKER
-- ============================================================
local lastClick   = 0
local clickActive = false

UserInputService.TouchStarted:Connect(function() clickActive=true  end)
UserInputService.TouchEnded:Connect(function()   clickActive=false end)

local function runAutoClicker()
    if not Config.AutoClicker.Enabled then return end

    local pressing = IsMobile and clickActive
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

    if not pressing then return end

    if Config.AutoClicker.LookCheck and not isLookingAtPlayer() then return end

    local now = tick()
    local interval = 1 / Config.AutoClicker.CPS
    if now - lastClick >= interval then
        lastClick = now
        mouse1click()
    end
end

-- ============================================================
-- KILL AURA
-- ============================================================
local function runKillAura()
    if not Config.KillAura.Enabled then return end
    local root = getRoot(LocalPlayer)
    if not root then return end
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not tool then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if Config.KillAura.TeamCheck and isMate(p) then continue end
        if not isAlive(p) then continue end
        local er = getRoot(p)
        if not er then continue end
        if (root.Position - er.Position).Magnitude <= Config.KillAura.Radius then
            pcall(function()
                local re = tool:FindFirstChildOfClass("RemoteEvent")
                if re then re:FireServer(er) end
            end)
        end
    end
end

-- ============================================================
-- AUTO SPRINT
-- ============================================================
local function runAutoSprint()
    if not Config.AutoSprint.Enabled then return end
    local hum = getHum(LocalPlayer)
    if hum then hum.WalkSpeed = 16 end
    if LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:SetAttribute("SprintEnabled", true)
            pcall(function()
                UserInputService:SetMenuOpen(false)
            end)
        end
    end
end

-- ============================================================
-- GUI
-- ============================================================
local SCALE   = IsMobile and 1.3 or 1.0
local W       = math.floor(320*SCALE)
local ROW     = math.floor(32*SCALE)
local FS_L    = math.floor(13*SCALE)
local FS_S    = math.floor(11*SCALE)
local SECTION_W = math.floor(148*SCALE)

local BG      = Color3.fromRGB(10,10,10)
local PANEL   = Color3.fromRGB(18,18,18)
local ROW_BG  = Color3.fromRGB(25,25,25)
local WHITE   = Color3.fromRGB(255,255,255)
local DIM     = Color3.fromRGB(140,140,140)
local ON_COL  = Color3.fromRGB(255,255,255)
local OFF_COL = Color3.fromRGB(45,45,45)

local GUI = Instance.new("ScreenGui")
GUI.Name = "KitPVP_v2"
GUI.ResetOnSpawn = false
GUI.IgnoreGuiInset = true
pcall(function() GUI.Parent = game:GetService("CoreGui") end)

-- Main frame
local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, W, 0, math.floor(500*SCALE))
Main.Position = UDim2.new(0,20,0,50)
Main.BackgroundColor3 = BG
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = not IsMobile
Main.ClipsDescendants = true
Main.Parent = GUI
Instance.new("UICorner",Main).CornerRadius = UDim.new(0,8)

-- Mobile drag
if IsMobile then
    local drag,ds,dp = false,nil,nil
    Main.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch then
            drag=true ds=i.Position dp=Main.Position
        end
    end)
    Main.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.Touch then
            local d=i.Position-ds
            Main.Position=UDim2.new(dp.X.Scale,dp.X.Offset+d.X,dp.Y.Scale,dp.Y.Offset+d.Y)
        end
    end)
    Main.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch then drag=false end
    end)
end

-- Title bar
local TBar = Instance.new("Frame")
TBar.Size = UDim2.new(1,0,0,math.floor(36*SCALE))
TBar.BackgroundColor3 = Color3.fromRGB(15,15,15)
TBar.BorderSizePixel = 0
TBar.Parent = Main
Instance.new("UICorner",TBar).CornerRadius = UDim.new(0,8)

local TLabel = Instance.new("TextLabel")
TLabel.Size = UDim2.new(1,-50,1,0)
TLabel.Position = UDim2.new(0,12,0,0)
TLabel.BackgroundTransparency = 1
TLabel.Text = "KIT PVP  •  DELTA"
TLabel.TextColor3 = WHITE
TLabel.Font = Enum.Font.GothamBold
TLabel.TextSize = FS_L
TLabel.TextXAlignment = Enum.TextXAlignment.Left
TLabel.Parent = TBar

-- Close/hide button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0,math.floor(26*SCALE),0,math.floor(26*SCALE))
CloseBtn.Position = UDim2.new(1,-math.floor(32*SCALE),0.5,-math.floor(13*SCALE))
CloseBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = WHITE
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = FS_S
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TBar
Instance.new("UICorner",CloseBtn).CornerRadius = UDim.new(0,4)
CloseBtn.MouseButton1Click:Connect(function() Main.Visible = false end)

-- Tab bar
local tabs = {"COMBAT","VISUALS","MOVEMENT"}
local activeTab = "COMBAT"
local tabBtns = {}
local tabContent = {}

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1,0,0,math.floor(32*SCALE))
TabBar.Position = UDim2.new(0,0,0,math.floor(36*SCALE))
TabBar.BackgroundColor3 = Color3.fromRGB(14,14,14)
TabBar.BorderSizePixel = 0
TabBar.Parent = Main

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Parent = TabBar

for i, name in ipairs(tabs) do
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1/#tabs, 0, 1, 0)
    Btn.BackgroundColor3 = name==activeTab and Color3.fromRGB(30,30,30) or Color3.fromRGB(14,14,14)
    Btn.Text = name
    Btn.TextColor3 = name==activeTab and WHITE or DIM
    Btn.Font = Enum.Font.GothamBold
    Btn.TextSize = FS_S
    Btn.BorderSizePixel = 0
    Btn.LayoutOrder = i
    Btn.Parent = TabBar
    tabBtns[name] = Btn

    -- Content frame for this tab
    local Content = Instance.new("ScrollingFrame")
    Content.Size = UDim2.new(1,-8,1,-math.floor(76*SCALE))
    Content.Position = UDim2.new(0,4,0,math.floor(72*SCALE))
    Content.BackgroundTransparency = 1
    Content.BorderSizePixel = 0
    Content.ScrollBarThickness = 3
    Content.ScrollBarImageColor3 = WHITE
    Content.Visible = name==activeTab
    Content.Parent = Main
    tabContent[name] = Content

    local CLayout = Instance.new("UIListLayout")
    CLayout.SortOrder = Enum.SortOrder.LayoutOrder
    CLayout.Padding = UDim.new(0,4)
    CLayout.Parent = Content

    CLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        Content.CanvasSize = UDim2.new(0,0,0,CLayout.AbsoluteContentSize.Y+8)
    end)
end

local function switchTab(name)
    activeTab = name
    for t, btn in pairs(tabBtns) do
        btn.BackgroundColor3 = t==name and Color3.fromRGB(30,30,30) or Color3.fromRGB(14,14,14)
        btn.TextColor3 = t==name and WHITE or DIM
        tabContent[t].Visible = t==name
    end
end

for name, btn in pairs(tabBtns) do
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- ============================================================
-- COMPONENT BUILDERS
-- ============================================================
local function addHeader(tab, text)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,-4,0,math.floor(20*SCALE))
    f.BackgroundTransparency = 1
    f.Parent = tabContent[tab]
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,-8,1,0)
    l.Position = UDim2.new(0,4,0,0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = DIM
    l.Font = Enum.Font.GothamBold
    l.TextSize = FS_S
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = f
end

local function addToggle(tab, label, cfg, key)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1,-4,0,ROW)
    Row.BackgroundColor3 = ROW_BG
    Row.BorderSizePixel = 0
    Row.Parent = tabContent[tab]
    Instance.new("UICorner",Row).CornerRadius = UDim.new(0,5)

    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(0.65,0,1,0)
    L.Position = UDim2.new(0,10,0,0)
    L.BackgroundTransparency = 1
    L.Text = label
    L.TextColor3 = Color3.fromRGB(210,210,210)
    L.Font = Enum.Font.Gotham
    L.TextSize = FS_L
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.Parent = Row

    local BW = math.floor(50*SCALE)
    local BH = math.floor(24*SCALE)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0,BW,0,BH)
    Btn.Position = UDim2.new(1,-(BW+8),0.5,-BH/2)
    Btn.BackgroundColor3 = cfg[key] and ON_COL or OFF_COL
    Btn.Text = cfg[key] and "ON" or "OFF"
    Btn.TextColor3 = cfg[key] and Color3.fromRGB(0,0,0) or DIM
    Btn.Font = Enum.Font.GothamBold
    Btn.TextSize = FS_S
    Btn.BorderSizePixel = 0
    Btn.Parent = Row
    Instance.new("UICorner",Btn).CornerRadius = UDim.new(0,4)

    Btn.MouseButton1Click:Connect(function()
        cfg[key] = not cfg[key]
        Btn.BackgroundColor3 = cfg[key] and ON_COL or OFF_COL
        Btn.Text = cfg[key] and "ON" or "OFF"
        Btn.TextColor3 = cfg[key] and Color3.fromRGB(0,0,0) or DIM
    end)
end

local function addSlider(tab, label, cfg, key, mn, mx)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1,-4,0,math.floor(48*SCALE))
    Row.BackgroundColor3 = ROW_BG
    Row.BorderSizePixel = 0
    Row.Parent = tabContent[tab]
    Instance.new("UICorner",Row).CornerRadius = UDim.new(0,5)

    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(1,-10,0,math.floor(18*SCALE))
    L.Position = UDim2.new(0,10,0,4)
    L.BackgroundTransparency = 1
    L.Text = label..": "..cfg[key]
    L.TextColor3 = Color3.fromRGB(200,200,200)
    L.Font = Enum.Font.Gotham
    L.TextSize = FS_S
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.Parent = Row

    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1,-20,0,math.floor(7*SCALE))
    Track.Position = UDim2.new(0,10,1,-math.floor(13*SCALE))
    Track.BackgroundColor3 = Color3.fromRGB(45,45,45)
    Track.BorderSizePixel = 0
    Track.Parent = Row
    Instance.new("UICorner",Track).CornerRadius = UDim.new(0,4)

    local Fill = Instance.new("Frame")
    Fill.Size = UDim2.new((cfg[key]-mn)/(mx-mn),0,1,0)
    Fill.BackgroundColor3 = WHITE
    Fill.BorderSizePixel = 0
    Fill.Parent = Track
    Instance.new("UICorner",Fill).CornerRadius = UDim.new(0,4)

    local dragging = false

    local function apply(px)
        local ts = Track.AbsolutePosition.X
        local te = ts + Track.AbsoluteSize.X
        local t  = math.clamp((px-ts)/(te-ts),0,1)
        local v  = math.floor(mn + t*(mx-mn))
        cfg[key] = v
        Fill.Size = UDim2.new(t,0,1,0)
        L.Text = label..": "..v
    end

    Track.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or
           i.UserInputType==Enum.UserInputType.Touch then
            dragging=true apply(i.Position.X)
        end
    end)
    Track.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMove or
           i.UserInputType==Enum.UserInputType.Touch) then
            apply(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or
           i.UserInputType==Enum.UserInputType.Touch then
            dragging=false
        end
    end)
end

-- ============================================================
-- BUILD TABS
-- ============================================================

-- COMBAT
addHeader("COMBAT","⚔  AIM")
addToggle("COMBAT","Aim Assist",    Config.AimAssist, "Enabled")
addToggle("COMBAT","Team Check",    Config.AimAssist, "TeamCheck")
addSlider("COMBAT","FOV",           Config.AimAssist, "FOV", 10, 400)
addSlider("COMBAT","Smoothness",    Config.AimAssist, "Smoothness", 0, 1)

addHeader("COMBAT","🖱  AUTOCLICKER")
addToggle("COMBAT","Auto Clicker",  Config.AutoClicker, "Enabled")
addToggle("COMBAT","Look Check",    Config.AutoClicker, "LookCheck")
addToggle("COMBAT","Team Check",    Config.AutoClicker, "TeamCheck")
addSlider("COMBAT","CPS",           Config.AutoClicker, "CPS", 1, 20)
addSlider("COMBAT","Look FOV",      Config.AutoClicker, "LookFOV", 20, 300)

addHeader("COMBAT","⚡  AURA")
addToggle("COMBAT","Kill Aura",     Config.KillAura, "Enabled")
addToggle("COMBAT","Team Check",    Config.KillAura, "TeamCheck")
addSlider("COMBAT","Radius",        Config.KillAura, "Radius", 1, 50)

-- VISUALS
addHeader("VISUALS","📦  ESP")
addToggle("VISUALS","ESP",          Config.ESP, "Enabled")
addToggle("VISUALS","Boxes",        Config.ESP, "Boxes")
addToggle("VISUALS","Names",        Config.ESP, "Names")
addToggle("VISUALS","Health",       Config.ESP, "Health")
addToggle("VISUALS","Distance",     Config.ESP, "Distance")

addHeader("VISUALS","⟶  TRACERS")
addToggle("VISUALS","Tracers",      Config.Tracers, "Enabled")

addHeader("VISUALS","✛  CROSSHAIR")
addToggle("VISUALS","Crosshair",    Config.Crosshair, "Enabled")
addSlider("VISUALS","Size",         Config.Crosshair, "Size", 4, 30)

addHeader("VISUALS","◯  FOV CIRCLE")
addToggle("VISUALS","FOV Circle",   Config.FOVCircle, "Enabled")

-- MOVEMENT
addHeader("MOVEMENT","🏃  SPEED")
addToggle("MOVEMENT","Auto Sprint", Config.AutoSprint, "Enabled")

-- ============================================================
-- MOBILE FLOAT BUTTON
-- ============================================================
if IsMobile then
    local FB = Instance.new("TextButton")
    FB.Size = UDim2.new(0,52,0,52)
    FB.Position = UDim2.new(1,-64,1,-80)
    FB.BackgroundColor3 = Color3.fromRGB(15,15,15)
    FB.Text = "☰"
    FB.TextColor3 = WHITE
    FB.Font = Enum.Font.GothamBold
    FB.TextSize = 22
    FB.BorderSizePixel = 0
    FB.Parent = GUI
    Instance.new("UICorner",FB).CornerRadius = UDim.new(0,26)
    FB.MouseButton1Click:Connect(function() Main.Visible = not Main.Visible end)
end

-- RightShift on PC
UserInputService.InputBegan:Connect(function(i,gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightShift then
        Main.Visible = not Main.Visible
    end
end)

-- ============================================================
-- PLAYER TRACKING
-- ============================================================
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then createESP(p) end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then createESP(p) end
end)
Players.PlayerRemoving:Connect(removeESP)

-- ============================================================
-- MAIN LOOPS
-- ============================================================
RunService.RenderStepped:Connect(function()
    updateESP()
    updateVisuals()
    runAimAssist()
end)

RunService.Heartbeat:Connect(function()
    runAutoClicker()
    runKillAura()
    runAutoSprint()
end)
