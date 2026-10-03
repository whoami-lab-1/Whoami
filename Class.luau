--!native
--!nonstrict

--[[
	Class++ (Executor Adaptation)
	Adaptado para entornos de inyección / exploits de Roblox.
	Sin dependencias externas ni módulo Logger.
--]]

local env = (getgenv and getgenv()) or _G or shared

-- ==========================================
-- 1. UTILITY & TYPE ENGINE (INLINED)
-- ==========================================

local nativeType = type
local nativeTypeof = typeof

local Type = {}

function Type.type(object: any): string
	local objType = nativeType(object)
	if objType ~= "table" and objType ~= "userdata" then return objType end
	local success, result = pcall(function() return (object :: any)["__type"] end)
	if success and result then return result end
	return objType
end

function Type.typeof(object: any): string
	local objType = nativeTypeof(object)
	local customType = Type.type(object)
	if customType == "Class" then
		return (object :: any)["__classtype"]
	elseif customType == "Object" then
		return (object :: any)["__objtype"]
	end
	return objType
end

local type = Type.type
local typeof = Type.typeof

local Util = {}

function Util.returnAccessSpecifier(index: string, objectData: any): (string?, any?)
	if objectData.Public and objectData.Public[index] ~= nil then return "Public", objectData.Public[index] end
	if objectData.Private and objectData.Private[index] ~= nil then return "Private", objectData.Private[index] end
	if objectData.Protected and objectData.Protected[index] ~= nil then return "Protected", objectData.Protected[index] end
	if objectData.Internal and objectData.Internal[index] ~= nil then return "Internal", objectData.Internal[index] end
	return nil
end

function Util.findPropertyFromIndex(classData: any, index: string, accessSpecifier: string?): any?
	local fAccessSpecifier = accessSpecifier or Util.returnAccessSpecifier(index, classData)
	if not fAccessSpecifier or not classData[fAccessSpecifier] then return end
	return classData[fAccessSpecifier][index]
end

function Util.getMethodContext(level: number): ((any) -> (any), string)
	local f, n
	pcall(function() 
		f = debug.info(level, 'f') 
		n = debug.info(level, 'n')
	end)
	return f, n
end

function Util.checkInheritance(class: any, classOrMethod: any): boolean
	if not class.Inherits then return false end
	for _, inherited in ipairs(class.Inherits) do
		if inherited == classOrMethod or (type(inherited) == "table" and inherited[classOrMethod]) then
			return true
		end
	end
	return false
end

function Util.checkFriendship(class: any, methodName: string, method: any, classes: {[string]: any}): boolean
	if not class.Friends then return false end
	for _, friend in ipairs(class.Friends) do
		if type(friend) == "Class" and friend[methodName] then
			return true
		elseif typeof(friend) == "string" then
			if classes[friend] and classes[friend][methodName] then return true end
		elseif typeof(friend) == "function" and friend == method then
			return true
		end
	end
	return false
end

function Util.inClassScope(class: any, objectData: any, overloadedFunctions: {any}, includeInherited: boolean, includeFriend: boolean, classes: {[string]: any}?, defaultLevel: number?): boolean
	local level: number = defaultLevel or 5
	while true do
		local method, methodName = Util.getMethodContext(level)
		if not method then return false end

		if Util.findPropertyFromIndex(objectData, methodName) == method then return true end
		if includeInherited and Util.checkInheritance(class, method) or includeFriend and classes and Util.checkFriendship(class, methodName, method, classes) then return true end
		if method == typeof or (methodName == "overloadHandler" and table.find(overloadedFunctions, method)) then return true end
		if class[methodName] == method then return true end

		level += 1
	end
	return false
end

function Util.binarySearch(array: {any}, value: any): any
	local Low: number = 1
	local High: number = #array
	while Low <= High do
		local Middle: number = Low + math.floor((High - Low) / 2)
		local MiddleValue: number = array[Middle]
		if value < MiddleValue then
			High = Middle - 1
		elseif MiddleValue < value then
			Low = Middle + 1
		else
			while Middle >= 1 and not (array[Middle] < value or value < array[Middle]) do
				Middle -= 1
			end
			return Middle + 1
		end
	end
	return nil
end

-- Reemplazos simples de Logger usando error / warn nativos
local function logError(msg: string, fatal: boolean?, args: {any}?)
	local formatted = "[Class++ Error]: " .. tostring(msg)
	if args then formatted ..= " (" .. table.concat(args, ", ") .. ")" end
	if fatal then error(formatted, 2) else warn(formatted) end
end

local function logErrorNonFatal(msg: string, flag: boolean?, args: {any}?)
	warn("[Class++ Non-Fatal Error]: " .. tostring(msg) .. (args and (" (" .. table.concat(args, ", ") .. ")") or ""))
end

local inClassScope = Util.inClassScope
local binarySearch = Util.binarySearch
local getMethodContext = Util.getMethodContext
local findPropertyFromIndex = Util.findPropertyFromIndex
local returnAccessSpecifier = Util.returnAccessSpecifier
local checkFriendship = Util.checkFriendship

-- ==========================================
-- 2. CLASS++ CORE ENGINE
-- ==========================================

local classes = {}
local classpp = {version = {major = 2, minor = 3, patch = 1, beta = false}, autoObjectDestruction = true}

local accessSpecifiers = {"Friend", "Internal", "Private", "Protected", "Public"}
local overloadableOperators = {"operator_add", "operator_div", "operator_eq", "operator_idiv", "operator_mod", "operator_mul", "operator_pow", "operator_sub", "operator_unm"}
local operatorMetamethodNames = {["operator_add"] = "__add", ["operator_div"] = "__div", ["operator_eq"] = "__eq", ["operator_idiv"] = "__idiv", ["operator_mod"] = "__mod", ["operator_mul"] = "__mul", ["operator_pow"] = "__pow", ["operator_sub"] = "__sub", ["operator_unm"] = "__unm"}

local function shallowCopy(original: any, copy: any): ()
	for key, val in pairs(original) do
		copy[key] = val
	end
end

local function deepCopy(original: any, copyMetatable: boolean?): any
	if nativeType(original) ~= "table" then return original end
	local copy = {}
	shallowCopy(original, copy)

	for key, value in pairs(original) do
		if nativeType(value) == "table" then
			local metatable = getmetatable(value)
			if not metatable then 
				copy[key] = deepCopy(value, true) 
			elseif not copyMetatable then 
				local success, result = pcall(setmetatable, value, {})
				local copyTable = success and result or {}
				if not success then shallowCopy(value, copyTable) end
				copy[key] = deepCopy(copyTable, true) 
			else 
				copy[key] = value
			end
		end
	end

	return copy
end

local function recursiveClean(tbl: any)
	for key, value in pairs(tbl) do
		local keyType = nativeTypeof(key)
		local valueType = nativeTypeof(value)

		if keyType == "Instance" then pcall(function() key:Destroy() end) end
		if valueType == "table" then
			recursiveClean(value)
		elseif valueType == "Instance" then
			pcall(function() value:Destroy() end)
		elseif valueType == "RBXScriptConnection" then
			pcall(function() value:Disconnect() end)
		elseif valueType == "thread" then
			pcall(task.cancel, value)
		end

		tbl[key] = nil
	end
end

local function checkTypeContext()
	for i = 5, 8 do
		local ctx, _ = getMethodContext(i)
		if ctx == type or ctx == typeof then
			return false
		end
	end
	return true
end

local function objectCleaner(objectData: any): any
	for accessSpecifier, attributesData in pairs(objectData) do
		if accessSpecifier == "Internal" then continue end
		recursiveClean(attributesData)
		objectData[accessSpecifier] = nil
	end

	if objectData.Internal then
		objectData.Internal.__locked = true
	end
	return objectData
end

local function runOnGarbageCollection(object: any, callback: () -> ())
	local alive_test = setmetatable({object}, {__mode = "v"})
	task.defer(function()
		while alive_test[1] ~= nil do
			task.wait(1)
		end
		callback()
	end)
end

local function garbageCollectionCallback(objectData: any, destructor: (any) -> ())
	if objectData.Internal and not objectData.Internal.__locked and destructor then
		local objectCopy = setmetatable({}, {__metatable = "This table is locked."})

		if objectData.Protected then
			for k, v in pairs(objectData.Protected) do objectCopy[k] = v end
		end
		if objectData.Public then
			for k, v in pairs(objectData.Public) do
				if k ~= "Destroy" and k ~= "super" then objectCopy[k] = v end
			end
		end
		if objectData.Private then
			for k, v in pairs(objectData.Private) do objectCopy[k] = v end
		end

		local success, err = pcall(destructor, objectCopy)
		if not success then logErrorNonFatal("unhandledError", true, {"destructor", err}) end

		objectCleaner(objectData)
		table.clear(objectCopy)
	end
	table.clear(objectData)
end

local function recursiveFindParentFunction(obj: any, method: (...any) -> any, class: any, findType: "constructor" | "function", methodName: string?, ...)
	local inheritedClass = class.Inherits and class.Inherits[1]
	if not class.classData then return end

	if findType == "constructor" then
		if inheritedClass and class.classData.constructor == method and inheritedClass.classData then
			return inheritedClass.classData.constructor(obj, ...)
		elseif inheritedClass then
			return recursiveFindParentFunction(obj, method, inheritedClass, "constructor", nil, ...)
		else
			logError("invalidConstructor", true, {typeof(obj)})
		end
	else
		if inheritedClass and inheritedClass.classData then
			local inheritedClassData = inheritedClass.classData
			local foundPublic = inheritedClassData.Public and inheritedClassData.Public[methodName]
			local foundProtected = inheritedClassData.Protected and inheritedClassData.Protected[methodName]

			if foundPublic and nativeTypeof(foundPublic) == "function" and class.classData.Public[methodName] == method and method ~= foundPublic then 
				return foundPublic(obj, ...) 
			elseif foundProtected and nativeTypeof(foundProtected) == "function" and (class.classData.Protected[methodName] == method or class.classData.Public[methodName] == method) and method ~= foundProtected then
				return foundProtected(obj, ...)
			else
				return recursiveFindParentFunction(obj, method, inheritedClass, "function", methodName, ...)
			end
		else
			logError("cannotFindBaseClassMethod", true, {methodName, class.Name})
		end
	end
end

local function sortAttributes(classData: any, className: string, class: any, inheritedClassAmount: number, inheritedClass: any, inheritedClassData: any): any
	local objectTbl = {
		Public = deepCopy(classData.Public or {}),
		Private = deepCopy(classData.Private or {}),
		Protected = deepCopy(classData.Protected or {}),
		Internal = {
			__type = "Object",
			__objtype = className,
			__locked = false
		}
	}

	local constructor = classData.constructor
	local destructor = classData.destructor

	function objectTbl.Public.Destroy(obj: any)
		local objectType = type(obj)
		local objectClassType = typeof(obj)

		if objectType ~= "Object" then logError("invalidDestructorCall", true) end
		if objectClassType ~= className then logError("classTypeMismatch", true, {objectType, className}) end

		if destructor then 
			local success, err = pcall(destructor, obj)
			if not success then logErrorNonFatal("unhandledError", true, {"destructor", err}) end
		end

		objectCleaner(objectTbl)
	end

	function objectTbl.Public.super(obj: any, ...)
		local objectType = type(obj)
		local objectClassType = typeof(obj)

		if objectType ~= "Object" then logError("invalidSuperCall", true) end
		if objectClassType ~= className then logError("classTypeMismatch", true, {objectType, className}) end
		if inheritedClassAmount > 1 or not inheritedClass then logError("invalidInheritation", true) end
		if not inheritedClassData then return end

		local method, currentMethod = getMethodContext(5)
		if currentMethod == "constructor" then
			return recursiveFindParentFunction(obj, method, class, "constructor", nil, ...)
		else
			return recursiveFindParentFunction(obj, method, class, "function", currentMethod, ...)
		end
	end
	return objectTbl
end

local function callOperator(functionName: string, obj: any, obj2: any?, silenceError: boolean?): boolean | any
	if nativeTypeof(obj) == "userdata" or nativeTypeof(obj) == "table" then
		local objFunction = obj[functionName]
		if objFunction then return objFunction(obj, obj2) end
	elseif obj2 and (nativeTypeof(obj2) == "userdata" or nativeTypeof(obj2) == "table") then
		local objFunction = obj2[functionName]
		if objFunction then return objFunction(obj2, obj) end
	end

	if not silenceError then logError("classNoMatchingFunctionError", true, {functionName}) end
	return false
end

local function setMetamethods(class: any, objectData: any, methods: any, overloadedFunctions: {any})
	local Internal = objectData.Internal
	methods.__metatable = 'The metatable is locked.'

	function methods:__index(index: string)
		if Internal.__locked then logError("classObjectLocked", true) end

		local accessSpecifier, property = returnAccessSpecifier(index, objectData)
		if accessSpecifier ~= "Public" and accessSpecifier ~= nil then
			if accessSpecifier == "Private" and not inClassScope(class, objectData, overloadedFunctions, false, true, classes) then
				logError("classPropertyIsPrivate", true, {index})
			elseif accessSpecifier == "Protected" and not inClassScope(class, objectData, overloadedFunctions, true, false) then
				logError("classPropertyIsProtected", true, {index})
			elseif accessSpecifier == "Internal" and checkTypeContext() then
				logError("classPropertyIsInternal", true, {index})
			end
		end

		if property ~= nil then return property elseif index ~= "constructor" and index ~= "destructor" and index ~= "__tostring" then logError("classMemberNotFound", true, {index}) end		
		return nil
	end

	function methods:__newindex(index: string, value: any)
		if Internal.__locked then logError("classObjectLocked", true) end
		if value == nil then logError("classMemberCannotSetToNil", true) end

		local accessSpecifier, property = returnAccessSpecifier(index, objectData)
		if accessSpecifier ~= "Public" and accessSpecifier ~= nil then
			if accessSpecifier == "Private" and not inClassScope(class, objectData, overloadedFunctions, false, true, classes) then
				logError("classPropertyIsPrivate", true, {index})
			elseif accessSpecifier == "Protected" and not inClassScope(class, objectData, overloadedFunctions, true, false) then
				logError("classPropertyIsProtected", true, {index})
			elseif accessSpecifier == "Internal" and checkTypeContext() then
				logError("classPropertyIsInternal", true, {index})
			end
		end

		if property == nil then logError("classMemberNotFound", true, {index}) elseif property == value then return end
		objectData[accessSpecifier][index] = value
	end

	function methods:__tostring()
		if Internal.__locked then logError("classObjectLocked", true) end

		local result = callOperator("__tostring", self, nil, true)
		return result or class.Name
	end

	for _, operatorFuncName in ipairs(overloadableOperators) do
		if objectData.Public and objectData.Public[operatorFuncName] then
			methods[operatorMetamethodNames[operatorFuncName]] = function(obj, obj2)
				if Internal.__locked then logError("classObjectLocked", true) end
				return callOperator(operatorFuncName, obj, obj2)
			end
		end
	end
end

local function checkValidAccessSpecifier(specifierString: string): (boolean, string?)
	local isFound = binarySearch(accessSpecifiers, specifierString)
	return isFound ~= nil, accessSpecifiers[isFound]
end

local function createClassObject(newClassData: any, className: string, inheritedClasses: {any}?)
	local overloadedFunctions = {}
	local staticMembers = {}

	local class = {
		Inherits = table.freeze(inheritedClasses or {}),
		Friends = table.freeze(newClassData.Friend or {}),
		Name = className,
		extends = function() logError("extendsRemoved", true) end
	}

	newClassData.Public = newClassData.Public or {}
	newClassData.Private = newClassData.Private or {}
	newClassData.Protected = newClassData.Protected or {}

	local inheritedClasses = class.Inherits
	local inheritedClassesAmount = #inheritedClasses
	local inheritedClass = inheritedClasses[1]
	local inheritedClassData = inheritedClass and inheritedClass.classData

	local autoObjectDestruction = classpp.autoObjectDestruction
	local constructor = newClassData.constructor
	local destructor = newClassData.destructor

	local methods = {
		__abstract = false,
		__final = false,
		__metatable = "This metatable is locked."
	}

	function methods.__index(t: any, i: string): any
		if i == "__type" and not checkTypeContext() then return "Class" end
		if i == "__classtype" and not checkTypeContext() then return className end
		if i == "classData" then return newClassData end

		local result = newClassData[i] or findPropertyFromIndex(newClassData, i)
		if not result then return staticMembers[i] end
		return result
	end

	function methods.__newindex(t: any, i: string, v: any)
		newClassData[i] = v
	end

	function class.new(...)
		local newObjData = sortAttributes(newClassData, className, class, inheritedClassesAmount, inheritedClass, inheritedClassData)
		local newObject = newproxy(true)
		local proxyMethods = getmetatable(newObject)

		if autoObjectDestruction then
			runOnGarbageCollection(newObject, function()
				garbageCollectionCallback(newObjData, destructor)
			end)
		end

		setMetamethods(class, newObjData, proxyMethods, overloadedFunctions)
		if constructor then constructor(newObject, ...) end
		return newObject
	end

	function class.overload(accessSpecifier: string, name: string, functionTable: {any})
		local overloadHandler = function(...)
			local args = {...}
			for _, func in ipairs(functionTable) do
				local success, argCount, isVariadic = pcall(debug.info, func, 'a')
				if not success or argCount == #args or isVariadic then
					return func(...)
				end
			end
		end
		newClassData[accessSpecifier][name] = overloadHandler
		table.insert(overloadedFunctions, overloadHandler)
	end

	return setmetatable(class, methods)
end

local function constructClass(classDataArg: any, className: string, otherClassDatas: any?, otherClasses: any?)
	local newClassData = classDataArg
	local nCObj = createClassObject(newClassData, className, otherClasses)
	classes[className] = nCObj
	return nCObj
end

local returnClassFunction = function(className: string, ...): any
	local argTable = {...}
	if #argTable >= 1 and type(argTable[1]) == "table" then
		return constructClass(argTable[1], className)
	end
	return function(classDataArg: any)
		return constructClass(classDataArg, className)
	end
end

function classpp.class(className: string): any
	return function(...): any
		return returnClassFunction(className, ...)
	end
end

function classpp.getClass(className: string): any
	return classes[className]
end

classpp.Type = Type
classpp.Util = Util

-- Registro global dentro del ejecutor
env.ClassPP = classpp
return classpp
