local StudioService = game:GetService("StudioService")
local RunService = game:GetService("RunService")
local Gameboy = require(script.Parent.Gameboy)

local enabled = pcall(function()
	local test = Instance.new("EditableImage")
	test:WritePixels(Vector2.zero, Vector2.one, { 1, 1, 1, 1 })
end)

if not enabled then
	warn("EditableImage Beta is not enabled! Go to 'File > Beta Features' and check 'EditableImage and EditableMesh' to use the Gameboy Emulator!")
	return
end

local toolbar = plugin:CreateToolbar("Gameboy Emulator")
local loadRomBtn = toolbar:CreateButton("Load ROM", "Load a *.gb ROM file.", "rbxassetid://147178256")
local windowToggle = toolbar:CreateButton("Emulator Window", "Toggle the emulator window.", "rbxassetid://920999449")
local ejectCartridge = toolbar:CreateButton("Cartridge Reset", "Forces the currently loaded ROM to be stopped.", "rbxassetid://12578031451")

local WIDTH = 160
local HEIGHT = 144

local WIDGET_INFO = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, true, WIDTH, HEIGHT, WIDTH, HEIGHT)

local gui = plugin:CreateDockWidgetPluginGui("LUAU_GB", WIDGET_INFO)
gui.Title = "Gameboy Emulator"
gui.Name = gui.Title

local gb = Gameboy.new()
local size = Vector2.new(WIDTH, HEIGHT)

local window = Instance.new("ImageLabel")
window.Position = UDim2.fromScale(0.5, 0.5)
window.BackgroundColor3 = Color3.new()
window.AnchorPoint = Vector2.one / 2
window.Size = UDim2.fromScale(1, 1)
window.ResampleMode = "Pixelated"
window.Parent = gui

local aspectRatio = Instance.new("UIAspectRatioConstraint")
aspectRatio.AspectRatio = WIDTH / HEIGHT
aspectRatio.Parent = window

local screen = Instance.new("EditableImage")
screen.Size = size
screen.Name = "Screen"
screen.Parent = window

local ticker = 0
local runner: thread?
local lastTick = os.clock()
local frameBuffer = buffer.create(WIDTH * HEIGHT * 4)

buffer.fill(frameBuffer, 0, 255)

local inputMap = {
	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.Right] = "Right",

	[Enum.KeyCode.X] = "A",
	[Enum.KeyCode.Z] = "B",

	[Enum.KeyCode.W] = "Up",
	[Enum.KeyCode.S] = "Down",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.D] = "Right",

	[Enum.KeyCode.Return] = "Start",
	[Enum.KeyCode.RightShift] = "Select",

	[Enum.KeyCode.DPadUp] = "Up",
	[Enum.KeyCode.DPadDown] = "Down",
	[Enum.KeyCode.DPadLeft] = "Left",
	[Enum.KeyCode.DPadRight] = "Right",

	[Enum.KeyCode.ButtonY] = "A",
	[Enum.KeyCode.ButtonX] = "B",
}

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	local key = inputMap[input.KeyCode]

	if key then
		gb.input.keys[key] = 1
		gb.input.update()
	end
end

local function onInputEnded(input: InputObject, gameProcessed: boolean)
	local key = inputMap[input.KeyCode]

	if key then
		gb.input.keys[key] = 0
		gb.input.update()
	end
end

local function runThread()
	local self = assert(runner)
	assert(self == coroutine.running())

	local hackRender = Instance.new("Part")
	hackRender.CFrame = workspace.CurrentCamera.CFrame
	hackRender.Parent = workspace

	local hackDecal = Instance.new("Decal")
	hackDecal.Parent = hackRender
	screen.Parent = hackRender

	task.wait()
	screen.Parent = window
	hackRender:Destroy()

	while true do
		local now = os.clock()
		local dt = now - lastTick

		lastTick = now
		ticker = math.min(ticker + dt * 60, 3)

		while ticker >= 1 do
			for i = 1, HEIGHT do
				if self ~= runner then
					return
				end

				debug.profilebegin(`hblank {i}`)
				gb:run_until_hblank()
				debug.profileend()
			end

			ticker -= 1
		end

		-- read pixels
		local pixels = gb.graphics.game_screen
		local i = 0

		for y = 0, HEIGHT - 1 do
			for x = 0, WIDTH - 1 do
				local pixel = pixels[y][x]
				buffer.writeu8(frameBuffer, i, pixel[1])
				buffer.writeu8(frameBuffer, i + 1, pixel[2])
				buffer.writeu8(frameBuffer, i + 2, pixel[3])

				i += 4
			end
		end

		screen:WritePixelsBuffer(Vector2.zero, size, frameBuffer)
		RunService.Heartbeat:Wait()
	end
end

local function onEjectCartridge()
	if runner then
		task.cancel(runner)
		runner = nil
	end

	gb.cartridge.reset()
	ejectCartridge:SetActive(false)
	screen:DrawRectangle(Vector2.zero, size, Color3.new(), 0)
end

local function onEnabledChanged()
	windowToggle:SetActive(gui.Enabled)
end

local function onWindowToggle()
	gui.Enabled = not gui.Enabled
	windowToggle:SetActive(gui.Enabled)
end

local function onLoadRom()
	local file: File? = StudioService:PromptImportFile({ "gb", "gbc" })

	if file then
		local rom = file:GetBinaryContents()
		gb.cartridge.load(rom)
		gb:reset()

		gui.Enabled = true
		runner = task.defer(runThread)
	end
end

local enabledListener = gui:GetPropertyChangedSignal("Enabled")
enabledListener:Connect(onEnabledChanged)
onEnabledChanged()

window.InputBegan:Connect(onInputBegan)
window.InputEnded:Connect(onInputEnded)

ejectCartridge.Click:Connect(onEjectCartridge)
windowToggle.Click:Connect(onWindowToggle)
loadRomBtn.Click:Connect(onLoadRom)
