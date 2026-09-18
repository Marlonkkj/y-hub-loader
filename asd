--// Y Hub Loader (Versão com Interface Restaurada + Anti-Lag Ativo)
local globalEnvironment = (getgenv and getgenv()) or _G
local baseEnvironment = (getfenv and getfenv()) or _G
local loaderConfig = globalEnvironment.YHubLoaderConfig
	or globalEnvironment.YCoreLoaderConfig
	or globalEnvironment.YAutoSignalLoaderConfig
	or {}

--// 1. APLICAR PROTEÇÃO DE FPS E MEMÓRIA (ANTI-LAG)
if not globalEnvironment.__AntiLagApplied then
	globalEnvironment.__AntiLagApplied = true

	local rawWait = task.wait
	globalEnvironment.task.wait = function(seconds)
		local sec = tonumber(seconds) or 0
		return rawWait(math.max(sec, 0.05))
	end

	if type(globalEnvironment.wait) == "function" then
		globalEnvironment.wait = function(seconds)
			local sec = tonumber(seconds) or 0
			return rawWait(math.max(sec, 0.05))
		end
	end
end

--// 2. CONFIGURAÇÃO BASE
local baseUrl = loaderConfig.BaseUrl or "https://raw.githubusercontent.com/GodErste/Y-Core/main/"
if baseUrl:sub(-1) ~= "/" then baseUrl = baseUrl .. "/" end

local function identity(callback) return callback end
local function attribute() return nil end

local function ensureFunction(environment, name, fallback)
	if type(environment[name]) ~= "function" then
		environment[name] = fallback
	end
	return environment[name]
end

ensureFunction(globalEnvironment, "LPH_ATTRIBUTES", attribute)
ensureFunction(globalEnvironment, "VM", attribute)
ensureFunction(globalEnvironment, "PRESET", attribute)
ensureFunction(globalEnvironment, "NONE", attribute)
ensureFunction(globalEnvironment, "FAST", attribute)
globalEnvironment["YHUB_NO_VIRTUALIZE"] = identity
ensureFunction(baseEnvironment, "LPH_ATTRIBUTES", globalEnvironment["LPH_ATTRIBUTES"])
ensureFunction(baseEnvironment, "VM", globalEnvironment["VM"])
ensureFunction(baseEnvironment, "PRESET", globalEnvironment["PRESET"])
ensureFunction(baseEnvironment, "NONE", globalEnvironment["NONE"])
ensureFunction(baseEnvironment, "FAST", globalEnvironment["FAST"])
baseEnvironment["YHUB_NO_VIRTUALIZE"] = globalEnvironment["YHUB_NO_VIRTUALIZE"]

local Framework = {
	Name = "Y Hub",
	Version = "0.1.0",
	BaseUrl = baseUrl,
	Cache = {},
	Config = loaderConfig,
	StartedAt = os.clock(),
}

globalEnvironment.YHubFramework = Framework
globalEnvironment.YCoreFramework = Framework

local function normalizeModulePath(modulePath)
	return tostring(modulePath or ""):gsub("\\", "/"):gsub("^/+", "")
end

local function loadLua(source, chunkName)
	local loadedChunk, errorMessage = loadstring(source, chunkName)
	assert(loadedChunk, errorMessage)
	return loadedChunk
end

local function setChunkEnvironment(loadedChunk, moduleEnvironment)
	if setfenv then
		setfenv(loadedChunk, moduleEnvironment)
	end
	return loadedChunk
end

function Framework:Fetch(modulePath)
	modulePath = normalizeModulePath(modulePath)
	return game:HttpGet(self.BaseUrl .. modulePath)
end

function Framework:FetchUrl(url)
	return game:HttpGet(tostring(url))
end

function Framework:LoadUrl(url, chunkName)
	local resolvedChunkName = chunkName or ("@" .. tostring(url))
	local moduleSource = self:FetchUrl(url)
	local loadedChunk = loadLua(moduleSource, resolvedChunkName)

	local moduleEnvironment = setmetatable({
		Framework = self,
		yrequire = function(childModulePath, childForceReload)
			return self:yrequire(childModulePath, childForceReload)
		end,
	}, {
		__index = baseEnvironment,
	})

	moduleEnvironment.Require = moduleEnvironment.yrequire
	return setChunkEnvironment(loadedChunk, moduleEnvironment)()
end

function Framework:yrequire(modulePath, forceReload)
	modulePath = normalizeModulePath(modulePath)

	if not forceReload and self.Cache[modulePath] ~= nil then
		return self.Cache[modulePath]
	end

	local moduleSource = self:Fetch(modulePath)
	local loadedChunk = loadLua(moduleSource, "@" .. modulePath)

	local moduleEnvironment = setmetatable({
		Framework = self,
		yrequire = function(childModulePath, childForceReload)
			return self:yrequire(childModulePath, childForceReload)
		end,
	}, {
		__index = baseEnvironment,
	})

	moduleEnvironment.Require = moduleEnvironment.yrequire
	local moduleResult = setChunkEnvironment(loadedChunk, moduleEnvironment)()

	if moduleResult == nil then
		moduleResult = true
	end

	self.Cache[modulePath] = moduleResult
	return moduleResult
end

Framework.Require = Framework.yrequire

--// 3. CARREGAMENTO DO JOGO
function Framework:Start()
	local gameRegistry = self:yrequire("games/index.lua", self.Config.ForceReload == true)
	local selectedGameId = self.Config.Game

	if selectedGameId == nil and type(gameRegistry.FindByPlaceId) == "function" then
		selectedGameId = gameRegistry.FindByPlaceId(game.PlaceId)
	end

	selectedGameId = tostring(selectedGameId or gameRegistry.Default or "shinsei"):lower()

	local gameInfo = nil
	if type(gameRegistry.GetGame) == "function" then
		gameInfo = gameRegistry.GetGame(selectedGameId)
	elseif type(gameRegistry.Games) == "table" then
		gameInfo = gameRegistry.Games[selectedGameId]
	end

	if type(gameInfo) ~= "table" then
		error("unknown game: " .. selectedGameId)
	end

	self.GameId = selectedGameId
	self.Game = gameInfo
	self.Name = gameInfo.Name or self.Name
	self.Version = tostring(gameInfo.Version or self.Version)

	local sourceMode = self.Config.SourceMode == true
	local gameModule

	if sourceMode then
		local gameModulePath = gameInfo.Entry or ("games/" .. selectedGameId .. "/init.lua")
		gameModule = self:yrequire(gameModulePath, self.Config.ForceReload == true)
	else
		local bundleUrl = gameInfo.BundleUrl or gameInfo.BuildUrl or gameInfo.LoaderUrl

		if bundleUrl then
			gameModule = self:LoadUrl(bundleUrl, "@" .. selectedGameId .. ".bundle")
		elseif gameInfo.Loader then
			gameModule = self:yrequire(gameInfo.Loader, self.Config.ForceReload == true)
		else
			local gameModulePath = gameInfo.Entry or ("games/" .. selectedGameId .. "/init.lua")
			gameModule = self:yrequire(gameModulePath, self.Config.ForceReload == true)
		end
	end

	if type(gameModule) == "table" and type(gameModule.Start) == "function" then
		return gameModule.Start(self)
	end

	return gameModule
end

return Framework:Start()
