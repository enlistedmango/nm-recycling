local processingPlayers = {}

local SYSTEM_NAME = "Recycling System"

local function sendEmailNotification(target, subject, message)
    local Player = exports.qbx_core:GetPlayer(target)
    if not Player then return end

    local phoneNumber = exports["lb-phone"]:GetEquippedPhoneNumber(target)
    if not phoneNumber then return end

    local email = exports["lb-phone"]:GetEmailAddress(phoneNumber)
    if not email then return end

    exports["lb-phone"]:SendMail({
        to = email,
        sender = SYSTEM_NAME,
        subject = subject,
        message = message
    })
end

local function InitializeDatabase()
    local success = exports.oxmysql:executeSync([[
        CREATE TABLE IF NOT EXISTS `recycling_batches` (
            `id` varchar(50) NOT NULL,
            `citizenid` varchar(50) NOT NULL,
            `item` varchar(50) NOT NULL,
            `amount` int(11) NOT NULL,
            `start_time` int(11) NOT NULL,
            `finish_time` int(11) NOT NULL,
            `completed` tinyint(1) NOT NULL DEFAULT 0,
            `collected` tinyint(1) NOT NULL DEFAULT 0,
            `location_id` int(11) NOT NULL DEFAULT 1,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`)
        )
    ]])

    if not success then
        print("^1ERROR: Failed to create recycling_batches table^7")
        return false
    end

    local hasItemType = exports.oxmysql:executeSync([[
        SELECT COUNT(*) as count
        FROM information_schema.columns
        WHERE table_name = 'recycling_batches'
        AND column_name = 'item_type'
    ]])

    if hasItemType[1].count == 0 then
        exports.oxmysql:executeSync([[
            ALTER TABLE `recycling_batches`
            ADD COLUMN `item_type` varchar(20) NOT NULL DEFAULT 'choice'
        ]])
    end

    local hasTargetMaterial = exports.oxmysql:executeSync([[
        SELECT COUNT(*) as count
        FROM information_schema.columns
        WHERE table_name = 'recycling_batches'
        AND column_name = 'target_material'
    ]])

    if hasTargetMaterial[1].count == 0 then
        exports.oxmysql:executeSync([[
            ALTER TABLE `recycling_batches`
            ADD COLUMN `target_material` varchar(50) NULL
        ]])
    end

    print("^2Successfully initialized recycling_batches database^7")
    return true
end

if not InitializeDatabase() then
    print("^1CRITICAL ERROR: Failed to initialize recycling database. The resource may not function correctly.^7")
end

local MIN_PROCESSING_TIME = 60

local function GenerateBatchId()
    return "batch_" .. math.random(1000000, 9999999)
end

RegisterNetEvent('recycle_exchanger:beginProcessing', function()
    local src = source
    if processingPlayers[src] then
        TriggerClientEvent('recycle_exchanger:processingResponse', src, false)
        return
    end
    processingPlayers[src] = true
    TriggerClientEvent('recycle_exchanger:processingResponse', src, true)
end)

RegisterNetEvent('recycle_exchanger:endProcessing', function()
    local src = source
    processingPlayers[src] = nil
end)

RegisterNetEvent('recycle_exchanger:createBatch',
    function(materialsAmount, itemType, processingFee, locationId, targetMaterial)
        local src = source
        local Player = exports.qbx_core:GetPlayer(src)

        if not Player then return end

        if not locationId then
            locationId = 1
        else
            locationId = tonumber(locationId) or 1
        end

        local actualLocationId = locationId
        for _, location in pairs(Config.Locations) do
            if location.id == locationId then
                actualLocationId = location.id
                break
            end
        end

        local citizenid = Player.PlayerData.citizenid

        exports.oxmysql:execute('SELECT COUNT(*) as count FROM recycling_batches WHERE citizenid = ? AND collected = 0',
            { citizenid },
            function(result)
                if result[1].count >= Config.BatchProcessing.maxBatchesPerPlayer then
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Materials Exchange',
                        description = 'You have too many active batches already',
                        type = 'error'
                    })
                    return
                end

                local itemConfig = Config.Materials[itemType] or Config.RecyclableItems[itemType]
                if not itemConfig then
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Materials Exchange',
                        description = 'Invalid item type requested',
                        type = 'error'
                    })
                    return
                end

                if itemType == 'recyclable_materials' then
                    if not targetMaterial or not Config.Materials[targetMaterial] then
                        TriggerClientEvent('ox_lib:notify', src, {
                            title = 'Materials Exchange',
                            description = 'Invalid target material type',
                            type = 'error'
                        })
                        return
                    end

                    local sourceItem = exports.ox_inventory:GetItem(src, 'recyclable_materials', nil, true)
                    local targetItem = exports.ox_inventory:GetItem(src, targetMaterial, nil, true)

                    if not sourceItem or not targetItem then
                        TriggerClientEvent('ox_lib:notify', src, {
                            title = 'Materials Exchange',
                            description = 'Invalid item configuration',
                            type = 'error'
                        })
                        return
                    end

                    itemConfig = Config.Materials[targetMaterial]
                end

                local hasItem = exports.ox_inventory:GetItem(src, itemType, nil, true)
                if not hasItem or hasItem < materialsAmount then
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Materials Exchange',
                        description = 'You do not have enough items',
                        type = 'error'
                    })
                    return
                end

                if processingFee > 0 then
                    local playerMoney = Player.Functions.GetMoney('cash')
                    if playerMoney < processingFee then
                        TriggerClientEvent('ox_lib:notify', src, {
                            title = 'Materials Exchange',
                            description = string.format('You need £%s to process this exchange', processingFee),
                            type = 'error'
                        })
                        return
                    end
                    Player.Functions.RemoveMoney('cash', processingFee)
                end

                local removed = exports.ox_inventory:RemoveItem(src, itemType, materialsAmount)
                if not removed then
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Materials Exchange',
                        description = 'Failed to remove items',
                        type = 'error'
                    })
                    return
                end

                local processingTime = Config.BatchProcessing.baseProcessingTime
                local itemProcessingTime = itemConfig.processingTime or 2000
                local additionalTime = math.ceil((materialsAmount / Config.BatchProcessing.itemsPerBatch) *
                    (itemProcessingTime / 1000))
                processingTime = math.max(MIN_PROCESSING_TIME, Config.BatchProcessing.baseProcessingTime + additionalTime)

                local currentTime = os.time()
                local finishTime = currentTime + processingTime
                local batchId = GenerateBatchId()

                exports.oxmysql:insert(
                    'INSERT INTO recycling_batches (id, citizenid, item, amount, start_time, finish_time, completed, collected, location_id, item_type, target_material) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    { batchId, citizenid, itemType, materialsAmount, currentTime, finishTime, 0, 0, actualLocationId,
                        itemConfig.type or 'choice', targetMaterial },
                    function(insertId)
                        if insertId then
                            local notifyLabel = itemType == 'recyclable_materials' and
                                Config.Materials[targetMaterial].label or itemConfig.label
                            TriggerClientEvent('ox_lib:notify', src, {
                                title = 'Materials Exchange',
                                description = string.format(
                                    'Your %d %s are being processed into %s. Return in about %s minutes.',
                                    materialsAmount,
                                    itemType == 'recyclable_materials' and 'recyclable materials' or itemConfig.label,
                                    notifyLabel,
                                    math.ceil(processingTime / 60)),
                                type = 'success',
                                duration = 6000
                            })

                            sendEmailNotification(src,
                                "New Recycling Batch Started",
                                string.format([[
🔄 Batch Processing Started

Amount: %d %s
Item Type: %s
Estimated Time: ~%d minutes

Your items are now being processed. You will receive another notification when the batch is ready for collection.

Location: %s
]], materialsAmount, itemConfig.label, itemConfig.label, math.ceil(processingTime / 60),
                                    Config.Locations[actualLocationId].name or "Recycling Center"))

                            TriggerClientEvent('recycle_exchanger:batchCreated', src, batchId, finishTime)

                            CreateThread(function()
                                Wait(1000)
                                exports.oxmysql:execute('SELECT * FROM recycling_batches WHERE id = ?', { batchId },
                                    function(result)
                                        if result and #result > 0 then
                                            local batch = result[1]
                                            local now = os.time()
                                            if batch.finish_time <= now then
                                                local newFinishTime = now + Config.BatchProcessing.baseProcessingTime +
                                                    60
                                                exports.oxmysql:execute(
                                                    'UPDATE recycling_batches SET finish_time = ? WHERE id = ?',
                                                    { newFinishTime, batchId })
                                            end
                                        end
                                    end)
                            end)

                            return true
                        else
                            exports.ox_inventory:AddItem(src, itemType, materialsAmount)

                            if processingFee > 0 then
                                Player.Functions.AddMoney('cash', processingFee)
                            end

                            TriggerClientEvent('ox_lib:notify', src, {
                                title = 'Materials Exchange',
                                description = 'Failed to create processing batch',
                                type = 'error'
                            })
                        end
                    end
                )
            end
        )
    end)

local function getPlayerBatches(citizenid, locationId)
    local currentTime = os.time()

    local result = exports.oxmysql:executeSync(
        'SELECT * FROM recycling_batches WHERE citizenid = ? AND collected = 0 AND location_id = ?',
        { citizenid, locationId })

    if not result or #result == 0 then
        return nil
    end

    local playerBatches = {}

    for _, batch in ipairs(result) do
        local timeLeft = math.max(0, batch.finish_time - currentTime)
        local isCompleted = (timeLeft == 0)

        local itemConfig = Config.Materials[batch.item] or Config.RecyclableItems[batch.item]
        local itemLabel = itemConfig and itemConfig.label or batch.item

        if isCompleted and batch.completed == 0 then
            exports.oxmysql:execute('UPDATE recycling_batches SET completed = 1 WHERE id = ?', { batch.id })

            local Player = exports.qbx_core:GetPlayerByCitizenId(batch.citizenid)
            if Player then
                sendEmailNotification(Player.PlayerData.source,
                    "✅ Recycling Batch Ready",
                    string.format([[
Your recycling batch has finished processing and is ready for collection!

Batch Details:
• %d %s
• Location: %s

Please visit the recycling station to collect your processed materials.]],
                        batch.amount,
                        (Config.Materials[batch.item] or Config.RecyclableItems[batch.item] or {}).label or batch.item,
                        Config.Locations[batch.location_id].name or "Recycling Center"))
            end
        end

        table.insert(playerBatches, {
            id = batch.id,
            item = batch.item,
            amount = batch.amount,
            completed = isCompleted,
            timeLeft = timeLeft,
            itemLabel = itemLabel,
            item_type = batch.item_type or 'choice'
        })
    end

    return playerBatches
end

lib.callback.register('recycle_exchanger:checkBatches', function(source, locationId)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end

    return getPlayerBatches(Player.PlayerData.citizenid, locationId)
end)

RegisterNetEvent('recycle_exchanger:collectBatch', function(batchId, locationId)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    if not locationId then
        locationId = 1
    else
        locationId = tonumber(locationId) or 1
    end

    local actualLocationId = locationId
    for _, location in pairs(Config.Locations) do
        if location.id == locationId then
            actualLocationId = location.id
            break
        end
    end

    local citizenid = Player.PlayerData.citizenid
    local currentTime = os.time()

    exports.oxmysql:execute(
        'SELECT * FROM recycling_batches WHERE id = ? AND citizenid = ? AND collected = 0 AND location_id = ?',
        { batchId, citizenid, actualLocationId },
        function(result)
            if not result or #result == 0 then
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Materials Exchange',
                    description = 'Batch not found at this location',
                    type = 'error'
                })
                return
            end

            local batch = result[1]

            if currentTime < batch.finish_time then
                local timeLeft = batch.finish_time - currentTime
                local minutes = math.floor(timeLeft / 60)
                local seconds = timeLeft % 60

                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Materials Exchange',
                    description = string.format('This batch is not ready yet. %d:%02d remaining', minutes, seconds),
                    type = 'error'
                })
                return
            end

            if batch.completed == 0 and currentTime >= batch.finish_time then
                exports.oxmysql:execute('UPDATE recycling_batches SET completed = 1 WHERE id = ?', { batchId })
                batch.completed = 1
            end

            if batch.item == 'recyclable_materials' then
                if not batch.target_material then
                    return false
                end

                local success = exports.ox_inventory:AddItem(Player.PlayerData.source, batch.target_material,
                    batch.amount)
                if success then
                    exports.oxmysql:execute('UPDATE recycling_batches SET collected = 1 WHERE id = ?', { batchId })
                    return true
                end
            elseif batch.item_type == 'fixed' then
                local itemConfig = Config.RecyclableItems[batch.item]
                if not itemConfig or not itemConfig.output then
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Materials Exchange',
                        description = 'Invalid item configuration',
                        type = 'error'
                    })
                    return
                end

                local allSuccess = true
                local addedItems = {}

                for _, output in ipairs(itemConfig.output) do
                    local amount = output.amount * batch.amount
                    local success = exports.ox_inventory:AddItem(src, output.item, amount)
                    if success then
                        table.insert(addedItems, {
                            item = output.item,
                            amount = amount,
                            label = Config.Materials[output.item] and Config.Materials[output.item].label or output.item
                        })
                    else
                        allSuccess = false
                        for _, added in ipairs(addedItems) do
                            exports.ox_inventory:RemoveItem(src, added.item, added.amount)
                        end
                        break
                    end
                end

                if allSuccess then
                    exports.oxmysql:execute('UPDATE recycling_batches SET collected = 1 WHERE id = ?', { batchId })

                    local outputSummary = {}
                    for _, added in ipairs(addedItems) do
                        table.insert(outputSummary, string.format('%d %s', added.amount, added.label))
                    end

                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Materials Exchange',
                        description = string.format('You received: %s',
                            table.concat(outputSummary, ', ')),
                        type = 'success'
                    })
                else
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Materials Exchange',
                        description = 'Not enough inventory space to collect your items',
                        type = 'error'
                    })
                end
            end
        end
    )
end)

AddEventHandler('playerDropped', function()
    local src = source
    processingPlayers[src] = nil
end)

RegisterNetEvent('recycle_exchanger:exchange', function(materialsAmount, itemType, rewardAmount, processingFee)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)

    if not Player then return end

    if Config.Technical.processingSync and not processingPlayers[src] then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Materials Exchange',
            description = 'Processing validation failed',
            type = 'error'
        })
        return
    end

    local hasItem = exports.ox_inventory:GetItemCount(src, 'recyclable_materials')

    if hasItem < materialsAmount then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Materials Exchange',
            description = 'You do not have enough recyclable materials',
            type = 'error'
        })
        return
    end

    if processingFee > 0 then
        local playerMoney = Player.Functions.GetMoney('cash')
        if playerMoney < processingFee then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Materials Exchange',
                description = string.format('You need £%s to process this exchange', processingFee),
                type = 'error'
            })
            return
        end
        Player.Functions.RemoveMoney('cash', processingFee)
    end

    if not Config.Materials[itemType] then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Materials Exchange',
            description = 'Invalid material type requested',
            type = 'error'
        })
        return
    end

    local removed = exports.ox_inventory:RemoveItem(src, 'recyclable_materials', materialsAmount)
    if removed then
        local success = exports.ox_inventory:AddItem(src, itemType, rewardAmount)
        if success then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Materials Exchange',
                description = string.format('Successfully exchanged for %s %s. Fee paid: £%s',
                    rewardAmount, Config.Materials[itemType].label, processingFee),
                type = 'success'
            })
        else
            exports.ox_inventory:AddItem(src, 'recyclable_materials', materialsAmount)
            Player.Functions.AddMoney('cash', processingFee)
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Materials Exchange',
                description = 'Not enough inventory space for the reward items',
                type = 'error'
            })
        end
    end
end)

CreateThread(function()
    Wait(5000)
    local currentTime = os.time()
    exports.oxmysql:execute('SELECT * FROM recycling_batches WHERE completed = 0', {}, function(result)
        if result and #result > 0 then
            for _, batch in ipairs(result) do
                if batch.finish_time <= batch.start_time or batch.start_time > currentTime then
                    local newStartTime = currentTime - 10
                    local processingTime = Config.BatchProcessing.baseProcessingTime +
                        math.ceil((batch.amount / Config.BatchProcessing.itemsPerBatch) * 60)
                    local newFinishTime = newStartTime + processingTime

                    exports.oxmysql:execute('UPDATE recycling_batches SET start_time = ?, finish_time = ? WHERE id = ?',
                        { newStartTime, newFinishTime, batch.id })
                end
            end
        end
    end)
end)

RegisterNetEvent('recycle_exchanger:notifyRobberyAttempt', function(batchId)
    local src = source
    local result = exports.oxmysql:executeSync('SELECT * FROM recycling_batches WHERE id = ?', { batchId })
    if not result or #result == 0 then return end

    local batch = result[1]
    local owner = exports.qbx_core:GetPlayerByCitizenId(batch.citizenid)

    if owner then
        local materialLabel = batch.item
        if Config.Materials[batch.item] and Config.Materials[batch.item].label then
            materialLabel = Config.Materials[batch.item].label
        elseif Config.RecyclableItems[batch.item] and Config.RecyclableItems[batch.item].label then
            materialLabel = Config.RecyclableItems[batch.item].label
        end

        if batch.item == 'recyclable_materials' and batch.target_material then
            if Config.Materials[batch.target_material] and Config.Materials[batch.target_material].label then
                materialLabel = Config.Materials[batch.target_material].label
            end
        end

        local locationName = "Recycling Center"
        if batch.location_id and Config.Locations[batch.location_id] and Config.Locations[batch.location_id].name then
            locationName = Config.Locations[batch.location_id].name
        end

        sendEmailNotification(owner.PlayerData.source,
            "⚠️ Security Alert: Recycling Batch",
            string.format([[
🚨 SECURITY ALERT

Someone is attempting to hack into your recycling batch:
• %d %s

Location: %s
Time: %s

Please be advised that if the hack is successful, you may lose some of your materials.
]], batch.amount, materialLabel, locationName, os.date("%H:%M:%S")))
    end
end)

RegisterNetEvent('recycle_exchanger:notifyRobberySuccess', function(batchId, amount)
    local src = source
    local result = exports.oxmysql:executeSync('SELECT * FROM recycling_batches WHERE id = ?', { batchId })
    if not result or #result == 0 then return end

    local batch = result[1]
    local owner = exports.qbx_core:GetPlayerByCitizenId(batch.citizenid)

    if owner then
        local materialLabel = batch.item
        if Config.Materials[batch.item] and Config.Materials[batch.item].label then
            materialLabel = Config.Materials[batch.item].label
        elseif Config.RecyclableItems[batch.item] and Config.RecyclableItems[batch.item].label then
            materialLabel = Config.RecyclableItems[batch.item].label
        end

        if batch.item == 'recyclable_materials' and batch.target_material then
            if Config.Materials[batch.target_material] and Config.Materials[batch.target_material].label then
                materialLabel = Config.Materials[batch.target_material].label
            end
        end

        local locationName = "Recycling Center"
        if batch.location_id and Config.Locations[batch.location_id] and Config.Locations[batch.location_id].name then
            locationName = Config.Locations[batch.location_id].name
        end

        sendEmailNotification(owner.PlayerData.source,
            "🔓 Recycling Batch Hack Alert",
            string.format([[
🚨 SECURITY BREACH ALERT

Someone has successfully hacked into your recycling batch!

Details:
• %d %s

Location: %s
Time: %s

The hacker has stolen %d items from your batch.
]], batch.amount, materialLabel, locationName, os.date("%H:%M:%S"), amount))
    end
end)

local function collectBatch(Player, batchId, locationId)
    local citizenid = Player.PlayerData.citizenid
    local currentTime = os.time()

    if not locationId then
        locationId = 1
    else
        locationId = tonumber(locationId) or 1
    end

    local actualLocationId = locationId
    for _, location in pairs(Config.Locations) do
        if location.id == locationId then
            actualLocationId = location.id
            break
        end
    end

    local result = exports.oxmysql:executeSync(
        'SELECT * FROM recycling_batches WHERE id = ? AND citizenid = ? AND collected = 0 AND location_id = ?',
        { batchId, citizenid, actualLocationId })

    if not result or #result == 0 then
        return false
    end

    local batch = result[1]

    if currentTime < batch.finish_time then
        return false
    end

    if batch.completed == 0 and currentTime >= batch.finish_time then
        exports.oxmysql:execute('UPDATE recycling_batches SET completed = 1 WHERE id = ?', { batchId })
        batch.completed = 1
    end

    if batch.item == 'recyclable_materials' then
        if not batch.target_material then
            return false
        end

        local success = exports.ox_inventory:AddItem(Player.PlayerData.source, batch.target_material, batch.amount)
        if success then
            exports.oxmysql:execute('UPDATE recycling_batches SET collected = 1 WHERE id = ?', { batchId })
            return true
        end
    elseif batch.item_type == 'fixed' then
        local itemConfig = Config.RecyclableItems[batch.item]
        if not itemConfig or not itemConfig.output then
            return false
        end

        local allSuccess = true
        local addedItems = {}

        for _, output in ipairs(itemConfig.output) do
            local amount = output.amount * batch.amount
            local success = exports.ox_inventory:AddItem(Player.PlayerData.source, output.item, amount)
            if success then
                table.insert(addedItems, {
                    item = output.item,
                    amount = amount
                })
            else
                allSuccess = false
                for _, added in ipairs(addedItems) do
                    exports.ox_inventory:RemoveItem(Player.PlayerData.source, added.item, added.amount)
                end
                break
            end
        end

        if allSuccess then
            exports.oxmysql:execute('UPDATE recycling_batches SET collected = 1 WHERE id = ?', { batchId })
            return true
        end
    else
        local success = exports.ox_inventory:AddItem(Player.PlayerData.source, batch.item, batch.amount)
        if success then
            exports.oxmysql:execute('UPDATE recycling_batches SET collected = 1 WHERE id = ?', { batchId })
            return true
        end
    end

    return false
end

lib.callback.register('recycle_exchanger:createBatch', function(source, data)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return false end

    local success = createBatch(Player, data.amount, data.itemType, data.fee, data.locationId, data.targetMaterial)
    return success
end)

lib.callback.register('recycle_exchanger:collectBatch', function(source, batchId, locationId)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return false end

    return collectBatch(Player, batchId, locationId)
end)

lib.callback.register('recycle_exchanger:getActiveBatchCount', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return 0 end

    local result = exports.oxmysql:executeSync(
        'SELECT COUNT(*) as count FROM recycling_batches WHERE citizenid = ? AND collected = 0',
        { Player.PlayerData.citizenid })

    return result[1].count or 0
end)

lib.callback.register('recycle_exchanger:getAllBatches', function(source, locationId)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return nil end

    locationId = tonumber(locationId) or 1

    local actualLocationId = locationId
    for _, location in pairs(Config.Locations) do
        if location.id == locationId then
            actualLocationId = location.id
            break
        end
    end

    local result = exports.oxmysql:executeSync('SELECT * FROM recycling_batches WHERE collected = 0 AND location_id = ?',
        { actualLocationId })
    if not result then return nil end

    local currentTime = os.time()
    local batches = {}

    for _, batch in ipairs(result) do
        local timeLeft = math.max(0, batch.finish_time - currentTime)
        local isCompleted = timeLeft == 0

        local itemConfig = Config.Materials[batch.item] or Config.RecyclableItems[batch.item]
        local itemLabel = itemConfig and itemConfig.label or batch.item

        if batch.item == 'recyclable_materials' then
            local targetMaterial = Config.Materials[batch.target_material or batch.item]
            if targetMaterial then
                itemConfig = targetMaterial
            end
        end

        if isCompleted and batch.completed == 0 then
            exports.oxmysql:execute('UPDATE recycling_batches SET completed = 1 WHERE id = ?', { batch.id })
        end

        table.insert(batches, {
            id = batch.id,
            item = batch.item,
            amount = batch.amount,
            completed = isCompleted,
            timeLeft = timeLeft,
            itemLabel = itemLabel,
            item_type = batch.item_type or 'choice',
            isOwner = (batch.citizenid == Player.PlayerData.citizenid),
            target_material = batch.target_material
        })
    end

    return batches
end)

lib.callback.register('recycle_exchanger:canRobBatch', function(source, locationId, batchId)
    if not Config.Robbery.enabled then return false end

    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return false end

    local hasItem = exports.ox_inventory:GetItemCount(source, Config.Robbery.hackItem) > 0
    if not hasItem then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Recycler Robbery',
            description = 'You need a laptop to hack the system',
            type = 'error'
        })
        return false
    end

    local lastAttempt = Player.PlayerData.metadata.lastRecyclerRobbery or 0
    if (os.time() - lastAttempt) < Config.Robbery.cooldown then
        local remainingTime = math.ceil((Config.Robbery.cooldown - (os.time() - lastAttempt)) / 60)
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Recycler Robbery',
            description = string.format('You must wait %d minutes before attempting another hack', remainingTime),
            type = 'error'
        })
        return false
    end

    local result = exports.oxmysql:executeSync('SELECT * FROM recycling_batches WHERE id = ?', { batchId })
    if not result or #result == 0 then return false end

    local batch = result[1]

    if batch.citizenid == Player.PlayerData.citizenid then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Recycler Robbery',
            description = 'You cannot hack your own batch',
            type = 'error'
        })
        return false
    end

    local currentTime = os.time()
    local totalTime = batch.finish_time - batch.start_time
    local elapsedTime = currentTime - batch.start_time
    local processedPercent = (elapsedTime / totalTime) * 100

    if processedPercent < Config.Robbery.minProcessedPercent then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Recycler Robbery',
            description = 'Batch not processed enough to hack',
            type = 'error'
        })
        return false
    end

    return true
end)

lib.callback.register('recycle_exchanger:robBatch', function(source, locationId, batchId)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return false end

    Player.PlayerData.metadata.lastRecyclerRobbery = os.time()
    Player.Functions.SetMetaData('lastRecyclerRobbery', Player.PlayerData.metadata.lastRecyclerRobbery)

    local result = exports.oxmysql:executeSync('SELECT * FROM recycling_batches WHERE id = ?', { batchId })
    if not result or #result == 0 then return false end

    local batch = result[1]
    local owner = exports.qbx_core:GetPlayerByCitizenId(batch.citizenid)

    local materialLabel = batch.item
    if Config.Materials[batch.item] and Config.Materials[batch.item].label then
        materialLabel = Config.Materials[batch.item].label
    elseif Config.RecyclableItems[batch.item] and Config.RecyclableItems[batch.item].label then
        materialLabel = Config.RecyclableItems[batch.item].label
    end

    local itemToGive = batch.item

    if batch.item == 'recyclable_materials' and batch.target_material then
        itemToGive = batch.target_material

        if Config.Materials[batch.target_material] and Config.Materials[batch.target_material].label then
            materialLabel = Config.Materials[batch.target_material].label
        end
    end

    if math.random(100) > Config.Robbery.successChance then
        if owner then
            sendEmailNotification(owner.PlayerData.source,
                "✅ Security Alert: Hack Attempt Failed",
                string.format([[
SECURITY ALERT: Hack Attempt Thwarted

Someone attempted to hack your recycling batch but failed:
• Batch: %d %s
• Location: %s
• Time: %s

Your materials are safe and secure. The security system successfully prevented unauthorized access.
]], batch.amount, materialLabel,
                    Config.Locations[batch.location_id] and Config.Locations[batch.location_id].name or
                    "Recycling Center",
                    os.date("%H:%M:%S")))
        end
        return false
    end

    local stolenAmount = math.floor(batch.amount * (Config.Robbery.rewardPercent / 100))

    if not itemToGive then
        return false
    end

    local success = exports.ox_inventory:AddItem(source, itemToGive, stolenAmount)
    if not success then
        if owner then
            sendEmailNotification(owner.PlayerData.source,
                "✅ Security Alert: Hack Attempt Failed",
                string.format([[
SECURITY ALERT: Hack Attempt Thwarted

Someone attempted to hack your recycling batch but failed:
• Batch: %d %s
• Location: %s
• Time: %s

Your materials are safe and secure. The hacker failed to extract any materials.
]], batch.amount, materialLabel,
                    Config.Locations[batch.location_id] and Config.Locations[batch.location_id].name or
                    "Recycling Center",
                    os.date("%H:%M:%S")))
        end
        return false
    end

    local remainingAmount = batch.amount - stolenAmount
    if remainingAmount > 0 then
        exports.oxmysql:execute('UPDATE recycling_batches SET amount = ? WHERE id = ?', { remainingAmount, batchId })
    else
        exports.oxmysql:execute('DELETE FROM recycling_batches WHERE id = ?', { batchId })
    end

    if owner then
        sendEmailNotification(owner.PlayerData.source,
            "🚨 Alert: Recycling Batch Compromised",
            string.format([[
SECURITY BREACH DETECTED

Your recycling batch has been compromised:
• Original Amount: %d %s
• Amount Stolen: %d %s (%d%% of batch)
• Remaining Amount: %d %s

Location: %s
Time: %s

We recommend increasing security measures for future batches.
]], batch.amount, materialLabel,
                stolenAmount, materialLabel,
                Config.Robbery.rewardPercent,
                remainingAmount, materialLabel,
                Config.Locations[batch.location_id] and Config.Locations[batch.location_id].name or "Recycling Center",
                os.date("%H:%M:%S")))
    end

    return true
end)

RegisterNetEvent('recycle_exchanger:alertRobbery', function(locationId)
    local src = source

    local coords = nil
    if locationId and Config.Locations[locationId] and Config.Locations[locationId].coords then
        coords = Config.Locations[locationId].coords
    else
        print("Warning: alertRobbery called with invalid locationId: " .. tostring(locationId))
        return
    end

    local Players = exports.qbx_core:GetQBPlayers()
    for _, v in pairs(Players) do
        if v.PlayerData.job.name == "police" and v.PlayerData.job.onduty then
            TriggerClientEvent('recycle_exchanger:policeAlert', v.PlayerData.source, coords)
        end
    end

    TriggerClientEvent('recycle_exchanger:alertNearbyPlayers', -1, coords)
end)

CreateThread(function()
    while true do
        Wait(10000) -- Check every 10 seconds

        local currentTime = os.time()
        local result = exports.oxmysql:executeSync([[
            SELECT * FROM recycling_batches
            WHERE completed = 0
            AND collected = 0
            AND finish_time <= ?
        ]], { currentTime })

        if result and #result > 0 then
            for _, batch in ipairs(result) do
                exports.oxmysql:execute('UPDATE recycling_batches SET completed = 1 WHERE id = ?', { batch.id })

                local Player = exports.qbx_core:GetPlayerByCitizenId(batch.citizenid)
                if Player then
                    sendEmailNotification(Player.PlayerData.source,
                        "✅ Recycling Batch Ready",
                        string.format([[
Your recycling batch has finished processing and is ready for collection!

Batch Details:
• %d %s
• Location: %s

Please visit the recycling station to collect your processed materials.]],
                            batch.amount,
                            (Config.Materials[batch.item] or Config.RecyclableItems[batch.item] or {}).label or
                            batch.item,
                            Config.Locations[batch.location_id].name or "Recycling Center"))
                end
            end
        end
    end
end)
