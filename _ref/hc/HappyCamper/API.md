# Happy Camper's camp lookup (HappyCamperAPI)

From Happy Camper 1.1.1, other addons can ask Happy Camper which camps it knows near the player: where they are, how long their fires have left and which objects they have.

## Terms

You may use `HappyCamperAPI` in your addon without asking, as long as:

- you only **read** from it;
- you **credit Happy Camper** wherever its data shows (for example "Camp data: Happy Camper");
- you **never send its data on** over chat or addon messages.

Anything else (copying Happy Camper's code, reading its saved data or internals, or listening on its camp channel) still needs Torridon's permission: ask through Happy Camper's CurseForge page.

## Getting started

Players may not have Happy Camper, or may have a version from before 1.1.1, so check that the lookup is there before calling it:

```lua
if HappyCamperAPI and HappyCamperAPI.version >= 1 then
    local camps = HappyCamperAPI.GetNearbyCamps()
end
```

If your addon looks camps up while it's loading (not just later, on an event or a click), add this to your .toc so Happy Camper loads first:

```
## OptionalDeps: HappyCamper
```

## HappyCamperAPI.version

A number, now `1`. It goes up only if a call changes in a way that could break an addon using it. New fields may be added to the camps without changing it, so don't assume the fields below are the only ones.

## HappyCamperAPI.GetNearbyCamps()

Returns a list of the camps Happy Camper knows **in the player's current zone**, **on the player's layer** (or whose layer isn't known), **nearest first**:

```lua
{
    {
        mapID = 1411,          -- the map it's on
        x = 0.532, y = 0.481,  -- its fire's position on that map (0 to 1)
        layer = 9,             -- the layer it's on (the zone's own number), or nil if not known
        timeLeft = 540,        -- seconds until its fire goes out, or nil if not known
        distance = 31.6,       -- yards from the player, or nil if it can't be told
        objects = {
            { name = "Arcane Salvager", profession = 333, tier = 2 },
            { name = "Sharpening Wheel", profession = 164, tier = 1 },
        },
    },
    -- ...
}
```

- **Fields that can be nil:** `layer` (the camp's layer, or the player's, isn't known yet), `timeLeft` (nobody with Happy Camper saw the fire lit, so its burn time isn't known), `distance` (the game can't place one of them). Also `tier` in an object, for an object Happy Camper doesn't know.
- **Objects:** one entry per object at the camp, sorted by name. `name` is as the game shows it, in the player's language, so match on `profession` (the profession's skill line ID) and `tier` (1 to 3), not on the name. All of them are in the table below.
- **Each call returns new tables.** Keep them or change them as you like: nothing in Happy Camper changes. The list is only as fresh as the call, so call again for current time left and distances.
- **It never raises an error.** If something goes wrong inside Happy Camper, you get an empty list.

### Which camps are listed

It never gives more than Happy Camper shows the player:

- **No player names.** Not who lit, reported or placed anything.
- **Standard mode:** players can choose Standard mode in Happy Camper, which shows other players' camps only as smoke on the map. For them the list holds only their own camps and the one they're standing at. Players in Enhanced mode get all of them.
- **Left out:** camps posted in chat, camps from other camp addons and camps only seen in passing (all of them only roughly placed), camps known to be on another layer, fires with no camp buffs, and fires that have gone out.
- **An empty list** when there are no camps near, or the player's position can't be read (in a dungeon, for example).

### How often to call it

It goes through every camp Happy Camper knows (at most 200), so call it when you need it: on an event, a click, or a timer of a second or more. Not every frame.

## Camp objects by profession and tier

| Profession | Skill line | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|---|
| Alchemy | 171 | Mana Well | Fermenter | Alchemy Laboratory |
| Blacksmithing | 164 | Sharpening Wheel | Anvil | Master Forge |
| Cooking | 185 | (the fire itself) | Cookie's Feast | Iron Oven |
| Enchanting | 333 | Enchanted Lute | Arcane Salvager | Arcane Forge |
| Engineering | 202 | Reagent Bot | Repair Bot | Anarchist's Workbench |
| First Aid | 129 | First Aid Kit | Toxin Study | Plague Doctor's Laboratory |
| Fishing | 356 | Fish Bowl | Fishing Rack | Fishing Hut |
| Herbalism | 182 | Incense Candle | Greenhouse | Seed Hybridizer |
| Leatherworking | 165 | Camp Tent | Tanning Rack | Sewing Machine |
| Mining | 186 | Lodestone | Rock Garden | Molten Foundry |
| Skinning | 393 | Camp Chair | Field Guide | Trapper's Workbench |
| Tailoring | 197 | Faction Banner | Spinning Wheel | Loom |

## Examples

**The nearest camp with an Arcane Salvager:**

```lua
local function NearestSalvager()
    if not HappyCamperAPI then return end
    for _, camp in ipairs(HappyCamperAPI.GetNearbyCamps()) do -- nearest first
        for _, object in ipairs(camp.objects) do
            if object.profession == 333 and object.tier == 2 then return camp end
        end
    end
end
```

**Whether the player is at a camp with one:** Happy Camper counts anything within 40 yards of a fire as part of its camp.

```lua
local camp = NearestSalvager()
local atSalvager = camp ~= nil and camp.distance ~= nil and camp.distance <= 40
```

**Showing a camp, with the credit:**

```lua
local camp = NearestSalvager()
if camp then
    local minutes = camp.timeLeft and math.ceil(camp.timeLeft / 60)
    print(format("Arcane Salvager %d yards away%s (camp data: Happy Camper)", math.floor(camp.distance or 0),
        minutes and format(", %d min left", minutes) or ""))
end
```

## Questions

Ask Torridon through Happy Camper's CurseForge page.
