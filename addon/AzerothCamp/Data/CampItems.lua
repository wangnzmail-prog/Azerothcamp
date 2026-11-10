-- Data\CampItems.lua · 露营物品 / 光环 ID 表（事实数据，来自游戏数据与社区核对）
-- 用途：按 itemID 识别背包里的营地制品，不再依赖中文名字匹配。
local ADDON, ns = ...

ns.CampData = {
    auras = {
        nearby     = 1283391, -- 营火在附近
        welcoming  = 1289723, -- 温馨营火（休息计时）
        benefits   = 1229741, -- 露营增益
        boosted    = 1229451, -- 强化休息（共享 1 小时冷却）
        wellRested = 429959,  -- 充分休息（睡袋）
        violet     = 1328375, -- 紫色火焰
    },

    campfires = {
        { item = 279981, slots = 3,  spell = 1229737 }, -- 基础
        { item = 279961, slots = 5,  spell = 1283400 }, -- 熟练
        { item = 279974, slots = 10, spell = 1291341 }, -- 专家
    },

    -- 每专业三件：{ 三阶(工作站), 二阶(升级), 一阶(给 buff) }
    professions = {
        { key = "alchemy",       effect = "法力回复",       items = { 279990, 279970, 279956 } },
        { key = "blacksmithing", effect = "力量",           items = { 279955, 279988, 279944 } },
        { key = "enchanting",    effect = "属性与抗性",     items = { 279987, 279985, 279976 } },
        { key = "engineering",   effect = "商人/修装",      items = { 279989, 279949, 279950 } },
        { key = "herbalism",     effect = "智力",           items = { 279947, 279964, 279962 } },
        { key = "leatherworking",effect = "休息经验",       items = { 279945, 279941, 279978 } },
        { key = "mining",        effect = "近战攻强",       items = { 279952, 279948, 279960 } },
        { key = "skinning",      effect = "暴击",           items = { 279938, 279969, 279979 } },
        { key = "tailoring",     effect = "精神",           items = { 279959, 279943, 279973 } },
        { key = "fishing",       effect = "全属性",         items = { 279966, 279965, 279967 } },
        { key = "firstaid",      effect = "耐力",           items = { 279951, 279940, 279968 } },
    },

    cooking = {
        { item = 279957, effect = "烹饪台" },   -- 铁烤箱
        { item = 279982, effect = "食物" },     -- 饼干盛宴
    },

    sleepingBag = 211527,
    campTent    = 279978,
}

-- itemID -> { prof, tier, effect }
local lookup = {}
for _, p in ipairs(ns.CampData.professions) do
    for tier, id in ipairs(p.items) do
        lookup[id] = { prof = p.key, effect = p.effect, tier = 4 - tier }
    end
end
for _, o in ipairs(ns.CampData.cooking) do
    lookup[o.item] = { prof = "cooking", effect = o.effect, tier = 1 }
end
lookup[ns.CampData.sleepingBag] = { prof = "bag", effect = "睡袋 每层+3%经验", tier = 1 }
for _, c in ipairs(ns.CampData.campfires) do
    lookup[c.item] = { prof = "cooking", effect = string.format("营火(%d格)", c.slots), tier = 1, campfire = c }
end
ns.CampData.lookup = lookup
