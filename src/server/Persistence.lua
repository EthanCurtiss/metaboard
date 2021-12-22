local CollectionService = game:GetService("CollectionService")
local HTTPService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local Common = game:GetService("ReplicatedStorage").MetaBoardCommon
local Config = require(Common.Config)
local LineInfo = require(Common.LineInfo)
local DrawingTask = require(Common.DrawingTask)
local Cache = require(Common.Cache)

local MetaBoard

local Persistence = {}
Persistence.__index = Persistence

function Persistence.Init()
    MetaBoard = require(script.Parent.MetaBoard)
end

local function serialiseVector2(v)
    local vData = {}
    vData.X = v.X
    vData.Y = v.Y
    return vData
end

local function deserialiseVector2(vData)
    return Vector2.new(vData.X, vData.Y)
end

local function serialiseColor3(c)
    local cData = {}
    cData.R = c.R
    cData.G = c.G
    cData.B = c.B
    return cData
end

local function deserialiseColor3(cData)
    return Color3.new(cData.R, cData.G, cData.B)
end

local function deserialiseLine(canvas, lineHandleData, zIndex)
    local start = deserialiseVector2(lineHandleData.Start)
    local stop = deserialiseVector2(lineHandleData.Stop)
    local color = deserialiseColor3(lineHandleData.Color)
    local thicknessYScale = lineHandleData.ThicknessYScale

    local lineInfo = LineInfo.new(start, stop, thicknessYScale, color)
    
    local worldLine = MetaBoard.CreateWorldLine("HandleAdornments", canvas, lineInfo, zIndex)
    LineInfo.StoreInfo(worldLine, lineInfo)

    return worldLine
end

local function serialiseLine(lineHandle)
    local lineHandleData = {}
    lineHandleData.Start = serialiseVector2(lineHandle:GetAttribute("Start"))
	lineHandleData.Stop = serialiseVector2(lineHandle:GetAttribute("Stop"))
	lineHandleData.Color = serialiseColor3(lineHandle:GetAttribute("Color"))
	lineHandleData.ThicknessYScale = lineHandle:GetAttribute("ThicknessYScale")
    return lineHandleData
end

local function deserialiseCurve(canvas, curveData)
    local curve = Instance.new("Folder")
    curve.Name = curveData.Name
    curve:SetAttribute("AuthorUserId", curveData.AuthorUserId)
    curve:SetAttribute("ZIndex", curveData.ZIndex)
    curve:SetAttribute("CurveType", curveData.CurveType)
    
    for _, lineHandleData in ipairs(curveData.LineHandles) do
        local lineHandle = deserialiseLine(canvas, lineHandleData, curveData.ZIndex)
        lineHandle.Parent = curve
    end

    return curve
end

local function serialiseCurve(curve)
    local curveData = {}
    curveData.Name = curve.Name
    curveData.AuthorUserId = curve:GetAttribute("AuthorUserId")
    curveData.ZIndex = curve:GetAttribute("ZIndex")
    curveData.CurveType = curve:GetAttribute("CurveType")

    local lineHandles = {}

    for _, lineHandle in ipairs(curve:GetChildren()) do
        table.insert(lineHandles, serialiseLine(lineHandle))
    end

    curveData.LineHandles = lineHandles

    return curveData
end

-- Restores an empty board to the contents stored in the DataStore
-- with the given persistence ID string
function Persistence.Restore(board, persistId)
    local DataStore = DataStoreService:GetDataStore(Config.DataStoreTag)

    if not DataStore then
        print("Persistence: DataStore not loaded")
        return
    end

    if #board.Canvas.Curves:GetChildren() > 0 then
        print("Persistence: Called Restore on a nonempty board")
        return
    end

    -- Get the value stored for the given persistId. Note that this may not
    -- have been set, which is fine
    local success, boardJSON = pcall(function()
        return DataStore:GetAsync(persistId)
    end)
    if not success then
        print("Persistence: Failed to read from DataStore for ID " .. persistId)
        return
    end

    -- Return if this board has not been stored
    if not boardJSON then
        print("No data for this persistId")
        return
    end

	boardData = HTTPService:JSONDecode(boardJSON)

    if not boardData then
        print("Persistence: failed to decode JSON")
        return
    end

    -- The board data is a table, each entry of which is a dictionary
    -- defining a curve
    for _, curveData in ipairs(boardData) do
        local curve = deserialiseCurve(board.Canvas, curveData)
        curve.Parent = board.Canvas.Curves
    end

    print("Persistence: Successfully restored board " .. persistId)
end

-- Stores a given board to the DataStore with the given ID
function Persistence.Store(board, persistId)
    local DataStore = DataStoreService:GetDataStore(Config.DataStoreTag)

    if not DataStore then
        print("Persistence: DataStore not loaded")
        return
    end

    local boardData = {}
    for _, curve in ipairs(board.Canvas.Curves:GetChildren()) do
        local curveData = serialiseCurve(curve)
        table.insert(boardData, curveData)
    end

    local boardJSON = HTTPService:JSONEncode(boardData)

    if not boardJSON then
        print("Persistence: Board JSON encoding failed")
        return
    end

    -- TODO pre-empt "value too big" error
    -- print("Persistence: Board JSON length is " .. string.len(boardJSON))

    local success, errormessage = pcall(function()
        return DataStore:SetAsync(persistId, boardJSON)
    end)
    if not success then
        print("Persistence: Failed to store to DataStore for ID " .. persistId)
        print(errormessage)
        return
    end

    print("Persistence: Successfully stored board " .. persistId)
end

return Persistence