local class = {}

local function class_destroy(instance)
    local function recurse_dtor(class, instance)
        local dtor = rawget(class, "__dtor")
        if dtor then return dtor(instance) end

        for _, p in ipairs(instance.__parents) do
            class_destroy(p, instance)
        end
    end
    return recurse_dtor(instance.__class, instance)
end

function class:__call(...)
    local cl = {}

    function cl:__call(...)
        local instance = {}

        instance.__index = self
        instance.__gc = class_destroy
        instance.__class = self

        local ctor = rawget(self, "__ctor")
        if ctor then ctor(self, ...) end
        return setmetatable(instance, instance)
    end

    cl.__parents = {...}

    if ... then
        local bases = cl.__parents
        if #bases == 1 then
            cl.__index = ...
        else
            function cl:__index(member)
                for _, base in ipairs(self.__parents) do
                    local value = base[member]
                    if value then return value end
                end
                return nil
            end
        end
    end

    local proxy = setmetatable({}, { __index = cl.__index or nil })

    function cl.__base()
        return proxy
    end

    return function(init)
        for k, v in pairs(init) do cl[k] = v end
        return setmetatable(cl, cl)
    end 
end

local function isinstance(instance, class)
    local function recurse_isinstance(class_instance, class)
        if class_instance == class then return true end
        for _, p in ipairs(class_instance.__parents) do
            if recurse_isinstance(p, class) then return true end
        end
        return false
    end
    return recurse_isinstance(instance.__class, class)
end

class.isinstance = isinstance

return setmetatable(class, class)
