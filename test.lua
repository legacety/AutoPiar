local ffi = require('ffi')
local imgui = require('mimgui')
local encoding = require('encoding')
local sampev = require('lib.samp.events')
local fa = require 'fAwesome6_solid'

encoding.default = 'CP1251'
u8 = encoding.UTF8

local adsend = false
local script_enabled = false
local newMessage = imgui.new.char[256]('')
local renderWindow = imgui.new.bool(false)
local tab = 1 

local chatTypes = {
    { id = '',    name = 'Îáû÷íûé ÷àò',    maxLength = 128, enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 0 },
    { id = 's',   name = 'Êğèê (/s)',      maxLength = 128, enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 0 },
    { id = 'vr',  name = 'VIP ÷àò (/vr)',  maxLength = 128, enabled = false, delay = 60, messages = {}, lastMessageTime = 0, messageIndex = 0 },
    { id = 'b',   name = 'Íğï ÷àò (/b)',   maxLength = 128, enabled = false, delay = 30, messages = {}, lastMessageTime = 0, messageIndex = 0 },
}

local function applyTheme()
    local style = imgui.GetStyle()
    local clr = style.Colors
    local bg = imgui.ImVec4(0.06, 0.08, 0.10, 1)
    local childBg = imgui.ImVec4(0.07, 0.09, 0.11, 1)
    local button = imgui.ImVec4(0.12, 0.16, 0.20, 1)
    local buttonHover = imgui.ImVec4(0.18, 0.22, 0.26, 1)
    local frame = imgui.ImVec4(0.10, 0.14, 0.18, 1)
    local text = imgui.ImVec4(0.85, 0.86, 0.88, 1)

    style.WindowRounding = 0
    style.ChildRounding = 4
    style.FrameRounding = 4
    style.ItemSpacing = imgui.ImVec2(10, 12)
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)

    clr[imgui.Col.Text] = text
    clr[imgui.Col.WindowBg] = bg
    clr[imgui.Col.ChildBg] = childBg
    clr[imgui.Col.TitleBg] = bg
    clr[imgui.Col.TitleBgActive] = bg
    clr[imgui.Col.Button] = button
    clr[imgui.Col.ButtonHovered] = buttonHover
    clr[imgui.Col.ButtonActive] = buttonHover
    clr[imgui.Col.FrameBg] = frame
    clr[imgui.Col.Separator] = imgui.ImVec4(0.15, 0.18, 0.21, 1)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    applyTheme()
    fa.Init(14)
end)

function main()
    while not isSampAvailable() do wait(100) end
    sampAddChatMessage("AutoPiar çàãğóæåí. Àêòèâàöèÿ - /ap", -1)   
    sampRegisterChatCommand('ap', function() 
        renderWindow[0] = not renderWindow[0]
    end)

    lua_thread.create(function()
        while true do
            if script_enabled then
                local currentTime = os.time()
                for _, chat in ipairs(chatTypes) do
                    if chat.enabled and #chat.messages > 0 and currentTime - chat.lastMessageTime >= chat.delay then
                        local message = chat.messages[chat.messageIndex + 1]
                        if message and message.enabled then
                            local prefix = chat.id ~= '' and '/' .. chat.id .. ' ' or ''
                            sampSendChat(prefix .. message.text)
                            chat.lastMessageTime = currentTime
                        end
                        chat.messageIndex = (chat.messageIndex + 1) % #chat.messages
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
        imgui.BeginChild('::left_panel', imgui.ImVec2(160, -45), true)
        for i, chat in ipairs(chatTypes) do
            if imgui.Button(u8(chat.name), imgui.ImVec2(-1, 30)) then
                tab = i
            end
        end
        imgui.EndChild()

        imgui.SameLine()

        imgui.BeginChild('::right_panel', imgui.ImVec2(0, -45), true)
        local current = chatTypes[tab]

        imgui.Text(u8('Íàñòğîéêè: ' .. current.name))
        imgui.Separator()

        local check_bool = imgui.new.bool(current.enabled)
        if imgui.Checkbox(u8'Âêëş÷èòü ğàññûëêó â ıòîò ÷àò##'..current.id, check_bool) then
            current.enabled = check_bool[0]
        end

        imgui.PushItemWidth(120)
        local delay_buf = imgui.new.int(current.delay)
        if imgui.InputInt(u8'Çàäåğæêà (ñåê)##'..current.id, delay_buf) then
            current.delay = math.max(1, delay_buf[0])
        end
        imgui.PopItemWidth()

        imgui.Text(u8'Ñïèñîê ñîîáùåíèé:')
        
        if imgui.BeginChild('##messages_list'..current.id, imgui.ImVec2(-1, 150), true) then
            for i = #current.messages, 1, -1 do
                local message = current.messages[i]
                
                imgui.PushStyleColor(imgui.Col.Text, message.enabled and imgui.ImVec4(0.25, 0.85, 0.25, 1.0) or imgui.ImVec4(0.90, 0.25, 0.25, 1.0))
                if imgui.Button((message.enabled and fa.TOGGLE_ON or fa.TOGGLE_OFF) .. '##tgl' .. current.id .. i, imgui.ImVec2(35, 25)) then 
                    message.enabled = not message.enabled 
                end
                imgui.PopStyleColor()
                imgui.SameLine()

                if imgui.Button(fa.PEN_TO_SQUARE .. '##edit' .. i, imgui.ImVec2(30, 25)) then
                    ffi.copy(newMessage, u8(message.text))
                end
                imgui.SameLine()

                if imgui.Button(u8(message.text) .. '##msg' .. i, imgui.ImVec2(imgui.GetContentRegionAvail().x - 38, 25)) then
                    ffi.copy(newMessage, u8(message.text))
                end
                imgui.SameLine()

                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.6, 0.2, 0.2, 0.6))
                if imgui.Button('X##del' .. i, imgui.ImVec2(30, 25)) then
                    table.remove(current.messages, i)
                end
                imgui.PopStyleColor()
            end
            imgui.EndChild()
        end

        imgui.PushItemWidth(-1)
        imgui.InputTextWithHint('##new_msg_input'..current.id, u8'Òåêñò ñîîáùåíèÿ...', newMessage, 256)
        if imgui.Button(u8'Äîáàâèòü â ñïèñîê', imgui.ImVec2(-1, 30)) then
            local str = u8:decode(ffi.string(newMessage))
            if #str > 0 and #str <= current.maxLength then
                table.insert(current.messages, {text = str, enabled = true})
                newMessage[0] = 0
            end
        end
        imgui.PopItemWidth()
        imgui.EndChild()

        local glob_sw = imgui.new.bool(script_enabled)
        if imgui.Checkbox(u8(script_enabled and 'ÑÊĞÈÏÒ ÂÊËŞ×ÅÍ' or 'ÑÊĞÈÏÒ ÂÛÊËŞ×ÅÍ'), glob_sw) then
            script_enabled = glob_sw[0]
            if script_enabled then
                for _, c in ipairs(chatTypes) do c.lastMessageTime = 0 end
            end
        end
        imgui.End()
    end
end)

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if adsend and text:find('ğåêëàìíîãî ñîîáùåíèÿ') then
        sampSendDialogResponse(id, 1, 0, '')
        adsend = false
        return false
    end
end