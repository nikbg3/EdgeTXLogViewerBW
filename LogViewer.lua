local BUFFER_SIZE = 1024 * 10
local LOGS_FOLDER = '/LOGS'
local REGEX_LINES = '([^\n]+)\n'
local REGEX_LINES_WITHOUT_NEW_LINE = '\n([^\n]*)$'
local REGEX_CSV_CELL = '[^,]+'
local REGEX_LOG_EXTENTION = '.csv$'
local REGEX_COLUMN_MU = '^(.-)%s*%((.-)%)$'
local REGEX_TIME = '[^,]+,[^,]+'
local TIME_STRING = '%02d/%02d,%02d:%02d:%02d'
local CHART_X_MIN = 0
local CHART_X_MAX = 128
local CHART_Y_MIN = 16
local CHART_Y_MAX = 55
local SLIDER_SIZE = 12
local CHART_LINE_SIZE_MIN = 3
local ChartLineSize = 3

local FirstRun = true
local CurrentMode = 2 -- 0: File; 1: Row, 2: Column
local IsShowingChart = false
local CurrentFileIndex = nil
local CurrentColumnIndex = nil
local NumberOfLogFiles = nil
local CurrentFileName = nil
local Columns = nil
local ColumnsMU = nil
local CurrentValue = nil
local CurrentLineText = ''
local NumberOfLines = nil
local CurrentLineIndex = nil
local SliderPosition = CHART_X_MAX - 1

local function getNumberOfLogFiles()
    local counter = 0
    for f in dir(LOGS_FOLDER) do
        if string.match(f, REGEX_LOG_EXTENTION) then
            counter = counter + 1
        end
    end
    return counter
end

local function getFileNameByIndex()
    local fileName = nil
    local i = 1
    for f in dir(LOGS_FOLDER) do
        if string.match(f, REGEX_LOG_EXTENTION) then
            fileName = f
            if i == CurrentFileIndex then
                return fileName
            end
            i = i + 1
        end
    end
    return nil
end

local function getFileTimeString()
    local info = fstat(LOGS_FOLDER .. '/' .. CurrentFileName)
    local t = info.time
    local result = string.format(TIME_STRING, t.mon, t.day, t.hour, t.min, t.sec)
    return result
end

local function getCurrentLineTimeString()
    -- Regex positive lookbehind is not supported in LUA. THerefore, did it like that
    for line in string.gmatch(CurrentLineText, REGEX_TIME) do
        local isFirst = false
        for columnText in string.gmatch(line, REGEX_CSV_CELL) do
        if isFirst then
            return columnText
        end
        isFirst = true
        end
    end
    return '????' -- No date time was matched
end

local function parseColumns()
    local f = io.open(LOGS_FOLDER .. '/' .. CurrentFileName)
    local buffer = io.read(f, BUFFER_SIZE)
    local columnString = nil

    for line in string.gmatch(buffer, REGEX_LINES) do
        columnString = line
        break
    end

    local columns = {}
    local columnsMU = {}
    local columnIndex = 0 -- Used to remove time
    for columnText in string.gmatch(columnString, REGEX_CSV_CELL) do
        if columnIndex < 2 then
            columnIndex = columnIndex + 1
        else
            local name, unit = string.match(columnText, REGEX_COLUMN_MU)
            if name ~= nil and unit ~= nil then
                columns[#columns + 1] = name
                columnsMU[#columnsMU + 1] = unit
            else
                columns[#columns + 1] = columnText
                columnsMU[#columnsMU + 1] = ''
            end
        end
    end

    io.close(f)

    return columns, columnsMU
end

local function getCurrentNumberOfLines()
    local numberOfLines = 0
    local f = io.open(LOGS_FOLDER .. '/' .. CurrentFileName)
    while true do
        local read = io.read(f, BUFFER_SIZE)
        if #read == 0 then
            io.close(f)
            break
        end

        for i = 1, #read do
            if string.sub(read, i, i) == "\n" then
                numberOfLines = numberOfLines + 1
            end
        end
    end
    return numberOfLines - 1 -- Remove the column name line
end

local function readCurrentLine()
    local result = ''
    local isFound = false
    local lineNumberIndex = 0
    local f = io.open(LOGS_FOLDER .. '/' .. CurrentFileName)
    local bufferFromPrevious = ''
    while not isFound do
        local read = bufferFromPrevious .. io.read(f, BUFFER_SIZE)

        for line in string.gmatch(read, REGEX_LINES) do
            if lineNumberIndex == CurrentLineIndex then
                result = line
                isFound = true
                io.close(f)
                break
            end

            lineNumberIndex = lineNumberIndex + 1
        end

        for m in string.gmatch(read, REGEX_LINES_WITHOUT_NEW_LINE) do
            bufferFromPrevious = m
        end
    end
    return result
end

local function getValueByLine(line)
    local value = nil
    local i = -1 -- Substract to ignore the date and time columns
    for valueText in string.gmatch(line, REGEX_CSV_CELL) do
        if i == CurrentColumnIndex then
            value = valueText
            break
        end
        i = i + 1
    end

    return value
end

local function getCurrentValue()
    return getValueByLine(CurrentLineText)
end

local function getAllCurrentValues() -- returns nil if non convertable to a number
    local values = {}
    local f = io.open(LOGS_FOLDER .. '/' .. CurrentFileName)
    local bufferFromPrevious = ''
    local isColumnRow = true

    while true do
        local read = bufferFromPrevious .. io.read(f, BUFFER_SIZE)
        if #read == 0 then
            io.close(f)
            break
        end

        for line in string.gmatch(read, REGEX_LINES) do
            if isColumnRow then
                isColumnRow = false
            else
                local value = tonumber(getValueByLine(line))
                if value == nil then -- Not convertable to a number
                    return nil
                end

                values[#values + 1] = value
            end
        end

        for m in string.gmatch(read, REGEX_LINES_WITHOUT_NEW_LINE) do
            bufferFromPrevious = m
        end
    end

    return values
end

local function findMinMaxHelper(array, startI, endI)
    if startI < 1 then
        startI = 1
    end

    local min = array[startI]
    local max = array[startI]

    for i = startI + 1, endI do
        if array[i] < min then
            min = array[i]
        end
        if array[i] > max then
            max = array[i]
        end
    end
    return min, max
end

local function findMinMax(array)
    if #array == 0 then
        return nil, nil -- Return nil if the array is empty
    end

    return findMinMaxHelper(array, 1, #array)
end

local function formatNumber(num)
    return string.gsub(string.format("%.2f", num), "%.?0+$", "")
end

local function normalizeOutliers(values)
    local digitsToFreq = {}
    local lengthToNorm = nil
    local maxLength = 1
    for _, v in ipairs(values) do -- Count numbers with different amount of digits
        local l = string.len(tostring(math.floor(v)))
        if digitsToFreq[l] == nil then
            digitsToFreq[l] = 1
        else
            local newLength = digitsToFreq[l] + 1
            if maxLength < newLength then
                maxLength = newLength
            end
            digitsToFreq[l] = newLength
        end
    end

    local currentNumbOfValues = 0
    for i = 1, maxLength do                          -- Find abnormal length of numbers
        if currentNumbOfValues / #values > 0.90 then -- Above 90% with bigger digit count most likely are outliers
            lengthToNorm = i
            break
        end
        if digitsToFreq[i] ~= nil then
            currentNumbOfValues = currentNumbOfValues + digitsToFreq[i]
        end
    end

    if lengthToNorm ~= nil then
        local prevNumb = 0
        for i, v in ipairs(values) do -- Normalize them by using the previous number
            if string.len(tostring(math.floor(v))) >= lengthToNorm then
                values[i] = prevNumb
            else
                prevNumb = v
            end
        end
    end

    return values
end

local function drawHeader()
    lcd.drawText(1, 0, "Log Viewer                            ", INVERS)
end

local function getChartValuesAll(values)
    local numberOfValuesPerPoint = math.ceil((#values * ChartLineSize) / (CHART_X_MAX - CHART_X_MIN))

    local isSmallSet = ChartLineSize > CHART_LINE_SIZE_MIN

    local avgValues = {}
    if isSmallSet then
        for i = 1, #values do
            avgValues[#avgValues + 1] = values[i]
        end
    else
        for i = 1, #values, numberOfValuesPerPoint do
            local acc = 0
            local startJ = i
            local endJ = math.min(i + numberOfValuesPerPoint, #values)
            for j = startJ, endJ do
                acc = acc + values[j]
            end
            local currentValue = acc / (endJ - startJ + 1)
            avgValues[#avgValues + 1] = currentValue
        end
    end

    local minV, maxV = findMinMax(avgValues)
    return avgValues, minV, maxV
end

local function drawChartByValues(values, minV, maxV)
    local range = CHART_Y_MAX - CHART_Y_MIN
    local positionX = CHART_X_MIN
    for i = 1, #values - 1 do
        local weightedValue1 = (range - (range * ((values[i] - minV) / (maxV - minV)))) + CHART_Y_MIN
        local weightedValue2 = (range - (range * ((values[i + 1] - minV) / (maxV - minV)))) + CHART_Y_MIN

        -- The last point has to be at the right end of the display
        local endPositionX = (i == #values - 1) and CHART_X_MAX or ChartLineSize + positionX
        lcd.drawLine(positionX, weightedValue1, endPositionX, weightedValue2, SOLID, 0)
        positionX = positionX + ChartLineSize
    end

    lcd.drawText(1, 9, formatNumber(maxV) .. ColumnsMU[CurrentColumnIndex], SMLSIZE)
    lcd.drawText(1, 57, formatNumber(minV) .. ColumnsMU[CurrentColumnIndex], SMLSIZE)
end

local function getMixMaxInCurrentSlice(values)
    local minIndex = math.ceil(#values * ((SliderPosition - SLIDER_SIZE) / 164))
    local maxIndex = math.floor(#values * (SliderPosition / 164))

    return findMinMaxHelper(values, minIndex, maxIndex)
end

local function ensureValues(values)
    lcd.clear()
    drawHeader()

    if values == nil or #values == 0 then
        lcd.drawText(11, 28, "No numeric available")
        return false
    end
    return true
end

local lastAvgValuesCacheIndex = ''
local lastAvgValues = nil
local lastValues = nil
local lastMinV = nil
local lastMaxV = nil
local function drawChart()
    local cacheIndex = CurrentFileName .. CurrentColumnIndex

    local avgValues = nil
    local minV = nil
    local maxV = nil
    local values = nil

    if cacheIndex == lastAvgValuesCacheIndex then
        avgValues = lastAvgValues
        values = lastValues
        minV = lastMinV
        maxV = lastMaxV

        if not ensureValues(values) then
            return
        end
    else
        local valuesUnfiltered = getAllCurrentValues()

        if not ensureValues(valuesUnfiltered) then
            return
        end

        values = normalizeOutliers(valuesUnfiltered)

        if #values == 1 then -- We have just a single value. Add one extra for the drawing
            values[#values + 1] = values[1]
        end

        local minValues = (CHART_X_MAX - CHART_Y_MIN) / CHART_LINE_SIZE_MIN
        if #values < minValues then -- We have less values than pixels available
            ChartLineSize = math.ceil((CHART_X_MAX - CHART_Y_MIN) / (#values - 1))
        else                        -- We have enough values for the pixels available
            ChartLineSize = CHART_LINE_SIZE_MIN
        end

        avgValues, minV, maxV = getChartValuesAll(values)

        lastAvgValuesCacheIndex = cacheIndex
        lastAvgValues = avgValues
        lastValues = values
        lastMinV = minV
        lastMaxV = maxV
    end

    if minV == maxV then -- We have a constant for a value. Spread them a bit
        minV = minV - 1
        maxV = maxV + 1
    end

    drawChartByValues(avgValues, minV, maxV)

    -- Draw the slider line
    lcd.drawLine(SliderPosition - SLIDER_SIZE, 8, SliderPosition - SLIDER_SIZE, 64, DOTTED, 0)
    lcd.drawLine(SliderPosition, 8, SliderPosition, 64, DOTTED, 0)

    local min, max = getMixMaxInCurrentSlice(values)
    lcd.drawText(90, 9, formatNumber(max) .. ColumnsMU[CurrentColumnIndex], SMLSIZE)
    lcd.drawText(90, 57, formatNumber(min) .. ColumnsMU[CurrentColumnIndex], SMLSIZE)
end

local function drawValueScreen()
    lcd.clear()
    local fileText = string.format('F: %s/%s', CurrentFileIndex, NumberOfLogFiles)
    local lineText = string.format('L: %s/%s', CurrentLineIndex, NumberOfLines)
    local columnText = string.format('C: %s/%s', CurrentColumnIndex, #Columns)

    drawHeader()

    lcd.drawText(1, 12, fileText, (CurrentMode == 0 and INVERS or 0))
    lcd.drawText(60, 12, getFileTimeString(), SMLSIZE)

    lcd.drawText(1, 24, lineText, (CurrentMode == 1 and INVERS or 0))
    lcd.drawText(60, 24, getCurrentLineTimeString(), SMLSIZE)

    lcd.drawText(1, 36, columnText, (CurrentMode == 2 and INVERS or 0))
    lcd.drawText(60, 36, Columns[CurrentColumnIndex])
    lcd.drawText(1, 50, CurrentValue .. ColumnsMU[CurrentColumnIndex])
end

local function handleRotRotateEventsValueScreen(event)
    if CurrentMode == 0 then
        if event == EVT_ROT_RIGHT and CurrentFileIndex + 1 <= NumberOfLogFiles then
            CurrentFileIndex = CurrentFileIndex + 1
        elseif event == EVT_ROT_LEFT and 1 < CurrentFileIndex then
            CurrentFileIndex = CurrentFileIndex - 1
        end

        CurrentFileName = getFileNameByIndex()
        NumberOfLines = getCurrentNumberOfLines()
        CurrentLineIndex = NumberOfLines    -- Go the the last line
        Columns, ColumnsMU = parseColumns() -- In case we have files with different telemetry settings

        -- Reset if out of range
        if CurrentColumnIndex + 1 > #Columns then
            CurrentColumnIndex = 1
        end

        CurrentLineText = readCurrentLine()
        CurrentValue = getCurrentValue()
    elseif CurrentMode == 1 then
        if event == EVT_ROT_RIGHT and CurrentLineIndex + 1 <= NumberOfLines then
            CurrentLineIndex = CurrentLineIndex + 1
        elseif event == EVT_ROT_LEFT and 1 < CurrentLineIndex then
            CurrentLineIndex = CurrentLineIndex - 1
        end

        CurrentLineText = readCurrentLine()
        CurrentValue = getCurrentValue()
    elseif CurrentMode == 2 then
        if event == EVT_ROT_RIGHT and CurrentColumnIndex + 1 <= #Columns then
            CurrentColumnIndex = CurrentColumnIndex + 1
        elseif event == EVT_ROT_LEFT and 1 < CurrentColumnIndex then
            CurrentColumnIndex = CurrentColumnIndex - 1
        end

        CurrentValue = getCurrentValue()
    end
end

local function handleEvents(event)
    if event == EVT_ROT_LEFT or event == EVT_ROT_RIGHT then
        if IsShowingChart then
            if event == EVT_ROT_LEFT then
                if SLIDER_SIZE >= SliderPosition - SLIDER_SIZE then
                    SliderPosition = SLIDER_SIZE
                else
                    SliderPosition = SliderPosition - SLIDER_SIZE
                end
            else
                if SliderPosition + SLIDER_SIZE >= CHART_X_MAX - 1 then
                    SliderPosition = CHART_X_MAX - 1
                else
                    SliderPosition = SliderPosition + SLIDER_SIZE
                end
            end
            drawChart()
            return
        end
        handleRotRotateEventsValueScreen(event)
        drawValueScreen()
    elseif event == EVT_EXIT_BREAK then
        if not IsShowingChart then
            CurrentMode = CurrentMode - 1
            if CurrentMode < 0 then
                CurrentMode = 2
            end
        else
            IsShowingChart = false
            SliderPosition = CHART_X_MAX
        end
        drawValueScreen()
    elseif event == EVT_ROT_BREAK then
        if IsShowingChart then
            IsShowingChart = false
            SliderPosition = CHART_X_MAX
            drawValueScreen()
        else
            IsShowingChart = true
            drawChart()
        end
    end
end

local function init()
    NumberOfLogFiles = getNumberOfLogFiles()
    CurrentFileIndex = NumberOfLogFiles -- Go the the last line
    CurrentColumnIndex = 1
    CurrentFileName = getFileNameByIndex()
    Columns, ColumnsMU = parseColumns()
    NumberOfLines = getCurrentNumberOfLines()
    CurrentLineIndex = NumberOfLines
    CurrentLineText = readCurrentLine()
    CurrentValue = getCurrentValue()
end

local function run(event)
    if FirstRun then
        drawValueScreen()
        FirstRun = false
    end

    handleEvents(event)

    return 0
end

return {
    init = init,
    run = run
}
