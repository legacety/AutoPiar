local ffi = require('ffi')
local imgui = require('mimgui')
local encoding = require('encoding')
local sampev = require('lib.samp.events')
local fa = require 'fAwesome6_solid'

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local newMessage = imgui.new.char[256]('')
local renderWindow = imgui.new.bool(false)
local status = imgui.new.bool(false)
local tab = 1 
local editingIndex = nil
local radio = false  
local advr = false

local selectedRadio = imgui.new.int(0)
local selectedType = imgui.new.int(0)

local AdCenter = {u8'Автоматически', u8'г. Лос-Сантос (LS)', u8'г. Сан-Фиерро (SF)', u8'г. Лас-Вентурас (LV)'}
local AdTypes = {u8'Обычное объявление', u8'VIP объявление'}
local combo_stations = imgui.new["const char*"][#AdCenter](AdCenter)
local combo_adtypes = imgui.new["const char*"][#AdTypes](AdTypes)

local chatTypes = {
    { id = '',    name = 'Обычный чат',    enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 1 },
    { id = 's',   name = 'Крик (/s)',      enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 1 },
    { id = 'vr',  name = 'VIP чат (/vr)',  enabled = false, delay = 60, messages = {}, lastMessageTime = 0, messageIndex = 1 },
    { id = 'b',   name = 'Нрп чат (/b)',   enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 1 },
    { id = 'ad',  name = 'Радиостанции (/ad)',    enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 1 },
}

function sms(text)
    sampAddChatMessage("{C285FF}[AutoPiar v4]{FFFFFF} " .. text, -1)
end

local function parseLastEdit(line)
    if not line or line == "" then return nil end
    line = line:gsub("{%x+}", "")
    local lastPart = line:match("%)%s+(.-)$") or line:match("%s%s+([^%$]+)$") or ""
    if lastPart == "" or lastPart:find("Нет") then return nil end

    local total, found = 0, false
    local hours = lastPart:match("(%d+)%s*ч")
    local minutes = lastPart:match("(%d+)%s*мин")
    local seconds = lastPart:match("(%d+)%s*сек")

    if hours then total = total + tonumber(hours) * 3600; found = true end
    if minutes then total = total + tonumber(minutes) * 60; found = true end
    if seconds then total = total + tonumber(seconds); found = true end
    return found and total or nil
end

local function applyTheme()
    local style = imgui.GetStyle()
    local clr = style.Colors
    
    style.WindowRounding = 0
    style.ChildRounding = 4
    style.FrameRounding = 4
    style.ItemSpacing = imgui.ImVec2(10, 12)
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)

    clr[imgui.Col.Text] = imgui.ImVec4(0.85, 0.86, 0.88, 1)
    clr[imgui.Col.WindowBg] = imgui.ImVec4(0.06, 0.08, 0.10, 1)
    clr[imgui.Col.ChildBg] = imgui.ImVec4(0.07, 0.09, 0.11, 1)
    clr[imgui.Col.TitleBg] = imgui.ImVec4(0.06, 0.08, 0.10, 1)
    clr[imgui.Col.TitleBgActive] = imgui.ImVec4(0.06, 0.08, 0.10, 1)
    clr[imgui.Col.Button] = imgui.ImVec4(0.12, 0.16, 0.20, 1)
    clr[imgui.Col.ButtonHovered] = imgui.ImVec4(0.18, 0.22, 0.26, 1)
    clr[imgui.Col.ButtonActive] = imgui.ImVec4(0.18, 0.22, 0.26, 1)
    clr[imgui.Col.FrameBg] = imgui.ImVec4(0.10, 0.14, 0.18, 1)
    clr[imgui.Col.Separator] = imgui.ImVec4(0.15, 0.18, 0.21, 1)
    clr[imgui.Col.CheckMark] = imgui.ImVec4(0.25, 0.85, 0.25, 1.0)
end

function imgui.ButtonActivated(active, ...)
    if active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.25, 0.30, 1))
        local result = imgui.Button(...)
        imgui.PopStyleColor()
        return result
    end
    return imgui.Button(...)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    applyTheme()
    fa.Init(14)
end)

function main()
    while not isSampAvailable() do wait(100) end
    sms("Скрипт загружен. Активация: {C285FF}/ap")
    sampRegisterChatCommand('ap', function() renderWindow[0] = not renderWindow[0] end)

    lua_thread.create(function()
        while true do
            if status[0] then
                local currentTime = os.time()
                for _, chat in ipairs(chatTypes) do
                    if chat.enabled and #chat.messages > 0 and (currentTime - chat.lastMessageTime) >= chat.delay then
                        local message = chat.messages[chat.messageIndex]
                        if message and message.enabled then
                            if chat.id == 'ad' then radio = true end
                            if chat.id == 'vr' then advr = true end                           
                            sampSendChat((chat.id ~= '' and '/'..chat.id..' ' or '') .. message.text)
                            chat.lastMessageTime = currentTime
                        end
                        chat.messageIndex = (chat.messageIndex % #chat.messages) + 1
                    end
                end
            end
            wait(1000)
        end
    end)
end

imgui.OnFrame(function() return renderWindow[0] end, function()
    local resX, resY = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(resX/2, resY/2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(635, 510), imgui.Cond.FirstUseEver)

    if imgui.Begin('AutoPiar v4', renderWindow, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse) then
        imgui.BeginChild('left', imgui.ImVec2(160, -40), true)
        for i, chat in ipairs(chatTypes) do
            if imgui.ButtonActivated(tab == i, u8(chat.name), imgui.ImVec2(-1, 30)) then tab = i; editingIndex = nil end
        end
        imgui.EndChild()
        imgui.SameLine()

        imgui.BeginChild('pravo', imgui.ImVec2(0, -40), true)
        local current = chatTypes[tab]
        imgui.Text(u8('Настройки: ' .. current.name))
        imgui.Separator()

        local check_chat = imgui.new.bool(current.enabled)
        if imgui.Checkbox(u8('Включить авто-отправку для ' .. current.name), check_chat) then current.enabled = check_chat[0] end
        
        imgui.PushItemWidth(120)
        local delay_buf = imgui.new.int(current.delay)
        if imgui.InputInt(u8'Задержка (сек)', delay_buf) then current.delay = math.max(1, delay_buf[0]) end
        imgui.PopItemWidth()

        if current.id == 'ad' then
            imgui.Separator()
            imgui.Text(u8'Настройки Радио:')
            imgui.PushItemWidth((imgui.GetContentRegionAvail().x - imgui.GetStyle().ItemSpacing.x) / 2)    
            imgui.Combo(u8'##Станция', selectedRadio, combo_stations, #AdCenter)
            imgui.SameLine()
            imgui.Combo(u8'##ТипОбъявления', selectedType, combo_adtypes, #AdTypes)
            imgui.PopItemWidth()
        end

        imgui.Separator()
        imgui.Text(u8'Список сообщений:')
        if imgui.BeginChild('##messages_list'..current.id, imgui.ImVec2(-1, 195), true) then
            for i = #current.messages, 1, -1 do
                local message = current.messages[i]
                imgui.PushStyleColor(imgui.Col.Text, message.enabled and imgui.ImVec4(0.25, 0.85, 0.25, 1.0) or imgui.ImVec4(0.90, 0.25, 0.25, 1.0))
                if imgui.Button((message.enabled and fa.TOGGLE_ON or fa.TOGGLE_OFF) .. '##tgl' .. i, imgui.ImVec2(35, 25)) then message.enabled = not message.enabled end
                imgui.PopStyleColor()
                imgui.SameLine()
                if imgui.Button(fa.PEN_TO_SQUARE .. '##edit' .. i, imgui.ImVec2(30, 25)) then ffi.copy(newMessage, u8(message.text)); editingIndex = i end
                imgui.SameLine()
                if imgui.Button(u8(message.text) .. '##msg' .. i, imgui.ImVec2(imgui.GetContentRegionAvail().x - 38, 25)) then ffi.copy(newMessage, u8(message.text)) end
                imgui.SameLine()
                if imgui.Button(fa.TRASH_CAN .. '##del' .. i, imgui.ImVec2(30, 25)) then table.remove(current.messages, i); if editingIndex == i then editingIndex = nil end end
            end
            imgui.EndChild()
        end
        imgui.PushItemWidth(-1)
        imgui.InputTextWithHint('##new_msg_input', u8'Текст сообщения...', newMessage, 256)
        if imgui.Button(editingIndex and u8'Сохранить изменения' or u8'Добавить в список', imgui.ImVec2(-1, 30)) then
            local text = u8:decode(ffi.string(newMessage))   
            if text:len() > 0 then
                if editingIndex then current.messages[editingIndex].text = text; editingIndex = nil
                else table.insert(current.messages, {text = text, enabled = true}) end
                ffi.fill(newMessage, ffi.sizeof(newMessage), 0)
            end
        end
        imgui.PopItemWidth()
        imgui.EndChild()

        imgui.Separator()
        imgui.Checkbox(u8(status[0] and 'Скрипт активирон' or 'Скрипт деактивирован'), status)
        imgui.End()
    end
end)

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if advr and (text:find('рекламного сообщения') or title:find('VIP')) then
        sampSendDialogResponse(id, 1, 0, '')
        advr = false
        return false
    end

    if radio then
        if title:find("Выберите радиостанцию") then
            local responseIndex = 0
            local stationNames = {[0] = "Los Santos", [1] = "Las Venturas", [2] = "San Fierro"}
            
            if selectedRadio[0] == 0 then 
                local stations = {}
                for line in text:gmatch("[^\r\n]+") do
                    local cleanLine = line:gsub("{%x+}", "")
                    if cleanLine:find("Los Santos") then stations[0] = parseLastEdit(line)
                    elseif cleanLine:find("Las Venturas") then stations[1] = parseLastEdit(line)
                    elseif cleanLine:find("San Fierro") then stations[2] = parseLastEdit(line) end
                end
                
                local minTime = nil
                local bestIdx = 2 
                for i = 0, 2 do
                    if stations[i] then
                        if not minTime or stations[i] < minTime then
                            minTime = stations[i]
                            bestIdx = i
                        end
                    end
                end
                responseIndex = bestIdx
                sms(("{FFFFFF}Автовыбор станции: {C285FF}%s"):format(stationNames[responseIndex]))
            else
                local manualMap = {[1] = 0, [2] = 2, [3] = 1}
                responseIndex = manualMap[selectedRadio[0]] or 0
            end
            sampSendDialogResponse(id, 1, responseIndex, "")
            return false
        end

        if text:find("Обычное объявление") or text:find("VIP объявление") then
            local typesMap = {[0]="обычное", [1]="vip"}
            local target = typesMap[selectedType[0]]
            
            local items = {}
            local count = 0
            for line in text:gmatch("[^\r\n]+") do
                local clean = line:gsub("{%x+}", ""):lower()
                if clean:find("объявление") then
                    items[count] = clean
                    count = count + 1
                end
            end

            local responseIndex = 0
            for i = 0, count - 1 do
                if items[i]:find(target) then responseIndex = i; break end
            end
            sampSendDialogResponse(id, 1, responseIndex, "")
            return false
        end

        if title:find("Подтверждение") or title:find("Подача") or text:find("Содержание:") then
            sampSendDialogResponse(id, 1, 0, "")
            sms("{FFFFFF}Объявление {C285FF}успешно{FFFFFF} отправлено!")
            radio = false
            return false
        end
    end
end