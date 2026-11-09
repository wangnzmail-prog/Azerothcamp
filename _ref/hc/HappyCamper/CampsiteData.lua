-- Happy Camper. Copyright (c) 2026 Torridon. All rights reserved; see LICENSE.
local _, ns = ...

-- Popular campsites to start from (Campsites.lua): spots where at least two
-- different players camped during the beta, from the developer's capture of
-- Happy Camper's own network traffic. Written by tools/make_campsites.py: don't
-- edit by hand. Places only, no names: { mapID, x, y, faction }, x and y from 0
-- to 1 on that map.
ns.CAMPSITE_SEED = {
    { 1429, 0.324, 0.499, "Alliance" }, -- 3 players
    { 1429, 0.424, 0.664, "Alliance" }, -- 3 players
    { 1431, 0.746, 0.466, "Alliance" }, -- 5 players
    { 1432, 0.348, 0.470, "Alliance" }, -- 4 players
    { 1433, 0.243, 0.477, "Alliance" }, -- 4 players
    { 1433, 0.274, 0.487, "Alliance" }, -- 6 players
    { 1436, 0.417, 0.723, "Alliance" }, -- 2 players
    { 1436, 0.539, 0.519, "Alliance" }, -- 2 players
    { 1436, 0.554, 0.478, "Alliance" }, -- 3 players
    { 1436, 0.566, 0.530, "Alliance" }, -- 5 players
    { 1437, 0.107, 0.591, "Alliance" }, -- 3 players
    { 1438, 0.576, 0.567, "Alliance" }, -- 3 players
}
