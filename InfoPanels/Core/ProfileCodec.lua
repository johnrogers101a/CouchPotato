-- InfoPanels/Core/ProfileCodec.lua
-- Profile string import/export following WeakAuras pattern:
-- Data table -> serialize -> LibDeflate compress -> base64 -> prepend "!IP:1!"
--
-- Functions are NEVER in the data table — only string keys and data values.
-- Marketplace metadata: description, author, tags, uid.
--
-- Single Responsibility: Encode/decode panel definitions to shareable strings.

local _, ns = ...
if not ns then ns = {} end

local CP = _G.CouchPotatoShared
local iplog = (CP and CP.CreateLogger) and CP.CreateLogger("IP") or function() end

local ProfileCodec = {}
ns.ProfileCodec = ProfileCodec

-- Current profile version
ProfileCodec.VERSION = 1

-- Try to load LibDeflate
local LibDeflate = ns.LibDeflate or _G.LibDeflate or (_G.LibStub and _G.LibStub("LibDeflate", true))

-------------------------------------------------------------------------------
-- Simple Lua table serializer (Lua 5.1 compatible, no loadstring needed).
-------------------------------------------------------------------------------
local function serialize(val, depth)
    depth = depth or 0
    if depth > 20 then return "nil" end

    local t = type(val)
    if t == "string" then
        return string.format("%q", val)
    elseif t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "nil" then
        return "nil"
    elseif t == "table" then
        local parts = {}
        local maxn = 0
        for i = 1, #val do
            maxn = i
            parts[#parts + 1] = serialize(val[i], depth + 1)
        end
        for k, v in pairs(val) do
            if type(k) == "number" and k >= 1 and k <= maxn and k == math.floor(k) then
                -- already handled
            else
                local key
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key = k
                else
                    key = "[" .. serialize(k, depth + 1) .. "]"
                end
                parts[#parts + 1] = key .. "=" .. serialize(v, depth + 1)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

-------------------------------------------------------------------------------
-- Safe deserializer (sandboxed, no arbitrary code execution).
-------------------------------------------------------------------------------
local function deserialize(str)
    if not str or str == "" then return nil, "Empty string" end

    local trimmed = str:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then return nil, "Empty string" end

    if trimmed:find("[%(%)]=") and not trimmed:find("^{") then
        return nil, "Invalid profile data"
    end

    local fn, err
    if setfenv and loadstring then
        fn, err = loadstring("return " .. trimmed)
        if fn then setfenv(fn, {}) end
    else
        fn, err = load("return " .. trimmed, "profile", "t", {})
    end

    if not fn then
        return nil, "Parse error: " .. tostring(err)
    end

    local ok, result = pcall(fn)
    if not ok then
        return nil, "Execution error: " .. tostring(result)
    end
    return result, nil
end

-------------------------------------------------------------------------------
-- Base64 encode/decode
-------------------------------------------------------------------------------
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64encode(data)
    local result = {}
    local pad = (3 - #data % 3) % 3
    data = data .. string.rep("\0", pad)
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + b * 256 + c
        result[#result + 1] = b64chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        result[#result + 1] = b64chars:sub(n % 64 + 1, n % 64 + 1)
    end
    for i = 1, pad do
        result[#result - i + 1] = "="
    end
    return table.concat(result)
end

local b64lookup = {}
for i = 1, #b64chars do
    b64lookup[b64chars:sub(i, i)] = i - 1
end

local function base64decode(data)
    data = data:gsub("[^%w+/=]", "")
    local result = {}
    local pad = 0
    if data:sub(-2) == "==" then pad = 2
    elseif data:sub(-1) == "=" then pad = 1 end

    for i = 1, #data, 4 do
        local c1 = b64lookup[data:sub(i, i)] or 0
        local c2 = b64lookup[data:sub(i + 1, i + 1)] or 0
        local c3 = b64lookup[data:sub(i + 2, i + 2)] or 0
        local c4 = b64lookup[data:sub(i + 3, i + 3)] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        result[#result + 1] = string.char(math.floor(n / 65536) % 256)
        result[#result + 1] = string.char(math.floor(n / 256) % 256)
        result[#result + 1] = string.char(n % 256)
    end
    local str = table.concat(result)
    if pad > 0 then str = str:sub(1, -pad - 1) end
    return str
end

-------------------------------------------------------------------------------
-- Fields to export (whitelist approach — no functions, no runtime state)
-------------------------------------------------------------------------------
local EXPORT_FIELDS = {
    "_v", "id", "title", "panelType", "layout",
    "lines", "bindings", "events", "visibility", "gap",
    "stats", "sections", "rows", "layoutData", "dataEntry",
    -- Marketplace metadata
    "description", "author", "tags", "uid",
    -- Panel type specific data
    "specOverride",
}

-------------------------------------------------------------------------------
-- Export: Convert a panel definition to a shareable profile string.
-- Format: "!IP:1!" + base64(deflate(serialized_definition))
-------------------------------------------------------------------------------
function ProfileCodec.Export(definition)
    if not definition then return nil, "No definition to export" end

    -- Build export structure (only whitelisted serializable fields)
    local exportDef = { _v = ProfileCodec.VERSION }
    for _, field in ipairs(EXPORT_FIELDS) do
        if definition[field] ~= nil then
            exportDef[field] = definition[field]
        end
    end

    local serialized = serialize(exportDef)
    if not serialized then return nil, "Serialization failed" end

    -- Compress if LibDeflate available
    local payload = serialized
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
        if compressed then
            payload = compressed
        end
    end

    -- Base64 encode and prepend versioned prefix
    local encoded = base64encode(payload)
    local profileString = "!IP:" .. ProfileCodec.VERSION .. "!" .. encoded

    iplog("Info", "Export: generated profile string, length=" .. #profileString)
    return profileString, nil
end

-------------------------------------------------------------------------------
-- GenerateShareText: Create a human-friendly share text with the string.
-------------------------------------------------------------------------------
function ProfileCodec.GenerateShareText(definition, profileString)
    local title = definition and definition.title or "Panel"
    return "[InfoPanels] " .. title .. " — " .. profileString
end

-------------------------------------------------------------------------------
-- Import: Parse a profile string into a panel definition.
-- Accepts both "!IP:N!..." (new) and "IP1:..." (legacy) formats.
-------------------------------------------------------------------------------
function ProfileCodec.Import(profileString)
    if not profileString or profileString == "" then
        return nil, "Empty import string"
    end

    -- Try new format: !IP:N!...
    local versionStr, encoded = profileString:match("^!IP:(%d+)!(.+)$")

    -- Fallback: legacy format IP1:...
    if not versionStr then
        versionStr, encoded = profileString:match("^IP(%d+):(.+)$")
    end

    if not versionStr or not encoded then
        return nil, "Invalid import string format. Expected '!IP:1!...' or 'IP1:...'"
    end

    local version = tonumber(versionStr)
    if not version then
        return nil, "Invalid version in import string"
    end

    if version > ProfileCodec.VERSION then
        return nil, "This string requires InfoPanels v" .. version .. " or later."
    end

    -- Base64 decode
    local ok, decoded = pcall(base64decode, encoded)
    if not ok or not decoded or decoded == "" then
        return nil, "Invalid import string: base64 decode failed"
    end

    -- Try decompress
    local serialized = decoded
    if LibDeflate then
        local decompressed = LibDeflate:DecompressDeflate(decoded)
        if decompressed then
            serialized = decompressed
        end
    end

    -- Deserialize
    local definition, err = deserialize(serialized)
    if not definition then
        return nil, "Invalid import string: " .. tostring(err)
    end

    if type(definition) ~= "table" then
        return nil, "Invalid import string: expected table definition"
    end

    if not definition.id or not definition.title then
        return nil, "Invalid import string: missing id or title"
    end

    -- Version migration
    if definition._v and definition._v < ProfileCodec.VERSION then
        iplog("Info", "Import: migrating from v" .. tostring(definition._v) .. " to v" .. ProfileCodec.VERSION)
        definition._v = ProfileCodec.VERSION
    end

    -- Strip version field from runtime definition
    definition._v = nil
    -- Imported panels are NOT builtin
    definition.builtin = false

    iplog("Info", "Import: successfully imported panel '" .. definition.title .. "'")
    return definition, nil
end

return ProfileCodec
