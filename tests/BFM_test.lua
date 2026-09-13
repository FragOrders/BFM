-- Run from repository root with Lua 5.1. No DCS or third-party libraries required.
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001,
        string.format("expected %.6f, got %.6f", expected, actual))
end

local function fixture()
    local f = { now = 0, players = {}, groups = {}, units = {}, menus = {}, commands = {},
        scheduled = {}, spawned = {}, messages = {}, terrain = 0, failSpawn = false }
    country = { id = { CJTF_RED = 80 } }
    Group = { Category = { AIRPLANE = 0, HELICOPTER = 1 } }
    Unit = {}
    AI = { Option = { Air = { id = { ROE = 0 }, val = { ROE = { OPEN_FIRE = 2 } } } } }
    function Group.getByName(name) return f.groups[name] end
    function Unit.getByName(name) return f.units[name] end
    land = { getHeight = function() return f.terrain end }
    env = { info = function() end }
    trigger = { action = { outTextForGroup = function(id, text)
        f.messages[#f.messages + 1] = { id = id, text = text }
    end } }
    timer = {
        getTime = function() return f.now end,
        scheduleFunction = function(callback, args, time)
            f.scheduled[#f.scheduled + 1] = { callback = callback, args = args, time = time }
            return #f.scheduled
        end,
    }
    missionCommands = {
        addSubMenuForGroup = function(id, label, parent)
            local menu = { id = id, label = label, parent = parent }
            f.menus[#f.menus + 1] = menu
            return menu
        end,
        addCommandForGroup = function(id, label, parent, callback, args)
            f.commands[#f.commands + 1] = {
                id = id, label = label, parent = parent, callback = callback, args = args,
            }
        end,
        removeItemForGroup = function(id, menu)
            assert(menu.id == id)
            menu.removed = true
        end,
    }
    function f:advance(seconds)
        local target = self.now + seconds
        while true do
            local nextIndex, nextItem
            for index, item in ipairs(self.scheduled) do
                if item.time <= target and (not nextItem or item.time < nextItem.time) then
                    nextIndex, nextItem = index, item
                end
            end
            if not nextItem then break end
            table.remove(self.scheduled, nextIndex)
            self.now = nextItem.time
            local again = nextItem.callback(nextItem.args, self.now)
            if again then
                nextItem.time = again
                self.scheduled[#self.scheduled + 1] = nextItem
            end
        end
        self.now = target
    end
    function f:group(id, name)
        local group = { id = id, name = name, exists = true, units = {} }
        function group:getID() return self.id end
        function group:getName() return self.name end
        function group:getCategory() return Group.Category.AIRPLANE end
        function group:isExist() return self.exists end
        function group:getUnits() return self.units end
        function group:destroy()
            self.exists = false
            f.groups[self.name] = nil
        end
        self.groups[name] = group
        return group
    end
    function f:player(group, name)
        local unit = { name = name, airborne = true, life = 100, occupied = true,
            position = { p = { x = 100, y = 3000, z = 200 }, x = { x = 1, y = 0, z = 0 } },
            velocity = { x = 200, y = 0, z = 0 } }
        function unit:getName() return self.name end
        function unit:isExist() return self.life > 0 end
        function unit:getLife() return self.life end
        function unit:getPlayerName() if self.occupied then return self.name end end
        function unit:inAir() return self.airborne end
        function unit:getGroup() return group end
        function unit:getPosition() return self.position end
        function unit:getVelocity() return self.velocity end
        group.units[#group.units + 1] = unit
        self.players[#self.players + 1] = unit
        return unit
    end
    function f:command(id, parent, label)
        for i = #self.commands, 1, -1 do
            local command = self.commands[i]
            if command.id == id and command.parent.label == parent and command.label == label then
                return command
            end
        end
        error("missing command: " .. parent .. "/" .. label)
    end
    function f:choose(id, parent, label)
        local command = self:command(id, parent, label)
        command.callback(command.args)
    end
    coalition = {
        side = { RED = 1, BLUE = 2 },
        getCountryCoalition = function(id) if id == country.id.CJTF_RED then return coalition.side.RED end end,
        getPlayers = function(side)
            assert(side == coalition.side.BLUE)
            local players = {}
            for _, unit in ipairs(f.players) do
                if unit.occupied then players[#players + 1] = unit end
            end
            return players
        end,
        addGroup = function(countryID, category, data)
            assert(countryID == country.id.CJTF_RED and category == Group.Category.AIRPLANE)
            if f.failSpawn then return nil end
            assert(not f.groups[data.name] and not f.units[data.units[1].name], "name collision")
            local group = f:group(100 + #f.spawned, data.name)
            group.data, group.created = data, f.now
            group.controller = {
                setOption = function(_, id, value) group.option = { id, value } end,
                setTask = function(_, task) group.task = task end,
            }
            function group:getController()
                assert(f.now >= self.created + 1, "controller accessed too early")
                return self.controller
            end
            f.spawned[#f.spawned + 1] = group
            return group
        end,
    }
    dofile("BFM.lua")
    return f
end

local tests = {}
function tests.geometry_and_payloads()
    local f = fixture()
    local player = f:player(f:group(1, "Blue"), "Lead")
    BFM.init()
    local cases = {
        { label = "Neutral (head-on)", offset = 2 * 1852, heading = math.pi },
        { label = "Offensive (you behind)", offset = 0.7 * 1852, heading = 0 },
        { label = "Defensive (enemy behind)", offset = -0.7 * 1852, heading = 0 },
    }
    for _, heading in ipairs({ 0, math.pi / 2, math.pi, 3 * math.pi / 2 }) do
        player.position.x = { x = math.cos(heading), y = 0, z = math.sin(heading) }
        for _, aircraft in ipairs({ { "MiG-29S", "MiG-29S" }, { "MiG-21bis", "MiG-21Bis" } }) do
            for _, case in ipairs(cases) do
                f:choose(1, aircraft[1], case.label)
                local group = f.spawned[#f.spawned]
                local unit = group.data.units[1]
                near(unit.x, 100 + math.cos(heading) * case.offset)
                near(unit.y, 200 + math.sin(heading) * case.offset)
                near(math.cos(unit.heading), math.cos(heading + case.heading))
                near(math.sin(unit.heading), math.sin(heading + case.heading))
                near(unit.alt, 3000)
                near(unit.speed, 200)
                assert(unit.type == aircraft[2] and next(unit.payload.pylons) == nil and unit.payload.gun == 100)
                assert(group.data.x == unit.x and group.data.y == unit.y)
                assert(group.task == nil)
                f:advance(1)
                assert(group.task.id == "AttackGroup" and group.task.params.groupId == 1)
            end
        end
    end
    assert(#f.spawned == 24)
end

function tests.reset_and_isolation()
    local f = fixture()
    local player = f:player(f:group(1, "Blue One"), "One")
    f:player(f:group(2, "Blue Two"), "Two")
    local unrelated = f:group(3, "Mission RED AI")
    BFM.init()
    f:choose(1, "MiG-29S", "Neutral (head-on)")
    local old = f.spawned[1]
    f:choose(2, "MiG-21bis", "Defensive (enemy behind)")
    player.position.p.x = 5000
    f:choose(1, "BFM", "Reset last opponent")
    assert(not old:isExist() and unrelated:isExist() and f.spawned[2]:isExist())
    near(f.spawned[3].data.units[1].x, 5000 + 2 * 1852)
    f:choose(1, "BFM", "Remove opponent")
    f:advance(1)
    assert(old.task == nil and f.spawned[3].task == nil)
    assert(f.spawned[2].task.params.groupId == 2 and unrelated:isExist())
    f:choose(1, "BFM", "Reset last opponent")
    assert(#f.spawned == 4)
end

function tests.rejected_spawns_preserve_fight()
    local f = fixture()
    local player = f:player(f:group(1, "Blue"), "One")
    BFM.init()
    f:choose(1, "MiG-29S", "Neutral (head-on)")
    local old = f.spawned[1]
    f.terrain = 2900
    f:choose(1, "MiG-21bis", "Defensive (enemy behind)")
    assert(#f.spawned == 1 and old:isExist())
    f.terrain, f.failSpawn = 0, true
    f:choose(1, "MiG-21bis", "Defensive (enemy behind)")
    assert(#f.spawned == 1 and old:isExist())
    f.failSpawn, player.airborne = false, false
    f:choose(1, "BFM", "Reset last opponent")
    assert(#f.spawned == 1)
    player.airborne = true
    player.position.x = { x = 0, y = 1, z = 0 }
    f:choose(1, "BFM", "Reset last opponent")
    assert(#f.spawned == 1)
    player.position.x = { x = 1, y = 0, z = 0 }
    f:choose(1, "BFM", "Reset last opponent")
    assert(f.spawned[2].data.units[1].type == "MiG-29S")
end

function tests.menu_and_player_lifecycle()
    local f = fixture()
    BFM.init()
    BFM.init()
    assert(#f.scheduled == 1 and #f.menus == 0)
    local group = f:group(1, "Blue")
    local lead = f:player(group, "Lead")
    local wing = f:player(group, "Wing")
    lead.airborne = false
    wing.position.p.x = 9000
    f:advance(5)
    assert(#f.menus == 3 and #f.commands == 8)
    f:choose(1, "BFM", "Reset last opponent")
    assert(#f.spawned == 0)
    f:choose(1, "MiG-29S", "Neutral (head-on)")
    near(f.spawned[1].data.units[1].x, 9000 + 2 * 1852)
    local stale = f:command(1, "MiG-29S", "Neutral (head-on)")
    wing.airborne = false
    f:advance(5)
    assert(not f.spawned[1]:isExist() and not f.menus[1].removed)
    lead.occupied, wing.occupied = false, false
    f:advance(5)
    assert(f.menus[1].removed)
    lead.occupied, lead.airborne = true, true
    f:advance(5)
    assert(#f.menus == 6)
    stale.callback(stale.args)
    assert(#f.spawned == 1)
    f:choose(1, "MiG-21bis", "Neutral (head-on)")
    assert(#f.spawned == 2)
end

function tests.config_and_speed_limits()
    local f = fixture()
    local player = f:player(f:group(1, "Blue"), "One")
    assert(not pcall(BFM.init, { tailDistanceNm = -1 }))
    assert(not pcall(BFM.init, { skill = "Player" }))
    assert(not pcall(BFM.init, { opponentCountry = 999 }))
    BFM.init({ neutralDistanceNm = 4, skill = BFM.Skill.ACE })
    player.velocity.x = 20
    f:choose(1, "MiG-29S", "Neutral (head-on)")
    local unit = f.spawned[1].data.units[1]
    near(unit.x, 100 + 4 * 1852)
    assert(unit.speed == 150 and unit.skill == BFM.Skill.EXCELLENT)
    player.velocity.x = 1000
    f:choose(1, "BFM", "Reset last opponent")
    assert(f.spawned[2].data.units[1].speed == 350)

    f = fixture()
    f:player(f:group(1, "Blue"), "One")
    BFM.init({ skill = BFM.Skill.CADET })
    f:choose(1, "MiG-21bis", "Neutral (head-on)")
    assert(f.spawned[1].data.units[1].skill == "Cadet")
end

function tests.collision_and_dead_opponent()
    local f = fixture()
    f:player(f:group(1, "Blue"), "One")
    local unrelated = f:group(9, "BFM Opponent 1")
    f.units["BFM Opponent 2 Pilot"] = {}
    BFM.init()
    f:choose(1, "MiG-29S", "Neutral (head-on)")
    assert(f.spawned[1].name == "BFM Opponent 3" and unrelated:isExist())
    f.spawned[1]:destroy()
    f:advance(5)
    f:choose(1, "BFM", "Reset last opponent")
    assert(#f.spawned == 2 and unrelated:isExist())
end

function tests.custom_airframes()
    local f = fixture()
    f:player(f:group(1, "Blue"), "One")
    local airframes = { { type = "F-5E-3", label = "Tiger", fuelKg = 1000 } }
    BFM.init({ opponents = airframes })
    assert(#f.menus == 2 and #f.commands == 5)
    assert(not pcall(function() f:command(1, "MiG-29S", "Neutral (head-on)") end))
    -- Caller mutation must not change the configured aircraft, load, or reset behavior.
    airframes[1].type, airframes[1].fuelKg = "MiG-29S", 2000
    f:choose(1, "Tiger", "Offensive (you behind)")
    local unit = f.spawned[1].data.units[1]
    assert(unit.type == "F-5E-3" and unit.payload.fuel == 1000)
    assert(next(unit.payload.pylons) == nil and unit.payload.gun == 100)
    f:choose(1, "BFM", "Reset last opponent")
    assert(f.spawned[2].data.units[1].type == "F-5E-3")
    f:advance(1)
    assert(f.spawned[2].task.params.groupId == 1)
end

function tests.airframe_list_validation_and_paging()
    local f = fixture()
    f:player(f:group(1, "Blue"), "One")
    local invalidLists = {
        {}, "MiG-29S", { "MiG-29S" }, { { type = "", fuelKg = 1000 } },
        { { type = "MiG-29S" } }, { { type = "MiG-29S", fuelKg = -1 } },
        { { type = "MiG-29S", fuelKg = math.huge } },
        { { type = "MiG-29S", fuelKg = 1000, label = " " } },
        { { type = "MiG-29S", fuelKg = 1000 }, { type = "MiG-29S", fuelKg = 1000 } },
        { [1] = { type = "MiG-29S", fuelKg = 1000 }, [3] = { type = "F-5E-3", fuelKg = 1000 } },
    }
    for _, list in ipairs(invalidLists) do
        assert(not pcall(BFM.init, { opponents = list }))
        assert(#f.menus == 0 and #f.scheduled == 0)
    end
    local airframes = { { type = "MiG-29S", fuelKg = 1750 } }
    for index = 2, 16 do
        airframes[index] = { type = "MiG-21Bis", label = "Fishbed " .. index, fuelKg = 1400 }
    end
    BFM.init({ opponents = airframes })
    assert(#f.commands == 16 * 3 + 2)
    assert(f:command(1, "MiG-29S", "Neutral (head-on)").parent.parent.label == "BFM")
    for _, menu in ipairs(f.menus) do
        local children = 0
        for _, child in ipairs(f.menus) do if child.parent == menu then children = children + 1 end end
        for _, command in ipairs(f.commands) do if command.parent == menu then children = children + 1 end end
        assert(children <= 10, "radio menu overflow")
    end
    f:choose(1, "Fishbed 16", "Defensive (enemy behind)")
    assert(f.spawned[1].data.units[1].type == "MiG-21Bis")
end

local passed = 0
for name, test in pairs(tests) do
    test()
    passed = passed + 1
    print("PASS " .. name)
end
print(string.format("%d BFM test scenarios passed", passed))
