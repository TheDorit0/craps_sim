local chipDenom = {
    [1000] = { t = 'Chip_1000' },
    [500] = { t = 'Chip_500' },
    [100] = { t = 'Chip_100' },
    [50] = { t = 'Chip_50' },
    [10] = { t = 'Chip_10' },
    [5] = { t = 'Chip_10'}
}
local puckPos = {
    [0] = {pos = {50.91, 2.44, -16.45}},
    [4] = {pos = {41.04, 2.44, -16.45}},
    [5] = {pos = {35.21, 2.44, -16.45}},
    [6] = {pos = {29.72, 2.44, -16.45}},
    [8] = {pos = {24.04, 2.44, -16.45}},
    [9] = {pos = {18.39, 2.44, -16.45}},
    [10] = {pos = {12.49, 2.44, -16.45}}
}
local dices = {}
local diceSum = 0
local point -- current point
local puck -- the puck obj

local bettingFor
local numplayers = 0
local players = { } -- the player obj
local bettingZones = {}

--------------------------- [[
-- event handlers
--------------------------- ]]
function onObjectRandomize( obj, color )
    if (obj.tag == 'Dice') and (not randomized) then
        randomized = true
        diceSum = 0
        broadcastToAll(players[color].name .. ': dice is out!')
        startLuaCoroutine(Global, 'diceRoll')
    end
end

function onObjectEnterScriptingZone(zone, obj)
    if not isChips(obj) then
        return
    end
    bz = bettingZones[zone.getGUID()]
    assignZoneBet(bz, obj, 'enter')
end

function onObjectLeaveScriptingZone(zone, obj)
    if not isChips(obj) then
        return
    end
    bz = bettingZones[zone.getGUID()]
    assignZoneBet(bz, obj, 'leave')
end

function setVars ()
  dices[1] = getObjectFromGUID('fb85e1')
  dices[2] = getObjectFromGUID('04e437')
  puck = getObjectFromGUID('8487a4')
  puck.setPositionSmooth(puckPos[0].pos, false, true)
end

function onLoad()
    Wait.time(setVars,2)

    -- initialize betting zones
    initializeZones()

    for i, ref in ipairs(Player.getPlayers()) do
        players[ref.color] = {
            color = ref.color,
            name = ref.steam_name,
            ref = ref,
            index = i,
            bettingSheet = {}
        }
        numplayers = numplayers + 1

        -- remove all hand object
        for _, obj in pairs(ref.getHandObjects()) do
            if isChips(obj) then
                obj.destruct()
            end
        end

        spawnStartingChips(ref)
    end

    startLuaCoroutine(Global, 'addPlayerToBetSheet')
end

function addPlayerToBetSheet()
    -- update player dropdown in betting sheet
    xml = UI.getXmlTable()
   dropdown = xml[1].children[1].children[2].children[1].children[1]
    options = dropdown.children
    for _, ref in ipairs(Player.getPlayers()) do
        table.insert(options, {
            tag = "Option",
            value = ref.steam_name,
        })
    end
    UI.setXmlTable(xml)

    return 1
end

--------------------------- [[
-- game logic
--------------------------- ]]

function diceRoll()
    diceSum = 0;

    while not dices[1].resting do
        coroutine.yield(0)
    end

    while not dices[2].resting do
        coroutine.yield(0)
    end
    log('dice stopped','diceRoll()')
    diceSum = dices[1].getValue() + dices[2].getValue()
    broadcastToAll('rolled: ' .. diceSum)

    if (diceSum == 7) or (diceSum == 11) then
        if point then
            if (diceSum == 7) then
                -- reset the point
                broadcastToAll('sevened out!')
                point = nil

                puck.setPositionSmooth(puckPos[0].pos, false, true)

                -- destroy all chips except comeLine
                for key, zone in pairs(bettingZones) do
                    if key == 'comeLine' then
                        payZoneBets(bettingZones['comeLine'])
                    elseif key == 'place' then
                        for _, placeZone in pairs(zone) do
                            destroyZoneBets(placeZone)
                            resetBettingSheet()
                            for _, p in pairs(players) do
                                p.bettingSheet = {}
                            end
                        end
                    else
                        destroyZoneBets(zone)
                    end
                end
            else
                -- eleven was rolled
                -- pay field
                payZoneBets(bettingZones['field'])
                -- pay comeline
                payZoneBets(bettingZones['comeLine'])
            end
        else
            broadcastToAll('front line winners!')

            -- if no point established
            -- pay come line
            payZoneBets(bettingZones['comeLine'])

            -- pay passline
            payZoneBets(bettingZones['passLine'])

            -- pay field if 11
            if (diceSum == 11) then
                payZoneBets(bettingZones['field'])
            end
        end
    elseif (diceSum == 2) or (diceSum == 3) or (diceSum == 12) then
        if not point then
            -- lose pass line, lose come / pay field
            destroyZoneBets(bettingZones['passLine'])
        end
        -- always pay field
        payZoneBets(bettingZones['field'])
    else
      log('4,5,6,8,9,10','diceRoll()')
        -- 4, 5, 6, 8, 9, 10
        if not point then
            broadcastToAll('point established')
            log(diceSum,'diceRoll() diceSum')
            log(puck,'diceRoll() puck')
            log(puckPos,'diceRoll() puck position')
            point = diceSum
            puck.setPositionSmooth(puckPos[diceSum].pos, false, true)
            log('Locking placeBets','diceRoll()')
            log(bettingZones,'diceRoll(bettingZones)')
            lockZoneChips(bettingZones['passLine'])
            -- TODO: allow ON place bets
        else
            if (diceSum == point) then
                broadcastToAll('point won! puck is OFF')
                point = nil
                puck.setPositionSmooth(puckPos[0].pos, false, true)

                -- passline
                payZoneBets(bettingZones['passLine'])
                unlockZoneChips(bettingZones['passLine'])

                -- passline odds
                payZoneBets(bettingZones['passLineOdds'])
            end

            -- pay place bets
            payPlaceZoneBets()
            -- TODO: update come bets
        end

        -- pay field bets
        if (diceSum == 4) or (diceSum == 9) or (diceSum == 10) then
            payZoneBets(bettingZones['field'])
        elseif (diceSum == 6) or (diceSum == 8) or (diceSum == 5) then
            destroyZoneBets(bettingZones['field'])
        end
    end

    randomized = false
    coroutine.yield(1)
end

--------------------------- [[
-- chip related functions
--------------------------- ]]
function isChips(obj)
    --print('obj is '..obj.tag)
    return (obj.tag == 'Chip') or (obj.tag == 'ChipStack') or (obj.tag == "Generic")
end

-- calculate the least amount of chips needed
-- to the given value
function chipDemonimator(value)
    -- must be multiples of 10
    if value % 10 != 0 then
        return {}
    end

    chips = { 1000, 500, 100, 50, 10 }
    ret = {}
    i = 1

    while not chipDenom[value] do
        v = chips[i]
        while value > v do
            value = value - v
            table.insert(ret, v)
        end
        i = i+1
    end

    if chipDenom[value] then
        table.insert(ret, value)
    end

    return ret
end

function onSpawnedChip(obj, zone, player)
    obj.setDescription('Owner ' .. player.name)
end

function spawnChip(value, zone, player)
    pos = payZonePosition(zone, player.index)
    chipV = chipDenom[value]
    chip = spawnObject({
        type = chipV.t,
        position = pos,
        callback_function = function(obj) onSpawnedChip(obj, zone, player) end
    })
    chip.use_hands = true
end

function spawnChipInHand(value, player)
    t = player.ref.getHandTransform()
    chipV = chipDenom[value]
    chip = spawnObject({
        type = chipV.t,
        position = t.position,
    })
    chip.use_hands = true
end

function payZonePosition(zone, index)
    scale = zone.ref.getScale()
    zp = zone.ref.getPosition()
    startx = zp.x - (scale.x / 2)
    dx = (index-1) * (scale.x / math.max(numplayers, 1))
    -- TODO: dy = 0
    return { x = startx + dx, y = zp.y, z = zp.z }
end

function destroyZoneBets(zone)
    for _, obj in pairs(zone.ref.getObjects()) do
        if isChips(obj) then
            obj.destroy()
        end
    end
    zone.bets = {}
end

function payPlaceZoneBets()
    zone = bettingZones['place'][diceSum]
    log(bettingZones,'payPlaceZoneBets -bettingZones')
    log(zone.bets,'payPlacezoneBets -zone.bets')
    for color, bet in pairs(zone.bets) do
        if bet['value'] then
            hand_value = 0 -- value send to the hand
            if (diceSum == 4) or (diceSum == 10) then
                -- 9 to 5
                hand_value = 9 * bet.value / 5
            elseif (diceSum == 5) or (diceSum == 9) then
                -- 7 to 5
                hand_value = 7 * bet.value / 5
            elseif (diceSum == 6) or (diceSum == 8) then
                -- 7 to 6
                hand_value = 7 * bet.value / 6
            end
            if hand_value > 0 then
              if(PayoutManager ~= nil) then
                PayoutManager.call('pay',{color = player.color, amt = hand_value})
                --zone.bets[player.color] = 0
              else
                print(string.format('give player %s: %d', color, hand_value))
                --TODO: is rounded up to nearest 10 due to chip value
                for _, c in pairs(chipDemonimator(math.ceil(hand_value/10)*10)) do
                    spawnChipInHand(c, player)
                end
              end
            end
        end
    end
end

function payZoneBets(zone)
  log (zone.ref,'zone.ref')
    for _, ref in pairs(zone.ref.getObjects()) do
      --print('obj is '..ref.tag)
        if isChips(ref) then
          --print('destructing chip'..ref.getGUID() )
            ref.destruct()
        end
    end

    for color, value in pairs(zone.bets) do
        player = players[color]
        next_value = 0
        print('player ' .. color .. ' amount  ' .. value .. ' in ' .. zone.zonetype)

        if (value > 0) then
            if zone.zonetype == 'passLine' then
                -- pays 1 : 1
                next_value = value + value
            elseif zone.zonetype == 'comeLine' then
                -- pays 1 : 1
                next_value = value + value
            elseif (zone.zonetype == 'field') then
                if (diceSum == 2) then
                    -- pays double, 2 to 1
                    next_value = value * 3
                elseif (diceSum == 12) then
                    -- pays triple, 3 to 1
                    next_value = value * 4
                else
                    -- pays 1 to 1
                    next_value = value * 2
                end
            elseif (zone.zonetype == 'passLineOdds') then
                if (diceSum == 4) or (diceSum == 10) then
                    -- 2 to 1
                    next_value = value * 3
                elseif (diceSum == 5) or (diceSum == 9) then
                    -- 3 to 2
                    next_value = value + (value * 3 / 2)
                elseif (diceSum == 6) or (diceSum == 8) then
                    -- 6 to 5
                    next_value = value + (6 * value / 5)
                end
            end
        end

        if next_value > 0 then
          print('player ' .. color .. ' next  ' .. next_value .. ' in ' .. zone.zonetype)
          --TheDorito use the payout manager to pay
          if(PayoutManager ~= nil) then
            PayoutManager.call('pay',{color = player.color, amt = next_value})
            zone.bets[player.color] = 0
          else
              for _, c in pairs(chipDemonimator(next_value)) do
                  spawnChip(c, zone, player)
              end
              zone.bets[player.color] = next_value
          end
        end
    end
end
--------------------------- [[
-- Player management
--------------------------- ]]

function groupHand(player)
    group(player.getHandObjects())
end

function onPlayerChangeColor(player)
    spawnStartingChips(Player[player])
end

function spawnStartingChips(player)
    print('Spawning starting chips')
    if(PayoutManager ~= nil) then
      PayoutManager.call('pay',{color = player.color, amt = 5000})
    else
      Wait.condition(function () PayoutManager.call('pay',{color = player.color, amt = 5000}) end,function () return PayoutManager ~= nil end)
    end
end

--------------------------- [[
-- Zone management
--------------------------- ]]
function assignZoneBet(zone, obj, bettype)
    if not zone.bets then
        zone.bets = {}
    end

    if not obj.held_by_color then
        return
    end

    if not zone.bets[obj.held_by_color] then
        zone.bets[obj.held_by_color] = 0
    end

    if zone.zonetype == 'place' then
        -- place bets are managed by host
        return
    end

    -- lastly, if we programatically spawned the chip. check if the object
    -- is already in zoneas
    if bettype == 'enter' then
        for _, exist in pairs(zone.ref.getObjects()) do
            if obj.getGUID() == exist.getGUID() then
                return
            end
        end
    end


    --modified ThDorito to work with custom Chips.
    if(obj.getValue() ~= nil and obj.tag == 'Chip') then
      value = obj.getValue() * math.max(obj.getQuantity(), 1)
    elseif (obj.tag == "Chip") then
      value = obj.value * math.max(obj.getQuantity(), 1)
    end
    if bettype == 'leave' then
      value = value * -1
    end

    zone.bets[obj.held_by_color] = math.max(zone.bets[obj.held_by_color] + value, 0)
end

function initializeZones()
    bettingZones['passLine'] = {
        zoneid = '67c5ba',
        zonetype = 'passLine',
        ref = getObjectFromGUID('67c5ba'),
        bets = {},
    }
    bettingZones['67c5ba'] = bettingZones['passLine']

    bettingZones['passLineOdds'] = {
        zoneid = '80b675',
        zonetype = 'passLineOdds',
        ref = getObjectFromGUID('80b675'),
        bets = {},
    }
    bettingZones['80b675'] = bettingZones['passLineOdds']

    bettingZones['comeLine'] = {
        zoneid = '101bb3',
        zonetype = 'comeLine',
        ref = getObjectFromGUID('101bb3'),
        bets = {},
    }
    bettingZones['101bb3'] = bettingZones['comeLine']

    bettingZones['field'] = {
        zoneid = '73ffbe',
        zonetype = 'field',
        ref = getObjectFromGUID('73ffbe'),
        bets = {},
    }
    bettingZones['73ffbe'] = bettingZones['field']

    bettingZones['place'] = {
        [4] = {
            zoneid = '8bd16e',
            zonetype = 'place',
            zonevalue = 4,
            ref = getObjectFromGUID('8bd16e'),
            bets = {},
        },
        [5] = {
            zoneid = '97cdf1',
            zonetype = 'place',
            zonevalue = 5,
            ref = getObjectFromGUID('97cdf1'),
            bets = {},
        },
        [6] = {
            zoneid = 'f7e456',
            zonetype = 'place',
            zonevalue = 6,
            ref = getObjectFromGUID('f7e456'),
            bets = {},
        },
        [8] = {
            zoneid = '47145d',
            zonetype = 'place',
            zonevalue = 8,
            ref = getObjectFromGUID('47145d'),
            bets = {}
        },
        [9] = {
            zoneid = '5861c8',
            zonetype = 'place',
            zonevalue = 9,
            ref = getObjectFromGUID('5861c8'),
            bets = {},
        },
        [10] = {
            zoneid = 'b315b4',
            zonetype = 'place',
            zonevalue = 10,
            ref = getObjectFromGUID('b315b4'),
            bets = {},
        },
    }
    bettingZones['8bd16e'] = bettingZones['place'][4]
    bettingZones['97cdf1'] = bettingZones['place'][5]
    bettingZones['f7e456'] = bettingZones['place'][6]
    bettingZones['47145d'] = bettingZones['place'][8]
    bettingZones['5861c8'] = bettingZones['place'][9]
    bettingZones['b315b4'] = bettingZones['place'][10]

    -- bettingZones[xxxx] = 'come4'
    -- bettingZones[xxxx] = 'come5'
    -- bettingZones[xxxx] = 'come6'
    -- bettingZones[xxxx] = 'come8'
    -- bettingZones[xxxx] = 'come9'
    -- bettingZones[xxxx] = 'come10'
    -- bettingZones[xxxx] = 'dontPassLine'
end

function lockZoneChips(zone)
    for _, obj in pairs(zone.ref.getObjects()) do
        if isChips(obj) then
            obj.setLock(true)
        end
    end
end

function unlockZoneChips(zone)
    for _, obj in pairs(zone.ref.getObjects()) do
        if isChips(obj) then
            obj.setLock(false)
        end
    end
end

--------------------------- [[
-- UI management
--------------------------- ]]

function getBettingSheetUI()
    -- update player dropdown in betting sheet
    xml = UI.getXmlTable()
    dropdown = xml[1].children[1].children[2].children[1].children[1]
    placeBets = xml[1].children[1].children[3].children
    placeBetValues = xml[1].children[1].children[4].children
    return {
        players = dropdown,
        placeBets = placeBets,
        placeBetValues = placeBetValues,
    }
end

function resetBettingSheet()
    UI.setAttribute('place_bet_4', 'isOn', false)
    UI.setAttributes('place_bet_4_value', { text = 0, interactable = 'false'})
    UI.setAttribute('place_bet_5', 'isOn', false)
    UI.setAttributes('place_bet_5_value', { text = 0, interactable = 'false'})
    UI.setAttribute('place_bet_6', 'isOn', false)
    UI.setAttributes('place_bet_6_value', { text = 0, interactable = 'false'})
    UI.setAttribute('place_bet_8', 'isOn', false)
    UI.setAttributes('place_bet_8_value', { text = 0, interactable = 'false'})
    UI.setAttribute('place_bet_9', 'isOn', false)
    UI.setAttributes('place_bet_9_value', { text = 0, interactable = 'false'})
    UI.setAttribute('place_bet_10', 'isOn', false)
    UI.setAttributes('place_bet_10_value', { text = 0, interactable = 'false'})
end

function onSelectPlayer(_, value, id)
    resetBettingSheet()
    for color, p in pairs(players) do
        if p.name == value then
            bettingFor = color
            for key, value in pairs(players[bettingFor].bettingSheet) do
                UI.setAttribute(key, 'isOn', value.isOn)
                UI.setAttribute(string.format('%s_value', key), 'text', value['amount'])
                if (value.isOn) then
                    UI.setAttribute(string.format('%s_value', key), 'interactable', 'true')
                end
            end
        end
    end
end

function onTogglePlaceBet(_, value, id)
    if not players[bettingFor] then
        return
    end
    players[bettingFor].bettingSheet[id] = {
        isOn = value,
        amount = 0,
    }
    valueID = string.format("%s_value", id)
    UI.setAttribute(valueID, 'interactable', value)
    if value == 'False' then
        UI.setAttribute(valueID, 'text', 0)
    end

    -- TODO: if there is zonebet for bettingFor,
    -- return the value into players hand
end

function onPlaceBetValue(_, value, id)
    betFor = UI.getAttribute(id, 'for')
    bet = players[bettingFor].bettingSheet[betFor]
    if value == nil or value == '' then
        value = 0
    end
    if bet and bet.isOn then
        bet['amount'] = tonumber(value)
    end
end

-- only use for 'house' controlled place bets
function onSubmitBets(_, value, id)
    UI.setValue('place_bet_status', '-')
    player = players[bettingFor]
    for betField, bet in pairs(player.bettingSheet) do
        zonetype = UI.getAttribute(betField, 'zonetype')
        zonevalue = UI.getAttribute(betField, 'zonevalue')
        if bet.isOn and bet['amount'] > 0 then
            zone = bettingZones['place'][tonumber(zonevalue)]
            if not zone['bets'][bettingFor] then
                zone.bets[bettingFor] = {}
            end
            log(zone['bets'],'onSubmitBets - zone[bets]')
            marker = zone['bets'][bettingFor].marker

            if not marker then
                position = payZonePosition(zone, player.index)
                marker = spawnObject({
                    type = 'Chip_100',
                    position = position,
                })
                Wait.frames(function() marker.setLock(true) end, 50)
            end
            marker.setDescription(string.format('%s: %d on %s', player.name, bet['amount'], zonevalue))
            marker.setLock(true)
            zone.bets[bettingFor] = {
                value = bet['amount'],
                marker = marker
            }
            -- TODO remove value from player's hand
            print(string.format('set bet %d on %s for %s', bet['amount'], betField, bettingFor))
        else
            print(string.format('removing bet %d from %s for %s', bet['amount'], betField, bettingFor))
            zone.bets[bettingFor].marker.destruct()
            zone.bets[bettingFor] = {}
        end
    end
end
