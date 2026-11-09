-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- Translations. The addon's text is written in English, and each English
-- string is its own key: L["Find a camp"] is the translation for the language
-- in use, or the English itself when there's none (so a missing translation
-- never breaks anything). Formats keep their %s and %d in the same order.
--
-- The language is the game's (GetLocale()), unless Options picks another. The
-- Locales files add their tables with ns.AddLocale; Core picks one at login
-- (ns.ApplyLocale), before any window is built, since saved settings aren't
-- loaded yet while these files run. Changing it in Options needs a /reload.
--
-- Everything sent to other players' addons is IDs and keys, never text, so
-- players on different languages work together. Only chat you click to send
-- (Say, General, Post plan) goes out in your own language.

local translations = {}  -- [locale] = { [English] = translation }
local active = nil
local applied = false
local hooks = {}         -- functions that translate a file's tables in place (ns.OnLocale)

-- Looking text up before the language is known would get the English, so it's
-- noted (the tests check nothing does).
ns.earlyLookups = {}

ns.L = setmetatable({}, {
    __index = function(_, key)
        if not applied then ns.earlyLookups[#ns.earlyLookups + 1] = key end
        return active and active[key] or key
    end,
})

-- fn(L) translates text in a file's tables (labels, phrases...) once the
-- language is known; those tables are built while the files load, before it is.
function ns.OnLocale(fn)
    hooks[#hooks + 1] = fn
end

-- Translates the listed fields of each entry in list, in place.
function ns.LocalizeFields(list, ...)
    local L = ns.L
    for _, entry in pairs(list) do
        for i = 1, select("#", ...) do
            local field = select(i, ...)
            if type(entry[field]) == "string" then entry[field] = L[entry[field]] end
        end
    end
end

-- The languages Happy Camper speaks, for Options: { code, name in that language },
-- in the order the Language menu lists them. There's no Polish game client:
-- plPL is only ever picked in Options, on an English client.
ns.LANGUAGES = {
    { "enUS", "English" },
    { "deDE", "Deutsch" },
    { "frFR", "Français" },
    { "esES", "Español" },
    { "ptBR", "Português" },
    { "plPL", "Polski" },
    { "zhCN", "简体中文" },
    { "koKR", "한국어" },
}

-- Clients whose language shares another's translation.
local SAME_AS = { enGB = "enUS", esMX = "esES", ptPT = "ptBR" }

function ns.AddLocale(locale, strings)
    translations[locale] = strings
end

-- The locale to use: Options' choice ("auto" or nil = the game's).
function ns.PickLocale(choice)
    local locale = (choice and choice ~= "auto") and choice or GetLocale()
    return SAME_AS[locale] or locale
end

-- Picks the language (once, at login) and translates the files' tables.
function ns.ApplyLocale(choice)
    local locale = ns.PickLocale(choice)
    active = translations[locale]
    ns.locale = active and locale or "enUS"
    ns.localeChoice = choice or "auto"
    if not applied then
        applied = true
        for _, fn in ipairs(hooks) do fn(ns.L) end
    end
    return ns.locale
end

-- Every translation table, for the tests (and the dev tools' previews in
-- other languages).
function ns.Translations()
    return translations
end

-- Once every addon has loaded (PLAYER_LOGIN): the other languages' tables
-- are let go (about a megabyte), since changing language needs a /reload.
-- With the dev tools on they stay, for their previews in other languages.
function ns.DropOtherTranslations()
    if ns.devCommands and next(ns.devCommands) then return end -- the dev tools are loaded
    for locale in pairs(translations) do
        if translations[locale] ~= active then translations[locale] = nil end
    end
end
