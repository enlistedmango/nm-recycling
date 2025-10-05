Config = {}

-- Enable/disable the new Web UI
-- If set to true, the new Web UI will be used
-- If set to false, ox_lib will be used
Config.UseWebUI = true

Config.ExchangeFee = {
    baseFee = 5,     -- Base processing fee
    perItemFee = 0.5 -- Additional fee per item (it will round up)
}

Config.Technical = {
    modelLoadTimeout = 5000,               -- How long to wait for models to load (ms)
    cacheLifetime = 10000,                 -- How long to cache inventory data (ms)
    recyclerModel =
    'bzzz_prop_recycler_a'                 -- Model used for all recyclers (paid model: https://bzzz.tebex.io/package/5372116 )
}

Config.Blip = {
    enabled = true,
    sprite = 365,
    color = 2,
    scale = 0.8,
    title = "Recycling Exchange"
}

Config.BatchProcessing = {
    baseProcessingTime = 600, -- Base time to process in seconds (5 minutes)
    itemsPerBatch = 200,      -- How many items can be processed in a single batch
    maxBatchesPerPlayer = 3   -- Maximum number of active batches per player
}

Config.Robbery = {
    enabled = true,
    minProcessedPercent = 50, -- Minimum % processed before robbery is possible
    hackingTime = 30,         -- Seconds it takes to hack the machine
    hackItem = 'laptop',      -- Item required to hack
    successChance = 70,       -- Chance of successful hack (%)
    cooldown = 600,           -- Cooldown between robbery attempts (seconds)
    rewardPercent = 100       -- Percentage of materials the robber gets
}

-- Available materials for exchange (1:1 ratio with recyclable materials)
Config.Materials = {
    ['plastic'] = {
        label = 'Plastic',
        icon = 'fas fa-prescription-bottle',
        processingTime = 2000, -- 2 seconds per item
    },
    ['steel'] = {
        label = 'Steel',
        icon = 'fas fa-layer-group',
        processingTime = 3000, -- 3 seconds per item
    },
    ['iron'] = {
        label = 'Iron',
        icon = 'fas fa-cube',
        processingTime = 3000, -- 3 seconds per item
    },
    ['aluminum'] = {
        label = 'Aluminum',
        icon = 'fas fa-beer',
        processingTime = 2500, -- 2.5 seconds per item
    },
    ['copper'] = {
        label = 'Copper',
        icon = 'fas fa-coins',
        processingTime = 4000, -- 4 seconds per item
    },
    ['glass'] = {
        label = 'Glass',
        icon = 'fas fa-wine-glass',
        processingTime = 1500, -- 1.5 seconds per item
    },
    ['rubber'] = {
        label = 'Rubber',
        icon = 'fas fa-ring',
        processingTime = 2000, -- 2 seconds per item
    },
    ['metalscrap'] = {
        label = 'Metal Scrap',
        icon = 'fas fa-cog',
        processingTime = 3000, -- 3 seconds per item
    },
    ['fabric'] = {
        label = 'Fabric',
        icon = 'fas fa-tshirt',
        processingTime = 2000, -- 2 seconds per item
    }
}

-- Recyclable items configuration
Config.RecyclableItems = {
    ['recyclable_materials'] = {
        label = 'Recyclable Materials',
        type = 'choice',       -- Player can choose what material to get
        processingTime = 2000, -- Base processing time per item
        icon = 'fas fa-recycle'
    },
    ['lockpick'] = {
        label = 'Lockpick',
        type = 'fixed', -- Fixed output of materials
        processingTime = 3000,
        icon = 'fas fa-unlock',
        output = {
            { item = 'metalscrap', amount = 2 },
            { item = 'steel',      amount = 1 },
            { item = 'plastic',    amount = 1 }
        }
    },
    ['phone'] = {
        label = 'Phone',
        type = 'fixed',
        processingTime = 5000,
        icon = 'fas fa-mobile-alt',
        output = {
            { item = 'plastic',     amount = 2 },
            { item = 'glass',       amount = 1 },
            { item = 'copper',      amount = 3 },
            { item = 'aluminum',    amount = 1 },
            { item = 'electronics', amount = 2 }
        }
    },
    ['radio'] = {
        label = 'Radio',
        type = 'fixed',
        processingTime = 4000,
        icon = 'fas fa-broadcast-tower',
        output = {
            { item = 'plastic',     amount = 2 },
            { item = 'copper',      amount = 2 },
            { item = 'metalscrap',  amount = 1 },
            { item = 'electronics', amount = 3 }
        }
    },
    ['armor'] = {
        label = 'Body Armor',
        type = 'fixed',
        processingTime = 6000,
        icon = 'fas fa-shield-alt',
        output = {
            { item = 'fabric',     amount = 3 },
            { item = 'metalscrap', amount = 2 },
            { item = 'plastic',    amount = 1 }
        }
    }
}

-- Recycling locations
Config.Locations = {
    {
        id = 1,
        coords = vector4(-347.27, -1541.51, 27.72, 274.21)
    },
    {
        id = 2,
        coords = vector4(-347.54, -1538.06, 27.72, 269.25)
    },
    {
        id = 3,
        coords = vector4(-343.61, -1537.79, 27.72, 273.25)
    },
    {
        id = 4,
        coords = vector4(-343.75, -1541.46, 27.72, 264.20)
    }
}

Config.version = '1.0.0'

return Config
