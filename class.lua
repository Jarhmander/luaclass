local class

local debug

local default_base

--[[!
--  List of metamethods, to be used for inherithed metamethods
--]]
local metalist =
{
    "__add", "__sub", "__mul", "__div",
    "__mod", "__pow",
    "__unm",
    "__idiv",
    "__band", "__bor", "__bxor", "__bnot",
    "__shl", "__shr",
    "__concat", "__len",
    "__eq", "__lt", "__le",
    "__newindex",
    "__call"
}

--[[!
--  @brief Small helper: return (given) table with itself as metatable
--]]
local function self_meta(t)
    return setmetatable(t, t)
end

--[[!
--  @brief impementation of `class.attributes`.
--]]
local function class_attributes(inst_or_class, attr)
    local i = 0
    local function it(mro)
        i = i+1
        while mro[i] do
            local cls = mro[i]
            local ret = rawget(cls, attr)
            i = i+1
            if ret then return ret, cls end
        end
        return nil
    end
    local cls = class.isclass(inst_or_class) and inst_or_class or inst_or_class.__class
    return it, cls.__mro
end

--[[!
--  @brief Implementation of `class.getattr`.
--]]
local function class_getattr(inst_or_class, attr)
    local it, mro = class_attributes(inst_or_class, attr)
    return it(mro)
end

--[[!
--  @brief Internal; on a fresh new instance, calls the ctor if it exists.
--]]
local function class_init_instance(cls, instance, ...)
    local ctor = rawget(cls, "__ctor")
    if ctor then ctor(instance, ...) end
    return instance
end

--[[!
--  @brief Implementation of `dtor` and `__gc`: destroy instance
--]]
local function class_destroy_instance(instance)
    for dtor in class_attributes(instance, "__dtor") do
        dtor(instance)
    end
end

--[[!
--  @brief Internal; try to get the classname
--]]
local function class_try_get_classname(cls)
    local classname

    local function fallback()
        if not classname then
            cls.__name = "anon" -- So tostring works.
            local s = tostring(cls)
            local hex = s:match("0x(%x+)")
            classname = "_anon_" .. (hex or '???')
        end
        cls.__classname = classname
    end

    if not debug then
        local ok, pkg = pcall(require, "debug")
        if not ok then return fallback() end
        debug = pkg
    end

    local dbg = debug.getinfo(3)
    local filename = string.match(dbg.source, "@(.+)")
    local f = filename and io.open(filename, "r")
    if not f then return fallback() end

    local line
    for i = 1, dbg.currentline do
        line = f:read()
    end

    classname = line:match "([%a_][%w_]*)%s*=%s*class%f[%s%p\0]"
    return fallback()
end

--[[!
--  @brief Initialize the field `__mro` with the linearization of the resolution order. Uses the C3
--  linearization algorithm.
--]]
local function class_c3_linearization(cls)
    local bases = cls.__bases
    local res = {cls}
    local mergelist = {}

    local function Baselist(bases)
        return self_meta
        {
            __index=bases;
            head=1;
            len=#bases;
            empty=function(self)
                return self.head > self.len
            end;
            in_tail=function(self, cls)
                for i = self.head+1, self.len do
                    if self[i] == cls then return true end
                end
                return false
            end;
            clear_cls=function(self, cls)
                if self[self.head] == cls then
                    self.head = self.head + 1
                end
            end;
            get_head=function(self)
                return self[self.head]
            end
        }
    end

    local function get_head()
        local function find_head_in_tails(head)
            for _, list in pairs(mergelist) do
                if list:in_tail(head) then return true end
            end
            return false
        end

        for _, l in ipairs(mergelist) do
            local head = l:get_head()
            if not find_head_in_tails(head) then return head end
        end
        error "Broken inheritance graph"
    end

    local function remove_head(head)
        local i = 1
        repeat
            local list = mergelist[i]
            list:clear_cls(head)
            if list:empty() then
                table.remove(mergelist, i)
            else
                i = i+1
            end
        until mergelist[i] == nil
    end

    for _, base in ipairs(bases) do
        table.insert(mergelist, Baselist(base.__mro))
    end
    table.insert(mergelist, Baselist(bases))

    while next(mergelist) do
        local head = get_head()
        table.insert(res, head)
        remove_head(head)
    end

    cls.__mro = res
    return cls
end

class = self_meta {}

--[[!
--  @brief Internal; make new class with some defined contents
--]]
local function class_create()
    local cls = { __bases = {default_base} }

    function cls:__call(...)
        local instance = {}

        instance.__index = self
        instance.__gc = class_destroy_instance
        instance.__class = self
        instance.__name = class.type(instance)

        for _, meta in ipairs(metalist) do
            instance[meta] = function (...)
                local m = class_getattr(cls, meta)
                if not m then error("unimplemented operator " .. meta, 2) end
                return m(...)
            end
        end

        self_meta(instance)

        return class_init_instance(self, instance, ...)
    end

    function cls:__index(member)
        return class_getattr(self, member)
    end

    return self_meta(cls)
end

--[[!
--  @brief Creation of a new class
--
--  This constructor can be used as follows:
--      [local] c = class {...}
--      [local] c = class "Name" {...}
--      [local] c = class (Base1 [, Base2 ...]) {...}
--      [local] c = class "Name" (Base1 [, Base2 ...]) {...}
--
--  More succintly, the syntax is as follows:
--      class [classname] [(bases...)] <attrlist>
--
--  In other words, you can omit the class name and/or the base classes specification but `attrlist`
--  is required.
--
--  If `classname` is omitted, the name is deduced automatically (not reliable: uses the debug
--  library, and requires the script to be available, and works only for simple cases). If it fails
--  to get the name automatically, the deduced `classname` will be `_anon_HHH`, where HHH is a
--  unique sequence of hex digits.
--
--  If `bases` is omitted, the class inherits from `class.object`.
--
--  `attrlist` is a possibly empty list of class attributes: regular functions, member functions and
--  class members (variable shared accross all instances of a class, much like static member
--  variables in C++)
--]]
function class:__call(...)
    local cls = class_create()

    local class_name, class_inherits, class_content

    function class_name(...)
        if select("#", ...) == 1 and type(...) == "string" then
            cls.__classname = ...
            return class_inherits
        else
            class_try_get_classname(cls)
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

        class_c3_linearization(cls)
        cls.__name = class.type(cls)
        for k, v in pairs(init) do
            cls[k] = v
        end
        return cls
    end

    return class_name(...)
end

--[[!
--  @brief Checks if the object is an instance of a class or subclass
--]]
function class.isinstance(instance, class)
    local cls = instance.__class
    for _, c in ipairs(cls.__mro) do
        if c == class then return true end
    end
    return false
end

--[[!
--  @brief Returns "class <name>" for a class, "instance of class <name>" for an instance, nil
--  otherwise.
--]]
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
    return s .. "class " .. cls.__classname
end

--[[!
--  @brief Tells if the argument is a class
--]]
function class.isclass(cls)
    local bases = rawget(cls, '__bases')
    return bases and type(bases) == "table"
end

--[[!
--  @brief Abstract method implementation.
--
--  Useful for hinting which methods are abstract and should be implemented proper. Assign this
--  function to fields meant to be methods that are to be implemented by derived class
--]]
function class.abstractmethod()
    error("abstract method called", 2)
end

default_base = self_meta {}

default_base.__bases = {}
default_base.__mro = {default_base}
default_base.dtor = class_destroy_instance
default_base.__classname = "object"
default_base.__name = class.type(default_base)
default_base.__newindex = rawset

--[[!
--  @brief class `object`, the base class of all classes.
--]]
class.object = default_base

--[[!
--  @brief Resolve an attribute in an instance or class
--
--  @param inst_or_class instance or class
--  @param attr          attribute to find
--
--  @return nil if the attribute is not found, otherwise the attribute and the class where it is
--  found.
--
--  @see class_getattr
--]]
class.getattr = class_getattr

--[[!
--  @brief Iterator; allow iterating through a class hierarchy, getting a single attribute
--
--  @param inst_or_class instance or class
--  @param attr          attribute to find
--
--  @return iterator function and the __mro list, so ```for attr in class.attributes(cls)```
--  iterates through the different attributes.
--
--  @see class_attributes
--]]
class.attributes = class_attributes

----------------------------------------------------------------------------------------------------

if rawget(_G, "RUN_TESTS") then
    local function list_equal(a, b)
        local i = 0
        repeat
            i = i + 1
            if a[i] ~= b[i] then return false end
        until a[i] == nil
        return true
    end

    local Foo = class "Foo"
    {
        __ctor = function(self, num)
            print("Foo called with:", num)
            self.bar = num
        end;
    }

    io.stdout:setvbuf "no"
    f = Foo(42)

    print(Foo)
    print(f)
    assert(f.bar == 42)
    print(class.type(Foo))
    print(class.type(f))

    assert(class.type(Foo) == "class Foo")
    assert(string.match(class.type(class{}), "^class _anon_%x+"))

    local A = class {}
    local B = class {}
    local C = class {}
    local D = class {}
    local E = class {}
    local K1 = class (A,B,C) {}
    local K2 = class (D,B,E) {}
    local K3 = class (D,A) {}
    local Z = class (K1,K2,K3) {}

    assert(list_equal(Z.__mro, {Z,K1,K2,K3,D,A,B,C,E,class.object}))

    local Bar = class
    {
        __add = function(a,b)
            print "Add!"
        end;
    }

    local _ = Bar() + Bar()
end

return class
