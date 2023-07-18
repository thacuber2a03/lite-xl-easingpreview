-- mod-version:3 -- lite-xl 2.1

-- Easing Previewer by @thacuber2a03
-- currently only works in lua

-- requires

local core = require 'core'
local config = require 'core.config'
local Object = require 'core.object'
local common = require 'core.common'
local command = require 'core.command'
local keymap = require 'core.keymap'
local style = require 'core.style'
local DocView = require 'core.docview'

-- I just have it here because I need to check something
local CommandView = require 'core.commandview'

-- config

config.plugins.easing_previewer = common.merge({
	displayWidth = 150,
	displayHeight = 100,

	arrowWidth = 0.2,
	arrowHeight = 0.2,

	pointSize = 5,
	steps = 100,
	padding = 10,

	config_spec = {
		name = "Easing Previewer",
		{
			label = "Width",
			description = "Width of the easing display in pixels.",
			path = "displayWidth",
			type = "number",
			default = 150,
			min = 100,
			max = 300,
		},
		{
			label = "Height",
			description = "Height of the easing display in pixels.",
			path = "displayHeight",
			type = "number",
			default = 100,
			min = 100,
			max = 300,
		},
		{
			label = "Arrow width",
			description = "Normalized width of the frame's arrow.",
			path = "arrowWidth",
			type = "number",
			default = .2,
			min = 0,
			max = 1,
		},
		{
			label = "Arrow height",
			description = "Normalized height of the frame's arrow.",
			path = "arrowHeight",
			type = "number",
			default = .2,
			min = 0,
			max = 1,
		},
		{
			label = "Point size",
			description = "Size of the points in the easing display.",
			path = "pointSize",
			type = "number",
			default = 4,
			min = 2,
			max = 5,
		},
		{
			label = "Step size",
			description = "Kinda like the resolution of the easing display.",
			path = "steps",
			type = "number",
			default = 100,
			min = 10,
			max = 1000,
		},
		{
			label = "Padding",
			description = "Padding of almost everything in this plugin.",
			path = "padding",
			type = "number",
			default = 10,
			min = 5,
			max = 20,
		}
	}
}, config.plugins.easing_previewer)

-- helpers

local function getEasingFunctionAtCaret()
	local doc = core.active_view.doc
	local caretY = doc:get_selection()
	local line = doc.lines[caretY]

	-- I want it to work for literally any programmer
	local easingFuncSignature = "function%s*[%w_]*%s*%(%s*t,%s*b%s*,%s*c%s*,%s*d%s*"

	-- find normal penner easing func
	local start = line:find(easingFuncSignature.."%)")
	-- find easing func with parameter s
	if not start then start = line:find(easingFuncSignature..",%s*s%s*%)") end
	-- find easing func with parameters a and p (amplitude and period)
	if not start then start = line:find(easingFuncSignature..",%s*a%s*,%s*a%s*%)") end

	local easingFunction
	if start then
		-- if it's a one-liner
		if line:find("end$") then return line, nil end
		easingFunction = "function(t, b, c, d)\n"
		local lineOffset = 1
		local endCount = 0
		local functionEnd = false
		while true do
			if not doc.lines[caretY+lineOffset] then
				return nil, {"Hit end of file before end of function."}
			end
			for _, _, text in doc.highlighter:each_token(caretY+lineOffset) do
				if text == "function" or text == "then" or text == "do" then
					endCount = endCount + 1
				end
				if text == "end" then endCount = endCount - 1 end
				if endCount < 0 then
					easingFunction = easingFunction .. "end"
					functionEnd = true
					break
				end
			end
			if functionEnd then break end
			local endLine = doc.lines[caretY+lineOffset]
			easingFunction = easingFunction .. endLine
			lineOffset = lineOffset + 1
		end
		return easingFunction, nil
	else
		return nil, {
			"Couldn't detect an easing function in this line.",
			"Make sure the caret is over the function signature, and that",
			"the function contains the parameters 't', 'b', 'c' and 'd', in that order.",
			"The function can also optionally contain either the parameter 's'",
			"or the parameters 'a' and 'p', but not both."
		}
	end
end

local function longestStringInTable(t)
	local tableCopy = {table.unpack(t)}
	table.sort(tableCopy, function(a,b) return #a > #b end)
	local str = tableCopy[1]
	tableCopy = nil
	collectgarbage()
	return str
end

-- EasingPreview

local EasingPreview = Object:extend()

function EasingPreview:new()
	self:reload()
	self:hide()
end

function EasingPreview:reload()
	self.isValidFunction = false
	self.errorMessage = {"Placeholder"}

	self.x = 0
	self.y = 0
	self.dispw = config.plugins.easing_previewer.displayWidth
	self.w = self.dispw

	self.padding = config.plugins.easing_previewer.padding
	self.steps = config.plugins.easing_previewer.steps
	self.sizeOfPoints = config.plugins.easing_previewer.pointSize

	self.h = 0
	self.hgoal = 0
	self.disph = config.plugins.easing_previewer.displayHeight

	self.arrowHeight = config.plugins.easing_previewer.arrowHeight
	self.arrowWidth  = config.plugins.easing_previewer.arrowWidth
end

function EasingPreview:invalidate(err)
	self.isValidFunction = false
	if err then self.errorMessage = err end
end

function EasingPreview:validate()
	local func, err = getEasingFunctionAtCaret()
	if not func then
		self:invalidate(err)
		return
	else
		self.isValidFunction = true
		local loadedFunc, loadErr = load("return "..func)
		if loadErr then
			self:invalidate { "There was an error loading this function:", loadErr, }
			return
		else
			loadedFunc = loadedFunc() -- get the actual easing function
			xpcall(function()
				if loadedFunc(0.5, 0, 1, 1) == nil then
					self:invalidate { "Uhhh, this function doesn't return anything...", }
					return
				end
				self.easingFunc = loadedFunc
			end, function(err)
				self:invalidate { "There was an error running this function:", err }
				return
			end)
		end
	end
end

function EasingPreview:show()
	self:reload()

	self.shown = true
	self.oldCaretX, self.oldCaretY = core.active_view.doc:get_selection()

	self:validate()

	if not self.isValidFunction then
		local biggestWidth = style.font:get_width(longestStringInTable(self.errorMessage))
		self.w = biggestWidth + self.padding*2
		self.hgoal = #self.errorMessage*style.font:get_height() + self.padding * 2
		self.arrowWidth = (biggestWidth/self.w)/10
		self.arrowHeight = 0.25
	else
		self.w = self.dispw
		self.hgoal = self.disph
		self.arrowWidth  = .2
		self.arrowHeight = .2
	end
end

function EasingPreview:hide()
	self.shown = false
	self.hgoal = 0
end

function EasingPreview:shiftHeightTowards(h)
	if math.abs(h-self.h) < 0.1 then self.h = h end
	self.h = self.h + (self.hgoal - self.h) * .125
	if self.h ~= self.hgoal then core.redraw = true end
end

function EasingPreview:update()
	self:shiftHeightTowards(self.hgoal)
	local isDocView = core.active_view:is(DocView)
	if not isDocView or not self.shown then self:hide() end

	if self.shown or isDocView then
		local caretX, caretY = core.active_view.doc:get_selection()
		if self.oldCaretX ~= caretX or self.oldCaretY ~= caretY then self:hide() end
		self.oldCaretX = caretX self.oldCaretY = caretY

		if self.hgoal ~= 0 then
			self.x, self.y = core.active_view:get_line_screen_position(caretX, caretY)
		end
	end
end

function EasingPreview:draw()
	local view = core.active_view
	local arrowWidth = self.arrowWidth*self.w
	local arrowHeight = self.arrowHeight*self.h

	local xpos = math.max(view.position.x+self.padding*2, self.x-self.w/2)
	local ypos = self.y-self.h-arrowHeight

	local flipArrow = false
	if ypos < view.position.y+self.padding then
		flipArrow = true
		ypos = self.y+arrowHeight*2
	end

	local frameColor = style.background3

	-- draw arrow
	for i = 1, arrowHeight do
		local t = i/arrowHeight
		local drawWidth = common.lerp(0, arrowWidth, t)
		local arrowY = self.y-common.lerp(0, arrowHeight, t)
		if flipArrow then arrowY = self.y+arrowHeight+common.lerp(0, arrowHeight, t) end
		renderer.draw_rect(
			(self.x)-drawWidth/2, arrowY,
			drawWidth, 1, frameColor
		)
	end

	core.push_clip_rect(xpos, ypos, self.w, self.h)

	-- draw widget
	renderer.draw_rect(xpos, ypos, self.w, self.h, style.background)

	if self.isValidFunction then
		renderer.draw_rect(xpos+self.padding, ypos, 2, self.h, style.text)
		renderer.draw_rect(xpos, ypos+self.padding, self.w, 2, style.text)
		renderer.draw_rect(xpos+self.w-self.padding, ypos, 2, self.h, style.text)
		renderer.draw_rect(xpos, ypos+self.h-self.padding, self.w, 2, style.text)

		local s = self.sizeOfPoints/2
		for i=0, self.steps do
			local t = i/self.steps
			local easeY = self.easingFunc(i, 0, 1, self.steps)
			renderer.draw_rect(
				common.lerp(xpos+self.padding-s, xpos+self.w-self.padding, t),
				common.lerp(ypos+self.h-self.padding-s, ypos+self.padding-s, easeY),
				self.sizeOfPoints, self.sizeOfPoints, style.caret
			)
		end
	else
		local totalHeight = #self.errorMessage*style.font:get_height()
		for i,message in ipairs(self.errorMessage) do
			renderer.draw_text(
				style.font, message,
				xpos+self.w/2-style.font:get_width(message)/2,
				ypos+self.h/2-totalHeight/2+(i-1)*style.font:get_height(),
				style.text
			)
		end
	end

	-- draw frame
	renderer.draw_rect(xpos, ypos, self.w, 2, frameColor)
	renderer.draw_rect(xpos+self.w-2, ypos, 2, self.h, frameColor)
	renderer.draw_rect(xpos, ypos+self.h-2, self.w, 2, frameColor)
	renderer.draw_rect(xpos, ypos, 2, self.h, frameColor)

	core.pop_clip_rect(xpos, ypos, self.w, self.h)
end

-- code injection

local instance = EasingPreview()

local dv_update = DocView.update
function DocView:update(...)
	dv_update(self, ...)
	if instance.h ~= 0 or instance.shown then
		instance:update()
	end
end

local dv_draw = DocView.draw
function DocView:draw(...)
	dv_draw(self, ...)
	if instance.h ~= 0 then
		instance:draw()
	end
end

-- settings

command.add(nil, {
	["easing-preview:show"] = function()
		local view = core.active_view
		if view:is(DocView) then instance:show() end
	end,
	-- if you for some reason feel like hiding it manually
	["easing-preview:hide"] = function() instance:hide() end
})

keymap.add {
	["ctrl+shift+e"] = "easing-preview:show",
	["ctrl+alt+e"]   = "easing-preview:hide",
}

return EasingPreview
