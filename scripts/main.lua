---@class ChallengeMod
ChallengeMod = {
	MOD_NAME = g_currentModName,
	BASE_DIRECTORY = g_currentModDirectory,
	baseXmlKey = "ChallengeMod",
	configFileName = "ChallengeModConfig.xml",
	isDevelopmentVersion = true
}

ChallengeMod.image = {
	path = Utils.getFilename('Icon_ChallengeMode.dds', ChallengeMod.BASE_DIRECTORY),
	--uvs = {0, 0,1,1}
}


local ChallengeMod_mt = Class(ChallengeMod)

function ChallengeMod.new(custom_mt)
	local self = setmetatable({}, custom_mt or ChallengeMod_mt)
	self.isServer = g_server
	self.visibleFarms = {}
	self.isAdminModeActive = false
	g_messageCenter:subscribe(MessageType.FARM_CREATED, self.newFarmCreated, self)

	if ChallengeMod.isDevelopmentVersion then
		addConsoleCommand('CmGenerateContracts', 'Generates new contracts', 'consoleGenerateFieldMission', g_missionManager)
		CmUtil.debugActive = true
	end

	return self
end

function ChallengeMod:newFarmCreated(farmId)
	self.visibleFarms[farmId] = true
end

function ChallengeMod:changeFarmVisibility(farmId, visible, noEvent)
	if self.visibleFarms[farmId] ~= nil then
		CmUtil.debug("Change visibility of farm %s", farmId)
		if visible == nil then
			self.visibleFarms[farmId] = not self.visibleFarms[farmId]
		else
			self.visibleFarms[farmId] = visible
		end
	else
		self.visibleFarms[farmId] = true
	end
	if noEvent == nil or noEvent == false then
		ChangeFarmVisibilityEvent.sendEvent(farmId, self.visibleFarms[farmId])
	end
end

function ChallengeMod:getIsFarmVisible(farmId)
	return self.visibleFarms[farmId]
end

function ChallengeMod:changeAdminPassword(newPassword, noEvent)
	if newPassword ~= nil then
		self.adminPassword = newPassword
		if noEvent == nil or noEvent == false then
			ChangeAdminPasswordEvent.sendEvent(newPassword)
		end
	end
end

function ChallengeMod:getAdminPassword()
	return self.adminPassword
end

function ChallengeMod:getDefaultAdminPassword()
	return self.defaultAdminPassword
end

function ChallengeMod:loadMap()
	self:setup()
end

function ChallengeMod:setup()
	self:registerXmlSchema()

	self.configFilePath = Utils.getFilename(self.configFileName, self.BASE_DIRECTORY)

	self:loadConfigData(self.configFilePath)

	self:loadFromSaveGame()

	self:setupGui()

	ChallengeMod.startVehicleButtonInfo = {
		text = g_i18n:getText("CM_buttonText_markStartVehicle"),
		inputAction = InputAction.MENU_EXTRA_1,
		callback = function ()
			local vehicle = g_currentMission.shopMenu.selectedDisplayElement.concreteItem

			vehicle.isStartVehicle = not vehicle.isStartVehicle
			ChallengeMod.setButtonText(vehicle)

			g_currentMission.shopMenu:updateButtonsPanel(g_currentMission.shopMenu.pageShopItemDetails)
		end
	}
end

function ChallengeMod:addStartVehicleButton(isOwned, numItems, hasCombinations)
	local buttons = self:getPageButtonInfo(g_currentMission.shopMenu.pageShopItemDetails)

	if numItems > 0 and g_challengeMod.isAdminModeActive then
		table.insert(buttons, ChallengeMod.startVehicleButtonInfo)

		local vehicle = g_currentMission.shopMenu.selectedDisplayElement.concreteItem

		ChallengeMod.setButtonText(vehicle)
	end

	self:updateButtonsPanel(g_currentMission.shopMenu.pageShopItemDetails)
end

function ChallengeMod.setButtonText(vehicle)
	if vehicle.isStartVehicle then
		ChallengeMod.startVehicleButtonInfo.text = g_i18n:getText("CM_buttonText_unmarkStartVehicle")
	else
		ChallengeMod.startVehicleButtonInfo.text = g_i18n:getText("CM_buttonText_markStartVehicle")
	end
end

ShopMenu.updateGarageButtonInfo = Utils.appendedFunction(ShopMenu.updateGarageButtonInfo, ChallengeMod.addStartVehicleButton)

function ChallengeMod:setupGui()
	g_gui:loadProfiles(Utils.getFilename("gui/guiProfiles.xml", self.BASE_DIRECTORY))
	self.frame = ScoreBoardFrame.new()
	g_gui:loadGui(Utils.getFilename("gui/ScoreBoardFrame.xml", self.BASE_DIRECTORY), "ScoreBoardPage", self.frame, true)

	CmUtil.fixInGameMenuPage(self.frame, "pageScoreBoard", self.image)

	self:setupDialogs()
end

function ChallengeMod:setupDialogs()
	local dialog = AddPointsDialog.new()
	g_gui:loadGui(Utils.getFilename("gui/dialogs/AddPointsDialog.xml", self.BASE_DIRECTORY), "AddPointsDialog", dialog, false)
end

function ChallengeMod:registerXmlSchema()
	self.xmlSchema = XMLSchema.new("ChallengeMod")
	self.xmlSchema:register(XMLValueType.STRING, self.baseXmlKey .. "#password", "Admin password")
	self.xmlSchema:register(XMLValueType.INT, self.baseXmlKey .. ".Farms.Farm(?)#id", "Farm id")
	self.xmlSchema:register(XMLValueType.BOOL, self.baseXmlKey .. ".Farms.Farm(?)#visible", "Farm visible", true)
	g_victoryPointManager:registerXmlSchema(self.xmlSchema, self.baseXmlKey)
	g_ruleManager:registerXmlSchema(self.xmlSchema, self.baseXmlKey)

	self.xmlConfigSchema = XMLSchema.new("ChallengeModConfig")
	self.xmlConfigSchema:register(XMLValueType.STRING, self.baseXmlKey .. "#defaultPassword", "Admin password", "")

	g_victoryPointManager:registerConfigXmlSchema(self.xmlConfigSchema, self.baseXmlKey)
	g_ruleManager:registerConfigXmlSchema(self.xmlConfigSchema, self.baseXmlKey)
end

function ChallengeMod:loadConfigData(filename)
	local xmlFile = XMLFile.loadIfExists("xmlFile", filename, self.xmlConfigSchema)
	if xmlFile ~= nil then
		CmUtil.debug("Challenge setup loaded from %s.", filename)
		self.adminPassword = xmlFile:getValue(self.baseXmlKey .. "#defaultPassword")
		self.defaultAdminPassword = self.adminPassword
		g_ruleManager:loadConfigData(xmlFile, self.baseXmlKey)
		g_victoryPointManager:loadConfigData(xmlFile, self.baseXmlKey)
		xmlFile:delete()
		return true
	else
		CmUtil.debug("Challenge setup xml could not be loaded.")
	end
end

function ChallengeMod:saveToXMLFile(filename)
	local xmlFile = XMLFile.create("xmlFile", filename, self.baseXmlKey, self.xmlSchema)
	if xmlFile ~= nil then
		CmUtil.debug("Challenge setup saved to %s.", filename)
		xmlFile:setValue(self.baseXmlKey .. "#password", self.adminPassword)
		local i = 0
		for farmId, visible in pairs(self.visibleFarms) do
			xmlFile:setValue(string.format("%s.Farms.Farm(%d)#id", self.baseXmlKey, i), farmId)
			xmlFile:setValue(string.format("%s.Farms.Farm(%d)#visible", self.baseXmlKey, i), visible)
			i = i + 1
		end
		g_ruleManager:saveToXMLFile(xmlFile, self.baseXmlKey)
		g_victoryPointManager:saveToXMLFile(xmlFile, self.baseXmlKey)
		xmlFile:save()
		xmlFile:delete()
	else
		CmUtil.debug("Challenge setup xml could not be created.")
	end
end

function ChallengeMod:saveStartVehicleAttributeToXMLFile(xmlFile, key, usedModNames)
	xmlFile:setBool(key .. "#isStartVehicle", self.isStartVehicle or false)
end

Vehicle.saveToXMLFile = Utils.appendedFunction(Vehicle.saveToXMLFile, ChallengeMod.saveStartVehicleAttributeToXMLFile)

function ChallengeMod:loadFromXMLFile(filename)
	local xmlFile = XMLFile.loadIfExists("xmlFile", filename, self.xmlSchema)
	if xmlFile ~= nil then
		CmUtil.debug("Challenge setup loaded from %s.", filename)
		self.adminPassword = xmlFile:getValue(self.baseXmlKey .. "#password", self.adminPassword)
		--maybe save password encrypted to increase user security. Many people use the same passwords everywhere so this could make them more attackable with a password saved in clear text

		xmlFile:iterate(self.baseXmlKey .. ".Farms.Farm", function(ix, key)
			local id = xmlFile:getValue(key .. "#id")
			local visible = xmlFile:getValue(key .. "#visible", true)
			if id ~= nil then
				self.visibleFarms[id] = visible
			end
		end)

		g_ruleManager:loadFromXMLFile(xmlFile, self.baseXmlKey)
		g_victoryPointManager:loadFromXMLFile(xmlFile, self.baseXmlKey)
		xmlFile:delete()
		return true
	else
		CmUtil.debug("Challenge setup xml could not be loaded.")
	end
end

function ChallengeMod:loadStartVehicleAttribute(i3dNode, failedReason, arguments, i3dLoadingId)
	local savegame = arguments["savegame"]

	if savegame ~= nil then
		self.isStartVehicle = savegame.xmlFile:getBool(savegame.key .. "#isStartVehicle", false)
	end
end

Vehicle.loadFinished = Utils.appendedFunction(Vehicle.loadFinished, ChallengeMod.loadStartVehicleAttribute)

function ChallengeMod:writeStream(streamId, connection)
	streamWriteString(streamId, self.adminPassword)

	for farmId, visible in pairs(self.visibleFarms) do
		streamWriteInt8(streamId, farmId)
		streamWriteBool(streamId, visible)
	end
	streamWriteInt8(streamId, -1)

	g_ruleManager:writeStream(streamId, connection)
	g_victoryPointManager:writeStream(streamId, connection)
end

function ChallengeMod:writeStreamVehicleAttribute(streamId, connection)
	streamWriteBool(streamId, self.isStartVehicle or false)
end
Vehicle.writeStream = Utils.appendedFunction(Vehicle.writeStream, ChallengeMod.writeStreamVehicleAttribute)

function ChallengeMod:readStream(streamId, connection)
	self.adminPassword = streamReadString(streamId)

	while true do
		local id = streamReadInt8(streamId)
		if id < 0 then
			break
		end
		self.visibleFarms[id] = streamReadBool(streamId)
	end
	g_ruleManager:readStream(streamId, connection)
	g_victoryPointManager:readStream(streamId, connection)
end

function ChallengeMod:readStreamVehicleAttribute(streamId, connection)
	self.isStartVehicle = streamReadBool(streamId)
end
Vehicle.readStream = Utils.appendedFunction(Vehicle.readStream, ChallengeMod.readStreamVehicleAttribute)

function ChallengeMod:reloadConfigData()
	--self:loadConfigData(self.configFilePath)
end

function ChallengeMod:loadFromSaveGame()
	if g_currentMission.missionInfo.savegameDirectory ~= nil then
		local fileName = g_currentMission.missionInfo.savegameDirectory .. "/" .. self.configFileName
		self:loadFromXMLFile(fileName)
	end
end

function ChallengeMod:saveToSaveGame()
	if g_modIsLoaded[ChallengeMod.MOD_NAME] then
		local saveGamePath = g_currentMission.missionInfo.savegameDirectory .. "/" .. ChallengeMod.configFileName
		g_challengeMod:saveToXMLFile(saveGamePath)
	end
end

ItemSystem.save = Utils.prependedFunction(ItemSystem.save, ChallengeMod.saveToSaveGame)

g_challengeMod = ChallengeMod.new()

addModEventListener(g_challengeMod)