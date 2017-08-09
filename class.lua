local class = {}

local function class_destroy_instance(instance)
    local function recurse_dtor(class, instance)
        local dtor = rawget(class, "__dtor")
        if dtor then return dtor(instance) end

        for _, p in ipairs(instance.__bases) do
            class_destroy_instance(p, instance)
        end
    end
    return recurse_dtor(instance.__class, instance)
end

local function self_meta(t)
    return setmetatable(t, t)
end

class.object = self_meta {}

default_base = class.object

local function class_create()
    local cls = { __bases = default_base }

    function cls:__call(...)
        local instance = {}

        instance.__index = self
        instance.__gc = class_destroy_instance
        instance.__class = self

        local ctor = rawget(self, "__ctor")
        if ctor then ctor(self, ...) end
        return self_meta(instance)
    end
    return self_meta(cls)
end

--[[
-- Support the following:
--
--   A = class { [foo = 1 etc] }
--   A = class "A" { [foo = 1 etc] }
--   A = class (base1 [, base2 ...]) { [foo = 1 etc] }
--   A = class "A" (base1 [, base2 ...]) { [foo = 1 etc] }
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

            function cls:__index(member)
                for _, base in ipairs(self.__bases) do
                    local value = base[member]
                    if value then return value end
                end
                return nil
            end
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
        for _, p in ipairs(class_instance.__bases) do
            if recurse_isinstance(p, class) then return true end
        end
        return false
    end
    return recurse_isinstance(instance.__class, class)
end

function class.type(obj)
    if type(obj) ~= "table" then return nil end
    local s = ""
    if obj.__class then s = "instance of " end
    if class.isclass(obj) then return s .. "class " .. obj.__name end
    return nil
end

function class.isclass(cls)
    return type(cls.__name) == "string"
end

return self_meta(class)
