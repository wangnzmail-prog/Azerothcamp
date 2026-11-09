local addonName, ns = ...

---------------------------------------------------------------------------
-- Kit Dock: shared by First Aid Kit, Camping Kit and Fishing Kit.
--
-- Every kit addon ships this same file. The first copy to load (or the
-- newest version) runs; the others just pick it up, so there is nothing
-- separate to install and a single kit on its own behaves exactly as before.
--
-- With two or more kits, their buttons snap to a small gold pin: three sit
-- in a triangle, two side by side (whichever way you dropped them). Opening a
-- docked kit glides it onto the pin and tucks the others in behind it, so
-- its slots fan out exactly as they do on their own. Drag a kit away from
-- the pin to float it; drop it on any other kit (or on the pin) to dock the
-- two together. Positions are only changed out of combat.
--
-- Dropping works the same whatever state the kits are in: the kit you let
-- go of joins whichever kit or pin is under it. Two floating kits dropped
-- together start a dock where they are; a kit dropped on a docked kit joins
-- that dock; an open kit dragged by its button carries its dock along, and
-- pulls in a floating kit it's dropped on. Any kit that was open closes on a
-- merge so you can see the result. A kit dragged to the edge of the screen
-- slides back in far enough for its slots to fit, docked or not.
--
-- A kit can register as edges only (edgesOnly in its Register call): it
-- snaps to the screen edges like any kit but never joins the pin, and other
-- kits never merge with it.
--
-- A kit dragged to a screen edge sticks there on its own, tucked half off
-- the screen until the mouse goes over it (or it's open). Whatever it pops
-- out as a reminder (a missing Well Fed, say) still shows beside it.
--
-- Tuck boxes hold kits you only need now and then: a small box on a screen
-- edge, tucked half off the screen until the mouse goes over it, with each
-- kit's reminders and pinned slots showing just inside it. Drop a kit onto
-- a kit on an edge and the two make a box there; drop a kit on a box to put
-- it in. Drag the pin (or the open kit carrying it) to an edge and its kits
-- go into a box right away, which follows along the edge until you let go;
-- pull back off the edge and they're on the pin again. There can be any
-- number of boxes; drag one onto another (by its grip, the pin's gold stud)
-- and they merge. Drag a box's grip away from the edges and it becomes the
-- pin again, taking every kit that can go on the pin with it (edges-only
-- kits stay in the box). A box down to one kit becomes that kit on the edge
-- on its own. A kit opened from a box steps out beside it and opens there,
-- and goes back in when it closes. Like everything else here, boxes only
-- move out of combat: in combat they stay as they were, and a kit in a box
-- stays there.
---------------------------------------------------------------------------

local VERSION = 24
local D = _G.KitDock
if D and (D.version or 0) >= VERSION then
    ns.Dock = D
    return
end
D = D or {}
_G.KitDock = D
ns.Dock = D
D.version = VERSION
D.kits = D.kits or {}
D.media = D.media or ("Interface\\AddOns\\" .. addonName .. "\\media\\")
-- Art new in this version (the Kits chest) comes from the kit that carries
-- this copy, since an older kit loaded first may not ship it.
local OWN_MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"

local ORDER = { "fak", "ck", "fk" }
local SNAP = 105 -- how close (UI units) a kit must come to merge (preview and drop)

-- The top dock (UI units).
local PARK_SIZE = 34     -- a parked kit's button on screen
local PARK_GAP = 8       -- between parked kits
local PARK_PAD = 8       -- from the box's ends to the first and last kit
local PARK_H = 50        -- the pill's height
local PARK_TUCK = 26     -- tucked: the box's outer edge sits this far past the screen's, so half of it shows
local PARK_SHOW = 8      -- out: still this far past the screen's edge (no gap to fall into), its kits all in view
local GRIP_SMALL, GRIP_BIG = 8, 18 -- the grip: a small dot on the box's corner, bigger under the mouse
local NOTE_GAP = 4       -- between the reminders in a box's row
local NOTE_COLS = 3      -- each kit's block in a box's row: this many along the edge, then another row inward
local GLYPH = 14         -- the small kit icon at the head of each block
local SEP_PAD = 7        -- either side of the rule between two kits' blocks
local PARK_SLIDE = 0.18  -- seconds to slide
local PARK_LINGER = 0.35 -- seconds the mouse has to be away before it tucks again

local function DB()
    KitDockDB = KitDockDB or {}
    local db = KitDockDB
    db.docked = db.docked or {}
    db.order = db.order or { "fak", "ck", "fk" }
    if db.triUp == nil then db.triUp = true end
    db.two = db.two or 0
    return db
end
D.DB = DB -- the kits' settings panels bind their docking options to it

local function InList(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
end

-- A kit the player has hidden (from its settings or the shared minimap menu)
-- sits out of the dock entirely.
local function Shown(k)
    local api = D.kits[k]
    return api and not (api.IsHidden and api.IsHidden())
end

-- A kit that never joins the pin (it only snaps to the screen edges).
local function EdgesOnly(k)
    local api = D.kits[k]
    return api and api.edgesOnly and true or false
end

-- Tuck boxes (saved): a list of { side, at, keys }, each a box on a screen
-- edge with the kits in it in order. A kit that isn't loaded or is hidden
-- keeps its place in its box but doesn't show. Kit Dock 22 had one box
-- (db.box) holding db.parked: that becomes the first box.
local function Boxes()
    local db = DB()
    if type(db.boxes) ~= "table" then
        db.boxes = {}
        local old = db.parked
        if type(old) == "table" and #old > 0 then
            local b = type(db.box) == "table" and db.box or {}
            db.boxes[1] = { side = b.side or "top", at = b.at, keys = { unpack(old) } }
        end
        db.parked, db.box = nil, nil
    end
    return db.boxes
end

-- The box a kit is in, and its place in it.
local function BoxOf(k)
    for _, b in ipairs(Boxes()) do
        local i = InList(b.keys, k)
        if i then return b, i end
    end
end

local function IsParked(k)
    return BoxOf(k) ~= nil
end

-- A kit that can go in a box: any kit, edges-only ones included (boxes are
-- on the edges too).
local function Parkable(k)
    return Shown(k)
end

-- A box's kits that are loaded and showing, in order.
local function BoxKeys(b)
    local keys = {}
    for _, k in ipairs(b.keys) do
        if D.kits[k] and Parkable(k) and not InList(keys, k) then keys[#keys + 1] = k end
    end
    return keys
end

-- Every boxed kit that's loaded and showing.
local function ParkedKeys()
    local keys = {}
    for _, b in ipairs(Boxes()) do
        for _, k in ipairs(BoxKeys(b)) do keys[#keys + 1] = k end
    end
    return keys
end

-- Take a kit out of whatever box it's in (the caller tidies up and lays out).
local function UnparkRaw(key)
    local b, i = BoxOf(key)
    if b then table.remove(b.keys, i) end
    return b
end

-- Kits that can go on the pin (parked ones are in the top dock instead).
local function Count()
    local n = 0
    for k in pairs(D.kits) do
        if Shown(k) and not EdgesOnly(k) and not IsParked(k) then n = n + 1 end
    end
    return n
end

local function Installed()
    local n = 0
    for _ in pairs(D.kits) do n = n + 1 end
    return n
end

-- Docking only means something with two or more kits showing.
function D.Active() return Count() >= 2 end

---------------------------------------------------------------------------
-- Kits snapped to a side of the screen. Saved as a list of entries, each
-- { side = "left"|"right"|"top"|"bottom", at = along, keys = { key } }:
-- one kit each, staying where it was put (kits on an edge never merge;
-- they can overlap, and you move them apart yourself). "along" runs down
-- the left and right edges (from the top) and across the top and bottom
-- (from the left), in UIParent units.
---------------------------------------------------------------------------

local function Edges()
    local db = DB()
    db.edges = db.edges or {}
    return db.edges
end

local function EdgeOf(key)
    for _, g in ipairs(Edges()) do
        local i = InList(g.keys, key)
        if i then return g, i end
    end
end

-- Which edge a kit is on, or nil.
function D.EdgeSide(key)
    local g = EdgeOf(key)
    if g then return g.side end
    local b = BoxOf(key)
    return b and b.side or nil
end

-- Kits on the pin, in their saved order (never ones on an edge).
local function DockedKeys()
    local keys = {}
    if not D.Active() then return keys end
    local db = DB()
    for _, k in ipairs(db.order) do
        if Shown(k) and not EdgesOnly(k) and db.docked[k] ~= false and not EdgeOf(k) and not IsParked(k) then keys[#keys + 1] = k end
    end
    for _, k in ipairs(ORDER) do -- anything missing from a saved order
        if Shown(k) and not EdgesOnly(k) and db.docked[k] ~= false and not EdgeOf(k) and not IsParked(k) and not InList(keys, k) then keys[#keys + 1] = k end
    end
    return keys
end

local function PinDocked(key)
    return InList(DockedKeys(), key) ~= nil
end

-- For the kits: placed by the dock (on the pin, on an edge or parked in the
-- top dock), not by their own saved spot.
function D.IsDocked(key)
    return PinDocked(key) or EdgeOf(key) ~= nil or (IsParked(key) and Parkable(key))
end

-- Whether a kit is in a tuck box, and whether it can be.
function D.IsParked(key) return IsParked(key) and Parkable(key) end
function D.Parkable(key) return Parkable(key) end

-- A frame's centre in UIParent units.
local function Center(f)
    local x, y = f:GetCenter()
    if not x then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * s, y * s
end

---------------------------------------------------------------------------
-- The pin
---------------------------------------------------------------------------

local function SavePin()
    local x, y = Center(D.pin)
    if x then DB().pin = { x, y } end
end

local function SetPinAt(x, y)
    D.pin:ClearAllPoints()
    D.pin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    DB().pin = { x, y }
end

-- For the kits: the pin was moved in combat (by a kit's secure code, see
-- Kit Core) to here, in UIParent units. Saved now; the next layout puts it
-- there properly.
function D.SavePinAt(x, y)
    if x and y then DB().pin = { x, y } end
end

-- The pin is a protected frame (from v19), so a kit's secure code can move it
-- in combat, and the docked kits with it: they're anchored to it. Its own
-- drag still only works out of combat.
local function Pin()
    if D.pin then return D.pin end
    local okp, p = pcall(CreateFrame, "Button", "KitDockPin", UIParent, "SecureActionButtonTemplate")
    if not okp or not p then p = CreateFrame("Button", "KitDockPin", UIParent) end
    p:SetSize(20, 20)
    p:SetFrameStrata("MEDIUM")
    p:SetFrameLevel(30)
    p:SetMovable(true)
    p:SetClampedToScreen(true)
    p:RegisterForDrag("LeftButton")
    -- The same gold stud as the shared minimap button. It glows under the
    -- mouse and the cursor turns into the move cursor over it, so it still
    -- reads as "drag me".
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.tex:SetTexture(D.media .. "pin_dot", nil, nil, "LINEAR")
    p.hl = p:CreateTexture(nil, "HIGHLIGHT")
    p.hl:SetTexture(D.media .. "glow_ring")
    p.hl:SetBlendMode("ADD")
    p.hl:SetPoint("CENTER")
    p.hl:SetSize(30, 30)
    p:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
        D.PinDragStart()
    end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not D.PinDragStop() then
            SavePin()
            D.Layout() -- (puts back the room its kits need from the edges)
        end
    end)
    p:SetScript("OnEnter", function(self)
        if SetCursor then pcall(SetCursor, "UI_MOVE_CURSOR") end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Move kits")
        GameTooltip:AddLine("Drag to move your kits together. Drag to a screen edge to tuck them all into the kit box there. Drag a kit away from the pin to float it on its own; drop it near the pin to dock it again.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function()
        if ResetCursor then pcall(ResetCursor) end
        GameTooltip:Hide()
    end)
    p:Hide()
    D.pin = p
    return p
end

-- The pin's saved spot, or under the first docked kit the first time.
local function PlacePin(keys)
    local db = DB()
    if db.pin and db.pin[1] and db.pin[2] then -- (older versions could save it without a y)
        SetPinAt(db.pin[1], db.pin[2])
        return
    end
    local first = keys[1] and D.kits[keys[1]]
    local x, y
    if first then x, y = Center(first.kit) end -- (not "first and Center()": that keeps only x)
    if not (x and y) then x, y = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2 end
    SetPinAt(x, y)
end

---------------------------------------------------------------------------
-- Layout (out of combat only; queued otherwise)
---------------------------------------------------------------------------

local busy = false

---------------------------------------------------------------------------
-- Animation: kits glide and grow (or shrink) into their new spot, and the
-- kits that tuck away fade out (or back in), instead of jumping.
---------------------------------------------------------------------------

local GLIDE = 0.24

local function Anims(kit)
    if kit.dockAG then return end
    local g = kit:CreateAnimationGroup()
    local jump = g:CreateAnimation("Translation") -- back to where it was, unseen
    jump:SetDuration(0.001)
    jump:SetOrder(1)
    local glide = g:CreateAnimation("Translation")
    glide:SetDuration(GLIDE)
    glide:SetSmoothing("IN_OUT")
    glide:SetOrder(2)
    local grow = g:CreateAnimation("Scale")
    grow:SetDuration(GLIDE)
    grow:SetSmoothing("IN_OUT")
    grow:SetOrder(2)
    kit.dockAG, kit.dockJump, kit.dockGlide, kit.dockGrow = g, jump, glide, grow
    local f = kit:CreateAnimationGroup()
    local a = f:CreateAnimation("Alpha")
    a:SetDuration(0.16)
    local sc = f:CreateAnimation("Scale")
    sc:SetDuration(0.16)
    sc:SetSmoothing("OUT")
    f:SetScript("OnFinished", function()
        local done = kit.fadeDone
        kit.fadeDone = nil
        if done then done() end
    end)
    kit.fadeAG, kit.fadeAlpha, kit.fadeScale = f, a, sc
end

-- Fade a kit button out (then run done, which hides it) or back in.
function D.Fade(kit, out, done)
    Anims(kit)
    kit.fadeAG:Stop()
    kit.fadeAlpha:SetFromAlpha(out and 1 or 0)
    kit.fadeAlpha:SetToAlpha(out and 0 or 1)
    local s0, s1 = out and 1 or 0.6, out and 0.6 or 1
    kit.fadeScale:SetScaleFrom(s0, s0)
    kit.fadeScale:SetScaleTo(s1, s1)
    kit.fadeDone = done
    kit.fadeAG:Play()
end

-- Kit buttons glide by being moved for real, a little each frame, rather
-- than with an animation: a new layout part-way through (the live merge
-- preview makes them often) then starts from wherever the kit actually is
-- on screen, so nothing snaps back to the old spot or jumps ahead.
local tweens = {}
local tweener = CreateFrame("Frame")
tweener:Hide()
D.tweener = tweener -- (for testing)

local function Smooth(t) return t * t * (3 - 2 * t) end

local function TweenApply(kit, tw, k)
    if tw.byOffset then -- (a slot or other frame: its own anchor, offset less and less)
        kit:ClearAllPoints()
        kit:SetPoint(tw.p, tw.rel, tw.rp, tw.x + tw.ox * (1 - k), tw.y + tw.oy * (1 - k))
        return
    end
    local s = tw.ss + (tw.es - tw.ss) * k
    local x = tw.sx + (tw.ex - tw.sx) * k
    local y = tw.sy + (tw.ey - tw.sy) * k
    kit:SetScale(s)
    local own = s * tw.parentEff / UIParent:GetEffectiveScale() -- UIParent units per kit unit
    kit:ClearAllPoints()
    kit:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / own, y / own)
end

local function TweenFinish(kit, tw)
    tweens[kit] = nil
    if tw.byOffset then
        if InCombatLockdown() then return end
        kit:ClearAllPoints()
        kit:SetPoint(tw.p, tw.rel, tw.rp, tw.x, tw.y)
        return
    end
    kit:SetScale(tw.es)
    kit:ClearAllPoints()
    kit:SetPoint(tw.p, tw.rel, tw.rp, tw.x, tw.y)
end

-- Stop a kit's glide where it should end (before something else moves it,
-- or when combat starts and frames can't move).
local function StopTween(kit)
    local tw = tweens[kit]
    if tw then TweenFinish(kit, tw) end
end
D.StopTween = StopTween

-- A kit button's scale as it will be: where a glide is taking it (it grows
-- or shrinks along the way), or as it is. Kit Core sizes the slots round it
-- from this, so they're placed for the button's real size, not part-way.
function D.ScaleOf(kit)
    local tw = tweens[kit]
    if tw and not tw.byOffset and tw.es then return tw.es end
    return kit:GetScale()
end

tweener:SetScript("OnUpdate", function(self, dt)
    -- Kit buttons are secure: once combat has locked them, a glide can't
    -- move or scale them. Freeze here; combat's end puts them in place.
    if InCombatLockdown() then self:Hide() return end
    local any = false
    for kit, tw in pairs(tweens) do
        tw.t = tw.t + dt
        if tw.t >= GLIDE then
            TweenFinish(kit, tw)
        else
            TweenApply(kit, tw, Smooth(tw.t / GLIDE))
            any = true
        end
    end
    if not any and not next(tweens) then self:Hide() end
end)

-- The kit has just been put where it ends up (anchor and scale); glide it
-- there from bx, by (in its old own units) at old effective scale bscale.
local function KitGlide(kit, bx, by, bscale)
    -- (not as combat starts either: the glide would run on into combat, where
    -- the kit can't move, and leave it part-way)
    if not bx or not kit:IsShown() or InCombatLockdown() then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return end
    local ui = UIParent:GetEffectiveScale()
    local ex, ey = Center(kit)
    if not ex then return end
    local es = kit:GetScale()
    local parentEff = kit:GetEffectiveScale() / es
    local sx, sy, ss = bx * bscale / ui, by * bscale / ui, bscale / parentEff
    if math.abs(sx - ex) < 0.5 and math.abs(sy - ey) < 0.5 and math.abs(ss - es) < 0.001 then return end
    local p, rel, rp, x, y = kit:GetPoint(1)
    if kit.dockAG then kit.dockAG:Stop() end
    tweens[kit] = { t = 0, sx = sx, sy = sy, ss = ss, ex = ex, ey = ey, es = es, parentEff = parentEff,
        p = p, rel = rel, rp = rp, x = x, y = y }
    TweenApply(kit, tweens[kit], 0)
    tweener:Show()
end

-- Any other frame (a kit's pinned slots, its timers) that has just been put
-- where it ends up: glide it there from bx, by (in its old own units) at old
-- effective scale bscale. Moved for real a little each frame, by easing off
-- an offset on its own anchor, so it still goes along with the kit it hangs
-- from, and so does everything on it: a game animation moves only the
-- picture, and a slot's cooldown numbers didn't follow (from v20).
local function Glide(frame, bx, by, bscale)
    if not bx or not frame:IsShown() or InCombatLockdown() then return end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return end -- (see KitGlide)
    if frame.GetNumPoints and frame:GetNumPoints() ~= 1 then return end
    local nx, ny = frame:GetCenter()
    if not nx then return end
    local eff = frame:GetEffectiveScale()
    local ox, oy = bx * (bscale / eff) - nx, by * (bscale / eff) - ny -- in the frame's own units
    if math.abs(ox) < 1 and math.abs(oy) < 1 then return end
    local cur = tweens[frame]
    local p, rel, rp, x, y
    if cur and cur.byOffset then
        p, rel, rp, x, y = cur.p, cur.rel, cur.rp, cur.x, cur.y -- (already gliding: its real anchor)
    else
        p, rel, rp, x, y = frame:GetPoint(1)
    end
    if not p then return end
    if frame.dockAG then frame.dockAG:Stop() end
    tweens[frame] = { t = 0, byOffset = true, p = p, rel = rel, rp = rp, x = x, y = y, ox = ox, oy = oy }
    TweenApply(frame, tweens[frame], 0)
    tweener:Show()
end

-- The kits use it too (KeepOnScreen, and for their pinned slots), so a free
-- kit nudged in from the edge slides the same way a docked one does.
D.Glide = function(frame, bx, by, bscale)
    for _, api in pairs(D.kits) do
        if api.kit == frame then return KitGlide(frame, bx, by, bscale) end
    end
    return Glide(frame, bx, by, bscale)
end

-- Docked kits keep their full size (each kit's own Size setting); docked
-- and closed, the kit is told (Compact) so it can fan its pinned slots
-- round the outside of its slice and hide extras that sit around its button.
local function SetCompact(api, on, angle, span)
    local base = api.BaseScale and api.BaseScale() or 1
    local kit = api.kit
    local scale = base
    local rescaled = math.abs(kit:GetScale() - scale) > 0.001
    if rescaled then kit:SetScale(scale) end
    angle, span = on and angle or nil, on and span or nil
    -- A size change needs the refresh too: the pinned slots fan out from the
    -- button's edge, wherever that now is.
    if rescaled or api.compact ~= on or api.compactAngle ~= angle or api.compactSpan ~= span then
        api.compact, api.compactAngle, api.compactSpan = on, angle, span
        -- Its slice of the dock: pinned slots fan out around the outside of
        -- the docked button, within this angle range (degrees, y up).
        if api.Compact then api.Compact(on, angle, span) end
    end
end

-- Tells a kit which edge it's on (or nil), so it lays its slots out in
-- columns (or rows) toward the middle of the screen.
-- The kit's slots glide into (or out of) the edge shape rather than jump:
-- BeginMove / EndMove around it, which nest inside a layout's own pair.
local function SetEdge(api, side)
    if api.edgeSide ~= side then
        api.edgeSide = side
        if api.Edge then
            if api.BeginMove then api.BeginMove() end
            api.Edge(side)
            if api.EndMove then api.EndMove() end
        end
    end
end

-- Docked, closed and shrunk (the kit hides its timers and small buttons).
function D.IsCompact(key)
    local api = D.kits[key]
    return api and api.compact or false
end

-- How big a docked kit is on screen (UIParent units) in a dock of n.
local function DockedSize(api, n, open)
    local kit = api.kit
    return kit:GetWidth() * (api.BaseScale and api.BaseScale() or 1)
end

-- Lay a kit's slots out for an edge, for the kits to call: cols is a list of
-- columns from the edge inward, each a list of { frame, size } (sizes in
-- the slots' own units), half is the kit button's half-size in those units.
-- divAfter puts a gap for a divider after that column. Returns each frame's
-- offset from the kit's centre, the divider's spot { x, y, len, vertical }
-- (or nil), and how long the longest column is (along the edge).
-- Left and right edges run their columns top to bottom; top and bottom
-- edges run their rows left to right.
local EDGE_VEC = { left = { 1, 0, 0, -1 }, right = { -1, 0, 0, -1 }, top = { 0, -1, 1, 0 }, bottom = { 0, 1, 1, 0 } }
function D.EdgeArrange(side, half, cols, divAfter)
    local v = EDGE_VEC[side] or EDGE_VEC.left
    local GAP, COLGAP = 6, 10
    local pos, cur, ext, divOut = {}, half + 10, 0, nil
    for ci, col in ipairs(cols) do
        if #col > 0 then
            local w, L = 0, -GAP
            for _, it in ipairs(col) do w = math.max(w, it.size) L = L + it.size + GAP end
            local mid, a = cur + w / 2, -L / 2
            for _, it in ipairs(col) do
                local m = a + it.size / 2
                pos[it.frame] = { v[1] * mid + v[3] * m, v[2] * mid + v[4] * m }
                a = a + it.size + GAP
            end
            ext = math.max(ext, L)
            cur = cur + w + COLGAP
            if divAfter == ci then
                divOut = cur + 1
                cur = cur + 12
            end
        end
    end
    local div
    if divOut and cur > divOut + 12 then -- only between two columns that are there
        div = { v[1] * divOut, v[2] * divOut, ext + 16, side == "left" or side == "right" }
    end
    return pos, div, ext
end

local EDGE_REACH = 70 -- a kit's centre this close (UI units) to a screen edge snaps it there
local EDGE_INSET = 4  -- gap between the screen edge and the kit button

local function Screen() return UIParent:GetWidth(), UIParent:GetHeight() end
local function AlongLen(side)
    local W, H = Screen()
    return (side == "left" or side == "right") and H or W
end
local function AlongOf(side, x, y)
    local W, H = Screen()
    if side == "left" or side == "right" then return H - y end
    return x
end
-- The kit button's half-size on screen at its own (not docked) size.
local function KitHalf(api)
    local kit = api.kit
    local base = api.BaseScale and api.BaseScale() or kit:GetScale()
    return kit:GetWidth() * base * (kit:GetEffectiveScale() / kit:GetScale()) / UIParent:GetEffectiveScale() / 2
end
-- Where a kit's centre goes for a spot along an edge (UI units).
local function EdgePos(side, half, a)
    local W, H = Screen()
    local d = EDGE_INSET + half
    if side == "left" then return d, H - a end
    if side == "right" then return W - d, H - a end
    if side == "top" then return a, H - d end
    return a, d
end
-- The edge a point is close enough to snap to, if any.
local function NearEdge(x, y)
    local W, H = Screen()
    local best, bd = nil, EDGE_REACH
    for side, d in pairs({ left = x, right = W - x, top = H - y, bottom = y }) do
        if d < bd then best, bd = side, d end
    end
    return best
end
-- How much room along the edge a kit takes (its strip closed, its columns
-- open), from the kit, or just its button.
local function EdgeExt(key, side, open)
    local api = D.kits[key]
    local e = api.EdgeExtent and api.EdgeExtent(side, open)
    return math.max(e or 0, KitHalf(api) * 2)
end
-- Where an edge entry's kits sit along the edge (their middles), kept on
-- screen with what's showing (open, or closed with whatever's pinned) --
-- that nudge is only for now, not saved. Also returns the span they take.
-- An entry saves its kit's middle (at), so pinning or unpinning a slot
-- grows or shrinks the strip around the kit without moving it. Entries
-- saved before that (start: where the first kit's strip began, possibly
-- several kits in a row) are worked out the old way.
local function GroupCenters(g, openKey)
    local c, ext, keys = {}, {}, {}
    for _, k in ipairs(g.keys) do if D.kits[k] and Shown(k) then keys[#keys + 1] = k end end
    if #keys == 0 then
        local a = g.at or g.start or 0
        return c, a, a, keys
    end
    if g.at then
        for _, k in ipairs(keys) do c[k] = g.at end
    else
        local a = g.start or 0
        for _, k in ipairs(keys) do
            local e = EdgeExt(k, g.side, false)
            c[k] = a + e / 2
            a = a + e
        end
    end
    for _, k in ipairs(keys) do ext[k] = EdgeExt(k, g.side, k == openKey) end
    local lo, hi = math.huge, -math.huge
    for _, k in ipairs(keys) do
        lo = math.min(lo, c[k] - ext[k] / 2)
        hi = math.max(hi, c[k] + ext[k] / 2)
    end
    local L, M = AlongLen(g.side), 8
    local sh = hi > L - M and (L - M) - hi or 0
    if lo + sh < M then sh = M - lo end
    for _, k in ipairs(keys) do c[k] = c[k] + sh end
    return c, lo + sh, hi + sh, keys
end

-- Take a kit off its edge.
local function LeaveEdge(key)
    local g, i = EdgeOf(key)
    if not g then return end
    table.remove(g.keys, i)
    if #g.keys == 0 then
        local groups = Edges()
        table.remove(groups, InList(groups, g))
    end
end

-- Put a kit on an edge at (x, y), right there, on its own. Kits on an edge
-- don't merge: dropped on or next to another, it just sits there too.
local function JoinEdge(key, side, x, y)
    LeaveEdge(key)
    DB().docked[key] = false
    local a = AlongOf(side, x, y)
    local ext = EdgeExt(key, side, false)
    local L = AlongLen(side)
    table.insert(Edges(), { side = side, at = math.max(8 + ext / 2, math.min(L - 8 - ext / 2, a)), keys = { key } })
end

-- Older saved entries: several kits sharing a spot are split up, and a
-- saved strip start becomes the kit's middle, each kit staying where it was.
local function SplitEdges()
    local groups = Edges()
    for gi = #groups, 1, -1 do
        local g = groups[gi]
        if #g.keys > 1 or not g.at then
            local c = GroupCenters(g, nil)
            -- (only kits loaded and showing have a spot worked out; wait for the rest)
            local ready = true
            for _, k in ipairs(g.keys) do if not c[k] then ready = false end end
            if ready then
                table.remove(groups, gi)
                for _, k in ipairs(g.keys) do
                    table.insert(groups, { side = g.side, at = c[k], keys = { k } })
                end
            end
        end
    end
end

-- A kit on an edge on its own tucks half off the screen until the mouse
-- goes over it, or while it's open. D.edgeState[key]: where it is along its
-- edge (c), how far it's slid out from its full spot (off, UI units: 0 is
-- all the way out), and its hover timing. Only out of combat: in combat it
-- stays as it was.
D.edgeState = D.edgeState or {}
local OUTWARD = { left = { -1, 0 }, right = { 1, 0 }, top = { 0, 1 }, bottom = { 0, -1 } }

-- How far a kit slides to tuck: its centre ends up on the screen's edge.
local function TuckDist(api) return EDGE_INSET + KitHalf(api) end

local function EdgeState(key)
    local st = D.edgeState[key]
    if not st then
        st = {}
        D.edgeState[key] = st
    end
    return st
end

-- Put an edge kit where its state says (its spot, slid out by off).
local function EdgeSet(api, st)
    local kit = api.kit
    local x, y = EdgePos(st.side, KitHalf(api), st.c)
    local o = OUTWARD[st.side] or OUTWARD.left
    x, y = x + o[1] * st.off, y + o[2] * st.off
    local s = kit:GetEffectiveScale() / UIParent:GetEffectiveScale()
    kit:ClearAllPoints()
    kit:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
end

-- A kit half off the screen can't be clamped to it: kits on an edge or in a
-- box let go of the clamp, the rest keep it.
local function SetClamp(api, on)
    local kit = api.kit
    if kit.SetClampedToScreen and kit.IsClampedToScreen and kit:IsClampedToScreen() ~= on then
        kit:SetClampedToScreen(on)
    end
end

local function EdgeTick(_, dt)
    if InCombatLockdown() then return end
    local now = GetTime()
    for _, g in ipairs(Edges()) do
        local k = g.keys[1]
        local api = k and D.kits[k]
        local st = k and D.edgeState[k]
        if api and st and st.c and st.side == g.side and Shown(k) and k ~= D.skip
            and not (D.dragging and D.dragging.key == k) and api.kit:IsShown() then
            local kit = api.kit
            local want = api.IsOpen() or (kit.IsMouseOver and kit:IsMouseOver(14, -14, -14, 14))
                or (st.hold and now < st.hold)
            if want then
                st.linger = 0
                st.out = true
            else
                st.linger = (st.linger or 0) + dt
                if st.linger >= PARK_LINGER then st.out = false end
            end
            local full = TuckDist(api)
            local target = st.out and 0 or full
            if st.off ~= target and not tweens[kit] then
                local step = dt / PARK_SLIDE * full
                if st.off < target then st.off = math.min(target, st.off + step) else st.off = math.max(target, st.off - step) end
                EdgeSet(api, st)
            end
        end
    end
end
local edgeTicker = D.edgeTicker or CreateFrame("Frame")
D.edgeTicker = edgeTicker
edgeTicker:SetScript("OnUpdate", EdgeTick)

D.NearEdge = NearEdge

-- While a kit (or the pin) is dragged within reach of a screen edge, a
-- short stretch of that edge lights up where it would land: a bright gold
-- line on the edge itself, fading out at the ends. It follows along as you
-- drag. EdgeGlow(nil) clears it.
local GLOW_LEN = 180  -- how long the lit stretch is
local GLOW_CAP = 50   -- of that, how much fades out at each end
local GLOW_THICK = 3
local LINE_A = 0.95
local function Fade(t, vertical, fromA, toA)
    local r, g, b = 1, 0.82, 0.2
    if CreateColor and pcall(t.SetGradient, t, vertical and "VERTICAL" or "HORIZONTAL",
        CreateColor(r, g, b, fromA), CreateColor(r, g, b, toA)) then
        return
    end
    if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, vertical and "VERTICAL" or "HORIZONTAL",
        r, g, b, fromA, r, g, b, toA) then
        return
    end
    t:SetColorTexture(r, g, b, (fromA + toA) / 2) -- no gradients here: a plain, dimmer end
end
local function GlowTex(f)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetBlendMode("ADD")
    return t
end
-- The line in three parts along the edge: a middle at full strength and
-- two ends fading out (HORIZONTAL gradients run left to right, VERTICAL
-- bottom to top).
local function ShapeGlow(f, side)
    local vert = side == "left" or side == "right" -- the edge runs up and down
    f:SetSize(vert and GLOW_THICK or GLOW_LEN, vert and GLOW_LEN or GLOW_THICK)
    for _, t in ipairs(f.pieces) do t:ClearAllPoints() end
    local lo, hi = vert and "BOTTOM" or "LEFT", vert and "TOP" or "RIGHT"
    local function Along(d) return vert and 0 or d, vert and d or 0 end
    local function Span(t, relA, offA, relB, offB)
        t:SetPoint(lo, f, relA, Along(offA))
        t:SetPoint(hi, f, relB, Along(offB))
        if vert then t:SetWidth(GLOW_THICK) else t:SetHeight(GLOW_THICK) end
    end
    Span(f.line, lo, GLOW_CAP, hi, -GLOW_CAP)
    f.line:SetColorTexture(1, 0.82, 0.2, LINE_A)
    Span(f.lineLo, lo, 0, lo, GLOW_CAP)
    Span(f.lineHi, hi, -GLOW_CAP, hi, 0)
    Fade(f.lineLo, vert, 0, LINE_A)
    Fade(f.lineHi, vert, LINE_A, 0)
end
function D.EdgeGlow(side, x, y)
    local f = D.glow
    if not side or not x then
        if f then f:Hide() end
        return
    end
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("HIGH")
        f:EnableMouse(false)
        f.line, f.lineLo, f.lineHi = GlowTex(f), GlowTex(f), GlowTex(f)
        f.pieces = { f.line, f.lineLo, f.lineHi }
        D.glow = f
    end
    if f.side ~= side then
        f.side = side
        ShapeGlow(f, side)
    end
    -- Centred on the kit along the edge, kept on screen.
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local half = GLOW_LEN / 2
    local cx, cy
    if side == "left" or side == "right" then
        cx = side == "left" and GLOW_THICK / 2 or W - GLOW_THICK / 2
        cy = math.min(math.max(y, half), H - half)
    else
        cy = side == "bottom" and GLOW_THICK / 2 or H - GLOW_THICK / 2
        cx = math.min(math.max(x, half), W - half)
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    f:Show()
end

---------------------------------------------------------------------------
-- Tuck boxes: kits parked until they're needed. Each is a small box on a
-- screen edge, tucked half off the screen; the mouse over it (or a kit open
-- from it, or a kit, a box or the pin dragged to it) slides it out. It moves
-- the kits in it along with it, so like the pin it only moves out of combat.
--   D.boxFrames  the frames that draw the boxes (f.box: the saved box)
--   D.hover      { box, extra } while something is dragged over a box
--   D.ghost      { n } while the open kit carrying the dock is at an edge:
--                the box it would make there (drawn by D.ghostFrame)
--   D.dragBox    the box whose grip is being dragged
---------------------------------------------------------------------------

D.boxFrames = D.boxFrames or {}

local function TopWidth(n)
    n = math.max(n, 1)
    return PARK_PAD * 2 + n * PARK_SIZE + (n - 1) * PARK_GAP
end

local function Over(f)
    if f.IsMouseOver then return f:IsMouseOver() end
    return MouseIsOver and MouseIsOver(f) or false
end

local function Vert(side) return side == "left" or side == "right" end

-- A box's length for n kits: just the row (the grip sits on its corner).
local function BoxLong(n) return TopWidth(n) end

-- Its middle along its side for n kits, kept on screen.
local function BoxAlong(side, at, n)
    local L = AlongLen(side)
    local half = BoxLong(n) / 2
    return math.max(half + 8, math.min(L - half - 8, at or L / 2))
end

-- How far into the screen a point is from a side.
local function Depth(side, x, y)
    local W, H = Screen()
    if side == "left" then return x end
    if side == "right" then return W - x end
    if side == "top" then return H - y end
    return y
end

-- The nearest side to a point (a box always goes on one).
local function NearestSide(x, y)
    local best, bd
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local d = Depth(side, x, y)
        if not bd or d < bd then best, bd = side, d end
    end
    return best
end

-- A box's colours; lit (gold) while something is dragged to it.
local function TopLook(f, lit)
    if f.lit == lit then return end
    f.lit = lit
    if f.SetBackdropColor then
        f:SetBackdropColor(0.05, 0.06, 0.08, 0.84)
        if lit then f:SetBackdropBorderColor(1, 0.82, 0.2, 1) else f:SetBackdropBorderColor(0.48, 0.39, 0.19, 1) end
    end
end

-- Where a frame's box shows right now: where its grip is being dragged, or
-- its own place.
local function BoxNow(f)
    local p = f.preview or f.box
    return p.side, p.at
end

-- How many kits a box is drawn for: those in it, plus any dragged over it.
local function BoxCount(f)
    if f.ghost then return D.ghost and D.ghost.n or 1 end
    local n = #BoxKeys(f.box)
    if D.hover and D.hover.box == f.box then n = n + (D.hover.extra or 0) end
    return n
end

-- Puts a box on its side for f.n kits, its outer edge f.off past the
-- screen's edge (positive: off screen).
local function BoxPoint(f)
    local side, at = BoxNow(f)
    local n = f.n or 1
    local a = BoxAlong(side, at, n)
    local key = side .. a .. ":" .. n .. ":" .. f.off
    if f.drawn == key then return end
    f.drawn = key
    local long = BoxLong(n)
    if Vert(side) then f:SetSize(PARK_H, long) else f:SetSize(long, PARK_H) end
    if f.grip then
        -- On the box's inner edge at its start end (the left, or the top on
        -- the sides), just inside the border: clear of the kits (the first
        -- kit's round rim leaves the corner free), and the mouse is still
        -- over the box while it's on the grip, so the box doesn't slide away.
        local IN, END = 5, 7
        local x, y
        if Vert(side) then
            x, y = (side == "left" and 1 or -1) * (PARK_H / 2 - IN), long / 2 - END
        else
            x, y = -(long / 2 - END), (side == "top" and -1 or 1) * (PARK_H / 2 - IN)
        end
        f.grip:ClearAllPoints()
        f.grip:SetPoint("CENTER", f, "CENTER", x, y)
    end
    local off = f.off
    f:ClearAllPoints()
    if side == "top" then f:SetPoint("TOP", UIParent, "TOPLEFT", a, off)
    elseif side == "bottom" then f:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", a, -off)
    elseif side == "left" then f:SetPoint("LEFT", UIParent, "TOPLEFT", -off, -a)
    else f:SetPoint("RIGHT", UIParent, "TOPRIGHT", off, -a) end
end

-- Any kit in this box open (stepped out beside it).
local function BoxOpen(b)
    for _, k in ipairs(BoxKeys(b)) do
        if D.kits[k].IsOpen() then return true end
    end
    return false
end

-- The box under a point (UI units), with room to spare, for dropping onto.
-- except: a box to leave out (the one being dragged). extra: kits it would
-- gain (it grows toward them).
local function BoxAt(cx, cy, except, extra)
    for _, b in ipairs(Boxes()) do
        if b ~= except then
            local n = #BoxKeys(b)
            if n > 0 then
                local m = n + (extra or 0)
                local a = BoxAlong(b.side, b.at, m)
                if math.abs(AlongOf(b.side, cx, cy) - a) <= BoxLong(m) / 2 + 50
                    and Depth(b.side, cx, cy) <= PARK_H + 60 then
                    return b
                end
            end
        end
    end
end

-- A kit on an edge on its own near a point: dropping there makes a box.
-- centers: where the kits were when a drag began (else where they are).
local function EdgeKitAt(key, cx, cy, centers)
    local best, bd
    for _, g in ipairs(Edges()) do
        local k = g.keys[1]
        if k and k ~= key and D.kits[k] and Shown(k) then
            local x, y
            if centers and centers[k] then x, y = centers[k][1], centers[k][2] else x, y = Center(D.kits[k].kit) end
            if x then
                local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
                if d < SNAP and (not bd or d < bd) then best, bd = k, d end
            end
        end
    end
    return best
end

-- Which place in box b a kit dropped at (x, y) would take.
local function ParkIndexAt(b, key, cx, cy)
    local others = 0
    for _, k in ipairs(BoxKeys(b)) do if k ~= key then others = others + 1 end end
    local m = others + 1
    local lo = BoxAlong(b.side, b.at, m) - BoxLong(m) / 2
    local i = math.floor((AlongOf(b.side, cx, cy) - lo - PARK_PAD + (PARK_SIZE + PARK_GAP) / 2) / (PARK_SIZE + PARK_GAP)) + 1
    return math.max(1, math.min(m, i))
end

-- Boxes tidied after any change: a kit listed twice keeps its first place, an
-- empty box goes, and a box down to one kit becomes that kit on the edge on
-- its own, where the box was. (Not the box whose grip is being dragged: it
-- stays until it's let go.)
local function Normalize()
    local boxes = Boxes()
    for i = #boxes, 1, -1 do
        local b = boxes[i]
        local seen, keys = {}, {}
        for _, k in ipairs(b.keys) do
            if not seen[k] then seen[k] = true keys[#keys + 1] = k end
        end
        b.keys = keys
        if b ~= D.dragBox then
            if #keys == 0 then
                table.remove(boxes, i)
            elseif #keys == 1 then
                table.remove(boxes, i)
                local k = keys[1]
                LeaveEdge(k)
                DB().docked[k] = false
                table.insert(Edges(), { side = b.side, at = b.at or AlongLen(b.side) / 2, keys = { k } })
            end
        end
    end
end
D.Normalize = Normalize

-- Slides a box out or in. Nothing moves in combat: it stays as it was.
local function TopTick(f, dt)
    if InCombatLockdown() or not f:IsShown() then return end
    if f.ghost and not D.ghost then f:Hide() return end
    -- Dragging a box by its grip: it follows the cursor round the screen
    -- edges, and over another box it lights that one up (let go to merge).
    -- Pulled away from the edges, the grip becomes the pin: the kits that
    -- can go on the pin come out onto it under the cursor.
    if f.dragging then
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = x / s, y / s
        local side = NearestSide(x, y)
        local away = Depth(side, x, y) > EDGE_REACH
        if away and (f.toPin or D.BoxPinKeys(f.box)[1]) then
            if not f.toPin then D.BoxToPin(f, true, x, y) end
            D.MoveFreed(f, x, y)
            D.hover = nil
        else
            local was = f.preview and f.preview.side or f.box.side
            f.preview = { side = side, at = AlongOf(side, x, y) }
            -- (the box is already where the cursor is when its kits go back
            -- in, so they glide there, not to where it started)
            if f.toPin then D.BoxToPin(f, false) was = side end
            local other = BoxAt(x, y, f.box, #BoxKeys(f.box))
            D.hover = other and { box = other, extra = #BoxKeys(f.box) } or nil
            if was ~= side then D.Layout() end -- the row turns with the side
        end
    end
    -- Its kits all pulled out onto the pin: the box goes (it's gone for good
    -- on letting go; dragging back to an edge brings it back).
    if not f.ghost then
        local gone = f.toPin and #BoxKeys(f.box) == 0
        f:SetAlpha(gone and 0 or 1)
    end
    local hovered = D.hover and D.hover.box == f.box
    local want = f.ghost or Over(f) or (f.grip and Over(f.grip)) or hovered or f.dragging or BoxOpen(f.box)
    if not want and f.hold and GetTime() < f.hold then want = true end
    if want then
        f.linger = 0
        f.out = true
    else
        f.linger = (f.linger or 0) + dt
        if f.linger >= PARK_LINGER then f.out = false end
    end
    local target = f.out and PARK_SHOW or PARK_TUCK
    if f.off ~= target then
        local step = dt / PARK_SLIDE * (PARK_TUCK - PARK_SHOW)
        if f.off < target then f.off = math.min(target, f.off + step) else f.off = math.max(target, f.off - step) end
    end
    f.n = math.max(1, BoxCount(f))
    BoxPoint(f)
    TopLook(f, (f.ghost or hovered or f.dragging) and true or false)
end

local BoxDrop -- (below)

local function NewBoxFrame(ghost)
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "BackdropTemplate")
    if not ok or not f then f = CreateFrame("Frame", nil, UIParent) end
    f:SetFrameStrata("LOW") -- under the kits (and the pin), over the world
    f:SetFrameLevel(10)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.06, 0.08, 0.84)
    end
    f.off = PARK_TUCK
    f.n = 1
    if ghost then
        -- Where the open kit carrying the dock would make a box: just drawn.
        f.ghost = true
        f.box = { side = "top", keys = {} }
        f.off = PARK_SHOW
        f:EnableMouse(false)
    else
        -- Drag the box (by its grip, or its edges) to move it anywhere along
        -- any screen edge; the kits in it come along.
        local function DragStart()
            if InCombatLockdown() or not f.box then return end
            f.dragging = true
            D.dragBox = f.box
        end
        local function DragStop() BoxDrop(f) end
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", DragStart)
        f:SetScript("OnDragStop", DragStop)
        -- The grip: the same gold stud as the pin, glowing under the mouse.
        local g = CreateFrame("Button", nil, f)
        g:SetSize(GRIP_SMALL, GRIP_SMALL)
        if g.SetHitRectInsets then g:SetHitRectInsets(-3, -3, -3, -3) end -- (easier to catch than it looks)
        g:SetFrameStrata("MEDIUM") -- (over the kits in the box, where it meets the middle one's rim)
        g:SetFrameLevel(40)
        g:RegisterForDrag("LeftButton")
        g.tex = g:CreateTexture(nil, "ARTWORK")
        g.tex:SetAllPoints()
        g.tex:SetTexture(D.media .. "pin_dot", nil, nil, "LINEAR")
        g.hl = g:CreateTexture(nil, "HIGHLIGHT")
        g.hl:SetTexture(D.media .. "glow_ring")
        g.hl:SetBlendMode("ADD")
        g.hl:SetPoint("CENTER")
        g.hl:SetSize(GRIP_BIG * 1.5, GRIP_BIG * 1.5)
        g:SetScript("OnDragStart", DragStart)
        g:SetScript("OnDragStop", DragStop)
        g:SetScript("OnEnter", function(self)
            self:SetSize(GRIP_BIG, GRIP_BIG)
            if SetCursor then pcall(SetCursor, "UI_MOVE_CURSOR") end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Move the kit box")
            GameTooltip:AddLine("Drag along any edge of the screen. Drop it on another box to merge them; drag it away from the edge to put its kits back on the pin.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        g:SetScript("OnLeave", function(self)
            if not f.dragging then self:SetSize(GRIP_SMALL, GRIP_SMALL) end
            if ResetCursor then pcall(ResetCursor) end
            GameTooltip:Hide()
        end)
        f.grip = g
        D.boxFrames[#D.boxFrames + 1] = f
    end
    f.drawn = nil
    f:SetScript("OnUpdate", TopTick)
    f:Hide()
    return f
end

-- Something dragged over a box (or off it: nil): it comes out, lit, with
-- room for `extra` more kits.
function D.Hover(box, extra)
    if box then
        if not (D.hover and D.hover.box == box and D.hover.extra == extra) then
            D.hover = { box = box, extra = extra or 0 }
        end
    else
        D.hover = nil
    end
end

-- The open kit carrying the dock at a screen edge (nil: not): the box it
-- would make there shows, lit, sized for n kits.
function D.Ghost(side, x, y, n)
    if side then
        local g = D.ghostFrame or NewBoxFrame(true)
        D.ghostFrame = g
        g.box.side, g.box.at = side, AlongOf(side, x, y)
        D.ghost = { n = n or 1 }
        g:Show()
    else
        D.ghost = nil
        if D.ghostFrame then D.ghostFrame:Hide() end
    end
end

-- The kits in box b that can go on the pin (not edges-only ones).
function D.BoxPinKeys(b)
    local keys = {}
    for _, k in ipairs(BoxKeys(b)) do if not EdgesOnly(k) then keys[#keys + 1] = k end end
    return keys
end

-- A box's grip pulled away from the edges (on), or back to them (off): the
-- kits that can go on the pin come out of the box onto it, at (x, y), or go
-- back in. What they were is kept so dragging back undoes it.
function D.BoxToPin(f, on, x, y)
    local db = DB()
    local b = f.box
    if on then
        local keys = D.BoxPinKeys(b)
        local undo = { boxKeys = { unpack(b.keys) }, docked = {}, keys = keys,
            pin = db.pin and { db.pin[1], db.pin[2] } or nil }
        for _, k in ipairs(keys) do undo.docked[k] = db.docked[k] end
        local keep = {}
        for _, k in ipairs(b.keys) do if not InList(keys, k) then keep[#keep + 1] = k end end
        b.keys = keep
        for _, k in ipairs(keys) do db.docked[k] = true end
        f.toPin = undo
        Pin()
        SetPinAt(x, y)
        D.Layout()
    elseif f.toPin then
        local undo = f.toPin
        f.toPin = nil
        b.keys = undo.boxKeys
        for _, k in ipairs(undo.keys) do db.docked[k] = undo.docked[k] end
        db.pin = undo.pin
        f.drawn = nil
        BoxPoint(f) -- (where it's being dragged to now, before its kits are laid out in it)
        D.Layout()
    end
end

-- Keeps what came out of a box under the cursor: the pin, or a lone kit
-- (a pin can't be one kit, so one kit just floats).
function D.MoveFreed(f, x, y)
    local u = f.toPin
    if not u then return end
    if PinDocked(u.keys[1]) then
        SetPinAt(x, y)
    else
        for _, k in ipairs(u.keys) do
            local kit = D.kits[k] and D.kits[k].kit
            if kit and not PinDocked(k) then
                StopTween(kit)
                local s = kit:GetEffectiveScale() / UIParent:GetEffectiveScale()
                kit:ClearAllPoints()
                kit:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
            end
        end
    end
end

-- Let go away from the edges: what came out stays out, the pin (or a lone
-- kit) right where it was dropped.
function D.FreedDrop(f)
    local u = f.toPin
    f.toPin = nil
    if not u then return end
    if PinDocked(u.keys[1]) then
        SavePin()
    else
        for _, k in ipairs(u.keys) do
            local api = D.kits[k]
            if api then
                DB().docked[k] = false
                api.SaveFree()
            end
        end
    end
end

-- A box's grip let go: off the edges its kits stay on the pin; on another
-- box the two merge; on a kit alone on an edge, that kit joins the box;
-- anywhere else along an edge, the box moves there.
BoxDrop = function(f)
    if not f.dragging then return end
    f.dragging = nil
    if f.grip and not Over(f.grip) then f.grip:SetSize(GRIP_SMALL, GRIP_SMALL) end
    D.dragBox = nil
    D.hover = nil
    local b, p = f.box, f.preview
    f.preview = nil
    if f.toPin then
        D.FreedDrop(f)
    elseif p and b then
        local s = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x, y = x / s, y / s
        local other = BoxAt(x, y, b, #BoxKeys(b))
        local ek = not other and EdgeKitAt(nil, x, y)
        if other then
            for _, k in ipairs(b.keys) do
                if not InList(other.keys, k) then other.keys[#other.keys + 1] = k end
            end
            b.keys = {}
            for _, g in ipairs(D.boxFrames) do
                if g.box == other then g.hold = GetTime() + 1.5 end
            end
        else
            b.side, b.at = p.side, p.at
            if ek then
                LeaveEdge(ek)
                b.keys[#b.keys + 1] = ek
            end
            f.hold = GetTime() + 1.5
        end
    end
    Normalize()
    if not InCombatLockdown() then D.Layout() end
end

-- Which way a kit without Park is fanned so its slots go off the screen.
local FAN = { top = 90, bottom = 270, left = 180, right = 0 }

-- A kit in a box: a small button. A kit that knows about parking (Park)
-- does the rest itself; one that doesn't is fanned toward the box's edge,
-- which sends its slots off the screen.
local function SetParked(api, on, side)
    local kit = api.kit
    local w = kit:GetWidth()
    local scale = (w and w > 0) and (PARK_SIZE / w) or 0.5
    if math.abs(kit:GetScale() - scale) > 0.001 then kit:SetScale(scale) end
    if api.parked == side then return end
    api.parked = side
    if api.Park then
        api.Park(true)
    elseif api.Compact then
        api.compact, api.compactAngle, api.compactSpan = true, FAN[side] or 90, 30
        api.Compact(true, FAN[side] or 90, 30)
    end
end

-- Back out of a box. (Without Park, the layout's SetCompact(false) undoes
-- the fanning.)
local function ClearParked(api)
    if api.quiet then
        api.quiet = false
        if api.Quiet then api.Quiet(false) end
    end
    if not api.parked then return end
    api.parked = nil
    if api.Park then api.Park(false) end
end

-- While a kit from a box is open, the others in it keep their pinned slots
-- and reminders out of the way (each kit hides them itself, sliding them
-- back in, so a refresh doesn't bring them back for a moment).
local function SetQuiet(api, on)
    on = on and true or false
    if (api.quiet or false) == on then return end
    api.quiet = on
    if api.Quiet then api.Quiet(on) end
end

-- One box's kits in a row along it, each gliding from where it was. A kit
-- opened from the box stays in it, small, and opens where it is: its slots
-- slide out of it toward the middle of the screen, so it closes again from
-- the same spot.
local function LayoutBoxKits(f, keys, before)
    local side = BoxNow(f)
    local n = #keys
    local anyOpen = false
    for _, k in ipairs(keys) do if D.kits[k].IsOpen() then anyOpen = true end end
    for i, k in ipairs(keys) do
        local api = D.kits[k]
        local kit = api.kit
        if k ~= D.skip then -- (not the one under the cursor)
            StopTween(kit)
            if api.BeginMove then api.BeginMove() end
            local d = (i - (n + 1) / 2) * (PARK_SIZE + PARK_GAP)
            local ax, ay = d, 0
            if Vert(side) then ax, ay = 0, -d end -- top to bottom down the side
            api.boxAt = { ax, ay } -- (UI units from the box's middle, for its row)
            SetClamp(api, false)
            SetParked(api, true, side)
            SetEdge(api, side)
            local ks = kit:GetScale()
            kit:ClearAllPoints()
            kit:SetPoint("CENTER", f, "CENTER", ax / ks, ay / ks)
            api.Tuck(false)
            local b = before[k]
            if b then KitGlide(kit, b[1], b[2], b[3]) end
            if api.EndMove then api.EndMove() end
            SetQuiet(api, anyOpen and not api.IsOpen())
        end
    end
    if anyOpen then f.off, f.out, f.linger = PARK_SHOW, true, 0 end -- (out while a kit is open from it)
    -- The open kit has a still gold glow round it in the box (the glow art,
    -- not animated).
    local hl = f.openHL
    if anyOpen and not hl then
        hl = f:CreateTexture(nil, "ARTWORK")
        hl:SetTexture(D.media .. "glow_ring")
        hl:SetBlendMode("ADD")
        hl:SetVertexColor(1, 0.82, 0.35)
        f.openHL = hl
    end
    if hl then
        local at
        for _, k in ipairs(keys) do
            if D.kits[k].IsOpen() then at = D.kits[k].boxAt end
        end
        if at then
            hl:SetSize(PARK_SIZE * 1.6, PARK_SIZE * 1.6)
            hl:ClearAllPoints()
            hl:SetPoint("CENTER", f, "CENTER", at[1], at[2])
            hl:Show()
        else
            hl:Hide()
        end
    end
end

-- What each boxed kit shows while closed (reminders, pinned slots), handed
-- over by the kit (Kit Core's PlaceSlots): D.notices[key] = { frame, ... }.
D.notices = D.notices or {}

-- A box's row of reminders: everything its closed kits show, side by side
-- in one line just inside the box, in the kits' order. While a kit from the
-- box is open, they all hide (fr.quiet), and come back when it closes.
-- The box's separators and kit glyphs (pooled on its frame).
-- (on a frame of their own over the box, so they fade together)
local function DecorFrame(fr)
    if not fr.decor then
        fr.decor = CreateFrame("Frame", nil, fr)
        fr.decor:SetAllPoints(fr)
        fr.decor:SetFrameLevel(fr:GetFrameLevel() + 2)
    end
    return fr.decor
end

local function Decor(fr, kind, i)
    fr[kind] = fr[kind] or {}
    local t = fr[kind][i]
    if not t then
        t = DecorFrame(fr):CreateTexture(nil, "OVERLAY")
        if kind == "seps" then t:SetColorTexture(0.66, 0.53, 0.24, 0.9) end
        fr[kind][i] = t
    end
    return t
end

local function HideDecor(fr, kind, from)
    for i = from, #(fr[kind] or {}) do fr[kind][i]:Hide() end
end

local function RelayNotices(fr)
    local b = fr.box
    if not b then return end
    local side = BoxNow(fr)
    -- One group per kit with something to show, in the box's order.
    local groups, all = {}, {}
    for _, k in ipairs(BoxKeys(b)) do
        local api = D.kits[k]
        local list = D.notices[k]
        if list and api.parked and not api.IsOpen() then
            local items = {}
            for _, f in ipairs(list) do
                if f:IsShown() and not InList(all, f) then
                    items[#items + 1] = f
                    all[#all + 1] = f
                end
            end
            if #items > 0 then groups[#groups + 1] = { key = k, api = api, items = items } end
        end
    end
    local function Frozen(f) return InCombatLockdown() and f.IsProtected and f:IsProtected() end
    -- Fade out (then hide), once, or at once in a fight.
    local function FadeOut(f)
        if f.boxFade == "out" then return end
        if InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) then
            f:Hide()
            return
        end
        f.boxFade = "out"
        D.Fade(f, true, function()
            f.boxFade = nil
            if not InCombatLockdown() then f:Hide() end
        end)
    end
    if BoxOpen(b) then
        -- A kit from the box is open: its rules and kit icons fade away (the
        -- kits put their own pinned slots and reminders away, see SetQuiet).
        if fr.decor and fr.decor:IsShown() then FadeOut(fr.decor) end
        fr.quiet = true
        return
    end
    local decor = DecorFrame(fr)
    if decor.boxFade == "out" then
        decor.boxFade = nil
        D.Fade(decor, false)
    elseif fr.fadeStamp and decor.boxFadeStamp ~= fr.fadeStamp then
        decor.boxFadeStamp = fr.fadeStamp
        if not decor:IsShown() then
            decor:Show()
            D.Fade(decor, false)
        end
    end
    decor:Show()
    -- Each kit's block: a head column with a small copy of the kit's icon and,
    -- under it, the kit's small buttons (buff timers, gear swap, pet spells);
    -- beside it the regular slots, NOTE_COLS along the edge and as many rows
    -- inward as they need. A thin gold rule between kits; the blocks together
    -- are centred on the box.
    local ui = UIParent:GetEffectiveScale()
    local o = OUTWARD[side] or OUTWARD.top
    local inner = PARK_H / 2 + NOTE_GAP -- (from the box's middle to the first row)
    local function Size(f) return f:GetWidth() * f:GetEffectiveScale() / ui end
    -- Small: a slot the kit marks small, or a kit's own extra (a timer), not a slot.
    local function Small(f) return f.isSmall or f.slot == nil end
    local deepest, total = 0, 0
    for gi, g in ipairs(groups) do
        g.smalls, g.bigs = {}, {}
        for _, f in ipairs(g.items) do
            if Small(f) then g.smalls[#g.smalls + 1] = f else g.bigs[#g.bigs + 1] = f end
        end
        local hw, hd = GLYPH, GLYPH
        for _, f in ipairs(g.smalls) do
            local w = Size(f)
            hw = math.max(hw, w)
            hd = hd + NOTE_GAP + w
        end
        local w = 0
        for _, f in ipairs(g.bigs) do w = math.max(w, Size(f)) end
        local cols = math.min(NOTE_COLS, #g.bigs)
        local rows = math.ceil(#g.bigs / NOTE_COLS)
        g.hw, g.w = hw, w
        g.len = hw + (cols > 0 and (NOTE_GAP + cols * w + (cols - 1) * NOTE_GAP) or 0)
        deepest = math.max(deepest, hd, rows > 0 and (rows * w + (rows - 1) * NOTE_GAP) or 0)
        total = total + g.len + (gi > 1 and (SEP_PAD * 2 + 1) or 0)
    end
    local function Spot(along, depth) -- (UI units from the box's middle)
        if Vert(side) then return -o[1] * depth, -along end
        return along, -o[2] * depth
    end
    -- Hung on its own kit (so it slides back into it, and goes along with it),
    -- at its spot in the row.
    local function Put(g, f, along, depth)
        if Frozen(f) then return end
        local x, y = Spot(along, depth)
        local at = g.api.boxAt or { 0, 0 }
        local sc = f:GetEffectiveScale() / ui
        local px, py = (x - at[1]) / sc, (y - at[2]) / sc
        StopTween(f)
        f:ClearAllPoints()
        f:SetPoint("CENTER", g.api.kit, "CENTER", px, py)
        f.placedX, f.placedY = px, py
    end
    local a = -total / 2
    for gi, g in ipairs(groups) do
        if gi > 1 then
            -- The rule between this kit and the one before.
            local t = Decor(fr, "seps", gi - 1)
            local x, y = Spot(a + SEP_PAD + 0.5, inner + deepest / 2)
            t:ClearAllPoints()
            t:SetPoint("CENTER", fr, "CENTER", x, y)
            if Vert(side) then t:SetSize(deepest, 1) else t:SetSize(1, deepest) end
            t:Show()
            a = a + SEP_PAD * 2 + 1
        end
        -- The head: the kit's glyph, then its small buttons, one under another.
        local mid = a + g.hw / 2
        local gl = Decor(fr, "glyphs", gi)
        local art = g.api.kit.icon and g.api.kit.icon.GetTexture and g.api.kit.icon:GetTexture()
        if art then gl:SetTexture(art) end
        gl:SetSize(GLYPH, GLYPH)
        local gx, gy = Spot(mid, inner + GLYPH / 2)
        gl:ClearAllPoints()
        gl:SetPoint("CENTER", fr, "CENTER", gx, gy)
        gl:SetShown(art ~= nil)
        local d = inner + GLYPH + NOTE_GAP
        for _, f in ipairs(g.smalls) do
            local w = Size(f)
            Put(g, f, mid, d + w / 2)
            d = d + w + NOTE_GAP
        end
        -- The regular slots beside it.
        local start = a + g.hw + NOTE_GAP
        for j, f in ipairs(g.bigs) do
            local col, row = (j - 1) % NOTE_COLS, math.floor((j - 1) / NOTE_COLS)
            Put(g, f, start + col * (g.w + NOTE_GAP) + g.w / 2, inner + row * (g.w + NOTE_GAP) + g.w / 2)
        end
        a = a + g.len
    end
    HideDecor(fr, "seps", math.max(1, #groups))
    HideDecor(fr, "glyphs", #groups + 1)
end

-- For the kits: what a boxed kit shows now, in order.
function D.BoxNotices(key, list)
    D.notices[key] = list
    local b = BoxOf(key)
    if not b then return end
    for _, fr in ipairs(D.boxFrames) do
        if fr.box == b and fr:IsShown() then return RelayNotices(fr) end
    end
end

-- Every box drawn by a frame (each keeps its frame from one layout to the
-- next, so it doesn't jump), and its kits laid out in it.
local function LayoutBoxes(before)
    local boxes = Boxes()
    local used = {}
    for _, f in ipairs(D.boxFrames) do
        if f.box and InList(boxes, f.box) and not used[f.box] then
            used[f.box] = f
        elseif not f.dragging then
            f.box = nil
        end
    end
    for _, b in ipairs(boxes) do
        if not used[b] then
            local f
            for _, g in ipairs(D.boxFrames) do
                if not g.box then f = g break end
            end
            f = f or NewBoxFrame()
            f.box, f.preview, f.toPin, f.drawn = b, nil, nil, nil
            -- A new box starts out (and stays out a moment, so you see it
            -- arrive): the kits gliding into it land where it stays, not
            -- where it was part-way through sliding.
            f.off = PARK_SHOW
            f.out = true
            f.hold = GetTime() + 1.5
            used[b] = f
        end
    end
    for _, f in ipairs(D.boxFrames) do
        local b = f.box
        local keys = b and BoxKeys(b) or {}
        local hovered = b and D.hover and D.hover.box == b
        if not b or (#keys == 0 and not hovered and not f.dragging) then
            f:Hide()
        else
            f.n = math.max(1, BoxCount(f))
            f.drawn = nil
            BoxPoint(f)
            f:Show()
            LayoutBoxKits(f, keys, before)
            if f.quiet and not BoxOpen(b) then
                -- A kit from the box just closed: the row's rules and icons fade back in.
                f.quiet = nil
                f.fadeStamp = GetTime()
            end
            RelayNotices(f)
        end
    end
end

-- D.skip: the kit being dragged during a live merge preview. Layout leaves
-- it alone (it's under the cursor) but still keeps its place in the dock.
local function DoLayout()
    SplitEdges()
    Normalize()
    local db = DB()
    local keys = DockedKeys()
    local pin = Pin()

    -- A kit that has left its box gets its slots back.
    for key, api in pairs(D.kits) do
        if api.parked and not (IsParked(key) and Parkable(key)) then ClearParked(api) end
    end

    -- A kit opened in place (see D.OpenInPlace): the kits that hide in
    -- combat step out (tucked) and the rest close up as a smaller dock.
    local inPlace = D.inPlace
    if inPlace and not (InList(keys, inPlace) and D.kits[inPlace].IsOpen()) then
        inPlace, D.inPlace = nil, nil
    end
    local away = {}
    if inPlace then
        local kept = {}
        for _, k in ipairs(keys) do
            local api = D.kits[k]
            if k ~= inPlace and api.HidesInCombat and api.HidesInCombat() then
                away[#away + 1] = k
            else
                kept[#kept + 1] = k
            end
        end
        keys = kept
    end

    -- Where every kit is on screen right now, before anything moves (moving
    -- the pin moves the kits on it), so each glides from where it really was.
    local before = {}
    for key, api in pairs(D.kits) do
        local kit = api.kit
        if key ~= D.skip and kit:IsShown() then
            local x, y = kit:GetCenter()
            if x then before[key] = { x, y, kit:GetEffectiveScale() } end
        end
    end

    -- Floating kits: their own saved spots and size, never tucked. One that
    -- was on the pin a moment ago glides to its spot like a docked kit would.
    for key, api in pairs(D.kits) do
        if not InList(keys, key) and key ~= D.skip and D.stay and D.stay[key] then
            -- Out of the dock only for a preview: stays put, as it is.
            local kit = api.kit
            StopTween(kit)
            local x, y = kit:GetCenter()
            if x then
                kit:ClearAllPoints()
                kit:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            end
        elseif not InList(keys, key) and key ~= D.skip and not EdgeOf(key) and not IsParked(key) then
            local kit = api.kit
            local b = before[key]
            local bx, by, bs
            if b then bx, by, bs = b[1], b[2], b[3] end
            StopTween(kit)
            if api.BeginMove then api.BeginMove() end
            SetCompact(api, false)
            SetEdge(api, nil)
            SetClamp(api, true)
            api.Tuck(false)
            api.PlaceFree()
            KitGlide(kit, bx, by, bs)
            if api.EndMove then api.EndMove() end
        end
    end

    -- Kits on the screen edges: each where it was put (kept on screen when
    -- it opens), tucked half off the screen until the mouse is over it (see
    -- EdgeTick). One that has just arrived stays out a moment first.
    for _, g in ipairs(Edges()) do
        local openKey
        for _, k in ipairs(g.keys) do
            if D.kits[k] and Shown(k) and D.kits[k].IsOpen() then openKey = k end
        end
        local c, lo, hi, gkeys = GroupCenters(g, openKey)
        for _, k in ipairs(gkeys) do
            local api = D.kits[k]
            if k == D.skip then
                SetEdge(api, g.side) -- under the cursor: just its slots take the edge shape
            else
                local kit = api.kit
                StopTween(kit)
                if api.BeginMove then api.BeginMove() end
                SetCompact(api, false)
                SetEdge(api, g.side)
                SetClamp(api, false)
                api.Tuck(false)
                local st = EdgeState(k)
                if st.off == nil or st.side ~= g.side or not st.c or math.abs(st.c - c[k]) > 1 then
                    st.off, st.out, st.linger = 0, true, 0
                    st.hold = GetTime() + 1.5
                end
                st.side, st.c = g.side, c[k]
                if api.IsOpen() then st.off, st.out = 0, true end
                EdgeSet(api, st)
                local b = before[k]
                if b then KitGlide(kit, b[1], b[2], b[3]) end
                if api.EndMove then api.EndMove() end
            end
        end
    end
    LayoutBoxes(before)
    for _, k in ipairs(away) do
        StopTween(D.kits[k].kit)
        D.kits[k].Tuck(true)
    end
    if #keys == 0 then
        -- (while the pin itself is dragged, it can't hide: it only fades)
        if D.pinDrag then pin:SetAlpha(0) else pin:Hide() end
        busy = false
        return
    end
    pin:SetAlpha(1)
    PlacePin(keys)
    -- Keep the pin far enough from the edges that whichever kit opens on it
    -- fits: the game holds that area on screen while you drag the pin, and
    -- an old spot (or a smaller window) is nudged in here.
    local L, R, T, B = 0, 0, 0, 0
    for _, k in ipairs(keys) do
        local api = D.kits[k]
        if api.Reach then
            local l, r, t, b = api.Reach()
            L, R, T, B = math.max(L, l), math.max(R, r), math.max(T, t), math.max(B, b)
        end
    end
    local hw = pin:GetWidth() / 2
    -- (not while the pin itself is dragged: it has to reach the edges, to
    -- tuck its kits into a box there)
    if pin.SetClampRectInsets and not D.pinDrag then
        pin:SetClampRectInsets(-math.max(0, L - hw), math.max(0, R - hw), math.max(0, T - hw), -math.max(0, B - hw))
    end
    if not D.pinDrag then
        local px, py = Center(pin)
        if px then
            local W, H = UIParent:GetWidth(), UIParent:GetHeight()
            local nx = math.min(math.max(px, L), math.max(L, W - R))
            local ny = math.min(math.max(py, B), math.max(B, H - T))
            if math.abs(nx - px) > 0.5 or math.abs(ny - py) > 0.5 then SetPinAt(nx, ny) end
        end
    end

    local openKey
    for _, k in ipairs(keys) do
        if D.kits[k].IsOpen() and k ~= inPlace then openKey = k end -- (one open in place doesn't take the pin)
    end

    -- Where each docked kit is now, so it can glide to its new spot (and
    -- where its pinned slots are: BeginMove / EndMove let the kit slide them
    -- along instead of them jumping while the button glides).
    -- While previewing a merge into a floating kit, that kit is held: not
    -- moved, not resized, just its slots re-arranged; the pin and the rest
    -- go around it.
    local hold = D.skip and D.anchor and D.anchor.key or nil
    for _, k in ipairs(keys) do
        local api = D.kits[k]
        if k ~= D.skip and k ~= hold then
            StopTween(api.kit)
            if api.BeginMove then api.BeginMove() end
        end
    end

    local n = #keys
    -- WoW's y runs up: 90 is straight up.
    local angles = n == 2 and { db.two, db.two + 180 }
        or n == 3 and (db.triUp and { 90, -30, 210 } or { -90, 30, 150 })
        or { 0 }
    -- Shrink the closed kits (full size for the one open on the pin, or a
    -- kit docked alone), and space them by their shrunken size.
    local size = 0
    for i, k in ipairs(keys) do
        local api = D.kits[k]
        if k == D.skip or k == hold then
            -- (the held kit keeps its real size, so the pin sits clear of it)
            size = math.max(size, k == hold and api.kit:GetWidth() * api.kit:GetScale() or DockedSize(api, n, false))
            -- Its slots take the shape they'd have docked here (rings round
            -- its button in its slice), without resizing it under the cursor.
            if api.Compact then
                if api.BeginMove then api.BeginMove() end -- its slots glide to the new shape
                if n > 1 then api.Compact(true, angles[i], n == 2 and 170 or 115)
                else api.Compact(api.compact or false, api.compactAngle, api.compactSpan) end
                if api.EndMove then api.EndMove() end
            end
        else
            SetEdge(api, nil)
            SetCompact(api, n > 1 and k ~= openKey and k ~= inPlace, angles[i], n == 2 and 170 or 115)
            local kit = api.kit
            size = math.max(size, kit:GetWidth() * kit:GetScale())
        end
    end
    local r = n == 2 and size * 0.55 or size * 0.66

    -- Two floating kits merging: the one you dropped onto (or are hovering
    -- over) is held exactly where it was, and the pin goes wherever that
    -- needs it, whatever sizes and spacing the dock settles on.
    local anchor = D.anchor
    if anchor and n > 1 then
        local ai = InList(keys, anchor.key)
        if ai and keys[ai] ~= openKey then
            local a = math.rad(angles[ai])
            SetPinAt(anchor.x - r * math.cos(a), anchor.y - r * math.sin(a))
        end
    end

    -- Opened in place: where it goes (from the pin), so that its open slots
    -- clear the other kits, which keep their spots.
    --   two kits: level with the other, on the pair's own line, just far
    --     enough along it that its slots on that side miss the other kit
    --   three: at its own spot, raised until its slots below the button clear
    --     the tops of the other two
    local inPlaceAt
    if inPlace and n > 1 then
        local ii = InList(keys, inPlace)
        local api = D.kits[inPlace]
        local L, R, T, B = 0, 0, 0, 0
        if api.Reach then L, R, T, B = api.Reach() end
        if n == 2 then
            local oi = 3 - ii
            local o = D.kits[keys[oi]].kit
            local oa = math.rad(angles[oi])
            local ox, oy = r * math.cos(oa), r * math.sin(oa)
            local ux, uy = -math.cos(oa), -math.sin(oa) -- (from the other kit toward this one)
            -- How far its slots reach back toward the other kit.
            local back = (ux >= 0 and L or R) * math.abs(ux) + (uy >= 0 and B or T) * math.abs(uy)
            local d = math.max(2 * r, back + o:GetWidth() * o:GetScale() / 2 + 6)
            inPlaceAt = { ox + ux * d, oy + uy * d }
        else
            local a = math.rad(angles[ii])
            local myX, myY = r * math.cos(a), r * math.sin(a)
            local top = -math.huge
            for i, k in ipairs(keys) do
                if k ~= inPlace then
                    local o = D.kits[k].kit
                    top = math.max(top, r * math.sin(math.rad(angles[i])) + o:GetWidth() * o:GetScale() / 2)
                end
            end
            inPlaceAt = { myX, math.max(myY, top + B + 6) }
        end
    end

    for i, k in ipairs(keys) do
        local api = D.kits[k]
        local kit = api.kit
        if k == D.skip or k == hold then -- under the cursor, or held where it is
        else
        local ks = kit:GetScale()
        local dx, dy = 0, 0
        if n > 1 and k ~= openKey then
            local a = math.rad(angles[i])
            dx, dy = r * math.cos(a), r * math.sin(a)
            if k == inPlace and inPlaceAt then dx, dy = inPlaceAt[1], inPlaceAt[2] end
        end
        kit:ClearAllPoints()
        kit:SetPoint("CENTER", pin, "CENTER", dx / ks, dy / ks)
        SetClamp(api, true)
        api.Tuck(openKey ~= nil and k ~= openKey)
        local b = before[k]
        if b and not (openKey ~= nil and k ~= openKey) then KitGlide(kit, b[1], b[2], b[3]) end
        if api.EndMove then api.EndMove() end
        end
    end
    pin:SetShown(n >= 2 and not openKey and not D.pinCombatHidden)

    -- Moved that far, the open kit's slots could run off the screen: then
    -- the pin (and everything on it) moves in for now. Not saved: the next
    -- layout puts the pin back at its own spot.
    if inPlaceAt then
        local api = D.kits[inPlace]
        local L, R, T, B = 0, 0, 0, 0
        if api.Reach then L, R, T, B = api.Reach() end
        local px, py = Center(pin)
        if px then
            local W, H, M = UIParent:GetWidth(), UIParent:GetHeight(), 4
            local fx, fy = px + inPlaceAt[1], py + inPlaceAt[2]
            local sx = math.max(0, M - (fx - L)) - math.max(0, (fx + R) - (W - M))
            local sy = math.max(0, M - (fy - B)) - math.max(0, (fy + T) - (H - M))
            if sx ~= 0 or sy ~= 0 then
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px + sx, py + sy)
            end
        end
    end
end

-- Lays every kit out: floating, on the pin, or on the screen edges.
-- Wrapped so a script error part-way through is reported but can't leave
-- the dock stuck: every later layout would be ignored (kits gone or frozen
-- until a /reload).
function D.Layout()
    if busy then return end
    if InCombatLockdown() then D.pending = true return end
    D.pending = nil
    busy = true
    local ok, err = pcall(DoLayout)
    busy = false
    if not ok then
        D.skip, D.anchor, D.stay = nil, nil, nil
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
    end
end

local queued = false
local function QueueLayout()
    if queued then return end
    queued = true
    local function run()
        queued = false
        D.Layout()
        if D.SetupMinimap then D.SetupMinimap() end
    end
    if C_Timer then C_Timer.After(0, run) else run() end
end

-- Each kit addon calls this at login with:
--   kit       its main button
--   IsOpen()  whether its slots are out
--   Close()   close it
--   Tuck(on)  hide (on) or show its button and pinned slots
--   PlaceFree() put it at its own saved spot
--   SaveFree()  save where it is now as its own spot
--   BeginMove() / EndMove()  (optional) called around any relayout that
--             moves the kit, so it can glide its pinned slots along too
--   HidesInCombat() (optional) true if the kit hides itself in combat; when
--             every docked kit does, the pin hides in combat as well
--   Edge(side) (optional) the kit is on a screen edge ("left", "right",
--             "top", "bottom") or not (nil): lay its slots out in columns
--             (or rows) toward the middle of the screen
--   EdgeExtent(side, open) (optional) how much room (UI units) the kit
--             takes along that edge, closed or open
--   name      (optional) shown in the shared Kits menu
--   edgesOnly (optional) never joins the pin; only snaps to screen edges
--   Park(on)  (optional) the kit is parked in the tuckbox (a small button
--             in a row) or not: hide its pinned slots and extras, and show
--             them again. Without it a parked kit is fanned toward the box's
--             edge, which sends its slots off the screen.
function D.Register(key, api)
    D.kits[key] = api
    QueueLayout()
end

---------------------------------------------------------------------------
-- Opening one kit closes the other docked ones
---------------------------------------------------------------------------

-- In a fight, or just about to be (as combat starts, First Aid Kit opens
-- itself): a kit in a box stays in it, closed.
local function BoxedInFight(key)
    if not IsParked(key) then return false end
    return InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
end

function D.Opening(key)
    if BoxedInFight(key) then
        local api = D.kits[key]
        if api and api.IsOpen() and not InCombatLockdown() then api.Close() end
        return
    end
    if not D.IsDocked(key) or InCombatLockdown() then return end
    local g = EdgeOf(key)
    local mates = g and g.keys or DockedKeys()
    local b = BoxOf(key)
    if b then mates = BoxKeys(b) end -- (kits in a box share it: one steps out at a time)
    for _, k in ipairs(mates) do
        local api = D.kits[k]
        if k ~= key and api and api.IsOpen() then api.Close() end
    end
    D.Layout()
end

-- A docked kit opening without taking the pin (First Aid Kit's "open on
-- combat"): the other kits stay where they are, docked and shrunk, and it
-- opens full size at its own spot, raised until its open slots clear them.
-- Kits that hide in combat step out, and the rest close up as a smaller
-- dock. Ends when the kit closes (D.Closed). Out of combat only: as combat
-- starts is the last moment (PLAYER_REGEN_DISABLED).
function D.OpenInPlace(key)
    if BoxedInFight(key) then return D.Opening(key) end
    if InCombatLockdown() then return end
    if not PinDocked(key) then return D.Opening(key) end
    for _, k in ipairs(DockedKeys()) do
        local api = D.kits[k]
        if k ~= key and api and api.IsOpen() then api.Close() end
    end
    D.inPlace = key
    D.Layout()
end

function D.Closed(key)
    if D.inPlace == key then D.inPlace = nil end
    if D.IsDocked(key) then D.Layout() end
end

---------------------------------------------------------------------------
-- Dragging a kit
---------------------------------------------------------------------------

-- A docked kit lets go of the pin and floats exactly where it is, at full
-- size. It's grown back before its spot is saved: anchor offsets are in a
-- frame's own scale, so saving a shrunken kit's spot and growing it after
-- would send it leaping across the screen.
local function Release(key)
    local api = D.kits[key]
    local kit = api.kit
    StopTween(kit)
    local x, y = Center(kit)
    DB().docked[key] = false
    SetCompact(api, false)
    if x then
        local s = kit:GetEffectiveScale() / UIParent:GetEffectiveScale()
        kit:ClearAllPoints()
        kit:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
        api.SaveFree()
    end
end

-- Takes a kit out of its box (the caller lays things out).
local function Unpark(key)
    UnparkRaw(key)
end

-- Whatever was open closes when kits merge, so the result is in view
-- instead of the newcomer tucking away behind the open kit.
local function CloseOpen()
    for _, k in ipairs(DockedKeys()) do
        local api = D.kits[k]
        if api.IsOpen() then api.Close() end
    end
end

-- A box's frame stays out a moment, so you see what just went in.
local function HoldBox(b)
    for _, f in ipairs(D.boxFrames) do
        if f.box == b then f.hold = GetTime() + 1.5 end
    end
end

-- A pin can't be one kit: after kits leave it (pinned: the pin as it was),
-- the one left behind floats where it is. For a preview it just stays put.
local function LonePin(pinned, preview)
    local left = DockedKeys()
    if #left == 1 and #pinned >= 2 then
        if preview then
            D.stay = { [left[1]] = true }
            DB().docked[left[1]] = false
        else
            Release(left[1])
        end
    end
end

-- Put a kit into box b at place `at` (the end if not given), out of
-- whatever it was on. Returns the box. (The caller lays things out.)
local function ParkInto(b, key, at, preview)
    local pinned = DockedKeys()
    LeaveEdge(key)
    local was, wi = BoxOf(key)
    if was then table.remove(was.keys, wi) end
    local n = #b.keys
    table.insert(b.keys, math.max(1, math.min(n + 1, at or n + 1)), key)
    DB().docked[key] = false
    LonePin(pinned, preview)
    return b
end

-- A new box (side, along) on an edge. reuse: a table to use for it (a
-- live preview makes "the same" box many times a second; one table keeps
-- it drawn by one frame instead of a new one each time).
local function NewBox(side, at, reuse)
    local b = reuse or {}
    b.side, b.at, b.keys = side, at, {}
    table.insert(Boxes(), b)
    return b
end

-- A new box where a kit sits on an edge on its own, with that kit in it.
local function BoxFromEdge(edgeKey, reuse)
    local g = EdgeOf(edgeKey)
    local b = NewBox(g.side, g.at or AlongLen(g.side) / 2, reuse)
    LeaveEdge(edgeKey)
    table.insert(b.keys, edgeKey)
    return b
end

-- A kit dropped (at cx, cy) onto a kit on an edge on its own: the two make
-- a box there, in the order they sit along the edge.
local function MakeBox(edgeKey, key, cx, cy, preview, reuse)
    local g = EdgeOf(edgeKey)
    local before = AlongOf(g.side, cx, cy) < (g.at or 0)
    local b = BoxFromEdge(edgeKey, reuse)
    return ParkInto(b, key, before and 1 or 2, preview)
end

-- What a kit was dropped on: the nearest other kit showing on screen, or
-- the pin, within SNAP of the drop point. Returns its key (or "pin") and
-- whether it's part of the dock. floatingOnly: only kits off the dock count
-- (for the open kit carrying its dock, which is already sitting on it).
local function DropTarget(key, cx, cy, pinX, pinY, centers, floatingOnly)
    if EdgesOnly(key) then return nil end -- it never merges with anything
    local docked = DockedKeys()
    local best, bestD, bestDocked
    local function try(k, x, y, inDock)
        if not x then return end
        local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
        if d < SNAP and (not bestD or d < bestD) then best, bestD, bestDocked = k, d, inDock end
    end
    for k, other in pairs(D.kits) do
        if k ~= key and Shown(k) and not EdgesOnly(k) and other.kit:IsVisible()
            and not (floatingOnly and InList(docked, k)) then
            local x, y
            if centers then
                if centers[k] then x, y = centers[k][1], centers[k][2] end
            else
                x, y = Center(other.kit)
            end
            try(k, x, y, InList(docked, k) ~= nil)
        end
    end
    local n = 0 -- the pin stands for the dock too (it hides while a kit is open on it)
    for _, k in ipairs(docked) do if k ~= key then n = n + 1 end end
    if n > 0 and not floatingOnly and (pinX or D.pin) then
        local x, y = pinX, pinY
        if not x then x, y = Center(D.pin) end
        try("pin", x, y, true)
    end
    return best, bestDocked
end

-- Join key to target (another kit, or "pin" for the dock), as if dropped at
-- cx, cy. Changes the saved dock (docked, order, side, pin); the caller lays
-- it out. Used for the drop and for the live preview while dragging.
local function Merge(key, target, targetDocked, cx, cy, centers, preview)
    local db = DB()
    if not targetDocked then
        -- Dropped on a floating kit: the two start a dock, set so the kit
        -- you dropped on stays where it is, and anything docked elsewhere
        -- lets go and floats where it is.
        for _, k in ipairs(DockedKeys()) do
            if k ~= key and k ~= target then
                if preview then -- just a preview: leave it exactly where it is
                    D.stay = D.stay or {}
                    D.stay[k] = true
                    DB().docked[k] = false
                else
                    Release(k)
                end
            end
        end
        local tx, ty
        if centers and centers[target] then tx, ty = centers[target][1], centers[target][2]
        else tx, ty = Center(D.kits[target].kit) end
        local two = math.floor(math.deg(math.atan2(cy - ty, cx - tx)) / 90 + 0.5) * 90
        local size = math.max(DockedSize(D.kits[key], 2), DockedSize(D.kits[target], 2))
        local a = math.rad(two + 180) -- the target's side of the pin
        -- Just noted: the layout moves the pin (after noting where every kit
        -- is), and holds the target where it is.
        Pin()
        db.pin = { tx - size * 0.55 * math.cos(a), ty - size * 0.55 * math.sin(a) }
        db.docked[target] = true
        db.docked[key] = true
        db.two = two
        D.anchor = { key = target, x = tx, y = ty }
        local order = { key, target }
        for _, k in ipairs(db.order) do if not InList(order, k) then order[#order + 1] = k end end
        db.order = order
        return
    end

    -- Join the dock at the pin, on the side (two kits) or corner (three)
    -- it was dropped on.
    local wasIn = InList(DockedKeys(), key) ~= nil -- already on it (moving corners)
    db.docked[key] = true
    local px, py
    if db.pin then px, py = db.pin[1], db.pin[2] else px, py = Center(Pin()) end
    local ang = math.deg(math.atan2(cy - py, cx - px))
    local keys = DockedKeys()
    if #keys == 2 then
        -- Two: the dropped kit takes the side it was dropped on.
        db.two = math.floor(ang / 90 + 0.5) * 90
        local other = keys[1] == key and keys[2] or keys[1]
        local order = { key, other }
        for _, k in ipairs(db.order) do if not InList(order, k) then order[#order + 1] = k end end
        db.order = order
    elseif #keys == 3 then
        -- Three: the dropped kit takes the nearest corner, swapping with
        -- whichever kit was there.
        local angles = db.triUp and { 90, -30, 210 } or { -90, 30, 150 }
        local bestI, bestD = 1, 999
        for i, a in ipairs(angles) do
            local diff = math.abs(((ang - a) % 360 + 540) % 360 - 180)
            if diff < bestD then bestI, bestD = i, diff end
        end
        -- Where the others sit now: their corners if it's already three,
        -- or their sides if it was two.
        local function Diff(a, b) return math.abs(((a - b) % 360 + 540) % 360 - 180) end
        local others, was = {}, {}
        for i, k in ipairs(keys) do
            if k ~= key then
                others[#others + 1] = k
                if wasIn then was[k] = angles[i] end
            end
        end
        if not wasIn then
            was[others[1]], was[others[2]] = db.two or 0, (db.two or 0) + 180
        end
        -- Each takes whichever free corner is nearest where it is, so
        -- nothing crosses over to the far side.
        local free = {}
        for i = 1, 3 do if i ~= bestI then free[#free + 1] = i end end
        local a, b = others[1], others[2]
        if Diff(was[a], angles[free[1]]) + Diff(was[b], angles[free[2]])
            > Diff(was[a], angles[free[2]]) + Diff(was[b], angles[free[1]]) then
            a, b = b, a
        end
        local placed = {}
        placed[bestI], placed[free[1]], placed[free[2]] = key, a, b
        for _, k in ipairs(db.order) do if not InList(placed, k) then placed[#placed + 1] = k end end
        db.order = placed
    end
end

-- Two kits left on the pin after a third comes off: they take the pair of
-- opposite sides (left/right or top/bottom) nearest where each sits now
-- (centers: where the kits were when the drag began), so neither crosses
-- over to the other side.
local function AngDiff(a, b) return math.abs(((a - b) % 360 + 540) % 360 - 180) end
local function KeepSides(centers)
    local db = DB()
    local keys = DockedKeys()
    if #keys ~= 2 or not db.pin then return end
    local px, py = db.pin[1], db.pin[2]
    local at = {}
    for _, k in ipairs(keys) do
        local c = centers and centers[k]
        local x, y
        if c then x, y = c[1], c[2] else x, y = Center(D.kits[k].kit) end
        if not x then return end
        at[k] = math.deg(math.atan2(y - py, x - px))
    end
    local best, bestCost
    for _, two in ipairs({ 0, 90, 180, 270 }) do
        for _, first in ipairs(keys) do
            local second = first == keys[1] and keys[2] or keys[1]
            local cost = AngDiff(at[first], two) + AngDiff(at[second], two + 180)
            if not bestCost or cost < bestCost then best, bestCost = { two, first, second }, cost end
        end
    end
    db.two = best[1]
    local order = { best[2], best[3] }
    for _, k in ipairs(db.order) do if not InList(order, k) then order[#order + 1] = k end end
    db.order = order
end

-- The saved dock as it was when a drag began, so the live preview can try
-- each arrangement and go back.
local function Snapshot()
    local db = DB()
    local s = { docked = {}, order = {}, two = db.two, pin = db.pin and { db.pin[1], db.pin[2] }, edges = {}, boxes = {} }
    for k, v in pairs(db.docked) do s.docked[k] = v end
    for i, k in ipairs(db.order) do s.order[i] = k end
    for i, g in ipairs(Edges()) do
        s.edges[i] = { side = g.side, at = g.at, start = g.start, keys = { unpack(g.keys) } }
    end
    -- (each box keeps its own table, so its frame stays with it)
    for i, b in ipairs(Boxes()) do
        s.boxes[i] = { ref = b, side = b.side, at = b.at, keys = { unpack(b.keys) } }
    end
    return s
end

-- Puts the saved dock back. keepPin leaves the pin frame (and the kits on
-- it) where the preview put them, so what's under the cursor can be read
-- from what's on screen.
local function Restore(s, keepPin)
    local db = DB()
    db.docked, db.order, db.two = {}, {}, s.two
    for k, v in pairs(s.docked) do db.docked[k] = v end
    for i, k in ipairs(s.order) do db.order[i] = k end
    db.pin = s.pin and { s.pin[1], s.pin[2] } or nil
    db.edges = {}
    for i, g in ipairs(s.edges or {}) do
        db.edges[i] = { side = g.side, at = g.at, start = g.start, keys = { unpack(g.keys) } }
    end
    db.boxes = {}
    for i, b in ipairs(s.boxes or {}) do
        local r = b.ref
        r.side, r.at, r.keys = b.side, b.at, { unpack(b.keys) }
        db.boxes[i] = r
    end
    if db.pin and D.pin and not keepPin then SetPinAt(db.pin[1], db.pin[2]) end
end

-- What the dragged kit is over, judged against the dock and the kits as they
-- were when the drag began (not where the preview has moved them, or the
-- kit you're aiming at could slide along under the cursor), with
-- the saved dock put back ready for Merge. The pin itself isn't moved here:
-- the next layout does that, after noting where every kit is, so nothing on
-- the pin jumps before it glides.
local function Resolve(drag, key, cx, cy)
    local s = drag.snap
    Restore(s, true)
    return DropTarget(key, cx, cy, s.pin and s.pin[1], s.pin and s.pin[2], drag.centers, drag.group)
end

-- The open kit carrying its dock, over a floating kit: that kit joins the
-- dock and stays exactly where it is, and the dock settles round it. Same
-- as dropping a closed kit on it.
local function JoinGroup(target, centers)
    local tx, ty
    if centers and centers[target] then tx, ty = centers[target][1], centers[target][2]
    else tx, ty = Center(D.kits[target].kit) end
    Pin()
    DB().docked[target] = true
    D.anchor = { key = target, x = tx, y = ty }
end

local function Signature()
    local db = DB()
    local p = db.pin or {}
    local e = {}
    for _, g in ipairs(Edges()) do
        e[#e + 1] = g.side .. math.floor((g.at or g.start or 0) + 0.5) .. ":" .. table.concat(g.keys, ",")
    end
    local bx = {}
    for _, b in ipairs(Boxes()) do
        bx[#bx + 1] = tostring(b) .. b.side .. ":" .. table.concat(b.keys, ",")
    end
    return table.concat(DockedKeys(), ",") .. "|" .. tostring(db.two) .. "|"
        .. math.floor((p[1] or 0) + 0.5) .. "," .. math.floor((p[2] or 0) + 0.5) .. "|" .. table.concat(e, ";")
        .. "|" .. table.concat(bx, ";")
end

-- While you drag a kit (not the open one carrying its dock), the dock
-- rearranges live: over another kit or the pin, the kits move into the
-- shape they'd take with this one joined, leaving its spot free; away from
-- everything, the dock closes up without it. Letting go settles it there.
--
-- Open kits merge just like closed ones: whatever's open on the dock being
-- formed (the kit you're dragging, the kit you're over, or the one open on
-- the pin) closes as soon as the merge shows, so the preview is exactly
-- what you get on letting go, and nothing tucks away behind an open kit.
local function Preview(key, cx, cy)
    local drag = D.dragging
    if not drag or not drag.snap or InCombatLockdown() then return end
    local target, targetDocked = Resolve(drag, key, cx, cy)
    D.anchor = nil
    D.stay = nil
    -- Over a box: the kit isn't joining anything here yet (the pin and the
    -- screen edge step aside), it just leaves what it was on; letting go puts
    -- it in the box.
    local box = not drag.group and Parkable(key) and BoxAt(cx, cy, nil, drag.box and 0 or 1) or nil
    if box then target = nil end
    -- Over a kit on an edge on its own: the two make a box there.
    local edgeKey = not drag.group and not box and EdgeKitAt(key, cx, cy, drag.centers) or nil
    if edgeKey then target = nil end
    -- (Carrying the dock, the edges don't count: the dock just moves.)
    local side = not drag.group and not box and not edgeKey and NearEdge(cx, cy) or nil
    -- Pulled away from its box, a kit leaves it (and a box left with one
    -- kit becomes that kit on its own on the edge).
    if drag.box and not box then UnparkRaw(key) end
    if drag.group then
        -- Carrying the dock: only a floating kit is something to merge with;
        -- away from one, the dock just follows along. Until it first meets
        -- one, nothing moves: the dock is under it.
        if not target and not drag.merged then return end
        if target then
            JoinGroup(target, drag.centers)
            drag.merged = true
        end
    elseif edgeKey then
        drag.previewBox = drag.previewBox or {}
        MakeBox(edgeKey, key, cx, cy, true, drag.previewBox)
        KeepSides(drag.centers) -- out of three: the two left keep their sides
    elseif side then
        target = nil
        JoinEdge(key, side, cx, cy)
        -- Pulled out of a pair: the kit left behind stays exactly where it is.
        local left = DockedKeys()
        if #left == 1 then
            D.stay = { [left[1]] = true }
            DB().docked[left[1]] = false
        end
        KeepSides(drag.centers) -- out of three: the two left keep their sides
    elseif target then
        LeaveEdge(key)
        Merge(key, target, targetDocked, cx, cy, drag.centers, true)
    else
        LeaveEdge(key)
        DB().docked[key] = false
        -- Pulled out of a pair: the kit left behind stays exactly where it is.
        local left = DockedKeys()
        if #left == 1 then
            D.stay = { [left[1]] = true }
            DB().docked[left[1]] = false
        end
        KeepSides(drag.centers) -- out of three: the two left keep their sides
    end
    local sig = Signature()
    if sig ~= drag.sig then
        drag.sig = sig
        D.skip = key -- before closing anything: a closing kit lays the dock out
        if target then CloseOpen() end
        D.Layout()
        -- Away from everything: the dragged kit's slots go back to how they
        -- really are. A kit that was held for a merge preview and isn't any
        -- more gets its own slots back too.
        local api = D.kits[key]
        if not target and api.Compact then api.Compact(api.compact or false, api.compactAngle, api.compactSpan) end
        if not side then SetEdge(api, nil) end
        local held = D.anchor and D.anchor.key or nil
        if drag.held and drag.held ~= held then
            local h = D.kits[drag.held]
            if h and h.Compact then h.Compact(h.compact or false, h.compactAngle, h.compactSpan) end
        end
        drag.held = held
    end
end

-- While a kit is dragged, a small watcher re-checks what's under it a few
-- times a second and updates the live preview.
local function Watcher()
    if D.watch then return D.watch end
    local w = CreateFrame("Frame")
    w:Hide()
    local elapsed = 0
    w:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.05 then return end
        elapsed = 0
        local drag = D.dragging
        local api = drag and D.kits[drag.key]
        if not api then return end
        local cx, cy = Center(api.kit)
        if cx then
            if drag.group then
                -- Carrying the dock to an edge: a box there lights up for it,
                -- or the box it would make shows.
                local n = #DockedKeys()
                local side = not drag.merged and NearEdge(cx, cy) or nil
                local b = side and BoxAt(cx, cy, nil, n) or nil
                local ek = side and not b and EdgeKitAt(nil, cx, cy, drag.centers) or nil
                D.Hover(b, n)
                D.Ghost(not b and side or nil, cx, cy, ek and n + 1 or n)
            else
                local extra = drag.box and 0 or 1
                local b = Parkable(drag.key) and BoxAt(cx, cy, nil, extra) or nil
                if b and drag.box and b ~= drag.box then extra = 1 end
                D.Hover(b, extra)
                D.EdgeGlow(not b and NearEdge(cx, cy) or nil, cx, cy)
            end
            Preview(drag.key, cx, cy)
        end
    end)
    D.watch = w
    return w
end

-- Called from a kit's OnDragStart. The kit open on the pin carries its
-- whole dock with it; any other kit moves on its own.
function D.DragStart(key)
    if InCombatLockdown() then return end
    local api = D.kits[key]
    local kit = api.kit
    -- Lift the kit off the pin at the same spot so it can move freely.
    StopTween(kit)
    local x, y = kit:GetCenter()
    if x then
        kit:ClearAllPoints()
        kit:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
    kit:StartMoving()
    -- Where every other kit sits right now: the preview judges what you're
    -- over against these, so its own rearranging doesn't move the target.
    local centers = {}
    for k, other in pairs(D.kits) do
        if k ~= key then
            StopTween(other.kit) -- where it's settling, not part-way there
            local x, y = Center(other.kit)
            if x then centers[k] = { x, y } end
        end
    end
    D.dragging = { key = key, group = PinDocked(key) and api.IsOpen(), snap = Snapshot(), centers = centers,
        parked = IsParked(key), box = BoxOf(key) }
    Watcher():Show()
end

-- Called from a kit's OnDragStop.
function D.DragStop(key)
    local drag = D.dragging
    D.dragging = nil
    if D.watch then D.watch:Hide() end
    D.EdgeGlow(nil)
    D.Hover(nil)
    D.Ghost(nil)
    D.skip = nil
    D.anchor = nil
    D.stay = nil
    local api = D.kits[key]
    local kit = api.kit
    kit:StopMovingOrSizing()
    if not drag then D.Layout() return end
    local db = DB()
    local cx, cy = Center(kit)
    if not cx then
        if drag.snap then Restore(drag.snap) end
        D.Layout()
        return
    end
    -- The saved dock as it was when the drag began, and what's under the kit.
    local target, targetDocked = Resolve(drag, key, cx, cy)

    if not drag.group and Parkable(key) then
        -- Dropped on a box: it goes in (or moves along its row).
        local b = BoxAt(cx, cy, nil, drag.box and 0 or 1)
        if b then
            ParkInto(b, key, ParkIndexAt(b, key, cx, cy))
            KeepSides(drag.centers) -- out of three: the two left keep their sides
            HoldBox(b)
            D.Layout()
            return
        end
        -- Dropped on a kit on an edge on its own: the two make a box there.
        local ek = EdgeKitAt(key, cx, cy, drag.centers)
        if ek then
            HoldBox(MakeBox(ek, key, cx, cy, false, drag.previewBox))
            KeepSides(drag.centers)
            D.Layout()
            return
        end
    end
    -- Pulled out of a box: an ordinary drop from here (the pin, an edge, or
    -- floating where it's let go).
    if drag.parked then Unpark(key) end

    if drag.group then
        local side = not target and not drag.merged and NearEdge(cx, cy) or nil
        if side then -- carried to an edge: they all tuck into a box there
            local n = #DockedKeys()
            local b = BoxAt(cx, cy, nil, n)
            local ek = not b and EdgeKitAt(nil, cx, cy, drag.centers)
            b = b or (ek and BoxFromEdge(ek)) or NewBox(side, AlongOf(side, cx, cy))
            D.TuckAll(b)
            return
        end
        if target then -- dropped on a floating kit: it joins, held where it is
            JoinGroup(target, drag.centers)
            CloseOpen()
            D.Layout()
            D.anchor = nil
            if api.Compact then api.Compact(api.compact or false, api.compactAngle, api.compactSpan) end
        else -- the open kit moved its dock: the pin follows it
            Pin()
            SetPinAt(cx, cy)
            D.Layout()
        end
        if drag.held and drag.held ~= target then
            local h = D.kits[drag.held]
            if h and h.Compact then h.Compact(h.compact or false, h.compactAngle, h.compactSpan) end
        end
        return
    end

    local side = NearEdge(cx, cy)
    if side then -- on a screen edge
        JoinEdge(key, side, cx, cy)
        SetCompact(api, false)
        KeepSides(drag.centers)
        local left = DockedKeys()
        local lone, lb
        if #left == 1 then
            lone = D.kits[left[1]].kit
            local x, y = lone:GetCenter()
            if x then lb = { x, y, lone:GetEffectiveScale() } end
            Release(left[1])
        end
        D.Layout()
        if lone and lb then KitGlide(lone, lb[1], lb[2], lb[3]) end
        if drag.held then
            local h = D.kits[drag.held]
            if h and h.Compact then h.Compact(h.compact or false, h.compactAngle, h.compactSpan) end
        end
        return
    end
    LeaveEdge(key)

    if not target then -- dropped on nothing: float right here
        Release(key)
        KeepSides(drag.centers)
        -- A dock can't be one kit: the one left behind floats where it is.
        local left = DockedKeys()
        local lone, lb
        if #left == 1 then
            lone = D.kits[left[1]].kit
            local x, y = lone:GetCenter()
            if x then lb = { x, y, lone:GetEffectiveScale() } end
            Release(left[1])
        end
        D.Layout()
        if lone and lb then KitGlide(lone, lb[1], lb[2], lb[3]) end -- grows back in place
        if drag.held then
            local h = D.kits[drag.held]
            if h and h.Compact then h.Compact(h.compact or false, h.compactAngle, h.compactSpan) end
        end
        if api.Compact then api.Compact(api.compact or false, api.compactAngle, api.compactSpan) end
        return
    end
    D.anchor = nil
    Merge(key, target, targetDocked, cx, cy, not drag.group and drag.centers or nil)
    CloseOpen()
    D.Layout()
    D.anchor = nil
    if drag.held and drag.held ~= target then
        local h = D.kits[drag.held]
        if h and h.Compact then h.Compact(h.compact or false, h.compactAngle, h.compactSpan) end
    end
    if api.Compact then api.Compact(api.compact or false, api.compactAngle, api.compactSpan) end
end

---------------------------------------------------------------------------
-- Slash helpers (each addon offers "dock" and "flip")
---------------------------------------------------------------------------

-- Dock every kit again, around the pin (or around this kit if there's none).
function D.DockAll(fromKey)
    if InCombatLockdown() then return end
    local db = DB()
    -- Edges-only kits keep their spots on the edges; everything else comes off.
    local keep = {}
    for _, g in ipairs(Edges()) do
        local keys = {}
        for _, k in ipairs(g.keys) do if EdgesOnly(k) then keys[#keys + 1] = k end end
        if #keys > 0 then keep[#keep + 1] = { side = g.side, at = g.at, start = g.start, keys = keys } end
    end
    db.edges = keep
    for _, bx in ipairs(Boxes()) do -- boxed kits come back to the pin too (edges-only ones stay in their boxes)
        local keys = {}
        for _, k in ipairs(bx.keys) do if EdgesOnly(k) then keys[#keys + 1] = k end end
        bx.keys = keys
    end
    local hadPin = db.pin and db.pin[1] and db.pin[2] and #DockedKeys() > 0
    for k in pairs(D.kits) do if not EdgesOnly(k) then db.docked[k] = true end end
    if not hadPin and fromKey and D.kits[fromKey] then
        local x, y = Center(D.kits[fromKey].kit)
        if x then Pin() SetPinAt(x, y) end
    end
    D.Layout()
end

-- Take a kit off the pin or its screen edge so it floats at its own saved
-- spot (a kit's "reset").
function D.Undock(key)
    if InCombatLockdown() or not D.kits[key] then return end
    LeaveEdge(key)
    Unpark(key)
    DB().docked[key] = false
    local api = D.kits[key]
    SetEdge(api, nil)
    SetCompact(api, false)
    D.Layout()
end

-- Put one kit on the pin (a kit's menu "On the pin"). It joins the others;
-- with no pin yet, the pin starts where the kit stands.
function D.Pin(key)
    local api = D.kits[key]
    if InCombatLockdown() or not api or EdgesOnly(key) then return end
    local db = DB()
    local hadPin = db.pin and db.pin[1] and db.pin[2] and #DockedKeys() > 0
    local x, y
    if not hadPin then x, y = Center(api.kit) end
    LeaveEdge(key)
    Unpark(key)
    db.docked[key] = true
    if x then Pin() SetPinAt(x, y) end
    D.Layout()
end

-- Put a kit in a box (b, or the box it's in, or one on the top edge, made
-- there if need be) at place `at` (the end if not given). Whatever it was on
-- lets go. For the kits' menus ("Top dock"); centers: where the kits were
-- when a drag began. Returns whether it went in.
function D.Park(key, at, centers, b)
    local api = D.kits[key]
    if InCombatLockdown() or not api or not Parkable(key) then return false end
    if not b then
        b = BoxOf(key)
        if not b then
            for _, x in ipairs(Boxes()) do
                if x.side == "top" then b = x break end
            end
        end
        b = b or NewBox("top", nil)
    end
    ParkInto(b, key, at)
    if centers then KeepSides(centers) end -- out of three: the two left keep their sides
    HoldBox(b)
    D.Layout()
    return true
end

-- Take a kit out of its box. It floats at its own saved spot.
function D.Unpark(key)
    if InCombatLockdown() or not IsParked(key) then return end
    Unpark(key)
    DB().docked[key] = false
    D.Layout()
end

-- These kits go into box b, out of whatever they were on. (The caller lays
-- things out.)
local function TuckInto(b, keys)
    for _, k in ipairs(keys) do
        LeaveEdge(k)
        UnparkRaw(k)
        if not InList(b.keys, k) then b.keys[#b.keys + 1] = k end
        DB().docked[k] = false
    end
end

-- Every kit on the pin goes into box b. Open kits close first. The pin is
-- left empty and hides.
function D.TuckAll(b)
    if InCombatLockdown() or not b then return end
    local keys = DockedKeys()
    for _, k in ipairs(keys) do
        local api = D.kits[k]
        if api.IsOpen() then api.Close() end
    end
    TuckInto(b, keys)
    HoldBox(b)
    D.Layout()
end

-- Dragging the pin itself. At a screen edge its kits go into a box there
-- right away: one already there (or a kit on its own there, which the box
-- takes in too), or a new one that follows the pin along the edge until you
-- let go. Back off the edge, they're on the pin again, under the cursor.
-- D.pinDrag: { snap (the dock when the drag began), keys (the pin's kits),
-- want (where they're tucked: a box, "edge:<key>" or "new:<side>", or nil),
-- box, isNew, reuse (one table for the box it makes) }.
local function PinDragTick()
    local pd = D.pinDrag
    if not pd or InCombatLockdown() or not D.pin then return end
    local x, y = Center(D.pin)
    if not x then return end
    local side = NearEdge(x, y)
    local want
    if side then
        local b = BoxAt(x, y, pd.isNew and pd.box or nil, pd.box and 0 or #pd.keys)
        if b and b == pd.box then
            want = pd.want -- (the box they're in now: still there)
        elseif b then
            want = b
        else
            local ek = EdgeKitAt(nil, x, y)
            want = ek and ("edge:" .. ek) or ("new:" .. side)
        end
    end
    if want ~= pd.want then
        Restore(pd.snap, true)
        DB().pin = { x, y }
        pd.want, pd.box, pd.isNew = want, nil, nil
        if want then
            pd.reuse = pd.reuse or {}
            local b
            if type(want) == "table" then
                b = want
            elseif want:sub(1, 5) == "edge:" then
                b = BoxFromEdge(want:sub(6), pd.reuse)
            else
                b = NewBox(side, AlongOf(side, x, y), pd.reuse)
                pd.isNew = true
            end
            TuckInto(b, pd.keys)
            pd.box = b
            HoldBox(b)
            D.pin:SetAlpha(0)
        else
            D.pin:SetAlpha(1)
        end
        D.Layout()
    elseif pd.isNew and pd.box then
        pd.box.side, pd.box.at = side, AlongOf(side, x, y) -- (its frame follows on its next tick)
    end
end

function D.PinDragStart()
    if InCombatLockdown() then return end
    D.pinDrag = { snap = Snapshot(), keys = DockedKeys() }
    -- Free to reach the edges while it's dragged (the next layout puts back
    -- the room the open kits need).
    if D.pin and D.pin.SetClampRectInsets then D.pin:SetClampRectInsets(0, 0, 0, 0) end
    local w = D.pinWatch
    if not w then
        w = CreateFrame("Frame")
        local elapsed = 0
        w:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 0.05 then return end
            elapsed = 0
            PinDragTick()
        end)
        D.pinWatch = w
    end
    w:Show()
end

-- Let go of the pin: tucked into a box at an edge, they stay there.
-- Returns whether they did (otherwise the pin just stays where it's dropped).
function D.PinDragStop()
    if D.pinWatch then D.pinWatch:Hide() end
    local pd = D.pinDrag
    D.pinDrag = nil
    if D.pin then D.pin:SetAlpha(1) end
    if not pd or not pd.want or InCombatLockdown() then return false end
    HoldBox(pd.box)
    D.Layout()
    return true
end

-- Slash command for trying it out: /kitdock park <key>, /kitdock unpark <key>.
SLASH_KITDOCK1 = "/kitdock"
SlashCmdList["KITDOCK"] = function(msg)
    local cmd, key = (msg or ""):match("^%s*(%S*)%s*(%S*)")
    cmd = (cmd or ""):lower()
    local function say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Kit Dock:|r " .. text) end
    if cmd == "park" and D.kits[key] then
        if not D.Park(key) then say("can't park " .. key .. " (in combat, or it's an edges-only kit)") end
    elseif cmd == "unpark" and D.kits[key] then
        D.Unpark(key)
    else
        local keys = {}
        for k in pairs(D.kits) do keys[#keys + 1] = k end
        table.sort(keys)
        say("/kitdock park <kit> or /kitdock unpark <kit>. Kits here: " .. table.concat(keys, ", "))
    end
end

-- Put the pin back in the middle of the screen.
function D.ResetPin()
    if InCombatLockdown() then return end
    Pin()
    SetPinAt(UIParent:GetWidth() / 2, UIParent:GetHeight() / 2)
    D.Layout()
end

-- A docking option changed somewhere (a kit's settings panel or the Kits
-- menu): let every kit's panel catch up.
function D.SettingsChanged()
    for _, api in pairs(D.kits) do
        if api.SettingsChanged then api.SettingsChanged() end
    end
end

-- Point the triangle the other way.
function D.Flip()
    if InCombatLockdown() then return end
    local db = DB()
    db.triUp = not db.triUp
    D.Layout()
end

---------------------------------------------------------------------------
-- One shared minimap button when two or more kits are installed. Its menu
-- shows or hides each kit entirely and opens each kit's settings. Each
-- addon's own minimap button steps aside while this one is there.
---------------------------------------------------------------------------

local NAMES = { fak = "First Aid Kit", ck = "Camping Kit", fk = "Fishing Kit" }

function D.SharedMinimap() return Installed() >= 2 end

local mmButton, menu

local function PlaceMinimap()
    if not mmButton then return end
    local angle = math.rad(DB().minimapAngle or 225)
    local r = (Minimap:GetWidth() / 2) + 6
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function BuildMenu()
    if menu then return menu end
    local ok, f = pcall(CreateFrame, "Frame", "KitDockMenu", UIParent, "BackdropTemplate")
    if not ok or not f then f = CreateFrame("Frame", "KitDockMenu", UIParent) end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0.06, 0.07, 0.05, 0.95)
        f:SetBackdropBorderColor(0.75, 0.62, 0.3, 1)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.07, 0.05, 0.95)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("Kits")
    f.rows = {}
    f:Hide()
    tinsert(UISpecialFrames, "KitDockMenu") -- Escape closes it
    menu = f
    return f
end

-- The kits in the menu: the docking kits first, then any others by name.
local function MenuKeys()
    local keys = {}
    for _, k in ipairs(ORDER) do if D.kits[k] then keys[#keys + 1] = k end end
    local rest = {}
    for k in pairs(D.kits) do if not InList(ORDER, k) then rest[#rest + 1] = k end end
    table.sort(rest, function(a, b) return (D.kits[a].name or a) < (D.kits[b].name or b) end)
    for _, k in ipairs(rest) do keys[#keys + 1] = k end
    return keys
end

local function FillMenu()
    local f = BuildMenu()
    local y = -30
    local i = 0
    for _, k in ipairs(MenuKeys()) do
        local api = D.kits[k]
        if api then
            i = i + 1
            local row = f.rows[i]
            if not row then
                row = {}
                local okc, cb = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
                if not okc or not cb then cb = CreateFrame("CheckButton", nil, f) cb:SetSize(24, 24) end
                cb:SetSize(24, 24)
                row.cb = cb
                row.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                local okb, gear = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
                if not okb or not gear then gear = CreateFrame("Button", nil, f) end
                gear:SetSize(70, 20)
                gear:SetText("Settings")
                row.gear = gear
                f.rows[i] = row
            end
            row.cb:ClearAllPoints()
            row.cb:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
            row.label:SetText(NAMES[k] or api.name or k)
            row.gear:ClearAllPoints()
            row.gear:SetPoint("RIGHT", f, "TOPRIGHT", -10, y - 12)
            row.cb:SetChecked(not (api.IsHidden and api.IsHidden()))
            row.cb:SetScript("OnClick", function(self)
                if InCombatLockdown() then
                    self:SetChecked(not self:GetChecked())
                    return
                end
                if api.SetHidden then api.SetHidden(not self:GetChecked()) end
                D.Layout()
            end)
            row.gear:SetScript("OnClick", function()
                f:Hide()
                if api.OpenSettings then api.OpenSettings() end
            end)
            row.cb:Show() row.label:Show() row.gear:Show()
            y = y - 28
        end
    end
    for j = i + 1, #f.rows do f.rows[j].cb:Hide() f.rows[j].label:Hide() f.rows[j].gear:Hide() end
    f:SetSize(240, -y + 10)
end

local function ToggleMenu()
    local f = BuildMenu()
    if f:IsShown() then f:Hide() return end
    FillMenu()
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", mmButton, "BOTTOMLEFT", 0, 0)
    f:Show()
end

function D.SetupMinimap()
    local shared = D.SharedMinimap()
    for _, api in pairs(D.kits) do
        if api.ApplyMinimap then api.ApplyMinimap() end -- own buttons step aside (or come back)
    end
    if not shared or not Minimap then
        if mmButton then mmButton:Hide() end
        return
    end
    if not mmButton then
        local b = CreateFrame("Button", "KitDockMinimapButton", Minimap)
        b:SetSize(31, 31)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        -- The Kits chest (it has its own gold rim), drawn 27 across inside the
        -- 31 button so it sits the same size as other addons' minimap buttons.
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon = icon
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture(D.media .. "glow_ring")
        hl:SetBlendMode("ADD")
        hl:SetAllPoints(icon)
        hl:SetAlpha(0.5)
        b:SetScript("OnClick", function() ToggleMenu() end)
        b:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local px, py = GetCursorPosition()
                local sc = Minimap:GetEffectiveScale()
                DB().minimapAngle = math.deg(math.atan2(py / sc - my, px / sc - mx)) % 360
                PlaceMinimap()
            end)
            GameTooltip:Hide()
        end)
        b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("Kits")
            GameTooltip:AddLine("Click: show or hide each kit, and open its settings", 1, 1, 1)
            GameTooltip:AddLine("Drag: move around the minimap", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mmButton = b
    end
    -- The chest at the size it shows on screen (addon art isn't mipmapped).
    local px = 27
    local h = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) -- (an "and" would keep only the width)
    if h and h > 0 then px = 27 * mmButton:GetEffectiveScale() * h / 768 end
    local size = 128
    for _, sz in ipairs({ 32, 48, 64, 96, 128 }) do if px <= sz then size = sz break end end
    mmButton.icon:SetTexture(OWN_MEDIA .. "kits_chest_" .. size, nil, nil, "LINEAR")
    mmButton:SetShown(DB().minimap ~= false)
    PlaceMinimap()
    if menu and menu:IsShown() then FillMenu() end
end

-- The pin steps out of the way in combat when every docked kit hides in
-- combat (each kit's own setting; First Aid Kit never does), and comes back
-- with them after. Combat also queues any layout that couldn't run.
local function PinHidesInCombat()
    local keys = DockedKeys()
    if #keys == 0 then return false end
    for _, k in ipairs(keys) do
        local api = D.kits[k]
        if not (api.HidesInCombat and api.HidesInCombat()) then return false end
    end
    return true
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        for kit in pairs(tweens) do StopTween(kit) end
        if D.pin and PinHidesInCombat() then
            D.pinCombatHidden = true
            D.pin:Hide()
        end
    else
        for kit in pairs(tweens) do StopTween(kit) end -- any frozen by combat
        local hidden = D.pinCombatHidden
        D.pinCombatHidden = nil
        if D.pending or hidden then D.Layout() end
    end
end)
