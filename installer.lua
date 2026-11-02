-- Run in Studio Edit mode in a NEW EMPTY place after configuring Server Authority.
-- This creates the three original reproduction scripts. It does not erase existing content.
assert(game:GetService("RunService"):IsEdit(), "Run in Studio Edit mode")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScripts = game:GetService("ServerScriptService")
local starterScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
for _, item in workspace:GetChildren() do
    assert(item:IsA("Camera") or item:IsA("Terrain"), "Use a new empty place with no baseplate or spawn location")
end
assert(not replicatedStorage:FindFirstChild("HopStep"), "HopStep already exists")
assert(not serverScripts:FindFirstChild("HopServer"), "HopServer already exists")
assert(not starterScripts:FindFirstChild("HopClient"), "HopClient already exists")
local function add(className, name, parent, source)
    local scriptObject = Instance.new(className)
    scriptObject.Name = name
    scriptObject.Source = source
    scriptObject.Parent = parent
end

add("ModuleScript", "HopStep", replicatedStorage, [==[
--!strict
-- Шаг на обеих сторонах: атрибут детали соседа считается из команды на модели, как Turn_IntentRate.
local HopStep = {}

function HopStep.run(bodies: { [string]: Model })
	local rival = bodies.Rival
	local part = rival and rival:FindFirstChild("Body") :: BasePart?
	if not (rival and part) then
		return
	end
	local rate = part:GetAttribute("Rate")
	local command = rival:GetAttribute("Cmd")
	if typeof(rate) == "number" and typeof(command) == "number" then
		local nextRate = rate + (command - rate) * 0.3
		part:SetAttribute("Rate", math.round(nextRate / 0.01) * 0.01)
	end
end

return HopStep
]==])

add("Script", "HopServer", serverScripts, [==[
-- Минимальный пример: откат по атрибуту соседней детали сдвигает другую предсказанную деталь.
-- Аргумент теста: "<подпись> change" — команда соседа меняется 15 раз в секунду, иначе постоянна.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local STS = game:GetService("StudioTestService")
local HopStep = require(RS:WaitForChild("HopStep"))

local CLIENTS = 2
local SPEED = 110
local WARMUP = 3
local MEASURE = 40

local gotArgs, args = pcall(function()
	return STS:GetTestArgs()
end)
local mode = if gotArgs and typeof(args) == "string" then args else "manual change"

local ready = Instance.new("RemoteEvent")
ready.Name = "HopReady"
ready.Parent = RS

local base = Instance.new("Part")
base.Name = "Base"
base.Anchored = true
base.Size = Vector3.new(200, 4, 30000)
base.Position = Vector3.new(0, -2, -14000)
base.Friction = 0
base.Parent = workspace

local folder = Instance.new("Folder")
folder.Name = "Hop"
local function body(name, x)
	local model = Instance.new("Model")
	model.Name = name
	-- детали уезжают от персонажа: иначе они выйдут из области стриминга
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = Vector3.new(4, 2, 6)
	part.Position = Vector3.new(x, 1.2, 0)
	part.Friction = 0
	part.Parent = model
	part:SetAttribute("Rate", 0)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VectorVelocity = Vector3.zero
	drive.MaxForce = 1e7
	drive.Parent = part
	model:SetAttribute("Cmd", 0)
	model.PrimaryPart = part
	model.Parent = folder
	return model
end
local own = body("Own", 0)
local rival = body("Rival", 8)
folder.Parent = workspace

local bodies = { Own = own, Rival = rival }
local rows = {}
local recording = false
Run:BindToSimulation(function()
	HopStep.run(bodies)
	if recording then
		table.insert(rows, string.format("%d %.2f", math.round(time() * 60), own.Body.Position.Z))
	end
end, Enum.StepFrequency.Hz60)

local done = {}
local reported = 0
ready.OnServerEvent:Connect(function(player, stage)
	if stage == "ready" then
		done[player] = true
	elseif stage == "reported" then
		reported += 1
	end
end)

local waited = os.clock()
local function readyCount()
	local count = 0
	for _ in done do
		count += 1
	end
	return count
end
while readyCount() < CLIENTS and os.clock() - waited < 90 do
	task.wait(0.2)
end
if readyCount() < CLIENTS then
	print("[HOP] abort: готовы " .. readyCount() .. " из " .. CLIENTS)
	pcall(function()
		STS:EndTest("abort")
	end)
	return
end
print(string.format("[HOP] ready %d, ждали %.1f с, режим %s", readyCount(), os.clock() - waited, mode))

own.Body.Drive.VectorVelocity = Vector3.new(0, 0, -SPEED)
rival.Body.Drive.VectorVelocity = Vector3.new(0, 0, -SPEED)
task.wait(WARMUP)
recording = true
workspace:SetAttribute("HopRec", true)
local start = os.clock()
while os.clock() - start < MEASURE do
	if string.find(mode, "change") then
		rival:SetAttribute("Cmd", 0.3 * math.sin((os.clock() - start) * 2.5))
	end
	task.wait(1 / 15)
end
workspace:SetAttribute("HopRec", false)
recording = false
local waitReports = os.clock()
while reported < CLIENTS and os.clock() - waitReports < 20 do
	task.wait(0.2)
end
print(string.format("[HOP] отчётов %d из %d", reported, CLIENTS))
local text = table.concat(rows, ";")
for i = 1, #text, 1500 do
	print("[TRACK]" .. string.sub(text, i, i + 1499))
end
print("[HOP] done")
task.wait(2)
pcall(function()
	STS:EndTest("done")
end)
]==])

add("LocalScript", "HopClient", starterScripts, [==[
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Run = game:GetService("RunService")
local HopStep = require(RS:WaitForChild("HopStep"))
if not game:IsLoaded() then
	game.Loaded:Wait()
end
local ready = RS:WaitForChild("HopReady")
local folder = workspace:WaitForChild("Hop")
local own = folder:WaitForChild("Own")
local rival = folder:WaitForChild("Rival")
local frame = own:WaitForChild("Body")
local rivalFrame = rival:WaitForChild("Body")
frame:WaitForChild("Drive")
rivalFrame:WaitForChild("Drive")
for _, model in { own, rival } do
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Constraint") then
			Run:SetPredictionMode(item, Enum.PredictionMode.On)
		end
	end
end
local bodies = { Own = own, Rival = rival }
local calls = {}
Run:BindToSimulation(function(dt)
	HopStep.run(bodies)
	if workspace:GetAttribute("HopRec") == true then
		table.insert(calls, { t = time(), dt = dt, r = Run:IsResimulating(), p = frame.Position, v = frame.AssemblyLinearVelocity })
	end
end, Enum.StepFrequency.Hz60)
local id = Players.LocalPlayer.UserId
print("[HOP] client ready " .. id .. " status " .. Run:GetPredictionStatus(frame).Name)
ready:FireServer("ready")

workspace:GetAttributeChangedSignal("HopRec"):Connect(function()
	if workspace:GetAttribute("HopRec") ~= false then
		return
	end
	local groups, normal, clock, moved, both = 0, 0, 0, 0, 0
	local previous
	local list = table.clone(calls)
	local lines = {}
	local journal = {}
	for i, call in list do
		table.insert(journal, string.format("%d %s %.2f", math.round(call.t * 60), if call.r then "R" else "N", call.p.Z))
		if call.r and not (list[i - 1] and list[i - 1].r) then
			groups += 1
		end
		if not call.r then
			if previous then
				local before = list[previous]
				local speed = before.v.Magnitude
				if speed > 10 then
					normal += 1
					local steps = (call.p - before.p):Dot(before.v.Unit) / (speed * call.dt)
					local ticks = (call.t - before.t) * 60
					local c, m = math.abs(ticks - 1) > 0.4, math.abs(steps - 1) > 0.4
					if c and m then
						both += 1
					elseif c then
						clock += 1
					elseif m then
						moved += 1
					end
					if c or m then
						table.insert(lines, string.format("[LT] вызов %d метка %d: рама %+.2f, метка %+.1f, пересчёт %d", i, math.round(call.t * 60), steps, ticks, i - previous - 1))
					end
				end
			end
			previous = i
		end
	end
	print(string.format("[LT] клиент %d пинг %.0f: вызовов %d, откатов %d, обычных %d, только метка %d, только рама %d, оба %d", id, Players.LocalPlayer:GetNetworkPing() * 1000, #list, groups, normal, clock, moved, both))
	for _, line in lines do
		print(line)
	end
	local text = table.concat(journal, ";")
	for i = 1, #text, 1500 do
		print("[CALLS]" .. string.sub(text, i, i + 1499))
	end
	ready:FireServer("reported")
end)
]==])

print("Reproduction scripts installed. Configure network settings, then start a two-client test.")
