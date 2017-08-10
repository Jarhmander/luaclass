local class = {}

local function self_meta(t)
    return setmetatable(t, t)
end

class.object = self_meta {}

class.object.__bases = {}

local default_base = class.object

local function class_init_instance(cls, instance, ...)
    local ctor = rawget(cls, "__ctor")
    if ctor then ctor(instance, ...) end
    return instance
end

local function class_destroy_instance(instance)
    -- FIX multi call to dtor in MI
    local visited = {}
    local function recurse_dtor(class, instance)
        if visited[class] then return end
        visited[class] = true
        local dtor = rawget(class, "__dtor")
        if dtor then dtor(instance) end

        for _, base in ipairs(instance.__bases) do
            class_destroy_instance(base, instance)
        end
    end
    return recurse_dtor(instance.__class, instance)
end

local function class_create()
    local cls = { __bases = default_base }

    function cls:__call(...)
        local instance = {}

        instance.__index = self
        instance.__gc = class_destroy_instance
        instance.__class = self

        instance = self_meta(instance)

        return class_init_instance(self, instance)
    end

    function cls:__index(member)
        for _, base in ipairs(self.__bases) do
            local value = base[member]
            if value then return value end
        end
        return nil
    end

    return self_meta(cls)
end

--[[
-- class:
--      __bases
--      __name
--
-- instance:
--      __class
--      __index
--      __gc
--]]
function class:__call(...)
    local cls = class_create()

    local class_name, class_inherits, class_content

    function class_name(...)
        if select("#", ...) == 1 and type(...) == "string" then
            cls.__name = ...
            return class_inherits
        else
            -- TODO
            cls.__name = "<unknown>"
        end
        return class_inherits(...)
    end

    function class_inherits(...)
        local maybe_class = ...

        if type(maybe_class) == "table" and class.isclass(maybe_class) then
            cls.__bases = {...}

            return class_content
        end
        return class_content(...)
    end

    function class_content(init, ...)
        if select("#", ...) > 0 or type(init) ~= "table" then
            error("syntax error")
        end
        for k, v in pairs(init) do cls[k] = v end
        return cls
    end

    return class_name(...)
end

function class.isinstance(instance, class)
    local function recurse_isinstance(class_instance, class)
        if class_instance == class then return true end
        for _, base in ipairs(class_instance.__bases) do
            if recurse_isinstance(base, class) then return true end
        end
        return false
    end
    return recurse_isinstance(instance.__class, class)
end

function class.type(obj)
    if type(obj) ~= "table" then return nil end
    local s = ""
    local cls = obj.__class
    if cls then
        s = "instance of "
    elseif class.isclass(obj) then
        cls = obj
    else
        return nil
    end
    return s .. "class " .. obj.__name
end

function class.isclass(cls)
    local bases = rawget(cls, '__bases')
    return bases and type(bases) == "table"
end

return self_meta(class)
