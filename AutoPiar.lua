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
local advr = false
local editingIndex = nil

local chatTypes = {
    { id = '',    name = 'Обычный чат',    maxLength = 128, enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 1 },
    { id = 's',   name = 'Крик (/s)',      maxLength = 128, enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 1 },
    { id = 'vr',  name = 'VIP чат (/vr)',  maxLength = 128, enabled = false, delay = 60, messages = {}, lastMessageTime = 0, messageIndex = 1 },
    { id = 'b',   name = 'Нрп чат (/b)',   maxLength = 128, enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 1 },
}

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
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    applyTheme()
    fa.Init(14)
end)

function main()
    while not isSampAvailable() do wait(100) end
    sampAddChatMessage("{C285FF}[Auto-Piar]{FFFFFF} загружен. Активация: {C285FF}/ap", -1)
    sampRegisterChatCommand('ap', function() 
        renderWindow[0] = not renderWindow[0]
    end)

    lua_thread.create(function()
        while true do
            if status[0] then
                local currentTime = os.time()
                for _, chat in ipairs(chatTypes) do
                    if chat.enabled and #chat.messages > 0 and currentTime - chat.lastMessageTime >= chat.delay then
                        local message = chat.messages[chat.messageIndex]
                        if message and message.enabled then
                            local prefix = chat.id ~= '' and '/' .. chat.id .. ' ' or ''
                            sampSendChat(prefix .. message.text)
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
    imgui.SetNextWindowSize(imgui.ImVec2(650, 420), imgui.Cond.FirstUseEver)

    if imgui.Begin('AutoPiar', renderWindow, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse) then
        imgui.BeginChild('left', imgui.ImVec2(160, -40), true)
        for i, chat in ipairs(chatTypes) do
            if imgui.ButtonActivated(tab == i, u8(chat.name), imgui.ImVec2(-1, 30)) then
                tab = i
            end
        end
        imgui.EndChild()

        imgui.SameLine()

        imgui.BeginChild('pravo', imgui.ImVec2(0, -40), true)
        local current = chatTypes[tab]

        imgui.Text(u8('Настройки: ' .. current.name))
        imgui.Separator()

        local check_chat = imgui.new.bool(current.enabled)
       if imgui.Checkbox(u8('Включить автоматический пиар для ' .. current.name), check_chat) then
            current.enabled = check_chat[0]
        end

        imgui.PushItemWidth(120)
        local delay_buf = imgui.new.int(current.delay)
        if imgui.InputInt(u8'Задержка (сек)##'..current.id, delay_buf) then
            current.delay = math.max(1, delay_buf[0])
        end
        imgui.PopItemWidth()
        imgui.Text(u8'Список сообщений:')
        
        if imgui.BeginChild('##messages_list'..current.id, imgui.ImVec2(-1, 150), true) then
            for i = #current.messages, 1, -1 do
                local message = current.messages[i]
                
                imgui.PushStyleColor(imgui.Col.Text, message.enabled and imgui.ImVec4(0.25, 0.85, 0.25, 1.0) or imgui.ImVec4(0.90, 0.25, 0.25, 1.0))
                if imgui.Button((message.enabled and fa.TOGGLE_ON or fa.TOGGLE_OFF) .. '##tgl' .. current.id .. i, imgui.ImVec2(35, 25)) then 
                    message.enabled = not message.enabled 
                end
                imgui.PopStyleColor()
                imgui.SameLine()

                if imgui.Button(fa.PEN_TO_SQUARE .. '##edit' .. current.id .. i, imgui.ImVec2(30, 25)) then
                    ffi.copy(newMessage, u8(message.text))
                    editingIndex = i
                end
                imgui.SameLine()

                if imgui.Button(u8(message.text) .. '##msg' .. i, imgui.ImVec2(imgui.GetContentRegionAvail().x - 38, 25)) then
                    ffi.copy(newMessage, u8(message.text))
                end
                imgui.SameLine()

                if imgui.Button(fa.TRASH_CAN .. '##del' .. current.id .. i, imgui.ImVec2(30, 25)) then
                    table.remove(current.messages, i)
                    if editingIndex == i then editingIndex = nil end
                end
            end
            imgui.EndChild()
        end

        imgui.PushItemWidth(-1)
        imgui.InputTextWithHint('##new_msg_input'..current.id, u8'Текст сообщения...', newMessage, 256)
        if imgui.Button(editingIndex and u8'Сохранить изменения' or u8'Добавить в список', imgui.ImVec2(-1, 30)) then
            local text = u8:decode(ffi.string(newMessage))   
            if editingIndex then
        current.messages[editingIndex].text = text
        editingIndex = nil
    else
        table.insert(current.messages, {text = text, enabled = true})
    end
    ffi.fill(newMessage, ffi.sizeof(newMessage), 0)
end

imgui.PopItemWidth()
imgui.EndChild()
        if imgui.Checkbox(u8(status[0] and 'СКРИПТ ВКЛЮЧЕН' or 'СКРИПТ ВЫКЛЮЧЕН'), status) then
            if status[0] then
                for _, c in ipairs(chatTypes) do c.lastMessageTime = 0 end
            end
        end
        imgui.End()
    end
end)

function imgui.ButtonActivated(active, ...)
    if active then
        local style = imgui.GetStyle()
        imgui.PushStyleColor(imgui.Col.Button, style.Colors[imgui.Col.Header])
        imgui.PushStyleColor(imgui.Col.ButtonHovered, style.Colors[imgui.Col.HeaderHovered])
        imgui.PushStyleColor(imgui.Col.ButtonActive, style.Colors[imgui.Col.HeaderActive])
        local result = imgui.Button(...)
        imgui.PopStyleColor(3)
        return result
    end
    return imgui.Button(...)
end

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if advr and text:find('рекламного сообщения') then
        sampSendDialogResponse(id, 1, 0, '')
        advr = false
        return false
    end
end