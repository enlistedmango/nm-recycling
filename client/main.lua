local config = require 'config.shared'

local isProcessing = false
local spawnedRecyclers = {}
local cachedMaterials = 0
local lastCacheTime = 0
local lastStatusCheck = 0

local createMainMenu, createExchangeMenu, openAmountMenu, startBatchProcessing, checkBatches, spawnRecyclers, cleanupRecyclers, getMaterialsCount, collectBatch

local SYSTEM_PHONE = "RECYCLER"

local function sendPhoneNotification(to, message)
    exports["lb-phone"]:SendMessage(SYSTEM_PHONE, to, message)
end

local function calculateFee(amount)
    local fee = Config.ExchangeFee.baseFee + (amount * Config.ExchangeFee.perItemFee)
    return fee
end

getMaterialsCount = function()
    local currentTime = GetGameTimer()

    if currentTime - lastCacheTime < Config.Technical.cacheLifetime then
        return cachedMaterials
    end

    cachedMaterials = exports.ox_inventory:GetItemCount('recyclable_materials')
    lastCacheTime = currentTime

    return cachedMaterials
end

local function toggleNuiFrame(shouldShow)
    SetNuiFocus(shouldShow, shouldShow)
end

RegisterCommand('show-nui', function()
    toggleNuiFrame(true)
    SendReactMessage('showUi', true)
    debugPrint('Show NUI frame')
end)

RegisterNUICallback('hideFrame', function(_, cb)
    toggleNuiFrame(false)
    debugPrint('Hide NUI frame')
    cb({})
end)

RegisterNUICallback('getClientData', function(data, cb)
    local retData <const> = { x = 100, y = 100, z = 100 }
    debugPrint('Data sent by React', json.encode(data))

    local curCoords = GetEntityCoords(PlayerPedId())

    local retData <const> = { x = curCoords.x, y = curCoords.y, z = curCoords.z }
    cb(retData)
end)

RegisterNUICallback('getRecyclingData', function(data, cb)
    local activeBatches = lib.callback.await('recycle_exchanger:getActiveBatchCount', false)
    local materialCount = getMaterialsCount()
    local locationId = data and data.locationId or 1

    local itemCounts = {
        ['recyclable_materials'] = materialCount
    }

    for itemName, _ in pairs(Config.RecyclableItems) do
        if itemName ~= 'recyclable_materials' then
            itemCounts[itemName] = exports.ox_inventory:GetItemCount(itemName)
        end
    end

    if Config.Robbery.enabled then
        itemCounts[Config.Robbery.hackItem] = exports.ox_inventory:GetItemCount(Config.Robbery.hackItem)
    end

    debugPrint('Raw locationId received: ' .. locationId)

    local retData = {
        materials = Config.Materials,
        recyclableItems = Config.RecyclableItems,
        activeBatches = activeBatches,
        maxBatches = Config.BatchProcessing.maxBatchesPerPlayer,
        materialCount = materialCount,
        itemCounts = itemCounts,
        locationId = locationId,
        robberyConfig = Config.Robbery
    }

    debugPrint('Sending recycling data to NUI with location ID: ' .. locationId)
    cb(retData)
end)

RegisterNUICallback('getBatches', function(data, cb)
    local locationId = data and data.locationId or 1
    local batches = lib.callback.await('recycle_exchanger:getAllBatches', false, locationId)

    debugPrint('Sending batch data for location #' .. locationId)
    cb(batches or {})
end)

RegisterNUICallback('startBatchProcessing', function(data, cb)
    local amount = data.amount
    local itemType = data.itemType
    local processingFee = data.processingFee
    local locationId = data.locationId
    local targetMaterial = data.targetMaterial

    if not amount or not itemType or not locationId then
        cb({ success = false, message = "Missing required parameters" })
        return
    end

    local itemCount = exports.ox_inventory:GetItemCount(itemType)

    if itemCount < amount then
        cb({ success = false, message = "Not enough materials" })
        return
    end

    isProcessing = true
    TaskStartScenarioInPlace(PlayerPedId(), "PROP_HUMAN_BUM_BIN", 0, true)

    Wait(3000)

    ClearPedTasks(PlayerPedId())
    isProcessing = false

    TriggerServerEvent('recycle_exchanger:createBatch', amount, itemType, processingFee, locationId, targetMaterial)
    lastCacheTime = 0

    cb({ success = true })
end)

RegisterNUICallback('collectBatch', function(data, cb)
    local batchId = data.batchId
    local locationId = data.locationId

    if not batchId or not locationId then
        cb({ success = false, message = "Missing required parameters" })
        return
    end

    local success = lib.callback.await('recycle_exchanger:collectBatch', false, batchId, locationId)

    cb({ success = success })
end)

local SYSTEM_PHONE = "RECYCLER"

local function sendPhoneNotification(to, message)
    exports["lb-phone"]:SendMessage(SYSTEM_PHONE, to, message)
end

local function calculateFee(amount)
    local fee = Config.ExchangeFee.baseFee + (amount * Config.ExchangeFee.perItemFee)
    return fee
end

createMainMenu = function(locationId)
    debugPrint('createMainMenu called with locationId: ' .. locationId)
    debugPrint('Config.Locations[locationId].id: ' .. Config.Locations[locationId].id)

    if Config.UseWebUI then
        toggleNuiFrame(true)
        SendReactMessage('showUi', { locationId = Config.Locations[locationId].id })
        debugPrint('Show recycling web UI for location #' .. Config.Locations[locationId].id)
    else
        -- Legacy OX_lib menu code
        local activeBatches = lib.callback.await('recycle_exchanger:getActiveBatchCount', false)
        local canRecycle = activeBatches < Config.BatchProcessing.maxBatchesPerPlayer

        lib.registerContext({
            id = 'recycling_main_menu',
            title = string.format('Recycling Station #%d', Config.Locations[locationId].id),
            options = {
                {
                    title = 'Recycle Materials',
                    description = canRecycle and 'Convert recyclable materials into useful resources' or
                        string.format('You have reached the maximum of %d active batches',
                            Config.BatchProcessing.maxBatchesPerPlayer),
                    icon = 'fas fa-recycle',
                    disabled = not canRecycle,
                    onSelect = function()
                        createExchangeMenu(locationId)
                    end
                },
                {
                    title = 'Check Processing Status',
                    description = string.format('Active Batches: %d/%d', activeBatches,
                        Config.BatchProcessing.maxBatchesPerPlayer),
                    icon = 'fas fa-hourglass-half',
                    onSelect = function()
                        checkBatches(locationId)
                    end
                }
            }
        })

        lib.showContext('recycling_main_menu')
    end
end

createExchangeMenu = function(locationId)
    local menuOptions = {}

    table.insert(menuOptions, {
        title = 'Recyclable Materials',
        description = 'Convert recyclable materials into various resources',
        icon = 'fas fa-recycle',
        disabled = true
    })

    for item, data in pairs(Config.Materials) do
        local playerMaterials = exports.ox_inventory:GetItemCount('recyclable_materials')
        local processTime = math.ceil(data.processingTime / 1000)

        local recycleData = {
            label = data.label,
            processingTime = data.processingTime,
            type = 'choice',
            item = item,
            target_material = item
        }

        table.insert(menuOptions, {
            title = data.label,
            description = string.format('Processing Time: %d seconds\nYou have: %d recyclable materials',
                processTime,
                playerMaterials),
            icon = data.icon or 'fas fa-recycle',
            metadata = {
                { label = 'Exchange Rate', value = '1:1' }
            },
            onSelect = function()
                openAmountMenu('recyclable_materials', recycleData, playerMaterials, locationId)
            end
        })
    end

    table.insert(menuOptions, {
        title = 'Specific Items',
        description = 'Break down specific items into materials',
        icon = 'fas fa-tools',
        disabled = true
    })

    for item, data in pairs(Config.RecyclableItems) do
        if item ~= 'recyclable_materials' then
            local playerItems = exports.ox_inventory:GetItemCount(item)
            local processTime = math.ceil(data.processingTime / 1000)

            local outputDesc = ''
            if data.type == 'fixed' and data.output then
                local outputs = {}
                for _, output in ipairs(data.output) do
                    table.insert(outputs, string.format('%d %s', output.amount, Config.Materials[output.item].label))
                end
                outputDesc = '\nOutput: ' .. table.concat(outputs, ', ')
            end

            table.insert(menuOptions, {
                title = data.label,
                description = string.format('Processing Time: %d seconds\nYou have: %d %s%s',
                    processTime,
                    playerItems,
                    data.label,
                    outputDesc),
                icon = data.icon or 'fas fa-recycle',
                metadata = {
                    { label = 'Type', value = data.type == 'fixed' and 'Fixed Output' or 'Choice' }
                },
                onSelect = function()
                    openAmountMenu(item, data, playerItems, locationId)
                end
            })
        end
    end

    lib.registerContext({
        id = 'recycling_exchange_menu',
        title = 'Recyclable Items Exchange',
        menu = 'recycling_main_menu',
        options = menuOptions
    })

    lib.showContext('recycling_exchange_menu')
end

openAmountMenu = function(itemType, itemData, playerItems, locationId)
    local input = lib.inputDialog(string.format('Exchange %s', itemData.label), {
        {
            type = 'number',
            label = 'Amount to Process',
            description = string.format('You have %d %s',
                playerItems,
                itemType == 'recyclable_materials' and 'recyclable materials' or itemData.label),
            icon = 'hashtag',
            min = 1,
            max = playerItems,
            default = 1
        }
    })

    if not input or not input[1] then return end

    local amount = math.floor(input[1])
    if amount < 1 then amount = 1 end
    if amount > playerItems then amount = playerItems end

    local processingFee = math.floor(calculateFee(amount))
    local processTime = math.ceil((Config.BatchProcessing.baseProcessingTime +
        (amount / Config.BatchProcessing.itemsPerBatch * (itemData.processingTime / 1000))) / 60)

    local confirmMessage
    if itemData.type == 'fixed' and itemData.output then
        local outputs = {}
        for _, output in ipairs(itemData.output) do
            table.insert(outputs, string.format('%d %s', output.amount * amount, Config.Materials[output.item].label))
        end
        confirmMessage = string.format(
            'Exchange Details:\n• %d %s → %s\n• Processing Time: ~%d minutes\n• Fee: £%d',
            amount, itemData.label, table.concat(outputs, ', '), processTime, processingFee
        )
    else
        confirmMessage = string.format(
            'Exchange Details:\n• %d %s → %d %s\n• Processing Time: ~%d minutes\n• Fee: £%d',
            amount, itemData.label, amount, itemData.label, processTime, processingFee
        )
    end

    local alert = lib.alertDialog({
        header = 'Confirm Exchange',
        content = confirmMessage,
        centered = true,
        cancel = true
    })

    if alert == 'confirm' then
        startBatchProcessing(amount, itemType, itemData, processingFee, locationId)
    end
end

checkBatches = function(locationId)
    local batches = lib.callback.await('recycle_exchanger:getAllBatches', false, locationId)

    if not batches or #batches == 0 then
        return lib.notify({
            title = 'Recycler',
            description = 'No active batches found',
            type = 'info'
        })
    end

    local options = {}

    if Config.Robbery.enabled then
        table.insert(options, {
            title = '🚨 Robbery Information',
            description = string.format(
                'You can attempt to hack other players\' batches.\nRequires: Laptop\nSuccess Rate: %d%%\nReward: %d%% of materials',
                Config.Robbery.successChance,
                Config.Robbery.rewardPercent
            ),
            disabled = true
        })
    end

    for _, batch in ipairs(batches) do
        local itemConfig = Config.Materials[batch.item] or Config.RecyclableItems[batch.item]
        local itemLabel = itemConfig and itemConfig.label or batch.item

        if batch.item == 'recyclable_materials' and batch.target_material then
            local targetMaterial = Config.Materials[batch.target_material]
            if targetMaterial then
                itemConfig = targetMaterial
                itemLabel = string.format('Recyclable → %s', targetMaterial.label)
            end
        end

        local timeText
        if batch.completed then
            timeText = '✅ Ready for collection'
        else
            local minutes = math.floor(batch.timeLeft / 60)
            local seconds = batch.timeLeft % 60
            if minutes > 0 then
                timeText = string.format('⏳ %d min %d sec remaining', minutes, seconds)
            else
                timeText = string.format('⏳ %d seconds remaining', seconds)
            end
        end

        local description = string.format('%s\n%s',
            batch.isOwner and '🔒 Your Batch' or '👥 Other Player\'s Batch',
            timeText
        )

        local title
        if batch.item_type == 'fixed' and itemConfig and itemConfig.output then
            title = string.format('%s - Input: %d units', itemLabel, batch.amount)

            local outputs = {}
            for _, output in ipairs(itemConfig.output) do
                local outputConfig = Config.Materials[output.item] or Config.RecyclableItems[output.item]
                local outputLabel = outputConfig and outputConfig.label or output.item
                table.insert(outputs, string.format('%d %s', output.amount * batch.amount, outputLabel))
            end
            description = description .. '\nOutput: ' .. table.concat(outputs, ', ')
        else
            title = string.format('%s - %d units', itemLabel, batch.amount)
        end

        local option = {
            title = title,
            description = description,
            icon = batch.completed and 'fas fa-check-circle' or 'fas fa-hourglass',
            disabled = not batch.isOwner and batch.completed,
            metadata = {
                { label = 'Status', value = batch.completed and '✅ Completed' or '⏳ Processing' },
                { label = 'Type', value = batch.item_type == 'fixed' and '🔧 Fixed Output' or '🔄 Choice' }
            }
        }

        if batch.isOwner then
            option.onSelect = function()
                if batch.completed then
                    local success = lib.callback.await('recycle_exchanger:collectBatch', false, batch.id, locationId)
                    if success then
                        lib.notify({
                            title = 'Materials Exchange',
                            description = 'Batch collected successfully',
                            type = 'success'
                        })
                    end
                else
                    local currentMinutes = math.floor(batch.timeLeft / 60)
                    local currentSeconds = batch.timeLeft % 60
                    lib.notify({
                        title = 'Materials Exchange',
                        description = string.format('This batch is still processing. %d:%02d remaining', currentMinutes,
                            currentSeconds),
                        type = 'info'
                    })
                end
            end
        elseif Config.Robbery.enabled then
            option.arrow = true
            option.onSelect = function()
                local canRob = lib.callback.await('recycle_exchanger:canRobBatch', false, locationId, batch.id)
                if not canRob then return end

                TriggerServerEvent('recycle_exchanger:notifyRobberyAttempt', batch.id)

                local success = lib.skillCheck({ 'easy', 'medium', 'medium' }, { 'w', 'a', 's', 'd' })

                if success then
                    TaskStartScenarioInPlace(PlayerPedId(), "WORLD_HUMAN_STAND_MOBILE", 0, true)

                    local result = lib.progressBar({
                        duration = Config.Robbery.hackingTime * 1000,
                        label = 'Hacking Recycler System',
                        useWhileDead = false,
                        canCancel = true,
                        disable = {
                            car = true,
                            move = true,
                            combat = true
                        },
                        anim = {
                            dict = "anim@heists@ornate_bank@hack",
                            clip = "hack_loop"
                        }
                    })

                    ClearPedTasks(PlayerPedId())

                    if result then
                        local robSuccess = lib.callback.await('recycle_exchanger:robBatch', false, locationId, batch.id)
                        if robSuccess then
                            lib.notify({
                                title = 'Hack Successful',
                                description = string.format('You stole %d%% of the materials!',
                                    Config.Robbery.rewardPercent),
                                type = 'success'
                            })

                            TriggerServerEvent('recycle_exchanger:notifyRobberySuccess', batch.id,
                                Config.Robbery.rewardPercent)
                        else
                            lib.notify({
                                title = 'Hack Failed',
                                description = 'The system rejected your attempt',
                                type = 'error'
                            })
                        end
                    end
                else
                    lib.notify({
                        title = 'Hack Failed',
                        description = 'The system detected your attempt!',
                        type = 'error'
                    })
                end
            end
        end

        table.insert(options, option)
    end

    lib.registerContext({
        id = 'recycling_batches_menu',
        title = 'Recycling Batches',
        menu = 'recycling_main_menu',
        options = options
    })

    lib.showContext('recycling_batches_menu')
end

spawnRecyclers = function()
    for k, location in pairs(Config.Locations) do
        local modelHash = GetHashKey(Config.Technical.recyclerModel)
        local success = lib.requestModel(modelHash, Config.Technical.modelLoadTimeout)

        if not success then
            print("^1ERROR: Failed to load model for recycler at location " .. k .. "^7")
            goto continue
        end

        local obj = CreateObject(
            modelHash,
            location.coords.x,
            location.coords.y,
            location.coords.z - 1.0,
            false,
            false,
            false
        )

        if not DoesEntityExist(obj) then
            print("^1ERROR: Failed to create recycler object at location " .. k .. "^7")
            SetModelAsNoLongerNeeded(modelHash)
            goto continue
        end

        SetEntityHeading(obj, location.coords.w)
        FreezeEntityPosition(obj, true)
        SetEntityAsMissionEntity(obj, true, true)

        spawnedRecyclers[k] = obj

        if Config.Blip.enabled then
            local blip = AddBlipForCoord(location.coords.x, location.coords.y, location.coords.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipColour(blip, Config.Blip.color)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(Config.Blip.title)
            EndTextCommandSetBlipName(blip)
        end

        exports.ox_target:addLocalEntity(obj, {
            {
                name = 'recycle_exchange_' .. k,
                icon = 'fas fa-recycle',
                label = 'Exchange Recyclables',
                onSelect = function()
                    createMainMenu(k)
                end,
                canInteract = function()
                    return not isProcessing
                end,
                distance = 2.0
            }
        })

        SetModelAsNoLongerNeeded(modelHash)

        ::continue::
    end
end

cleanupRecyclers = function()
    for k, obj in pairs(spawnedRecyclers) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
    spawnedRecyclers = {}
end

CreateThread(function()
    spawnRecyclers()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanupRecyclers()
    end
end)

startBatchProcessing = function(materialsAmount, itemType, itemData, processingFee, locationId)
    local itemCount = exports.ox_inventory:GetItemCount(itemType)

    if itemCount < materialsAmount then
        return lib.notify({
            title = 'Materials Exchange',
            description = string.format('You do not have enough %s',
                itemType == 'recyclable_materials' and 'recyclable materials' or itemData.label),
            type = 'error'
        })
    end

    local targetMaterial = nil
    if itemType == 'recyclable_materials' then
        targetMaterial = itemData.target_material
    end

    TriggerServerEvent('recycle_exchanger:createBatch', materialsAmount, itemType, processingFee, locationId,
        targetMaterial)
    lastCacheTime = 0

    isProcessing = true
    TaskStartScenarioInPlace(PlayerPedId(), "PROP_HUMAN_BUM_BIN", 0, true)

    Wait(3000)

    ClearPedTasks(PlayerPedId())
    isProcessing = false
end

collectBatch = function(batchId, locationId)
    TriggerServerEvent('recycle_exchanger:collectBatch', batchId, locationId)
end


RegisterNUICallback('canRobBatch', function(data, cb)
    local batchId = data.batchId
    local locationId = data.locationId

    if not batchId or not locationId then
        cb({ success = false, message = "Missing required parameters" })
        return
    end

    local canRob = lib.callback.await('recycle_exchanger:canRobBatch', false, locationId, batchId)

    cb({ success = canRob })
end)

RegisterNUICallback('attemptRobBatch', function(data, cb)
    local batchId = data.batchId
    local locationId = data.locationId

    if not batchId or not locationId then
        cb({ success = false, message = "Missing required parameters" })
        return
    end

    TriggerServerEvent('recycle_exchanger:notifyRobberyAttempt', batchId)

    local success = lib.skillCheck({ 'easy', 'medium', 'medium' }, { 'w', 'a', 's', 'd' })

    if success then
        TaskStartScenarioInPlace(PlayerPedId(), "WORLD_HUMAN_STAND_MOBILE", 0, true)

        local result = lib.progressBar({
            duration = Config.Robbery.hackingTime * 1000,
            label = 'Hacking Recycler System',
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = true,
                move = true,
                combat = true
            },
            anim = {
                dict = "anim@heists@ornate_bank@hack",
                clip = "hack_loop"
            }
        })

        ClearPedTasks(PlayerPedId())

        if result then
            local robSuccess = lib.callback.await('recycle_exchanger:robBatch', false, locationId, batchId)
            if robSuccess then
                lib.notify({
                    title = 'Hack Successful',
                    description = string.format('You stole %d%% of the materials!',
                        Config.Robbery.rewardPercent),
                    type = 'success'
                })

                TriggerServerEvent('recycle_exchanger:notifyRobberySuccess', batchId,
                    Config.Robbery.rewardPercent)

                cb({ success = true })
            else
                lib.notify({
                    title = 'Hack Failed',
                    description = 'The system rejected your attempt',
                    type = 'error'
                })

                cb({ success = false, message = "System rejected hack attempt" })
            end
        else
            cb({ success = false, message = "Cancelled" })
        end
    else
        lib.notify({
            title = 'Hack Failed',
            description = 'The system detected your attempt!',
            type = 'error'
        })

        cb({ success = false, message = "Failed skill check" })
    end
end)
