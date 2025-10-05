# nm-recycling

A comprehensive recycling system with batch processing, player interaction, and robbery mechanics.

## Features

- Convert 'recyclable_materials' into various resources
- Batch processing system with realistic wait times
- Option to choose between modern WebUI or legacy ox_lib menus
- Player-to-player interaction with robbery mechanics
- Email notifications via lb-phone integration
- Multiple recycling locations with customizable settings
- Detailed progress tracking and batch management

## Requirements

- qbx_core
- ox_lib
- ox_inventory
- lb-phone (for notifications)

## Installation

1. Extract the resource to your server resources folder
2. Add `ensure nm-recycling` to your server.cfg
3. Configure the settings in `config/shared.lua` to match your server's economy

## Configuration Options

- `UseWebUI`: Toggle between WebUI (true) or legacy ox_lib menus (false)
- Customize materials, processing times, and exchange rates
- Set up multiple recycling locations
- Configure robbery mechanics and success rates

## How It Works

Players can bring 'recyclable_materials' to recycling stations and convert them into various resources. The system processes materials in batches, allowing players to start multiple processing jobs and return later to collect their processed materials.

The robbery system enables player interaction by allowing thieves to attempt hacking into other players' batches to steal resources, creating dynamic gameplay opportunities.

## Credits

Developed by EnlistedMango
