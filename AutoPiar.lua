local ffi = require('ffi')
local imgui = require('mimgui')
local encoding = require('encoding')
local sampev = require('lib.samp.events')

encoding.default = 'CP1251'
u8 = encoding.UTF8

local adsend = false

local configName = imgui.new.char[32]('')
local newMessage = imgui.new.char[256]('')

function json()
    local filePath = getWorkingDirectory()..'\\config\\legacy.json'
    local class = {}
    if not doesDirectoryExist(getWorkingDirectory()..'\\config') then createDirectory(getWorkingDirectory()..'\\config') end
    function class:Save(tbl)
        local f = io.open(filePath, 'w')
        f:write(tbl and encodeJson(tbl) or '{}')
        f:close()
        return true
    end
    function class:Load(defaultTable)
        if not doesFileExist(filePath) then self:Save(defaultTable or {}) end
        local f = io.open(filePath, 'r')
        local content = f:read('*a')
        f:close()
        local t = decodeJson(content) or {}
        for k, v in pairs(defaultTable) do if t[k] == nil then t[k] = v end end
        self:Save(t)
        return t
    end
    return class
end

local chatTypes = {
    { id = '', name = 'Обычный чат', maxLength = 128 },
    { id = 's', name = 'Крик (/s)', maxLength = 128 },
    { id = 'vr', name = 'VIP чат (/vr)', maxLength = 128 },
    { id = 'b', name = 'Нрп чат (/b)', maxLength = 128 },
}

local function makeDefaultADV()
    return {
        [''] = { enabled = false, delay = 30, messages = {}, lastMessageTime = 0 },
        s = { enabled = false, delay = 30, messages = {}, lastMessageTime = 0 },
        vr = { enabled = false, delay = 30, messages = {}, lastMessageTime = 0 },
        b = { enabled = false, delay = 30, messages = {}, lastMessageTime = 0 },
    }
end

local settings = json():Load({
    main = { enabled = false, activeConf = 1 },
    configs = { { name = "Основной", adv = makeDefaultADV() } }
})

local menu = setmetatable({ state = false, duration = 0.5 }, {
    __index = function(self, v)
        if v == "switch" then
            return function()
                if self.process and self.process:status() ~= "dead" then return false end
                self.timer = os.clock()
                self.state = not self.state
                self.process = lua_thread.create(function()
                    while true do wait(0)
                        local t = os.clock() - self.timer
                        local a = math.min(t / self.duration, 1)
                        self.alpha = self.state and a or 1 - a
                        if a == 1 then break end
                    end
                end)
                return true
            end
        elseif v == "alpha" then
            return self.state and 1 or 0
        end
    end
})

local showMenu = imgui.new.bool(true)
local editingIndex = {}
local editingBuffer = {}

function main()
    while not isSampAvailable() do wait(100) end

    sampAddChatMessage("{C285FF}[Auto-Piar]{FFFFFF} загружен  |  Активация: {C285FF}/ap{FFFFFF}  |  Автор: {FFD700}legacy.", -1)
    sampRegisterChatCommand('ap', function() menu.switch() end)

    imgui.OnInitialize(function()
        imgui.GetIO().IniFilename = nil
        theme()
    end)

    local selectedChat = chatTypes[1].id

    imgui.OnFrame(function() return menu.alpha > 0 end, function(cls)
        local resX, resY = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(resX/2, resY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(800, 440), imgui.Cond.FirstUseEver)
        cls.HideCursor = not menu.state
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, menu.alpha)

        if imgui.Begin('legacy.', showMenu, imgui.WindowFlags.NoResize) then
            imgui.BeginChild('::configChild', imgui.ImVec2(-(resX / 3), -65), true)
            for i, config in ipairs(settings.configs) do
                if imgui.ButtonActivated(i == settings.main.activeConf, u8(config.name).."##"..i, imgui.ImVec2(-30, 20)) then
                    settings.main.activeConf = i
                    json():Save(settings)
                end
                if i > 1 then
                    imgui.SameLine()
                    if imgui.Button(u8'X##'..i, imgui.ImVec2(20, 20)) then
                        table.remove(settings.configs, i)
                        if settings.main.activeConf >= i then settings.main.activeConf = 1 end
                        json():Save(settings)
                    end
                end
            end
            imgui.EndChild()

            if not showMenu[0] then menu.switch() showMenu[0] = true end

            imgui.SameLine()

            imgui.BeginChild('::chatSelectChild', imgui.ImVec2(150, -65), true)
            for _, chat in ipairs(chatTypes) do
                if imgui.ButtonActivated(selectedChat == chat.id, u8(chat.name), imgui.ImVec2(-1, 20)) then
                    selectedChat = chat.id
                end
            end
            imgui.EndChild()

            imgui.SameLine()

            imgui.BeginChild('::mainChild', imgui.ImVec2(0, -65), true)
            local chat = chatTypes[1]
            for _, c in ipairs(chatTypes) do if c.id == selectedChat then chat = c end end
            local adv = settings.configs[settings.main.activeConf].adv[chat.id]

            imgui.Text(u8'Настройки для: ' .. u8(chat.name))
            imgui.Separator()

            if imgui.Checkbox(u8'Включить##'..chat.id, imgui.new.bool(adv.enabled)) then
                adv.enabled = not adv.enabled
                json():Save(settings)
            end

            imgui.PushItemWidth(100)
            local delay = imgui.new.int(adv.delay)
            if imgui.InputInt(u8'Задержка##'..chat.id, delay) then
                adv.delay = math.max(1, delay[0])
                json():Save(settings)
            end
            imgui.Tooltip(u8'Интервал между сообщениями (секунды)')
            imgui.PopItemWidth()

            if imgui.BeginChild('Messages##'..chat.id, imgui.ImVec2(-1, 150), true) then
                editingIndex[chat.id] = editingIndex[chat.id] or 0
                for i = #adv.messages, 1, -1 do
                    local msg = adv.messages[i]
                    if editingIndex[chat.id] == i then
                        editingBuffer[chat.id] = editingBuffer[chat.id] or imgui.new.char[256](u8(msg))
                        if imgui.InputText('##edit'..chat.id..i, editingBuffer[chat.id], 256, imgui.InputTextFlags.EnterReturnsTrue) then
                            local newMsg = u8:decode(ffi.string(editingBuffer[chat.id]))
                            if #newMsg > 0 and #newMsg <= chat.maxLength then
                                adv.messages[i] = newMsg
                                json():Save(settings)
                            end
                            editingIndex[chat.id] = 0
                        end
                    else
                        imgui.BeginGroup()
                        if imgui.Button(u8(msg)..'##msg'..i, imgui.ImVec2(-30, 20)) then
                            editingIndex[chat.id] = i
                            editingBuffer[chat.id] = imgui.new.char[256](u8(msg))
                        end
                        imgui.SameLine()
                        if imgui.Button(u8'X##del'..chat.id..i, imgui.ImVec2(20, 20)) then
                            table.remove(adv.messages, i)
                            json():Save(settings)
                            if editingIndex[chat.id] == i then editingIndex[chat.id] = 0 end
                        end
                        imgui.EndGroup()
                    end
                end
                imgui.EndChild()
            end

            imgui.PushItemWidth(-1)
            imgui.InputTextWithHint('##newMsg'..chat.id, u8'Введите сообщение...', newMessage, 256)
            if imgui.Button(u8'Добавить##'..chat.id, imgui.ImVec2(-1, 25)) then
                local msg = u8:decode(ffi.string(newMessage))
                if #msg > 0 and #msg <= chat.maxLength then
                    table.insert(adv.messages, msg)
                    json():Save(settings)
                end
            end
            imgui.PopItemWidth()
            imgui.EndChild()

            if imgui.Button(u8'Создать', imgui.ImVec2(-(resX / 3), -1)) then
                imgui.OpenPopup('##createConfigPopup')
            end

            imgui.SameLine()
            imgui.BeginChild('::settingsChild', imgui.ImVec2(0, -1), false)
            local enableCheckbox = imgui.new.bool(settings.main.enabled)
            if imgui.Checkbox(u8'Включить скрипт', enableCheckbox) then
                settings.main.enabled = enableCheckbox[0]
                for _, conf in ipairs(settings.configs) do
                    for _, chat in ipairs(chatTypes) do
                        conf.adv[chat.id].lastMessageTime = 0
                    end
                end
                json():Save(settings)
            end
            imgui.SameLine()
            imgui.EndChild()
        end

        if imgui.BeginPopupModal('##createConfigPopup', nil, imgui.WindowFlags.NoResize) then
            imgui.SetWindowSizeVec2(imgui.ImVec2(200, 140))
            imgui.PushItemWidth(-1)
            imgui.InputTextWithHint('##configName', u8'Название конфигурации', configName, 32)
            imgui.PopItemWidth()
            if imgui.Button(u8'Создать', imgui.ImVec2(-1, 25)) then
                local name = u8:decode(ffi.string(configName))
                if #name > 0 then
                    local newAdv = makeDefaultADV()
                    table.insert(settings.configs, { name = name, adv = newAdv })
                    json():Save(settings)
                    imgui.CloseCurrentPopup()
                end
            end
            imgui.Separator()
            if imgui.Button(u8'Закрыть', imgui.ImVec2(-1, 25)) then imgui.CloseCurrentPopup() end
            imgui.EndPopup()
        end

        imgui.PopStyleVar()
    end)

    lua_thread.create(function()
        while true do wait(100)
            if settings.main.enabled then
                for _, chat in ipairs(chatTypes) do
                    local adv = settings.configs[settings.main.activeConf].adv[chat.id]
                    if adv.enabled and #adv.messages > 0 and os.time() - adv.lastMessageTime >= adv.delay then
                        local i = (adv.messageIndex or 0) % #adv.messages + 1
                        local msg = adv.messages[i]
                        if chat.id == 'vr' then
                            adsend = true
                            sampSendChat('/vr ' .. msg)
                        else
                            sampSendChat((chat.id ~= '' and '/'..chat.id..' ' or '') .. msg)
                        end
                        adv.messageIndex = i
                        adv.lastMessageTime = os.time()
                        json():Save(settings)
                    end
                end
            end
        end
    end)
end

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if text:find('Стоимость рекламного сообщения:') and adsend then
        sampSendDialogResponse(id, 1, 0, '')
        adsend = false -- сбрасываем флаг после подтверждения
        return false
    end
end

function imgui.ButtonActivated(active, ...)
    if active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.GetStyle().Colors[imgui.Col.TextSelectedBg])
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.GetStyle().Colors[imgui.Col.TextSelectedBg])
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.GetStyle().Colors[imgui.Col.TextSelectedBg])
        local result = imgui.Button(...)
        imgui.PopStyleColor(3)
        return result
    end
    return imgui.Button(...)
end

function imgui.Tooltip(text)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip()
        imgui.Text(text)
        imgui.EndTooltip()
    end
end

function theme()
    local style = imgui.GetStyle()
    local clr, col = imgui.Col, style.Colors
    local vec4 = imgui.ImVec4
    style.WindowRounding = 4
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    style.ChildRounding = 2
    style.FrameRounding = 4
    style.ItemSpacing = imgui.ImVec2(10, 10)
    col[clr.Text] = vec4(0.95, 0.96, 0.98, 1)
    col[clr.TitleBgActive] = vec4(0.07, 0.11, 0.13, 1)
    col[clr.WindowBg] = vec4(0.07, 0.11, 0.13, 1)
    col[clr.ChildBg] = col[clr.WindowBg]
    col[clr.Button] = vec4(0.15, 0.20, 0.24, 1)
    col[clr.ButtonHovered] = vec4(0.20, 0.25, 0.29, 1)
    col[clr.ButtonActive] = col[clr.ButtonHovered]
    col[clr.FrameBg] = col[clr.Button]
    col[clr.FrameBgHovered] = col[clr.ButtonHovered]
    col[clr.FrameBgActive] = col[clr.ButtonHovered]
end