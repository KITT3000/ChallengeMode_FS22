VictoryPoint = {
	MONEY_TEXT =
		function (money)
			return string.format("%f/%s", g_i18n:getCurrency(money), g_i18n:getCurrencySymbol(true))
		end,
	AREA_TEXT =	function (area)
			return string.format("%f/%s", g_i18n:getArea(area), g_i18n:getAreaUnit())
		end,
	VOLUME_TEXT = function (liters)
			return string.format("%f/%s", g_i18n:getFluid(liters), g_i18n:getText("unit_literShort"))
		end
}
local VictoryPoint_mt = Class(VictoryPoint, ScoreBoardElement)
---@class VictoryPoint : ScoreBoardElement
function VictoryPoint.new(name, value, factor, title, unitTextFunc, dependency, custom_mt)
	local self = ScoreBoardElement.new(name, title, custom_mt or VictoryPoint_mt)
	self.value = value
	self.factor = factor
	self.title = title
	self.dependency = dependency
	self.unitTextFunc = unitTextFunc
	if unitTextFunc then
		self.factorText = self[unitTextFunc](factor)
	end
	return self
end

function VictoryPoint.createFromXml(data, value)
	return VictoryPoint.new(data.name, value, data.default, data.title, data.unitTextFunc, data.dependency)
end

function VictoryPoint:getValue()
	if self.value == nil then 
		CmUtil.debug("Victory point value is nil: %s", self.name)
		printCallstack()
	end
	return self.value * self.factor
end

function VictoryPoint:getFactor()
	return self.factor
end

function VictoryPoint:setFactor(newFactor)
	self.factor = newFactor	
end

function VictoryPoint:getText()
	if self.factor and math.abs(self.factor) > 0 then 
		return string.format("%.1f",self.value * self.factor)
	else 
		return ""
	end
end

function VictoryPoint:getTitle()
	return self.title
end

function VictoryPoint:getFactorText()
	if not self.dependency then
		if self.unitTextFunc then 
			return self[self.unitTextFunc](self.factor)
		else
			return self.factor
		end
	end
	return ""
end

function VictoryPoint:onTextInput(value)
	if not self.dependency then
		g_victoryPointManager:onTextInput(self, self.category, value)
	end
end

function VictoryPoint:isTextInputAllowed()
	return true
end

function VictoryPoint:clone(farmId, farm)
	
end

function VictoryPoint:__tostring()
	return string.format("title: %s, value*factor: %.1f", self.title, self.value * self.factor)
end

function VictoryPoint:saveToXMLFile(xmlFile, baseXmlKey)
	xmlFile:setValue(baseXmlKey .. "#name", self.name)
	xmlFile:setValue(baseXmlKey, self.factor)
end

function VictoryPoint:loadFromXMLFile(xmlFile, baseXmlKey)
	local value = xmlFile:getValue(baseXmlKey)
	if value ~= nil then 
		self.factor = value
	end
end

function VictoryPoint:applyValues(staticCategory)
	local element = staticCategory:getElementByName(self.name)
	if element then 
		self:setFactor(element:getFactor())
	end
end