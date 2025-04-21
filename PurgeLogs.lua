local LOGS_FOLDER = '/LOGS'

local function init()
end

local function drawHeader()
    lcd.drawText(1, 0, "Purge Log Files                            ", INVERS)
end

local function purgeLogFiles()
    lcd.clear()
    drawHeader()
    lcd.drawText(1, 25, "Please wait...")

    for f in dir(LOGS_FOLDER) do
        del(LOGS_FOLDER .. '/' .. f)
    end
end

local function run(event)
    lcd.clear()
    drawHeader()
    lcd.drawText(1, 25, "Long press [ENTER] to")
    lcd.drawText(1, 35, "delete all log files")

    if event == EVT_ROT_LONG then
        purgeLogFiles()
        return 1
    end

    return 0
end

return {
    init = init,
    run = run
}
