-- Standalone, guns-only BFM for BLUE player airplane groups; no MIST/MOOSE needed.
-- Mission start: DO SCRIPT FILE BFM.lua, then DO SCRIPT BFM.init().
-- Put Combined Joint Task Forces Red on RED in the mission's country setup.
-- See README.md for configuration, multiplayer behavior, and mission checks.
BFM = {}

do
    local METERS_PER_NM = 1852
    local METERS_PER_FOOT = 0.3048
    local MENU_INTERVAL = 5
    local CONTROLLER_DELAY = 1
    local MESSAGE_SECONDS = 12
    local AIRFRAMES_PER_MENU = 7
    local MIN_SPEED = 150 -- m/s; keep the AI above a practical spawn speed
    local MAX_SPEED = 350
    local ROUTE_LENGTH = 10 * METERS_PER_NM
    local TASK = { CAP = "CAP", COMBO = "ComboTask", ATTACK_GROUP = "AttackGroup" }
    local WAYPOINT = { TURNING_POINT = "Turning Point", BARO = "BARO" }

    -- Mission Editor labels mapped to DCS's serialized aircraft skill values.
    BFM.Skill = {
        CADET = "Cadet", ROOKIE = "Average", TRAINED = "Good",
        VETERAN = "High", ACE = "Excellent", RANDOM = "Random",
    }
    -- Keep existing mission configuration compatible with the original names.
    BFM.Skill.AVERAGE = BFM.Skill.ROOKIE
    BFM.Skill.GOOD = BFM.Skill.TRAINED
    BFM.Skill.HIGH = BFM.Skill.VETERAN
    BFM.Skill.EXCELLENT = BFM.Skill.ACE
    BFM.Setup = { NEUTRAL = "neutral", OFFENSIVE = "offensive", DEFENSIVE = "defensive" }
    local setups = {
        { kind = BFM.Setup.NEUTRAL, label = "Neutral (head-on)", positionSign = 1, headingOffset = math.pi },
        { kind = BFM.Setup.OFFENSIVE, label = "Offensive (you behind)", positionSign = 1, headingOffset = 0 },
        { kind = BFM.Setup.DEFENSIVE, label = "Defensive (enemy behind)", positionSign = -1, headingOffset = 0 },
    }
    local defaultOpponents = {
        { label = "MiG-29S", type = "MiG-29S", fuelKg = 1750 },
        { label = "MiG-21bis", type = "MiG-21Bis", fuelKg = 1400 },
    }

    local config
    local initialized = false
    local serial = 0
    local sessions = {}

    local function message(session, text)
        trigger.action.outTextForGroup(session.groupID, "BFM: " .. text, MESSAGE_SECONDS)
    end

    -- These handles are optional: a group/unit may have died or despawned.
    local function liveGroup(session)
        local group = Group.getByName(session.groupName)
        if group and group:isExist() and group:getID() == session.groupID then
            return group
        end
    end

    local function referencePlayer(session)
        local group = liveGroup(session)
        if group then
            for _, unit in ipairs(group:getUnits()) do
                if unit:isExist() and unit:getLife() > 0 and unit:getPlayerName() and unit:inAir() then
                    return unit
                end
            end
        end
    end

    local function removeOpponent(session)
        if session.opponent then
            if session.opponent:isExist() then
                session.opponent:destroy()
            end
            session.opponent = nil
        end
    end

    local function removeSession(session)
        removeOpponent(session)
        missionCommands.removeItemForGroup(session.groupID, session.menu)
        sessions[session.groupID] = nil
    end

    local function nextName()
        local name
        repeat
            serial = serial + 1
            name = string.format("BFM Opponent %d", serial)
        until not Group.getByName(name) and not Unit.getByName(name .. " Pilot")
        return name
    end

    local function waypoint(x, z, altitude, speed)
        return {
            x = x, y = z, alt = altitude, alt_type = WAYPOINT.BARO,
            speed = speed, speed_locked = true,
            type = WAYPOINT.TURNING_POINT, action = WAYPOINT.TURNING_POINT,
            task = { id = TASK.COMBO, params = { tasks = {} } },
        }
    end

    local function spawnOpponent(args)
        local session = args.session
        if sessions[session.groupID] ~= session then
            return -- Callback from a menu belonging to a previous slot/session.
        end
        local player = referencePlayer(session)
        if not player then
            message(session, "An airborne player in your group is required.")
            return
        end

        local position = player:getPosition()
        local forward = position.x
        local horizontalLength = math.sqrt(forward.x * forward.x + forward.z * forward.z)
        if horizontalLength < 0.01 then
            message(session, "Level out before requesting a setup.")
            return
        end
        local dx, dz = forward.x / horizontalLength, forward.z / horizontalLength
        local setup = args.setup
        local distance = config.tailDistanceNm * METERS_PER_NM
        if setup.kind == BFM.Setup.NEUTRAL then
            distance = config.neutralDistanceNm * METERS_PER_NM
        end
        local x = position.p.x + dx * distance * setup.positionSign
        local z = position.p.z + dz * distance * setup.positionSign
        local altitude = position.p.y
        local clearance = config.minimumClearanceFeet * METERS_PER_FOOT
        if altitude - land.getHeight({ x = x, y = z }) < clearance then
            message(session, "Not enough terrain clearance at the spawn point. Climb or turn toward lower terrain.")
            return
        end

        local heading = (math.atan2(dz, dx) + setup.headingOffset) % (2 * math.pi)
        local velocity = player:getVelocity()
        local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
        speed = math.max(MIN_SPEED, math.min(MAX_SPEED, speed))
        local destinationX = x + math.cos(heading) * ROUTE_LENGTH
        local destinationZ = z + math.sin(heading) * ROUTE_LENGTH
        local destinationAltitude = math.max(altitude,
            land.getHeight({ x = destinationX, y = destinationZ }) + clearance)
        local name = nextName()
        local opponent = args.opponent
        local groupData = {
            name = name, task = TASK.CAP, start_time = 0,
            lateActivation = false, uncontrolled = false, hidden = false,
            communication = false, x = x, y = z,
            route = { points = {
                waypoint(x, z, altitude, speed),
                waypoint(destinationX, destinationZ, destinationAltitude, speed),
            } },
            units = { {
                name = name .. " Pilot", type = opponent.type, skill = config.skill,
                x = x, y = z, alt = altitude, alt_type = WAYPOINT.BARO,
                speed = speed, heading = heading, psi = -heading,
                callsign = 101, onboard_num = string.format("%03d", serial % 1000),
                payload = { pylons = {}, fuel = opponent.fuelKg, gun = 100, flare = 0, chaff = 0 },
            } },
        }

        local spawned = coalition.addGroup(config.opponentCountry, Group.Category.AIRPLANE, groupData)
        if not spawned then -- addGroup can fail at runtime, e.g. an unavailable aircraft type.
            message(session, "DCS could not spawn the opponent; the previous fight has been kept.")
            return
        end
        removeOpponent(session)
        session.opponent = spawned
        session.lastSelection = { session = session, opponent = opponent, setup = setup }

        -- DCS needs time to create the controller after addGroup (Hoggit addGroup notes).
        timer.scheduleFunction(function()
            if sessions[session.groupID] ~= session or session.opponent ~= spawned then
                return
            end
            if not spawned:isExist() then
                session.opponent = nil
                return
            end
            if not referencePlayer(session) then
                removeOpponent(session)
                return
            end
            local controller = spawned:getController()
            controller:setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.OPEN_FIRE)
            controller:setTask({ id = TASK.ATTACK_GROUP, params = { groupId = session.groupID } })
        end, nil, timer.getTime() + CONTROLLER_DELAY)

        message(session, string.format("%s, %s, %.1f NM from %s. Guns only; fight begins immediately.",
            opponent.label, setup.label, distance / METERS_PER_NM, player:getName()))
    end

    local function createSession(group)
        local session = { groupID = group:getID(), groupName = group:getName() }
        sessions[session.groupID] = session
        session.menu = missionCommands.addSubMenuForGroup(session.groupID, "BFM")
        local airframeMenu = session.menu
        for index, opponent in ipairs(config.opponents) do
            if index > 1 and (index - 1) % AIRFRAMES_PER_MENU == 0 then
                airframeMenu = missionCommands.addSubMenuForGroup(session.groupID, "More airframes", airframeMenu)
            end
            local menu = missionCommands.addSubMenuForGroup(session.groupID, opponent.label, airframeMenu)
            for _, setup in ipairs(setups) do
                missionCommands.addCommandForGroup(session.groupID, setup.label, menu, spawnOpponent,
                    { session = session, opponent = opponent, setup = setup })
            end
        end
        missionCommands.addCommandForGroup(session.groupID, "Reset last opponent", session.menu, function()
            if session.lastSelection then
                spawnOpponent(session.lastSelection)
            else
                message(session, "Choose an opponent and setup first.")
            end
        end)
        missionCommands.addCommandForGroup(session.groupID, "Remove opponent", session.menu, function()
            removeOpponent(session)
            message(session, "Opponent removed.")
        end)
    end

    local function updateMenus(_, time)
        local occupied = {}
        for _, player in ipairs(coalition.getPlayers(coalition.side.BLUE)) do
            if player:isExist() and player:getLife() > 0 then
                local group = player:getGroup()
                if group and group:getCategory() == Group.Category.AIRPLANE then
                    local groupID = group:getID()
                    occupied[groupID] = true
                    local session = sessions[groupID]
                    if session and session.groupName ~= group:getName() then
                        removeSession(session)
                        session = nil
                    end
                    if not session then
                        createSession(group)
                    end
                end
            end
        end
        for groupID, session in pairs(sessions) do
            if not occupied[groupID] then
                removeSession(session)
            elseif session.opponent then
                if not referencePlayer(session) then
                    removeOpponent(session)
                elseif not session.opponent:isExist() then
                    session.opponent = nil
                end
            end
        end
        return time + MENU_INTERVAL
    end

    -- options is intentionally optional. Call once after loading; repeated calls do nothing.
    function BFM.init(options)
        if initialized then
            return
        end
        config = {
            opponentCountry = country.id.CJTF_RED,
            neutralDistanceNm = 2,
            tailDistanceNm = 0.7,
            minimumClearanceFeet = 1000,
            skill = BFM.Skill.VETERAN,
            opponents = defaultOpponents,
        }
        for key, value in pairs(options or {}) do
            assert(config[key] ~= nil, "BFM: unknown configuration option " .. tostring(key))
            config[key] = value
        end
        for _, key in ipairs({ "neutralDistanceNm", "tailDistanceNm", "minimumClearanceFeet" }) do
            local value = config[key]
            assert(type(value) == "number" and value > 0 and value < math.huge,
                "BFM: " .. key .. " must be a finite positive number")
        end
        local validSkill = false
        for _, skill in pairs(BFM.Skill) do
            if config.skill == skill then validSkill = true end
        end
        assert(validSkill, "BFM: skill must be a BFM.Skill value")
        assert(type(config.opponents) == "table" and #config.opponents > 0,
            "BFM: opponents must be a non-empty array")
        local configuredOpponents, labels = {}, {}
        local count = 0
        for key in pairs(config.opponents) do
            assert(type(key) == "number" and key >= 1 and key <= #config.opponents and key % 1 == 0,
                "BFM: opponents must be a contiguous array")
            count = count + 1
        end
        assert(count == #config.opponents, "BFM: opponents must be a contiguous array")
        for index, opponent in ipairs(config.opponents) do
            local context = "BFM: opponents[" .. index .. "] "
            assert(type(opponent) == "table", context .. "must be a table")
            assert(type(opponent.type) == "string" and opponent.type:find("%S"),
                context .. "requires a DCS aircraft type")
            -- label is optional; the aircraft type is its documented default.
            local label = opponent.label
            if label == nil then label = opponent.type end
            assert(type(label) == "string" and label:find("%S"), context .. "label must be non-empty")
            assert(not labels[label], context .. "label must be unique")
            local fuel = opponent.fuelKg
            assert(type(fuel) == "number" and fuel > 0 and fuel < math.huge,
                context .. "fuelKg must be a finite positive number")
            labels[label] = true
            configuredOpponents[index] = { label = label, type = opponent.type, fuelKg = fuel }
        end
        -- Own a snapshot so later edits to the caller's table cannot alter live menus or resets.
        config.opponents = configuredOpponents
        assert(coalition.getCountryCoalition(config.opponentCountry) == coalition.side.RED,
            "BFM: opponentCountry must belong to RED in this mission")
        updateMenus(nil, timer.getTime())
        timer.scheduleFunction(updateMenus, nil, timer.getTime() + MENU_INTERVAL)
        initialized = true
        env.info(string.format("BFM initialized: %d airframes, guns only", #config.opponents))
    end
end
