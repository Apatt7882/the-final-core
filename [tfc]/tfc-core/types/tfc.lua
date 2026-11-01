---@meta
-- LuaLS type definitions for The Final Core. Never loaded at runtime.

---@class TFCModuleDefinition
---@field name string unique module name, e.g. 'accounts'
---@field version? string semver, e.g. '0.1.0'
---@field dependencies? table list of names and/or name = constraint, e.g. { 'jobs', accounts = '>=0.2.0' }

---@class TFCLog
---@field Debug fun(msg: any, ...: any)
---@field Info fun(msg: any, ...: any)
---@field Warn fun(msg: any, ...: any)
---@field Error fun(msg: any, ...: any)

---@class TFCCallback
---@field Register fun(name: string, handler: function, opts?: { rateLimit?: integer })
---@field Await fun(name: string, ...: any): ... client only
---@field AwaitClient fun(target: integer, name: string, ...: any): ... server only

---@class TFC
---@field Name string
---@field CoreResource string
---@field Resource string the resource this TFC object lives in
---@field IsServer boolean
---@field Context 'server'|'client'
---@field Version string
---@field Config TFCConfig core only
---@field Log TFCLog
---@field Callback TFCCallback
---@field On fun(name: string, handler: function): table
---@field Off fun(handle: table)
---@field Emit fun(name: string, ...: any)
---@field OnNet fun(eventName: string, handler: function, opts?: { rateLimit?: integer }): table
---@field RegisterModule fun(def: TFCModuleDefinition, onReady?: fun()): boolean, string server only
TFC = {}
