--!nocheck

local class = loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/whoami-lab-1/Whoami/refs/heads/main/Class.luau"
))().class

local Whoami = {}

local services = {}
local controllers = {}

local started = false

--// Models
local ServiceModel = class("Service") {
	Public = {
		Name = "",
		Services = {},
	}
}

--// Resolve ServicesUsed
local function resolveServices(servicesUsed)
	local resolved = {}

	if servicesUsed == nil then
		return resolved
	end

	assert(
		type(servicesUsed) == "table",
		"[Whoami] 'ServicesUsed' debe ser una tabla"
	)

	for _, service in servicesUsed do
		assert(
			typeof(service) == "Instance",
			"[Whoami] Cada elemento de 'ServicesUsed' debe ser un Instance"
		)

		local serviceName = service.Name

		assert(
			resolved[serviceName] == nil,
			"[Whoami] Servicio duplicado: " .. serviceName
		)

		resolved[serviceName] = service
	end

	return table.freeze(resolved)
end

function Whoami.CreateService(config)
	assert(
		not started,
		"[Whoami] No puedes crear servicios después de iniciar"
	)

	assert(
		type(config) == "table",
		"[Whoami] Config debe ser una tabla"
	)

	assert(
		type(config.Name) == "string",
		"[Whoami] El servicio requiere 'Name'"
	)

	assert(
		not services[config.Name],
		"[Whoami] Servicio ya registrado: " .. config.Name
	)

	local serviceName = config.Name
	local serviceServices = resolveServices(config.ServicesUsed)

	local public = config.Public or {}

	--// Reserved framework properties
	assert(
		public.Services == nil,
		"[Whoami] 'Services' está reservado por el framework"
	)

	public.Services = serviceServices
	public.Name = serviceName

	local ServiceClass = class(serviceName)(ServiceModel) {
		Public = public
	}

	services[serviceName] = ServiceClass

	return ServiceClass
end

function Whoami.GetService(name)
	assert(
		type(name) == "string",
		"[Whoami] El nombre del servicio debe ser una cadena"
	)

	local service = services[name]

	if not service then
		warn("[Whoami] Servicio no existe: " .. name)
		return nil
	end

	return service
end

local function registerBuiltInServices()

	--// LocalPlayerService
	local LocalPlayerService = {
		Name = "LocalPlayerService",

		ServicesUsed = {
			game:GetService("Players"),
		},

		Public = {

			--// Player
			GetPlayer = function(self)
				return self.Services.Players.LocalPlayer
			end,

			GetTeam = function(self)
				return self:GetPlayer().Team
			end,

			--// Player Containers
			GetBackpack = function(self)
				return self:GetPlayer():WaitForChild("Backpack")
			end,

			GetPlayerGui = function(self)
				return self:GetPlayer():WaitForChild("PlayerGui")
			end,

			GetPlayerScripts = function(self)
				return self:GetPlayer():WaitForChild("PlayerScripts")
			end,

			--// Character
			GetCharacter = function(self)
				return self:GetPlayer().Character
			end,

			GetHumanoid = function(self)
				local Character = self:GetCharacter()

				return Character
					and Character:FindFirstChildOfClass("Humanoid")
			end,

			GetRootPart = function(self)
				local Character = self:GetCharacter()

				return Character
					and Character:FindFirstChild("HumanoidRootPart")
			end,

			--// Client
			GetCamera = function(self)
				return workspace.CurrentCamera
			end,

			GetMouse = function(self)
				return self:GetPlayer():GetMouse()
			end,

			--// State
			HasCharacter = function(self)
				return self:GetCharacter() ~= nil
			end,

			IsAlive = function(self)
				local Humanoid = self:GetHumanoid()

				return Humanoid ~= nil
					and Humanoid.Health > 0
			end,

			--// Waiting
			WaitForCharacter = function(self)
				return self:GetPlayer().Character
					or self:GetPlayer().CharacterAdded:Wait()
			end,

			WaitForHumanoid = function(self)
				local Character = self:WaitForCharacter()

				return Character:WaitForChild("Humanoid")
			end,

			WaitForRootPart = function(self)
				local Character = self:WaitForCharacter()

				return Character:WaitForChild("HumanoidRootPart")
			end,
		}
	}

	Whoami.CreateService(LocalPlayerService)
end

function Whoami.Start()
	assert(
		not started,
		"[Whoami] Ya se ha iniciado"
	)

	registerBuiltInServices()

	started = true
end

return Whoami
