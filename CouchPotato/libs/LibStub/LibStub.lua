-- LibStub - Library versioning stub
-- MIT License
-- This is the real LibStub implementation used by Ace3 and most WoW addons

local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
local LibStub = _G[LIBSTUB_MAJOR]

if not LibStub or LibStub.minor < LIBSTUB_MINOR then
    LibStub = LibStub or {libs = {}, minors = {}}
    _G[LIBSTUB_MAJOR] = LibStub
    LibStub.minor = LIBSTUB_MINOR

    -- LibStub:NewLibrary(major, minor)
    -- Creates a new library or upgrades an existing one
    -- Returns nil if the existing library is newer or same version
    function LibStub:NewLibrary(major, minor)
        assert(type(major) == "string", "Bad argument #1 to `NewLibrary' (string expected)")
        minor = assert(tonumber(string.match(minor, "%d+")), "Bad argument #2 to `NewLibrary' (number or numeric string expected)")

        local oldminor = self.minors[major]
        if oldminor and oldminor >= minor then
            return nil
        end

        self.minors[major] = minor
        self.libs[major] = self.libs[major] or {}
        return self.libs[major], oldminor
    end

    -- LibStub:GetLibrary(major, silent)
    -- Returns the library with the given major version, or errors if not found
    function LibStub:GetLibrary(major, silent)
        if not self.libs[major] and not silent then
            error(string.format("Cannot find a library instance of %q.", tostring(major)), 2)
        end
        return self.libs[major], self.minors[major]
    end

    -- LibStub:IterateLibraries()
    -- Returns an iterator over all registered libraries
    function LibStub:IterateLibraries()
        return pairs(self.libs)
    end

    setmetatable(LibStub, {__call = LibStub.GetLibrary})
end
