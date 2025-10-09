--[[MIT License

Copyright (c) 2025 BerserkerStudios

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Spring = require(ReplicatedStorage.Packages.Spring)
local Sera = require(ReplicatedStorage.Packages.Sera)

local SHOOT_SCHEMA = Sera.Schema({ --serilization template
	startPos = Sera.Vector3,
	endPos = Sera.Vector3,
})

local VIEW_MODEL_DOWN_SCALE = 0.2

local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local crosshairGui = playerGui:WaitForChild("CrosshairGui") --we need to wfc screenGuis but not their children

local character = player.Character
local hrp = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera

local viewModel
local shooting = false
local debounce = false
local hideLight

local swaySpring = Spring.new(vector.zero) --Vector3.zero works the same but luau server auto complete gave me vector.zero as the first option 🤷‍♂️
swaySpring.Speed = 10
swaySpring.Damping = 1

local bobbingSpring = Spring.new(vector.zero)
bobbingSpring.Speed = 30
bobbingSpring.Damping = 1

local recoilSpring = Spring.new(vector.zero)
recoilSpring.Speed = 35
recoilSpring.Damping = 0.8 --damping controls how smooth the spring is, 0-1 (1 is highest smoothness)

local function playSoundWithRandomness(template)
	local sound: Sound = template:Clone()
	sound.PlayOnRemove = true --when the sound is destroyed the sound will play at its previous position
	
	local distortion = Instance.new("DistortionSoundEffect", sound) --oh no second parameter, actually it doesnt matter since the parent of sound is nil
	distortion.Level = math.random(0, 40) / 100 --we will get a value from 0 to 0.40, math.random requires the first param to be lower then second
	
	sound.Parent = SoundService --if we parented to a part we would get sound rollOff which we dont want
	sound:Destroy() --clean up and play the sound in one method, lovely!
end

local function recoil()
	local recoil = viewModel.Configuration:GetAttribute("Recoil") --using attributes on a Configuration instance for easy editing
	
	local tween = TweenService:Create( --creating a new tween and saving it to a varible since we need to connect to its completed event
		camera,
		TweenInfo.new(0.05, Enum.EasingStyle.Back), --this easing style makes the tween slightly overshoot the target and then go back
		{ FieldOfView = 70 + math.random(9, 15) * (recoil / 100) } --in 0.05 seconds the FielOfView property will be 70 + math.random(9, 15) * (recoil / 100)
	)
	tween:Play()

	tween.Completed:Once(function() --when the tween ends
	    --sine easing works based on the values of the sin function
		TweenService:Create(camera, TweenInfo.new(0.03, Enum.EasingStyle.Sine), { FieldOfView = 70 }):Play()
	end)
	
	Lighting.ShootBlur.Size = math.random(0, 30) / 10 --the reason im doing / 10 is so we get decimals
	Lighting.ShootBlur.Enabled = true
	task.delay(0.1, function() --task.wait(0.1) task.defer()
		Lighting.ShootBlur.Enabled = false --make the blur dissapear
	end)
	
	local y = math.random(recoil * 90, recoil * 110) / 100 --math.random works in integers so we have to multiply the params and then devide the value if we want more randomness
	local z = math.random(recoil * 90, recoil * 110) / 130
	local x = math.random(-recoil * 90, recoil * 90) / 700
	local recoilVector = Vector3.new(x, -y, z)

	recoilSpring:Impulse(recoilVector)
end

local function bob(addition)
	return math.sin(tick() * addition * 1.3) * 0.5 --tick returns the amount of seconds since the unix epoch
end

local function updateViewModel()
	local finalCF = camera.CFrame

	local bobble = Vector3.new(bob(10), bob(5), bob(5))
	bobbingSpring:Impulse(bobble / 5 * hrp.Velocity.Magnitude / 5) --hrp.Velocity.Magnitude is the speed the character is walking

	finalCF = finalCF:ToWorldSpace( --bob spring is relative so we need to put it to world space
		CFrame.new(
			bobbingSpring.Position.Y * VIEW_MODEL_DOWN_SCALE,
			bobbingSpring.Position.X * VIEW_MODEL_DOWN_SCALE,
			0
		)
	)

	local mouseDelta = UserInputService:GetMouseDelta() --returns the change of the mouse pos in the last frame
	swaySpring:Impulse(
		Vector3.new(-mouseDelta.X / 30 * VIEW_MODEL_DOWN_SCALE, mouseDelta.Y / 16 * VIEW_MODEL_DOWN_SCALE, 0) --we need to multiply by view model down scale otherwise it would be huge
	)
	finalCF *= CFrame.new(swaySpring.Position.X / 2, swaySpring.Position.Y / 2, 0)
	finalCF *= CFrame.Angles(recoilSpring.Position.Y / 3, 0, 0) --angles(fromEulerAnglesXYZ) is in radians
	finalCF *= CFrame.new(recoilSpring.Position.X, 0, recoilSpring.Position.Z)
	
	viewModel.HumanoidRootPart.CFrame = finalCF --everything is welded to hrp so changing its cf is same as doing pivot to on the model
end

local function setupViewModel()
	viewModel = ReplicatedStorage.GunSystem.ViewModels:WaitForChild("AKM"):Clone()
	viewModel:ScaleTo(VIEW_MODEL_DOWN_SCALE) --down scaling the model so it doesnt clip trough walls
	viewModel.Parent = camera
end

local function setupCrosshair()
	UserInputService.MouseIconEnabled = false --hides the mouse
	player.CameraMode = Enum.CameraMode.LockFirstPerson --forces first person camera mode
	
	crosshairGui.Enabled = true
end

local function shoot()
	local serialized, errorMsg = Sera.Serialize(SHOOT_SCHEMA, { --serializing makes the data smaller
		startPos = camera.CFrame.Position,
		endPos = camera.CFrame.LookVector * 200, --the direction the camera is looking made 200x longer
	})
	if not errorMsg then
		ReplicatedStorage.Remotes.Shoot:FireServer(serialized) --send over data to the server
	end
	
	do
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude --this type makes the raycast exclude everything thats on the raycastParams list
		raycastParams.FilterDescendantsInstances = {character, viewModel} --exclude character and viewModel from the raycast
		
		--sends a line from origin to endPos, returns anything the line hits
		local raycast = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 200, raycastParams)
		
		if raycast then
			local endPos = raycast.Position --the position the raycast touched an instance
			local startPos = viewModel.ShootPart.Position
			
			--using vector.magnitude insteand of Vector3.Magnitude since its faster
			local distance = vector.magnitude(viewModel.ShootPart.Position - endPos) --magnitude gets the length of a vector
			local speed = distance / 1000
			
			local tracer = ReplicatedStorage.GunSystem.Effects.Tracer:Clone()
			tracer.Part0.Position = startPos --Tracer is a model with 2 parts and a beam, named it 0 and 1 to follow robloxes naming convention
			tracer.Part1.Position = startPos
			tracer.Parent = workspace

			local tweenInfo = TweenInfo.new(speed, Enum.EasingStyle.Circular)
			TweenService:Create(tracer.Part1, tweenInfo, {Position = endPos}):Play() --we dont put this tween into a variable since we just need to play it
			task.delay(speed / 2, function()
				TweenService:Create(tracer.Part0, tweenInfo, {Position = endPos}):Play()
				task.wait(speed / 2)
				tracer:Destroy() --removes the instance from the instance tree and disconnects its connections, does the same for its descendants

				local bulletHole = ReplicatedStorage.GunSystem.Effects.BulletHole:Clone()
				--.lookAt changes the cframe to have the parts front face facing the position in the second param
				bulletHole.CFrame = CFrame.lookAt(endPos, endPos + raycast.Normal) --raycast.Normal gives us the side we hit
				bulletHole.Parent = workspace
				task.delay(2, function() --the function will be called after aprox. 2 seconds
					TweenService:Create(bulletHole.Decal, TweenInfo.new(0.5, Enum.EasingStyle.Sine),
						{Transparency = 1}):Play()
					task.wait(0.5) --we could do tween.Completed but making a connection when we can just do task.wait is stupid
					bulletHole:Destroy()
				end)
				local hit = ReplicatedStorage.GunSystem.Effects.Hit:Clone()
				hit.CFrame = CFrame.lookAt(endPos, endPos + raycast.Normal)
				hit.Parent = workspace
				task.wait(0.01) --emit sometimes doesnt work if you do it right after parenting to world root
				hit.Attachment.Smoke:Emit(1) --send 1 particle out of the emitter
				hit.Attachment.Flash:Emit(3) --send 3 particles out of the emitter
				task.wait(1)
				hit:Destroy()
			end)
		end
	end
	
	recoil()
	
	playSoundWithRandomness(SoundService.Shoot)
	
	crosshairGui.Reticle.UIScale.Scale = 1.5 --UIScale is an instance that relatively controls the size of its parent
	TweenService:Create(
		crosshairGui.Reticle.UIScale,
		TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play() --tween is linear interpolation made easy (and has easing styles)
	
	for _, v in viewModel.ShootPart.MuzzleFX:GetChildren() do --loop trough all the children of MuzzleFX
		if v:IsA("ParticleEmitter") then --if the class of v is particle emitter
			v:Emit(1)
		elseif v:IsA("PointLight") then
			v.Enabled = true
			if hideLight then --if we have defined the var and it isnt nil
				task.cancel(hideLight) --yield and destroy the thread
			end
			hideLight = task.delay(0.07, function()
				v.Enabled = false
			end)
		end
	end
end

local function startShooting()
	if debounce then
		return --stop the code from running
	end

	shooting = true

	local cd = 60 / viewModel.Configuration:GetAttribute("FireRate") --attributes are properties of an instance that you can custom make

	task.defer(function() --defers the thread untill the next heartbeat
		while shooting do --while shooting is true
			debounce = true --debounce is making sure you cannot spam m1 to shoot faster
			
			shoot()
			task.wait(cd) --yields the code for cd seconds
			
			debounce = false
		end
	end)
end

local function stopShooting()
	shooting = false --true and false are called "booleans"
end

do --does an indentation
	setupCrosshair()
	setupViewModel()

	RunService.PreRender:Connect(function() --runs before a frame is rendered(replacement for RenderStepped)
		updateViewModel()
	end)

	UserInputService.InputBegan:Connect(function(input, processed) --runs when you starting holding a key/mouse button
		if processed then return end --if were in the roblox menu or such

		if input.UserInputType == Enum.UserInputType.MouseButton1 then --if we pressed left click
			startShooting() --calls the function, runs the code in the function
		end
	end)

	UserInputService.InputEnded:Connect(function(input) --runs when you let go off a key/mouse button
		if input.UserInputType == Enum.UserInputType.MouseButton1 then --if we stop holding left click
			stopShooting()
		end
	end)
end
