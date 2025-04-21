local LOGS_FOLDER = '/LOGS'
local deleteCommand = false
local isDeleting = false

local function init()
end

local function drawHeader()
    lcd.drawText(1, 0, "Purge Log Files                            ", INVERS)
end

local function purgeLogFiles()
    for f in dir(LOGS_FOLDER) do
        del(LOGS_FOLDER .. '/' .. f)
    end
end

local function run(event)
    if isDeleting then
        purgeLogFiles()
        return 1
    elseif deleteCommand then
        lcd.clear()
        drawHeader()
        lcd.drawText(1, 25, "Please wait...")
        isDeleting = true
    else
        lcd.clear()
        drawHeader()
        lcd.drawText(1, 25, "Long press [ENTER] to")
        lcd.drawText(1, 35, "delete all log files")

        if event == EVT_ROT_LONG then
            deleteCommand = true;
        end
    end

    return 0
end

return {
    init = init,
    run = run
}
