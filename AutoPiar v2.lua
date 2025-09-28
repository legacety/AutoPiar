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
    local filePath = getWorkingDirectory()..'\\config\\autopiar.json'
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
    { id = '',  name = 'Обычный чат',      maxLength = 128 },
    { id = 's', name = 'Крик (/s)',         maxLength = 128 },
    { id = 'vr',name = 'VIP чат (/vr)',     maxLength = 128 },
    { id = 'b', name = 'Нрп чат (/b)',      maxLength = 128 },
}

local function makeDefaultADV()
    return {
        [''] = { enabled = false, delay = 30, messages = {}, lastMessageTime = 0 },
        s     = { enabled = false, delay = 30, messages = {}, lastMessageTime = 0 },
        vr    = { enabled = false, delay = 180, messages = {}, lastMessageTime = 0 },
        b     = { enabled = false, delay = 30, messages = {}, lastMessageTime = 0 },
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
local selectedIndex = {}
local focusMode = imgui.new.bool(false)

local digitMap = {
    ["0"] = ":na:",
    ["1"] = ":nb:",
    ["2"] = ":nc:",
    ["3"] = ":nd:",
    ["4"] = ":ne:",
    ["5"] = ":nf:",
    ["6"] = ":ng:",
    ["7"] = ":nh:",
    ["8"] = ":ni:",
    ["9"] = ":nj:",
}

local function formatMessage(msg)
    if type(msg) ~= "string" then
        return ""
    end

    local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if result and myId then
        local idStr = tostring(myId):gsub(".", function(d)
            return digitMap[d] or d
        end)
        msg = msg:gsub("{id}", idStr)
    else
        msg = msg:gsub("{id}", "")
        sampAddChatMessage("{C285FF}[Auto-Piar]{FFFFFF} Не удалось определить ID игрока (PLAYER_PED).", -1)
    end
    return msg
end

local function drawChatSettings(chat, adv)
    imgui.Text(u8'Настройки для: ' .. u8(chat.name))
    imgui.Separator()

    local enabled = imgui.new.bool(adv.enabled)
    if imgui.Checkbox(u8'Включить##'..chat.id, enabled) then
        adv.enabled = enabled[0]
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
        selectedIndex[chat.id] = selectedIndex[chat.id] or 0

        for i = 1, #adv.messages do
            local msg = adv.messages[i]
            if type(msg) == "string" then
                local isSelected = imgui.new.bool(i == selectedIndex[chat.id])
                if imgui.Checkbox('##select'..chat.id..i, isSelected) then
                    if selectedIndex[chat.id] == 0 then
                        selectedIndex[chat.id] = i
                    elseif selectedIndex[chat.id] == i then
                        selectedIndex[chat.id] = 0
                    else
                        adv.messages[i], adv.messages[selectedIndex[chat.id]] = adv.messages[selectedIndex[chat.id]], adv.messages[i]
                        selectedIndex[chat.id] = 0
                        json():Save(settings)
                    end
                end
                imgui.SameLine()

                if editingIndex[chat.id] == i then
                    editingBuffer[chat.id] = editingBuffer[chat.id] or imgui.new.char[256](u8(msg))
                    imgui.PushItemWidth(-1)
                    if imgui.InputText('##edit'..chat.id..i, editingBuffer[chat.id], 256, imgui.InputTextFlags.EnterReturnsTrue) then
                        local newMsg = u8:decode(ffi.string(editingBuffer[chat.id]))
                        if #newMsg > 0 and #newMsg <= chat.maxLength then
                            adv.messages[i] = newMsg
                            json():Save(settings)
                        end
                        editingIndex[chat.id] = 0
                    end
                    imgui.PopItemWidth()
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
                        if selectedIndex[chat.id] >= i then selectedIndex[chat.id] = 0 end
                        break
                    end
                    imgui.EndGroup()
                end
            end
        end
        imgui.EndChild()
    end

    local function addMessage()
        local msg = u8:decode(ffi.string(newMessage))
        if #msg > 0 and #msg <= chat.maxLength then
            table.insert(adv.messages, msg)
            json():Save(settings)
            ffi.copy(newMessage, '')
        end
    end

    imgui.PushItemWidth(-1)
    local entered = imgui.InputTextWithHint('##newMsg'..chat.id, u8'Введите сообщение...', newMessage, 256, imgui.InputTextFlags.EnterReturnsTrue)
    if entered then addMessage() end
    if imgui.Button(u8'Добавить##'..chat.id, imgui.ImVec2(-1, 25)) then addMessage() end
    imgui.PopItemWidth()
end

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
            imgui.Separator()
            if not showMenu[0] then menu.switch() showMenu[0] = true end

            local chat = chatTypes[1]
            for _, c in ipairs(chatTypes) do if c.id == selectedChat then chat = c end end
            local adv = settings.configs[settings.main.activeConf].adv[chat.id]

            if focusMode[0] then
                if imgui.Button(u8'< Назад к спискам', imgui.ImVec2(-1, 30)) then focusMode[0] = false end
                imgui.Separator()
                drawChatSettings(chat, adv)
            else
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

                imgui.SameLine()

                imgui.BeginChild('::chatSelectChild', imgui.ImVec2(150, -65), true)
                for _, c in ipairs(chatTypes) do
                    if imgui.ButtonActivated(selectedChat == c.id, u8(c.name), imgui.ImVec2(-1, 20)) then
                        if selectedChat == c.id then
                            focusMode[0] = true
                        else
                            selectedChat = c.id
                            focusMode[0] = false
                        end
                    end
                end
                imgui.EndChild()

                imgui.SameLine()

                imgui.BeginChild('::mainChild', imgui.ImVec2(0, -65), true)
                drawChatSettings(chat, adv)
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
                        for _, c in ipairs(chatTypes) do
                            conf.adv[c.id].lastMessageTime = 0
                        end
                    end
                    json():Save(settings)
                end
                imgui.SameLine()
                imgui.EndChild()
            end
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
                        local msg = formatMessage(adv.messages[i])
                        if msg ~= "" then
                            if chat.id == 'vr' then
                                adsend = true
                                sampSendChat('/vr ' .. msg)
                            else
                                sampSendChat((chat.id ~= '' and '/'..chat.id..' ' or '') .. msg)
                            end
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
        adsend = false
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
    local clr = style.Colors
    
    style.WindowRounding = 0
    style.ChildRounding = 0
    style.FrameRounding = 5
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    style.ItemSpacing = imgui.ImVec2(10, 10)
    
    clr[imgui.Col.Text] = imgui.ImVec4(0.85, 0.86, 0.88, 1)
    clr[imgui.Col.WindowBg] = imgui.ImVec4(0.05, 0.08, 0.10, 1)
    clr[imgui.Col.ChildBg] = clr[imgui.Col.WindowBg]
    clr[imgui.Col.Button] = imgui.ImVec4(0.10, 0.15, 0.18, 1)
    clr[imgui.Col.ButtonHovered] = imgui.ImVec4(0.15, 0.20, 0.23, 1)
    clr[imgui.Col.ButtonActive] = clr[imgui.Col.ButtonHovered]
    clr[imgui.Col.FrameBg] = clr[imgui.Col.Button]
    clr[imgui.Col.FrameBgHovered] = clr[imgui.Col.ButtonHovered]
    clr[imgui.Col.FrameBgActive] = clr[imgui.Col.ButtonHovered]
    clr[imgui.Col.TitleBg] = clr[imgui.Col.WindowBg]
    clr[imgui.Col.TitleBgActive] = clr[imgui.Col.WindowBg]
    clr[imgui.Col.TitleBgCollapsed] = clr[imgui.Col.WindowBg]

    clr[imgui.Col.MenuBarBg] = clr[imgui.Col.WindowBg]
end
