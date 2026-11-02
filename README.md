# Server Authority: predicted part with constant velocity sometimes stalls or jumps back around resimulation, then overshoots

I can't attach a place file, so the full repro scripts are inline at the bottom. I ran the installer as-is in a fresh empty place and did a full two-client test with it. The three scripts it creates are exactly the ones I measured with.

**What's happening**

With Server Authority on, a predicted part moving at constant speed sometimes stalls or steps *backwards* around a resim. A later resim then jumps it forward to make up the difference. The simulation time labels stay continuous through these pairs, so the clock looks fine. Only the position goes wrong.

The repro is standalone, with no code from my motorcycle game. The scene has a long floor, default characters, and two independent parts driven at 110 studs/s by LinearVelocity. Both clients predict both parts. A shared 60 Hz BindToSimulation function updates an attribute on one part ("Rival"). The part I'm measuring ("Own") doesn't depend on that attribute.

Between normal (non-resim) callbacks I'd expect about 110/60 ≈ 1.83 studs. Instead I sometimes get 0 or −1 step, and later +2 or +3. Here's a real pair with the Rival's command held constant. The scripts print in Russian:

```text
[LT] вызов 3491 метка 2961: рама -1.00, метка +1.0, пересчёт 7
[LT] вызов 3502 метка 2964: рама +3.00, метка +1.0, пересчёт 8
```

What the fields mean:
- `вызов` – callback number since recording started, resim callbacks included.
- first `метка` – time label, `round(time() * 60)`.
- `рама` – distance moved since the previous normal callback, in normal steps. Should be +1.
- second `метка` – change in time label since the previous normal callback. Should be +1.
- `пересчёт` – resim callbacks between the two normal samples.

So that's −2 steps, then +2 steps of error, or about ±3.67 studs. This is the part's physics position, not the camera or any smoothing.

**Numbers**

Setup: Studio 0.745.0.7451137 on macOS, one local server and two clients on the same machine, launched via `StudioTestService:ExecuteMultiplayerTestAsync`. Each condition got 3 runs of about 40 s each, so each row is 6 client reports.

| Network (in/out) | Rival command | Resim sequences | Position anomalies | Time-label anomalies |
| --- | --- | ---: | ---: | ---: |
| All artificial settings 0 | Changing | 2110 | 10 | 0 |
| Min delay 30/30 ms | Changing | 2131 | 6 | 0 |
| 30/30 ms, jitter 12/15 ms, loss 0.2/0.3% | Changing | 1929 | 7 | 1 |
| 30/30 ms, jitter 12/15 ms, loss 0.2/0.3% | Constant | 1077 | 8 | 0 |

All 12 runs finished on both clients. In total there were 31 position anomalies across 7247 resim sequences, showing up in 9 of the 24 client reports. Every one of the 31 had continuous time labels and resim callbacks in between. The single time-label anomaly was a separate event. The biggest error in this series was 2 steps.

The constant row has the highest rate, 0.74% against 0.28–0.47% for the others. But all 8 came from both clients of a single run, so I wouldn't read much into it. What it does show is that a changing command isn't needed to get the bug.

How I count:
- A **sequence** is a contiguous group of callbacks where `IsResimulating()` is true.
- An **anomaly** is movement more than 0.4 step off the expected +1, based on the previous velocity and the callback dt.

Events cluster and don't happen every run. Nothing here shows latency or jitter is required.

**Separate thing: time jump, then catch-up**

One extra run (not in the table) showed something different. The network settings were 30/30 ms delay, 12/15 ms jitter, 0.2/0.3% loss, IncomingReplicationLag = 0.

```text
[LT] вызов 1015 метка 1201: рама +1.00, метка +10.0, пересчёт 0
[LT] вызов 1033 метка 1207: рама +9.97, метка +1.0, пересчёт 12
```

Here the time label jumped 10 ticks with no resim, but the part only moved 1 step. That left it about 9 steps behind the clock. A few callbacks later, after 12 resim callbacks, it moved 9.97 steps in one interval (≈16.4 studs) and basically caught back up. Over the whole stretch it's about 11 steps in 11 ticks. I'm keeping this apart from the paired errors above, since there the clock never jumps. I don't know what causes the time jump itself.

The same run is also how I checked the installer. Both clients were ready after 6.7 s, both reports came in, the test ended with `done`, and none of the scripts errored.

**Repro**

1. Create a new empty place with no baseplate and no spawn. Leave `Players.CharacterAutoLoads = true`.
2. Set `Workspace.AuthorityMode = Server`. Check these are set: StreamingEnabled = true, NextGenerationReplication = Enabled, PlayerScriptsUseInputActionSystem = Enabled, UseFixedSimulation = Enabled, SignalBehavior = Deferred.
3. In Edit mode, paste the installer (in the spoiler at the bottom) into the Command Bar. It adds 3 scripts and refuses to run if Workspace isn't empty.
4. Zero the network sim settings, including the legacy IncomingReplicationLag:

```lua
local n = settings().Network
n.IncomingReplicationLag = 0
n.InboundNetworkMinDelayMs = 0
n.OutboundNetworkMinDelayMs = 0
n.InboundNetworkJitterMs = 0
n.OutboundNetworkJitterMs = 0
n.InboundNetworkLossPercent = 0
n.OutboundNetworkLossPercent = 0
```

5. Launch from a context that's allowed to call it:

```lua
game:GetService("StudioTestService"):ExecuteMultiplayerTestAsync(2, "zero change 1")
```

I've only launched through this API, not the Server & Clients button. The label doesn't touch network settings. If it contains `change`, the Rival's command varies; without it, the command stays constant. The server waits for both clients, starts the parts, warms up for 3 s, and records for about 40 s. Each client then prints an `[LT]` summary and anomaly lines. It's intermittent, so if nothing shows up, rerun with a new label.

**What I don't know**

- I don't know the internal cause or how old the restored state is. Default characters are still in the scene, and nothing here says which instance triggers each resim.
- The long `[CALLS]` / `[TRACK]` dumps got truncated, so treat them as incomplete. The short `[LT]` lines are intact and agree with each other. Totals come from in-script counters, not a full trajectory rebuild.
- I didn't read back the network settings in each client's log. Both clients share one server, so their reports aren't independent trials.
- I've only tested Studio on one Mac. I haven't tried a published game, separate machines, or another OS, and I haven't measured how it looks on screen.

**Ask**

Could you look into the paired errors? Or is there a supported way to tell whether the problem is the state that gets *restored* at the start of a resim, or the *number of steps replayed*? I can't separate those two from script.

The installer is also available as a separate file: [installer.lua](installer.lua) (paste its contents into the Studio Command Bar).

[details="Scene installer (original repro sources)"]
```lua
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
```
[/details]
