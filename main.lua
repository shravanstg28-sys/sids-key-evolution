-- ============================================================
-- SID'S AIMBOT & PERFORMANCE SUITE: ESCALATION LOCK EDITION
-- Complete Framework with Integrated Daily Key System
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)

-- ============================================================
-- KEY SYSTEM CONFIGURATION (Must match index.html)
-- ============================================================
local KEY_WEBSITE_URL = "https://sid-key-portal.netlify.app/" -- Replace with your hosted index.html URL
local SECRET_SALT     = 73915                            -- Must match SECRET_SALT in index.html
local SAVE_FILE_NAME  = "SidsSuite_SavedKey.txt"

local function GetExpectedDailyKey()
    local utc = os.date("!*t")
    local rawHash = ((utc.year * 37) + (utc.month * 131) + (utc.day * 997) + SECRET_SALT) * 17
    local unsigned = rawHash % 4294967296
    return string.format("SID-%08X", unsigned)
end

local function IsKeyValid(inputKey)
    if type(inputKey) ~= "string" then return false end
    local cleaned = inputKey:gsub("%s+", ""):upper()
    return cleaned == GetExpectedDailyKey()
end

-- ============================================================
-- PART 1 OF 4: CONFIGURATION & SETTINGS
-- ============================================================
local Settings = {
    AimKey          = Enum.UserInputType.MouseButton2,
    ToggleKey       = Enum.KeyCode.Q, 
    AimbotEnabled   = false,
    TeamCheck       = true,
    WallCheck       = true,        
    TargetPart      = "Head",
    
    FOV             = 9999,         
    MaxStudDistance = 800,          
    PredictiveMove  = false,        
    PredictionMult  = 0,       
    
    Triggerbot      = false,       
    
    ChamsEnabled    = false,
    EnemyColor      = Color3.fromRGB(255, 10, 80),   
    TeamColor       = Color3.fromRGB(0, 235, 180),   
    
    HitboxesEnabled = false,
    HitboxSize      = 4.5,
    HitboxAlpha     = 0.3,
    
    FlyEnabled      = false,
    FlySpeed        = 100,
    
    SpeedEnabled    = false,
    WalkSpeed       = 120
}

local States = { IsAiming = false }
local flightAttachment, flightVelocity, flightConnection
local visualHitboxes, connectionTracks = {}, {}
local HITBOX_BASE = Vector3.new(4, 6, 2)
local MenuToggleButtonUpdateRef = nil
local MobileToggle = nil

-- ============================================================
-- PART 2 OF 4: SOLVERS & DISTANCE ENGINE
-- ============================================================
local function IsTargetVisible(targetChar, targetPart)
    if not Settings.WallCheck then return true end
    if not targetChar or not targetPart then return false end
    
    local Origin = Camera.CFrame.Position
    local Direction = (targetPart.Position - Origin)
    
    local Params = RaycastParams.new()
    Params.FilterType = Enum.RaycastFilterType.Exclude
    Params.FilterDescendantsInstances = {LocalPlayer.Character, targetChar}
    Params.IgnoreWater = true
    
    local Result = Workspace:Raycast(Origin, Direction, Params)
    return Result == nil
end

local function getOptimalTarget()
    if not Camera then return nil, nil end
    local CameraCFrame = Camera.CFrame
    local CameraPosition = CameraCFrame.Position
    local CameraLookVector = CameraCFrame.LookVector
    
    local ClosestTarget = nil
    local HighestAlignment = -2 -- Minimum dot product threshold floor
    local TargetPlayerReference = nil
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local isTeammate = (Settings.TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team)
            if not isTeammate then
                local character = player.Character
                local humanoid  = character and character:FindFirstChildOfClass("Humanoid")
                local targetPart = character and character:FindFirstChild(Settings.TargetPart)
                
                if character and humanoid and humanoid.Health > 0 and targetPart then
                    local targetPosition = targetPart.Position
                    local directionToTarget = (targetPosition - CameraPosition)
                    local studDistance = directionToTarget.Magnitude
                    
                    if studDistance <= Settings.MaxStudDistance then
                        local directionUnit = directionToTarget.Unit
                        local alignment = CameraLookVector:Dot(directionUnit)
                        
                        if alignment > HighestAlignment then
                            if IsTargetVisible(character, targetPart) then
                                HighestAlignment = alignment
                                ClosestTarget = targetPart
                                TargetPlayerReference = player
                            end
                        end
                    end
                end
            end
        end
    end
    return ClosestTarget, TargetPlayerReference
end

-- ============================================================
-- PART 3 OF 4: PROCESSING LOOPS
-- ============================================================
local function cleanElements(player)
    if visualHitboxes[player] then
        pcall(function() visualHitboxes[player]:Destroy() end)
        visualHitboxes[player] = nil
    end
end

local function applyVisuals(player)
    local function processCharacter(char)
        if not char then return end
        local hrp = char:WaitForChild("HumanoidRootPart", 5) or char:FindFirstChild("HumanoidRootPart")
        local hum = char:WaitForChild("Humanoid", 5) or char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then return end
        
        local isTeammate = (Settings.TeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team)
        
        if Settings.ChamsEnabled and not isTeammate then
            local oldCham = char:FindFirstChild("SuiteCham")
            if oldCham then oldCham:Destroy() end
            
            local highlight = Instance.new("Highlight")
            highlight.Name = "SuiteCham"
            highlight.Adornee = char
            highlight.FillTransparency = 0.2
            highlight.OutlineTransparency = 0
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = isTeammate and Settings.TeamColor or Settings.EnemyColor
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.Parent = char
        else
            local oldCham = char:FindFirstChild("SuiteCham")
            if oldCham then oldCham:Destroy() end
        end
        
        if Settings.HitboxesEnabled and player ~= LocalPlayer and not isTeammate then
            cleanElements(player)
            local hitboxPart = Instance.new("Part")
            hitboxPart.Name = "SuiteVisualHitbox"
            hitboxPart.CanCollide = false; hitboxPart.Anchored = false; hitboxPart.Massless = true
            hitboxPart.Transparency = Settings.HitboxAlpha; hitboxPart.Color = Settings.EnemyColor
            hitboxPart.Material = Enum.Material.Neon; hitboxPart.Size = HITBOX_BASE * Settings.HitboxSize
            hitboxPart.Parent = char
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = hrp; weld.Part1 = hitboxPart; weld.Parent = hitboxPart
            visualHitboxes[player] = hitboxPart
        else
            cleanElements(player)
        end
    end
    if connectionTracks[player] then connectionTracks[player]:Disconnect() end
    connectionTracks[player] = player.CharacterAdded:Connect(processCharacter)
    if player.Character then processCharacter(player.Character) end
end

local function updateWorldVisuals()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then applyVisuals(p) end
    end
end

Players.PlayerAdded:Connect(function(p) if p ~= LocalPlayer then applyVisuals(p) end end)
Players.PlayerRemoving:Connect(function(p)
    if connectionTracks[p] then connectionTracks[p]:Disconnect() connectionTracks[p] = nil end
    cleanElements(p)
end)

local function setFly(state)
    Settings.FlyEnabled = state
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    if state then
        if flightAttachment then flightAttachment:Destroy() end
        if flightVelocity then flightVelocity:Destroy() end
        if flightConnection then flightConnection:Disconnect() end
        flightAttachment = Instance.new("Attachment", hrp)
        flightVelocity = Instance.new("LinearVelocity", hrp)
        flightVelocity.MaxForce = 9e9
        flightVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        flightVelocity.Attachment0 = flightAttachment
        hum.PlatformStand = true
        flightConnection = RunService.RenderStepped:Connect(function()
            if not Settings.FlyEnabled or not hrp.Parent or not flightVelocity.Parent then
                if flightConnection then flightConnection:Disconnect() end
                return
            end
            local moveDir = hum.MoveDirection
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump then
                moveDir = moveDir + Vector3.new(0,1,0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                moveDir = moveDir - Vector3.new(0,1,0)
            end
            flightVelocity.VectorVelocity = moveDir.Magnitude > 0 and moveDir.Unit * Settings.FlySpeed or Vector3.new(0,0,0)
            hrp.Velocity = Vector3.new(0,0,0)
        end)
    else
        if flightConnection then flightConnection:Disconnect() flightConnection = nil end
        if flightVelocity then flightVelocity:Destroy() flightVelocity = nil end
        if flightAttachment then flightAttachment:Destroy() flightAttachment = nil end
        if hum then hum.PlatformStand = false end
    end
end

local function setSpeed(state)
    Settings.SpeedEnabled = state
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = state and Settings.WalkSpeed or 16 end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.3)
    if Settings.SpeedEnabled then setSpeed(true) end
    if Settings.FlyEnabled then setFly(true) end
end)

-- ============================================================
-- PART 4 OF 4: DASHBOARD INTERFACE & KEY GATE
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.ResetOnSpawn = false
ScreenGui.Name = "SidsEvolutionSuite"
pcall(function() ScreenGui.Parent = CoreGui end)

local InterfaceScale = Instance.new("UIScale")
InterfaceScale.Scale = 1
InterfaceScale.Parent = ScreenGui

local function updateInterfaceScale()
    local viewport = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize)
        or Vector2.new(1280, 720)
    local fitScale = math.min(viewport.X / 700, viewport.Y / 650, 1)
    InterfaceScale.Scale = math.clamp(fitScale, 0.62, 1)
end

updateInterfaceScale()
if Workspace.CurrentCamera then
    Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateInterfaceScale)
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    task.defer(updateInterfaceScale)
    if Workspace.CurrentCamera then
        Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateInterfaceScale)
    end
end)

local function InitializeSuiteDashboard()
    -- Start combat & input loops only after valid key verification
    RunService.PreRender:Connect(function()
        local targetPart, targetPlayer = getOptimalTarget()
        
        if Settings.AimbotEnabled and States.IsAiming and targetPart and Camera then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, targetPart.Position)
        end
        
        if Settings.Triggerbot and targetPart then
            local mousePos = UserInputService:GetMouseLocation()
            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if onScreen then
                local deltaDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                if deltaDist <= (Settings.HitboxSize * 6) then
                    pcall(function() mouse1click() end)
                end
            end
        end
    end)

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.UserInputType == Settings.AimKey then 
            States.IsAiming = true 
        elseif input.KeyCode == Settings.ToggleKey then
            Settings.AimbotEnabled = not Settings.AimbotEnabled
            if MobileToggle then
                MobileToggle.Text = Settings.AimbotEnabled and "AIMBOT: ON" or "AIMBOT: OFF"
                MobileToggle.BackgroundColor3 = Settings.AimbotEnabled
                    and Color3.fromRGB(115, 15, 55) or Color3.fromRGB(25, 27, 35)
            end
            if MenuToggleButtonUpdateRef then
                MenuToggleButtonUpdateRef(Settings.AimbotEnabled)
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Settings.AimKey then States.IsAiming = false end
    end)

    -- Build Main Dashboard Frame
    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 275, 0, 485)
    MainFrame.Position = UDim2.new(0.05, 0, 0.25, 0)
    MainFrame.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
    MainFrame.BackgroundTransparency = 0.15
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui

    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 14); UICorner.Parent = MainFrame

    local GlowStroke = Instance.new("UIStroke")
    GlowStroke.Thickness = 1.5
    GlowStroke.Color = Color3.fromRGB(255, 10, 80)
    GlowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    GlowStroke.Parent = MainFrame

    local HeaderGradient = Instance.new("Frame")
    HeaderGradient.Size = UDim2.new(1, 0, 0, 50)
    HeaderGradient.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    HeaderGradient.BorderSizePixel = 0
    HeaderGradient.Parent = MainFrame

    local HGCorner = Instance.new("UICorner")
    HGCorner.CornerRadius = UDim.new(0, 14); HGCorner.Parent = HeaderGradient

    local UIGradient = Instance.new("UIGradient")
    UIGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 10, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 0, 20))
    }
    UIGradient.Rotation = 45
    UIGradient.Parent = HeaderGradient

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 16, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "SID'S AIMBOT"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.TextSize = 15
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = HeaderGradient

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 30, 0, 30)
    CloseBtn.Position = UDim2.new(1, -40, 0, 10)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    CloseBtn.BackgroundTransparency = 0.6
    CloseBtn.Text = "×"
    CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseBtn.TextSize = 18
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.Parent = HeaderGradient

    local CBCorner = Instance.new("UICorner")
    CBCorner.CornerRadius = UDim.new(1, 0); CBCorner.Parent = CloseBtn

    local Container = Instance.new("ScrollingFrame")
    Container.Size = UDim2.new(1, -32, 1, -75)
    Container.Position = UDim2.new(0, 16, 0, 65)
    Container.BackgroundTransparency = 1
    Container.BorderSizePixel = 0
    Container.ScrollBarThickness = 2
    Container.ScrollBarImageColor3 = Color3.fromRGB(255, 10, 80)
    Container.Parent = MainFrame

    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Padding = UDim.new(0, 10)
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIListLayout.Parent = Container

    local OpenBtn = Instance.new("TextButton")
    OpenBtn.Size = UDim2.new(0, 130, 0, 38)
    OpenBtn.Position = UDim2.new(0.05, 0, 0.05, 0)
    OpenBtn.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
    OpenBtn.BorderSizePixel = 0
    OpenBtn.Text = "⚡ SID'S EVOLUTION"
    OpenBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    OpenBtn.TextSize = 11
    OpenBtn.Font = Enum.Font.GothamBold
    OpenBtn.Visible = false
    OpenBtn.Parent = ScreenGui

    local OpenCorner = Instance.new("UICorner")
    OpenCorner.CornerRadius = UDim.new(0, 10); OpenCorner.Parent = OpenBtn

    local OpenStroke = Instance.new("UIStroke")
    OpenStroke.Thickness = 1.5; OpenStroke.Color = Color3.fromRGB(255, 10, 80); OpenStroke.Parent = OpenBtn

    -- Touch Controls
    MobileToggle = Instance.new("TextButton")
    MobileToggle.Name = "MobileAimbotToggle"
    MobileToggle.Size = UDim2.new(0, 142, 0, 42)
    MobileToggle.Position = UDim2.new(1, -158, 1, -108)
    MobileToggle.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
    MobileToggle.BorderSizePixel = 0
    MobileToggle.Text = "AIMBOT: OFF"
    MobileToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    MobileToggle.TextSize = 12
    MobileToggle.Font = Enum.Font.GothamBold
    MobileToggle.Visible = UserInputService.TouchEnabled
    MobileToggle.Parent = ScreenGui
    Instance.new("UICorner", MobileToggle).CornerRadius = UDim.new(0, 10)
    local MobileToggleStroke = Instance.new("UIStroke")
    MobileToggleStroke.Color = Color3.fromRGB(255, 10, 80)
    MobileToggleStroke.Thickness = 1.5
    MobileToggleStroke.Parent = MobileToggle

    local MobileAim = Instance.new("TextButton")
    MobileAim.Name = "MobileHoldToAim"
    MobileAim.Size = UDim2.new(0, 142, 0, 48)
    MobileAim.Position = UDim2.new(1, -158, 1, -58)
    MobileAim.BackgroundColor3 = Color3.fromRGB(255, 10, 80)
    MobileAim.BorderSizePixel = 0
    MobileAim.Text = "HOLD TO AIM"
    MobileAim.TextColor3 = Color3.fromRGB(255, 255, 255)
    MobileAim.TextSize = 12
    MobileAim.Font = Enum.Font.GothamBold
    MobileAim.Visible = UserInputService.TouchEnabled
    MobileAim.Parent = ScreenGui
    Instance.new("UICorner", MobileAim).CornerRadius = UDim.new(0, 10)

    MobileToggle.Activated:Connect(function()
        Settings.AimbotEnabled = not Settings.AimbotEnabled
        MobileToggle.Text = Settings.AimbotEnabled and "AIMBOT: ON" or "AIMBOT: OFF"
        MobileToggle.BackgroundColor3 = Settings.AimbotEnabled
            and Color3.fromRGB(115, 15, 55) or Color3.fromRGB(25, 27, 35)
        if MenuToggleButtonUpdateRef then
            MenuToggleButtonUpdateRef(Settings.AimbotEnabled)
        end
    end)

    MobileAim.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            States.IsAiming = true
            MobileAim.Text = "AIMING..."
        end
    end)
    MobileAim.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            States.IsAiming = false
            MobileAim.Text = "HOLD TO AIM"
        end
    end)

    -- Dragging Logic
    local dragToggle = nil
    local dragSpeed = 0.1
    local dragStart = nil
    local startPos = nil

    local function updateInput(input)
        local delta = input.Position - dragStart
        local position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        TweenService:Create(MainFrame, TweenInfo.new(dragSpeed), {Position = position}):Play()
    end

    MainFrame.InputBegan:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and UserInputService:GetFocusedTextBox() == nil then
            dragToggle = true
            dragStart = input.Position
            startPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragToggle = false
                end
            end)
        end
    end)

    MainFrame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseBehavior or input.UserInputType == Enum.UserInputType.Touch then
            if dragToggle then
                updateInput(input)
            end
        end
    end)

    CloseBtn.MouseButton1Click:Connect(function()
        TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Size = UDim2.new(0, 275, 0, 0)}):Play()
        task.wait(0.22)
        MainFrame.Visible = false
        OpenBtn.Visible = true
    end)

    OpenBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = true
        OpenBtn.Visible = false
        TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 275, 0, 485)}):Play()
    end)

    local function AddModularToggle(titleText, stateDefault, isMainAimbot, actionCallback)
        local Frame = Instance.new("Frame")
        Frame.Size = UDim2.new(1, -4, 0, 42)
        Frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
        Frame.BorderSizePixel = 0
        Frame.Parent = Container
        
        local FCorner = Instance.new("UICorner")
        FCorner.CornerRadius = UDim.new(0, 8); FCorner.Parent = Frame
        
        local FStroke = Instance.new("UIStroke")
        FStroke.Thickness = 1
        FStroke.Color = stateDefault and Color3.fromRGB(255, 10, 80) or Color3.fromRGB(28, 32, 42)
        FStroke.Parent = Frame

        local Label = Instance.new("TextLabel")
        Label.Size = UDim2.new(0.6, 0, 1, 0)
        Label.Position = UDim2.new(0, 14, 0, 0)
        Label.BackgroundTransparency = 1
        Label.Text = titleText
        Label.TextColor3 = Color3.fromRGB(195, 205, 220)
        Label.TextSize = 12
        Label.Font = Enum.Font.GothamSemibold
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.Parent = Frame

        local Track = Instance.new("TextButton")
        Track.Size = UDim2.new(0, 36, 0, 20)
        Track.Position = UDim2.new(1, -50, 0.5, -10)
        Track.BackgroundColor3 = stateDefault and Color3.fromRGB(255, 10, 80) or Color3.fromRGB(35, 40, 50)
        Track.Text = ""
        Track.Parent = Frame
        
        local TCorner = Instance.new("UICorner")
        TCorner.CornerRadius = UDim.new(1, 0); TCorner.Parent = Track

        local Knob = Instance.new("Frame")
        Knob.Position = stateDefault and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        Knob.Size = UDim2.new(0, 14, 0, 14)
        Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Knob.BorderSizePixel = 0
        Knob.Parent = Track
        
        local KCorner = Instance.new("UICorner")
        KCorner.CornerRadius = UDim.new(1, 0); KCorner.Parent = Knob

        local isToggled = stateDefault
        
        local function setVisualState(targetState)
            isToggled = targetState
            TweenService:Create(Track, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundColor3 = isToggled and Color3.fromRGB(255, 10, 80) or Color3.fromRGB(35, 40, 50)
            }):Play()
            TweenService:Create(Knob, TweenInfo.new(0.2, Enum.EasingStyle.Cubic), {
                Position = isToggled and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
            }):Play()
            TweenService:Create(FStroke, TweenInfo.new(0.2), {
                Color = isToggled and Color3.fromRGB(255, 10, 80) or Color3.fromRGB(28, 32, 42)
            }):Play()
        end
        
        if isMainAimbot then
            MenuToggleButtonUpdateRef = function(newState)
                setVisualState(newState)
            end
        end

        Track.MouseButton1Click:Connect(function()
            isToggled = not isToggled
            actionCallback(isToggled)
            setVisualState(isToggled)
        end)
    end

    AddModularToggle("Rigid Escalation Lock (Q)", Settings.AimbotEnabled, true, function(v)
        Settings.AimbotEnabled = v
        if MobileToggle then
            MobileToggle.Text = v and "AIMBOT: ON" or "AIMBOT: OFF"
            MobileToggle.BackgroundColor3 = v and Color3.fromRGB(115, 15, 55) or Color3.fromRGB(25, 27, 35)
        end
    end)
    AddModularToggle("Wall Visibility Check", Settings.WallCheck, false, function(v) Settings.WallCheck = v end)
    AddModularToggle("Instant Crosshair Trigger", Settings.Triggerbot, false, function(v) Settings.Triggerbot = v end)
    AddModularToggle("Exclude Teammates", Settings.TeamCheck, false, function(v) Settings.TeamCheck = v updateWorldVisuals() end)
    AddModularToggle("Hyper Radiant Chams", Settings.ChamsEnabled, false, function(v) Settings.ChamsEnabled = v updateWorldVisuals() end)
    AddModularToggle("Expanded Hitbox Cubes", Settings.HitboxesEnabled, false, function(v) Settings.HitboxesEnabled = v updateWorldVisuals() end)
    AddModularToggle("Vector Air Flight", Settings.FlyEnabled, false, function(v) setFly(v) end)
    AddModularToggle("Ground Speed Matrix", Settings.SpeedEnabled, false, function(v) setSpeed(v) end)
end

-- ============================================================
-- KEY VERIFICATION GATEWAY
-- ============================================================
local KeyVerified = false
pcall(function()
    if isfile and readfile and isfile(SAVE_FILE_NAME) then
        if IsKeyValid(readfile(SAVE_FILE_NAME)) then
            KeyVerified = true
        end
    end
end)

if KeyVerified then
    InitializeSuiteDashboard()
else
    local KeyFrame = Instance.new("Frame")
    KeyFrame.Size = UDim2.new(0, 290, 0, 200)
    KeyFrame.Position = UDim2.new(0.5, -145, 0.5, -100)
    KeyFrame.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
    KeyFrame.BackgroundTransparency = 0.08
    KeyFrame.BorderSizePixel = 0
    KeyFrame.Parent = ScreenGui

    local KCorner = Instance.new("UICorner")
    KCorner.CornerRadius = UDim.new(0, 14)
    KCorner.Parent = KeyFrame

    local KStroke = Instance.new("UIStroke")
    KStroke.Thickness = 1.5
    KStroke.Color = Color3.fromRGB(255, 10, 80)
    KStroke.Parent = KeyFrame

    local KHeader = Instance.new("Frame")
    KHeader.Size = UDim2.new(1, 0, 0, 44)
    KHeader.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    KHeader.BorderSizePixel = 0
    KHeader.Parent = KeyFrame
    Instance.new("UICorner", KHeader).CornerRadius = UDim.new(0, 14)

    local KGrad = Instance.new("UIGradient")
    KGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 10, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 0, 20))
    }
    KGrad.Rotation = 45
    KGrad.Parent = KHeader

    local KTitle = Instance.new("TextLabel")
    KTitle.Size = UDim2.new(1, -24, 1, 0)
    KTitle.Position = UDim2.new(0, 14, 0, 0)
    KTitle.BackgroundTransparency = 1
    KTitle.Text = "⚡ SID'S KEY VERIFICATION"
    KTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    KTitle.TextSize = 14
    KTitle.Font = Enum.Font.GothamBold
    KTitle.TextXAlignment = Enum.TextXAlignment.Left
    KTitle.Parent = KHeader

    local KeyInput = Instance.new("TextBox")
    KeyInput.Size = UDim2.new(1, -32, 0, 38)
    KeyInput.Position = UDim2.new(0, 16, 0, 58)
    KeyInput.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
    KeyInput.PlaceholderText = "Paste key here (SID-XXXXXXXX)..."
    KeyInput.PlaceholderColor3 = Color3.fromRGB(120, 130, 145)
    KeyInput.Text = ""
    KeyInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    KeyInput.TextSize = 12
    KeyInput.Font = Enum.Font.Code
    KeyInput.ClearTextOnFocus = false
    KeyInput.Parent = KeyFrame
    Instance.new("UICorner", KeyInput).CornerRadius = UDim.new(0, 8)
    local InputStroke = Instance.new("UIStroke", KeyInput)
    InputStroke.Color = Color3.fromRGB(35, 40, 50)

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -32, 0, 18)
    StatusLabel.Position = UDim2.new(0, 16, 0, 102)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = "Click 'Get Key' to copy the portal link."
    StatusLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
    StatusLabel.TextSize = 11
    StatusLabel.Font = Enum.Font.Gotham
    StatusLabel.Parent = KeyFrame

    local GetKeyBtn = Instance.new("TextButton")
    GetKeyBtn.Size = UDim2.new(0.46, -16, 0, 36)
    GetKeyBtn.Position = UDim2.new(0, 16, 0, 132)
    GetKeyBtn.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
    GetKeyBtn.Text = "GET KEY"
    GetKeyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    GetKeyBtn.TextSize = 12
    GetKeyBtn.Font = Enum.Font.GothamBold
    GetKeyBtn.Parent = KeyFrame
    Instance.new("UICorner", GetKeyBtn).CornerRadius = UDim.new(0, 8)
    local GetStroke = Instance.new("UIStroke", GetKeyBtn)
    GetStroke.Color = Color3.fromRGB(255, 10, 80)

    local VerifyBtn = Instance.new("TextButton")
    VerifyBtn.Size = UDim2.new(0.46, -16, 0, 36)
    VerifyBtn.Position = UDim2.new(0.54, 0, 0, 132)
    VerifyBtn.BackgroundColor3 = Color3.fromRGB(255, 10, 80)
    VerifyBtn.Text = "VERIFY KEY"
    VerifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    VerifyBtn.TextSize = 12
    VerifyBtn.Font = Enum.Font.GothamBold
    VerifyBtn.Parent = KeyFrame
    Instance.new("UICorner", VerifyBtn).CornerRadius = UDim.new(0, 8)

    GetKeyBtn.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard(KEY_WEBSITE_URL)
            StatusLabel.Text = "✓ Link copied! Paste it in your browser."
            StatusLabel.TextColor3 = Color3.fromRGB(0, 235, 180)
        else
            StatusLabel.Text = KEY_WEBSITE_URL
        end
    end)

    VerifyBtn.MouseButton1Click:Connect(function()
        if IsKeyValid(KeyInput.Text) then
            StatusLabel.Text = "✓ Access Granted! Loading suite..."
            StatusLabel.TextColor3 = Color3.fromRGB(0, 235, 180)
            pcall(function()
                if writefile then
                    writefile(SAVE_FILE_NAME, KeyInput.Text:gsub("%s+", ""):upper())
                end
            end)
            task.wait(0.4)
            KeyFrame:Destroy()
            InitializeSuiteDashboard()
        else
            StatusLabel.Text = "✕ Invalid or expired key. Try again."
            StatusLabel.TextColor3 = Color3.fromRGB(255, 60, 90)
        end
    end)
end
