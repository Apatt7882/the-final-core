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

---@class TFCPlayerData
---@field source integer
---@field userId integer
---@field characterId integer
---@field cid string 8-character public character id
---@field slot integer
---@field firstname string
---@field lastname string
---@field dob string|nil YYYY-MM-DD
---@field sex 'm'|'f'|nil
---@field metadata table

---@class TFCNotify
---@field title? string
---@field description? string
---@field type? 'inform'|'success'|'error'|'warning'
---@field duration? integer

---@class TFCUI
---@field Notify fun(srcOrData: integer|TFCNotify|string, data?: TFCNotify|string) client: Notify(data); server: Notify(src, data)
---@field ShowPrompt fun(text: string) client only: show an interaction prompt, e.g. "[E] Open shop"
---@field HidePrompt fun() client only: hide the interaction prompt
---@field Menu fun(menu: { id: string, title: string, options: table[] }): boolean client only: context menu (ox_lib)
---@field Input fun(heading: string, rows: table[]): table|nil client only: input dialog (ox_lib)
---@field Progress fun(data: { duration: integer, label: string, anim?: table, canCancel?: boolean }): boolean client only
---@field SkillCheck fun(difficulty?: string|string[], keys?: string[]): boolean client only: skill check (ox_lib)

---@class TFC
---@field UI TFCUI
---@field PlayerData TFCPlayerData|nil client only
---@field OnPlayerLoaded fun(fn: fun(data: TFCPlayerData)) client only
---@field OnPlayerUnloaded fun(fn: fun()) client only
---@field OnMetadataChanged fun(fn: fun(key: string, value: any)) client only
---@field GetPlayer fun(src: integer|string): TFCPlayer|nil server only
---@field GetPlayerByCid fun(cid: string): TFCPlayer|nil server only
---@field GetPlayers fun(): integer[] server only: sources of loaded players
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
