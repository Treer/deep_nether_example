--[[
  Deep Nether (mod for Minetest)

  A template example for adding Nether "layers" - deeper realms in the Nether.
  Fork and adapt it.

  See nether_api.txt in the nether mod for more interop coding info.


  Copyright 2021 Treer

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to
  deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
]]--

if minetest.get_translator == nil then
	error(S("The @1 mod requires Minetest 5", minetest.get_current_modname()), 0)
end
local S = minetest.get_translator(minetest.get_current_modname())

if not nether.useBiomes then
	error(S("The @1 mod requires the Nether biomes mapgen", minetest.get_current_modname()), 0)
end

-- Global deepnether namespace
deepnether               = {}
deepnether.fogColor      = "#3D1500"
deepnether.modName       = minetest.get_current_modname() -- set the name by changing mod.conf
deepnether.portalName    = S("Deep-Nether Portal")
deepnether.DEPTH_CEILING = math.floor((nether.DEPTH_FLOOR_LAYERS - 6) / 80) * 80
deepnether.DEPTH_FLOOR   = deepnether.DEPTH_CEILING - (80 * 3)
deepnether.BUFFER_ZONE   = 70

-- Update nether.DEPTH_FLOOR_LAYERS so the next layer will be positioned below this one
-- (See nether_api.txt for more details)
nether.DEPTH_FLOOR_LAYERS = deepnether.DEPTH_FLOOR

-- Shift any overlapping biomes out of the way before we create the deepnether biome(s)
-- (See nether_api.txt for more details)
if nether.mapgen ~= nil and nether.mapgen.shift_existing_biomes ~= nil then
	nether.mapgen.shift_existing_biomes(deepnether.DEPTH_FLOOR, deepnether.DEPTH_CEILING)
else
	minetest.log("warning", deepnether.modName .. " was unable to shift existing biomes, the " .. deepnether.modName .. " biome may have incomplete coverage.");
end

--============--
--== Portal ==--
--============--

local portalName = deepnether.modName .. "_portal"

-- Use the Portal API to add a portal type which goes between the Nether and this Nether layer
-- See portal_api.txt for documentation
local portalRegistered = nether.register_portal(portalName, {
	shape               = nether.PortalShape_Traditional,
	frame_node_name     = "nether:basalt_hewn",
	wormhole_node_color = 5, -- 5 is red
	particle_color      = "#FE3",
	particle_texture    = {
		name      = "nether_particle_anim2.png", -- bubbles
		animation = {
			type = "vertical_frames",
			aspect_w = 7,
			aspect_h = 7,
			length = 1,
		},
		scale = 1.5
	},
	title = deepnether.portalName,
	book_of_portals_pagetext = S([[Construction requires 14 blocks of hewn basalt, which we obtained from basalt islands in the lava lakes of the Nether. The finished frame is four blocks wide, five blocks high, and stands vertically, like a doorway.

This portal takes you out of the frying pan and into the fire, oh what I would give for sunlight, trees, and birdsong.]]),

	is_within_realm = function(pos)
		-- return true if pos is inside this nether layer
		return pos.y < deepnether.DEPTH_CEILING and pos.y > deepnether.DEPTH_FLOOR
	end,

	find_realm_anchorPos = function(surface_anchorPos, player_name)
		local destination_pos = table.copy(surface_anchorPos)
		destination_pos.y = deepnether.DEPTH_CEILING - 1 -- temp value so find_nearest_working_portal() returns portals in the layer

		-- a y_factor of 0 makes the search ignore the altitude of the portals (as long as they are in the nether layer)
		local existing_portal_location, existing_portal_orientation =
			nether.find_nearest_working_portal(portalName, destination_pos, 8, 0)

		if existing_portal_location ~= nil then
			return existing_portal_location, existing_portal_orientation
		else
			destination_pos.y = deepnether.find_layer_ground_y(destination_pos.x, destination_pos.z, player_name)
			return destination_pos
		end
	end,

	find_surface_anchorPos = function(realm_anchorPos, player_name)
		local destination_pos = table.copy(realm_anchorPos)
		destination_pos.y = deepnether.DEPTH_CEILING + 1 -- temp value so find_nearest_working_portal() returns portals in the layer

		-- a y_factor of 0 makes the search ignore the altitude of the portals (as long as they are outside the Nether)
		local existing_portal_location, existing_portal_orientation =
			nether.find_nearest_working_portal(portalName, destination_pos, 8, 0)

		if existing_portal_location ~= nil then
			return existing_portal_location, existing_portal_orientation
		else
			-- This layer under the nether normally considers the nether to be the surface!
			if nether.NETHER_REALM_ENABLED then
				local start_y = nether.DEPTH_CEILING - math.random(500, 1500) -- Search starting altitude
				destination_pos.y = nether.find_nether_ground_y(destination_pos.x, destination_pos.z, start_y, player_name)
			else
				-- The nether realm created by the nether mod is turned off on this server (perhaps to use _this_ mod as
				-- the nether realm?), so I guess we'll have to consider the overworld surface to be the surface.
				destination_pos.y = nether.find_surface_target_y(destination_pos.x, destination_pos.z, portalName, player_name)
			end
			return destination_pos
		end
	end,

	on_created = function(portalDef, anchorPos, orientation)
		-- replace any lava below the portal with nether brick, in case the new portal spawned over a lava lake

		-- find bounds around the portal to scan for lava
		local pos1 = portalDef.shape.get_schematicPos_from_anchorPos(anchorPos, orientation)
		local size = table.copy(portalDef.shape.schematic.size)
		if orientation == 90 or orientation == 270 then
			local temp_x = size.x
			size.x = size.z
			size.z = temp_x
		end
		local pos2 = {x = pos1.x + (size.x - 1), y = pos1.y + (size.y - 1), z = pos1.z + (size.z - 1)}
		pos1.y = pos1.y - 4 -- include the ground below the portal schematic

		-- scan for lava
		local lavaPositions = minetest.find_nodes_in_area(pos1, pos2, {"nether:lava_source", "nether:lava_crust"})

		-- replace any lava that was found
		for _, lavaPos in ipairs(lavaPositions) do
			minetest.swap_node(lavaPos, {name="nether:brick_deep"})
		end
	end,

	on_ignite = function(portalDef, anchorPos, orientation)
		-- make some sparks fly
		local p1, p2 = portalDef.shape:get_p1_and_p2_from_anchorPos(anchorPos, orientation)
		local pos = vector.divide(vector.add(p1, p2), 2)

		local textureName = portalDef.particle_texture
		if type(textureName) == "table" then textureName = textureName.name end

		minetest.add_particlespawner({
			amount = 110,
			time   = 0.1,
			minpos = {x = pos.x - 0.5, y = pos.y - 1.2, z = pos.z - 0.5},
			maxpos = {x = pos.x + 0.5, y = pos.y + 1.2, z = pos.z + 0.5},
			minvel = {x = -5, y = -1, z = -5},
			maxvel = {x =  5, y =  1, z =  5},
			minacc = {x =  0, y =  0, z =  0},
			maxacc = {x =  0, y =  0, z =  0},
			minexptime = 0.1,
			maxexptime = 0.5,
			minsize = 0.2 * portalDef.particle_texture_scale,
			maxsize = 0.8 * portalDef.particle_texture_scale,
			collisiondetection = false,
			texture = textureName .. "^[colorize:#FFC:alpha",
			animation = portalDef.particle_texture_animation,
			glow = 8
		})
	end
})

if not portalRegistered then
	error(deepnether.modName .. " was unable to register its portal. Perhaps another mod has already registered one with the same shape and material. Check for errors in the debug.txt file for more details.")
end


--=====================--
--== Atmospheric fog ==--
--=====================--

-- Set appropriate distance-fog if climate_api is available
--
-- Delegating to a mod like climate_api means nether won't unexpectedly stomp on the sky of
-- any other mod.
-- Skylayer is another mod which can perform this role, and skylayer support could be added
-- here as well.
if minetest.get_modpath("climate_api") and minetest.global_exists("climate_api") and climate_api.register_weather ~= nil then

	climate_api.register_influence(
		"deepnether_biome",
		function(pos)
			if pos.y <= deepnether.DEPTH_CEILING and pos.y >= deepnether.DEPTH_FLOOR then
				return "inside"
			end
			return "outside"
		end
	)

	-- using sky type "plain" unfortunately means we don't get smooth fading transitions when
	-- the color of the sky changes, but it seems to be the only way to obtain a sky colour
	-- which doesn't brighten during the daytime.
	local deepNetherSky = {
		sky_data = {
			base_color = deepnether.fogColor,
			type = "plain",
			textures = nil,
			clouds = false,
		},
		sun_data = {
			visible = false,
			sunrise_visible = false
		},
		moon_data = {
			visible = false
		},
		star_data = {
			visible = false
		}
	}

	climate_api.register_weather(
		"nether:nether",
		{ deepnether_biome = "inside" },
		{ ["climate_api:skybox"] = deepNetherSky }
	)
end



--============--
--== Mapgen ==--
--============--

local CAVERN_FLOOR   = deepnether.DEPTH_FLOOR   + deepnether.BUFFER_ZONE
local CAVERN_CEILING = deepnether.DEPTH_CEILING - deepnether.BUFFER_ZONE
local CAVERN_HEIGHT  = CAVERN_CEILING - CAVERN_FLOOR
local LAVA_LEVEL     = CAVERN_FLOOR + 5


if minetest.registered_nodes["nether:native_mapgen"] == nil then
	-- The nether's mapgen must have been disabled, guess it won't mind if we register its "native_mapgen" node
	minetest.register_node(":nether:native_mapgen", {})
end

-- Set node_cave_liquid to "air" to avoid lava and water being generated in the caverns.
-- nether:native_mapgen is used to avoid ores and decorations being generated according
-- to landforms created by the native mapgen before our on_generated() runs.
-- Ores and decorations can be registered against "nether:rack_deep" instead, and the
-- lua on_generate() callback will carve the caverns with nether:rack_deep before invoking
-- generate_decorations and generate_ores.
minetest.register_biome({
	name = deepnether.modName .. "_caverns",
	node_stone  = "nether:native_mapgen", -- nether:native_mapgen is used here to prevent the native mapgen from placing ores and decorations.
	node_filler = "nether:native_mapgen", -- The lua on_generate will transform nether:native_mapgen into nether:rack then decorate and add ores.
	node_dungeon = "nether:brick_deep",
	-- Setting node_cave_liquid to "air" avoid lava and water being generated mid-air in the caverns and making a mess.
	node_cave_liquid = "air",
	y_max = deepnether.DEPTH_CEILING,
	y_min = deepnether.DEPTH_FLOOR,
	vertical_blend = 0,
	heat_point = 50,
	humidity_point = 50,
})

minetest.register_ore({ -- add lava falling from the ceiling
	ore_type       = "scatter",
	ore            = "default:lava_source",
	wherein        = {"nether:rack", "nether:rack_deep"},
	clust_scarcity = 32 * 32 * 32,
	clust_num_ores = 4,
	clust_size     = 2,
	y_max = deepnether.DEPTH_CEILING,
	y_min = math.floor((deepnether.DEPTH_CEILING + deepnether.DEPTH_FLOOR) / 2)
})

minetest.register_ore({ -- adds glowstones near the ground for more light
	ore_type       = "scatter",
	ore            = "nether:glowstone",
	wherein        = {"nether:rack", "nether:rack_deep"},
	clust_scarcity = 13 * 13 * 13,
	clust_num_ores = 4,
	clust_size     = 2,
	y_max = math.floor((deepnether.DEPTH_CEILING + deepnether.DEPTH_FLOOR) / 2),
	y_min = LAVA_LEVEL
})

-- use one of the nether's fumarole decorations to add fumaroles to this layer
local fumaroleDecoration = minetest.registered_decorations["Sunken nether fumarole"]
if fumaroleDecoration == nil then
	-- the nether realm might be disabled, or the name of the fumarole decoration changed
	minetest.log("warning", deepnether.modName .. " was unable to find the nether fumarole decoration, so will skip it.")
 else
	minetest.register_decoration({
		name           = deepnether.modName .. " fumarole",
		place_on       = {"nether:rack_deep"},
		sidelen        = 80,
		fill_ratio     = 0.01,
		y_max          = LAVA_LEVEL + 15,
		y_min          = LAVA_LEVEL,
		deco_type      = fumaroleDecoration.deco_type,
		schematic      = fumaroleDecoration.schematic,
		replacements   = fumaroleDecoration.replacements,
		flags          = fumaroleDecoration.flags,
		place_offset_y = fumaroleDecoration.place_offset_y
	})
end

local np_cave = {
	offset     = -0.05, -- make the scale range -1 to +0.9, so that abs(noise) will provide two different scales of peak
	scale      = 0.95,
	spread     = {x = 128, y = 128, z = 128},
	seed       = 59033,
	octaves    = 7,
	persist    = 0.54,
	lacunarity = 2.0,
	--flags    = ""
}
local nbuf_cave = {}
local dbuf      = {}
local nobj_cave = nil

local c_air              = minetest.get_content_id("air")
local c_netherrack       = minetest.get_content_id("nether:rack")
local c_netherrack_deep  = minetest.get_content_id("nether:rack_deep")
local c_lavasea_source   = minetest.get_content_id("nether:lava_source") -- same as lava but with staggered animation to look better as an ocean
local c_lava_crust       = minetest.get_content_id("nether:lava_crust")
local c_native_mapgen    = minetest.get_content_id("nether:native_mapgen")

local function on_generated(minp, maxp, seed)

	if minp.y > deepnether.DEPTH_CEILING or maxp.y < deepnether.DEPTH_FLOOR then
		return
	end

	local vm, emerge_min, emerge_max = minetest.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new{MinEdge=emerge_min, MaxEdge=emerge_max}
	local data = vm:get_data(dbuf)

	local x0, y0, z0 = minp.x, math.max(minp.y, deepnether.DEPTH_FLOOR),   minp.z
	local x1, y1, z1 = maxp.x, math.min(maxp.y, deepnether.DEPTH_CEILING), maxp.z
	local yCaveStride = x1 - x0 + 1
	local ystride = area.ystride
	local math_abs = math.abs

	nobj_cave = nobj_cave or minetest.get_perlin_map(np_cave, {x = yCaveStride, y = yCaveStride})
	local nvals_cave = nobj_cave:get_2d_map_flat({x=minp.x, y=minp.z}, {x=yCaveStride, y=yCaveStride}, nbuf_cave)

	for z = z0, z1 do
		local vi_xz = area:index(x0, y0, z) -- Initial voxelmanip index
		local noise_i = 1 + (z - z0) * yCaveStride
		for x = x0, x1 do
			local noise = math_abs(nvals_cave[noise_i])
			local noiseSquared = noise * noise
			local ceil_y  = CAVERN_CEILING - (0.68 * CAVERN_HEIGHT) * noiseSquared * noiseSquared
			local floor_y = CAVERN_FLOOR   + (0.3  * CAVERN_HEIGHT) * (noiseSquared * noiseSquared * noiseSquared / 1.6 + noise / 3)

			local vi = vi_xz
			for y = y0, y1 do
				if y < floor_y or y > ceil_y then
					data[vi] = c_netherrack_deep
				elseif y > LAVA_LEVEL then
					data[vi] = c_air
				elseif y == LAVA_LEVEL and noise > 0.29 then
					data[vi] = c_lava_crust
				else
					data[vi] = c_lavasea_source
				end
				vi = vi + ystride
			end

			vi_xz = vi_xz + 1
			noise_i = noise_i + 1
		end
	end
	vm:set_data(data)

	minetest.generate_ores(vm)
	minetest.generate_decorations(vm)

	vm:set_lighting({day = 0, night = 0}, minp, maxp)
	vm:calc_lighting()
	vm:update_liquids()
	vm:write_to_map()
end
minetest.register_on_generated(on_generated)


-- use knowledge of this layer mapgen algorithm to return a suitable ground level for placing a portal.
-- player_name is optional, allowing a player to spawn a remote portal in their own protected areas.
deepnether.find_layer_ground_y = function(target_x, target_z, start_y, player_name)
	local cavePerlin = minetest.get_perlin(np_cave)
	local noise = math.abs(cavePerlin:get_2d({x = target_x, y = target_z}))
	local floor_level =  CAVERN_FLOOR + CAVERN_HEIGHT * 0.3 * ((noise * noise * noise * noise * noise * noise) / 1.6 + noise / 3)

	return math.max(LAVA_LEVEL, floor_level) + 1
end