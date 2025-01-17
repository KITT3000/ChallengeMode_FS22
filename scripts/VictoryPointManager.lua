VictoryPointManager = {

}
local VictoryPointManager_mt = Class(VictoryPointManager)
---@class VictoryPointManager
function VictoryPointManager.new(custom_mt)
	local self = setmetatable({}, custom_mt or VictoryPointManager_mt)
	self.isServer = g_server

	self.totalPoints = {}
	self.additionalPoints = {}
	self.pointList = {}

	return self
end

function VictoryPointManager:registerXmlSchema(xmlSchema, baseXmlKey)
	ScoreBoardList.registerXmlSchema(xmlSchema, baseXmlKey .. ".VictoryPoints")

	xmlSchema:register(XMLValueType.INT, baseXmlKey .. ".VictoryPoints#goal", "Goal of the challenge in points", 1000000)
	baseXmlKey = baseXmlKey .. ".AdditionalPoints"
	xmlSchema:register(XMLValueType.INT, baseXmlKey .. ".Farm(?)#id", "Id of Farm with additional Points")
	baseXmlKey = baseXmlKey .. ".Farm(?)"
	xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".Point(?)", "The reason why the additonal Point was added.")
	baseXmlKey = baseXmlKey .. ".Point(?)"
	xmlSchema:register(XMLValueType.INT, baseXmlKey .. "#points", "Value of how many Points this point is worth.", 0)
	xmlSchema:register(XMLValueType.STRING, baseXmlKey .. "#date", "Documents when the additional Point was added.")
	xmlSchema:register(XMLValueType.STRING, baseXmlKey .. "#addedBy", "Documents which user has added the additional Point")
end

function VictoryPointManager:registerConfigXmlSchema(xmlSchema, baseXmlKey)
	CmUtil.registerConfigXmlSchema(xmlSchema, baseXmlKey .. ".VictoryPoints")
	xmlSchema:register(XMLValueType.INT, baseXmlKey .. ".VictoryPoints#goal", "Victory point goal")

	xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".VictoryPoints.IgnoredFillTypes.IgnoredFillType(?)",
		"Ignored fill type")

end

function VictoryPointManager:loadConfigData(xmlFile, baseXmlKey)
	self.configData, self.titles = CmUtil.loadConfigCategories(xmlFile, baseXmlKey .. ".VictoryPoints")
	self.victoryGoal = xmlFile:getValue(baseXmlKey .. ".VictoryPoints#goal", 100000)

	VictoryPointManager.ignoredFillTypes = {}
	xmlFile:iterate(baseXmlKey .. ".VictoryPoints.IgnoredFillTypes.IgnoredFillType", function(ix, key)
		local name = xmlFile:getValue(key)
		if name then
			CmUtil.debug("Ignored fill type: %s", name)
			local fillType = g_fillTypeManager:getFillTypeIndexByName(name)
			if fillType then
				VictoryPointManager.ignoredFillTypes[fillType] = true
			end
		end
	end)

	self.staticPointList = self:getNewPointList()
end

function VictoryPointManager:saveToXMLFile(xmlFile, baseXmlKey)
	self.staticPointList:saveToXMLFile(xmlFile, baseXmlKey .. ".VictoryPoints", 0)
	xmlFile:setValue(baseXmlKey .. ".VictoryPoints#goal", self.victoryGoal)

	-- Save additional points to xml file
	local idx = 0
	baseXmlKey = baseXmlKey .. ".AdditionalPoints"
	for farmId, points in pairs(self.additionalPoints) do
		xmlFile:setValue(string.format(baseXmlKey .. ".Farm(%d)#id", idx), farmId)

		local idx_point = 0
		for _, point in pairs(points) do
			local xmlKeyForFarm = string.format(baseXmlKey .. ".Farm(%d).Point(%d)", idx, idx_point)

			xmlFile:setValue(xmlKeyForFarm .. "#points", point.points)
			xmlFile:setValue(xmlKeyForFarm .. "#addedBy", point.addedBy)
			xmlFile:setValue(xmlKeyForFarm .. "#date", point.date)
			xmlFile:setValue(xmlKeyForFarm, point.reason)

			idx_point = idx_point + 1
		end
		idx = idx + 1
	end
end

function VictoryPointManager:loadFromXMLFile(xmlFile, baseXmlKey)
	ScoreBoardList.loadFromXMLFile(self, xmlFile, baseXmlKey .. ".VictoryPoints")
	self.victoryGoal = xmlFile:getValue(baseXmlKey .. ".VictoryPoints#goal", self.victoryGoal)

	-- Load additional points from xml file
	baseXmlKey = baseXmlKey .. ".AdditionalPoints.Farm"
	xmlFile:iterate(baseXmlKey, function (ix, key)
		local farmId = xmlFile:getValue(key .. "#id")

		xmlFile:iterate(key .. ".Point", function (idx, farmKey)
			local reason = xmlFile:getValue(farmKey)
			local points = xmlFile:getValue(farmKey .. "#points")
			local addedBy = xmlFile:getValue(farmKey .. "#addedBy")
			local date = xmlFile:getValue(farmKey .. "#date")

			self:addAdditionalPoint(farmId, CmUtil.packPointData(points, addedBy, date, reason))
		end)
	end)
end

function VictoryPointManager:writeStream(streamId, connection)
	CmUtil.debug("VictoryPointManager write stream.")
	self.staticPointList:writeStream(streamId)

	streamWriteInt32(streamId, self.victoryGoal)

	--tell client number of elements
	streamWriteInt32(streamId, #self.additionalPoints)
	for farmId, points in pairs(self.additionalPoints) do
		streamWriteInt32(streamId, #points)
		for _, point in pairs(points) do
			streamWriteInt8(streamId, farmId)
			streamWriteInt32(streamId, point.points)
			streamWriteString(streamId, point.addedBy)
			streamWriteString(streamId, point.date)
			streamWriteString(streamId, point.reason)
		end
	end
end

function VictoryPointManager:readStream(streamId, connection)
	CmUtil.debug("VictoryPointManager read stream.")
	self.staticPointList:readStream(streamId)

	self.victoryGoal = streamReadInt32(streamId)

	local numberOfFarms = streamReadInt32(streamId)
	for i = 1, numberOfFarms do
		local numberOfPoints = streamReadInt32(streamId)
		for j= 1, numberOfPoints do
			local farmId = streamReadInt8(streamId)
			local points = streamReadInt32(streamId)
			local addedBy = streamReadString(streamId)
			local date = streamReadString(streamId)
			local reason = streamReadString(streamId)

			local point = CmUtil.packPointData(points, addedBy, date, reason)
			g_victoryPointManager:addAdditionalPoint(farmId, point, true)
		end
	end
end

function VictoryPointManager:addFillTypeFactors(category, factorData, farmId)
	local maxFillLevel = g_ruleManager:getGeneralRuleValue("maxFillLevel")
	local fillLevels = VictoryPointsUtil.getStorageAmount(farmId, maxFillLevel)
	fillLevels = VictoryPointsUtil.getPalletAmount(farmId, maxFillLevel, fillLevels)
	VictoryPointsUtil.addFillTypeFactors(fillLevels, category, factorData)
end

function VictoryPointManager:addStorageFactors(category, factorData, farmId)
	local maxFillLevel = g_ruleManager:getGeneralRuleValue("maxFillLevel")
	local fillLevels = VictoryPointsUtil.getStorageAmount(farmId, maxFillLevel)
	VictoryPointsUtil.addFillTypeFactors(fillLevels, category, factorData)
end

function VictoryPointManager:addBaleFactors(category, factorData, farmId)
	local maxFillLevel = g_ruleManager:getGeneralRuleValue("maxFillLevel")
	local fillLevels = VictoryPointsUtil.getBaleAmount(farmId, maxFillLevel)
	VictoryPointsUtil.addFillTypeFactors(fillLevels, category, factorData)
end

function VictoryPointManager:addPalletFactors(category, factorData, farmId)
	local maxFillLevel = g_ruleManager:getGeneralRuleValue("maxFillLevel")
	local fillLevels = VictoryPointsUtil.getPalletAmount(farmId, maxFillLevel)
	VictoryPointsUtil.addFillTypeFactors(fillLevels, category, factorData)
end

function VictoryPointManager:addAnimalFactors(category, factorData, farmId)
	local maxNumberOfAnimals = g_ruleManager:getGeneralRuleValue("maxNumberOfAnimals")
	local numberOfAnimals = VictoryPointsUtil.getAnimalAmount(farmId, maxNumberOfAnimals)
	VictoryPointsUtil.addAnimalTypeFactors(numberOfAnimals, category, factorData)
end

function VictoryPointManager:addMoneyFactor(category, factorData, farmId)
	local farm = g_farmManager:getFarmById(farmId)
	local money = farm and farm.money - farm.loan or 0
	category:addElement(VictoryPoint.createFromXml(factorData, money))
end

function VictoryPointManager:addAreaFactor(category, factorData, farmId)
	local area = VictoryPointsUtil.getTotalArea(farmId)
	category:addElement(VictoryPoint.createFromXml(factorData, area))
end

function VictoryPointManager:addBuildingsFactor(category, factorData, farmId)
	local value = VictoryPointsUtil.getTotalBuildingSellValue(farmId)
	category:addElement(VictoryPoint.createFromXml(factorData, value))
end

function VictoryPointManager:addProductionsFactor(category, factorData, farmId)
	local maxFillLevel = g_ruleManager:getGeneralRuleValue("maxFillLevel")
	local value = VictoryPointsUtil.getTotalProductionValue(farmId, maxFillLevel)
	category:addElement(VictoryPoint.createFromXml(factorData, value))
end

function VictoryPointManager:addVehiclesFactor(category, factorData, farmId)
	local value = VictoryPointsUtil.getVehicleSellValue(farmId)
	category:addElement(VictoryPoint.createFromXml(factorData, value))
end

function VictoryPointManager:addDependentPoint(category, factorData, farmId, dependency)
	CmUtil.debug("Dependent: %s, points: %s", factorData.name, dependency:count() or 0)
	category:addElement(VictoryPoint.createFromXml(factorData, farmId ~= nil and dependency:count() or 0))
end

function VictoryPointManager:getNewPointList(farmId)
	local dependedPoints = {}
	local pointList = ScoreBoardList.new("victoryPoints", self.titles)
	for _, categoryData in ipairs(self.configData) do
		local category = ScoreBoardCategory.new(categoryData.name, categoryData.title)
		for pIx, pointData in ipairs(categoryData.elements) do
			if pointData.dependency == nil then
				if pointData.genericFunc == nil then
					category:addElement(VictoryPoint.createFromXml(pointData))
				else
					self[pointData.genericFunc](self, category, pointData, farmId)
				end
			else
				table.insert(dependedPoints, {
					data = pointData,
					cName = categoryData.name,
					pIx = pIx
				})
			end
		end
		pointList:addElement(category)
	end
	if self.staticPointList then
		pointList:applyValues(self.staticPointList)
		for i, point in ipairs(dependedPoints) do
			local category = pointList:getElementByName(point.cName)
			if point.data.genericFunc == nil then
				category:addElement(VictoryPoint.createFromXml(point.data), point.pIx)
			else
				local dependency = pointList:getElementByName(point.data.dependency)
				self[point.data.genericFunc](self, category, point.data, farmId, dependency)
			end
		end
	end
	return pointList
end

function VictoryPointManager:calculatePoints(farmId)
	self.pointList[farmId] = self:getNewPointList(farmId)
	self.totalPoints[farmId] = self.pointList[farmId]:count() + self:sumAdditionalPoints(farmId)
end

function VictoryPointManager:sumAdditionalPoints(farmId)
	local sumPoints = 0

	if self.additionalPoints[farmId] ~= nil then
		for _, point in pairs(self.additionalPoints[farmId]) do
			sumPoints = sumPoints + point.points
		end
	end

	return sumPoints
end

function VictoryPointManager:update()
	self.pointList = {}
	self.totalPoints = {}
	local farms = g_farmManager:getFarms()
	for _, farm in pairs(farms) do
		local farmId = farm.farmId
		if CmUtil.isValidFarm(farmId, farm) then
			CmUtil.debug("Calculating points for farm id: %d", farmId)
			self:calculatePoints(farmId)
		end
	end
end

function VictoryPointManager:getList(farmId)
	return farmId ~= nil and self.pointList[farmId] or self.staticPointList
end

function VictoryPointManager:getListByName()
	return self.staticPointList
end

function VictoryPointManager:getTotalPoints(farmId)
	return self.totalPoints[farmId]
end

function VictoryPointManager:getAdditionalPointsForFarm(farmId)
	return self.additionalPoints[farmId]
end

function VictoryPointManager:isVictoryGoalReached(farmId)
	return self.totalPoints[farmId] > self.victoryGoal
end

function VictoryPointManager:getGoal()
	return self.victoryGoal
end

function VictoryPointManager:setGoal(newGoal, noEventSend)
	self.victoryGoal = tonumber(newGoal)
	CmUtil.debug("Set goal to %s", self.victoryGoal)
	if noEventSend == nil or noEventSend == false then
		ChangeGoalEvent.sendEvent(self.victoryGoal)
	end
end

function VictoryPointManager:addAdditionalPoint(farmId, point, noEvent)
	if self.additionalPoints[farmId] == nil then
		self.additionalPoints[farmId] = {}
	end

	table.insert(self.additionalPoints[farmId], 1, point)
	if noEvent == nil or noEvent == false then
		AddPointsEvent.sendEvent(farmId, point)
	end
end

g_victoryPointManager = VictoryPointManager.new()
