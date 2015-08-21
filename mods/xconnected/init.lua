
xconnected = {}

-- this table contains the new postfix and param2 for a newly placed node
-- depending on its neighbours
local xconnected_get_candidate = {};
-- no neighbours
xconnected_get_candidate[0]  = {"_c0", 0 };
-- exactly one neighbour
xconnected_get_candidate[1]  = {"_c1", 1 };
xconnected_get_candidate[2]  = {"_c1", 0 };
xconnected_get_candidate[4]  = {"_c1", 3 };
xconnected_get_candidate[8]  = {"_c1", 2 };
-- a line between two nodes
xconnected_get_candidate[5]  = {"_ln", 1 };
xconnected_get_candidate[10] = {"_ln", 0 };
-- two neighbours
xconnected_get_candidate[3]  = {"_c2", 0 };
xconnected_get_candidate[6]  = {"_c2", 3 };   
xconnected_get_candidate[12] = {"_c2", 2 };
xconnected_get_candidate[9]  = {"_c2", 1 };
-- three neighbours
xconnected_get_candidate[7]  = {"_c3", 3 };
xconnected_get_candidate[11] = {"_c3", 0 }; 
xconnected_get_candidate[13] = {"_c3", 1 };
xconnected_get_candidate[14] = {"_c3", 2 };
-- four neighbours
xconnected_get_candidate[15] = {"_c4", 1 };

local directions = {
	{x = 1, y = 0, z = 0},
	{x = 0, y = 0, z = 1},
	{x = -1, y = 0, z = 0},
	{x = 0, y = 0, z = -1},
}


-- each node depends on the position and amount of neighbours of the same type;
-- the param2 value of the neighbour is not important here
xconnected_update_one_node = function( pos, name, digged )
	if( not( pos ) or not( name) or not( minetest.registered_nodes[name])) then
		return;
	end

	local candidates = {0,0,0,0};
	local id   = 0;
	local pow2 = {1,2,4,8};
	for i, dir in pairs(directions) do
		local node = minetest.get_node( {x=pos.x+dir.x, y=pos.y, z=pos.z+dir.z });
		if(    node
		   and node.name
		   and minetest.registered_nodes[node.name] ) then
	
			local ndef= minetest.registered_nodes[node.name];
			-- nodes that drop the same are considered similar xconnected nodes
			if( ndef.drop == name 
			  -- ..and also those that share the xcentered group
			  or (ndef.groups and ndef.groups.xconnected)) then
				candidates[i] = node.name;
				id = id+pow2[i];
			end
			-- connect to other solid nodes as well
			if(   ndef.walkable ~= false
			  and ndef.drawtype ~= "nodebox") then
				-- this neighbour does not need updating
				candidates[i] = 0;
				-- ..but is relevant as far as selecting our shape goes
				id = id+pow2[i];
			end
		end
	end
	if( digged ) then
		return candidates;
	end
	local new_node = xconnected_get_candidate[ id ];
	if( new_node and new_node[1] ) then
		local new_name = string.sub( name, 1, string.len( name )-3 )..new_node[1];
		if(     new_name and minetest.registered_nodes[ new_name ]) then
			minetest.swap_node( pos, {name=new_name, param2=new_node[2] });
		-- if no central node without neighbours is defined, take the c4 variant
		elseif( new_node[1]=='_c0' and not( minetest.registered_nodes[ new_name ])) then
			minetest.swap_node( pos, {name=name,     param2=0 });
		end
	end
	return candidates;
end


-- called in on_construct and after_dig_node
xconnected_update = function( pos, name, active, has_been_digged )
	if( not( pos ) or not( name) or not( minetest.registered_nodes[name])) then
		return;
	end

	local c = xconnected_update_one_node( pos, name, has_been_digged );
	for j,dir2 in pairs(directions) do
		if( c[j]~=0 and c[j]~='ignore') then
			xconnected_update_one_node( {x=pos.x+dir2.x, y=pos.y, z=pos.z+dir2.z}, c[j], false );
		end
	end		
end

-- def: that part of the node definition that is shared between all nodes
-- node_box_data: has to be a table that contains defs for   "c0", "c1", "c2", "c3", "c4", "ln"
-- c<nr>: node is connected to that many neighbours clockwise
-- ln: node has 2 neighbours at opposite ends and forms a line with them
xconnected.register = function( name, def, node_box_data, selection_box_data )

	for k,v in pairs( node_box_data ) do 
		-- some common values for all xconnected nodes
		def.drawtype   = "nodebox";
		def.paramtype  = "light";
		def.paramtype2 = "facedir";
		-- similar xconnected nodes are identified by having the same drop
		def.drop = name.."_c4";
		-- nodebox and selection box have been calculated using smmyetry
		def.node_box = {
			type = "fixed",
			fixed = node_box_data[k],
		};
		def.selection_box = {
			type = "fixed",
			fixed = selection_box_data[k],
		};

		if( not( def.tiles )) then
			def.tiles = def.textures;
		end

		-- nodes of the xconnected type all share one group and connect to each other
		if( not( def.groups )) then
			def.groups = {xconnected=1,oddly_breakable_by_hand=1,choppy=1};
		else
			def.groups.xconnected = 1;
		end

		local new_def = minetest.deserialize( minetest.serialize( def ));
		if( k=='c4' ) then
			-- update nodes when needed
			new_def.on_construct = function( pos )
				return xconnected_update( pos, name.."_c4", true, nil );
			end
		else
			-- avoid spam in creative inventory
			new_def.groups.not_in_creative_inventory = 1;
		end
		-- update neighbours when this node is dug
		new_def.after_dig_node = function(pos, oldnode, oldmetadata, digger)
			return xconnected_update( pos, name.."_c4", true, true );
		end

		-- actually register the node
		minetest.register_node( name.."_"..k, new_def );
	end
end


-- make use of the symmetry of the nodes and calculate the nodeboxes that way
-- (may also be used for collusion boxes);
-- the center_node_box_list is shared by all nodes that have nighbours
xconnected.construct_node_box_data = function( node_box_list, center_node_box_list, node_box_line )
	local res = {};
	res.c1 = {};
	res.c2 = {};
	res.c3 = {};
	res.c4 = {};

	-- start with the node that is only connected to one neighbour
	for _,v in pairs( node_box_list ) do
		-- the node c1 already contains all nodes rotated the right way
		table.insert( res.c1, v );
		table.insert( res.c2, v );
		table.insert( res.c3, v );
		table.insert( res.c4, v );
	end

	-- this node is connected to two neighbours and forms a curve/corner;
	-- it keeps the nodes from above plus..
	for _,v in pairs( node_box_list ) do
		-- swap x and z - we are working on a corner node
		table.insert( res.c2, {v[3], v[2], v[1],    v[6], v[5], v[4]});
		table.insert( res.c3, {v[3], v[2], v[1],    v[6], v[5], v[4]});
		table.insert( res.c4, {v[3], v[2], v[1],    v[6], v[5], v[4]});
	end
	
	-- now we have a t-crossing
	for _,v in pairs( node_box_list ) do
		-- mirror x
		table.insert( res.c3, {v[4], v[2], v[3]-0.5,  v[1], v[5], v[6]-0.5});
		table.insert( res.c4, {v[4], v[2], v[3]-0.5,  v[1], v[5], v[6]-0.5});
	end

	-- ...and now a node which is connected to four neighbours
	for _,v in pairs( node_box_list ) do
		-- swap x and z and mirror
		table.insert( res.c4, {v[3]-0.5, v[2], v[4],    v[6]-0.5, v[5], v[1]});
	end

	res.c0 = {};
	for _,v in pairs( center_node_box_list ) do
		table.insert( res.c0, v );
		table.insert( res.c1, v );
		table.insert( res.c2, v );
		table.insert( res.c3, v );
		table.insert( res.c4, v );
	end	

	-- no center node
	if( #res.c0 < 1 ) then
		res.c0 = nil;
	end

	res.ln = node_box_line;
	return res;
end


-- emulate xpanes
xconnected.register_pane = function( name, tiles, def )
	local node_box_data = xconnected.construct_node_box_data(
		-- a half-pane
		{{-1/32, -0.5, 0,     1/32, 0.5, 0.5}},
		-- there is nothing special in the center
		{},
		-- a full pane (with neighbours on opposite sides)
		{{-1/32, -0.5, -0.5,  1/32, 0.5, 0.5}});
	local selection_box_data = 
		xconnected.construct_node_box_data(
		{{-0.06, -0.5, 0,     0.06, 0.5, 0.5}},
		{},
		{{-0.06, -0.5, -0.5,  0.06, 0.5, 0.5}});
	if( not( def )) then
		def = {
			description = name.." Pane",
			textures = {tiles,tiles,tiles,tiles},
			is_ground_content = false,
			sunlight_propagates = true,
			use_texture_alpha = true,
			sounds = default.node_sound_glass_defaults(),
			groups = {snappy=2, cracky=3, oddly_breakable_by_hand=3, pane=1},
		};
	end
	xconnected.register( name,
		def,
		-- node boxes (last one: full one)
		node_box_data,
		-- selection boxes (last one: full one)
		selection_box_data
		);

-- TODO: register_craft would be needed as well (for backwards compatibility)
end

xconnected.register_wall = function( name, tiles, def )
	local node_box_data = xconnected.construct_node_box_data(
		-- one extension
		{{-3/16, -0.5,    0,  3/16,  5/16, 0.5}},
		-- the central part
		{{-4/16, -0.5, -4/16, 4/16,  0.5, 4/16 }},
		-- neighbours on two opposide sides
		{{-3/16, -0.5,  -0.5, 3/16, 5/16, 0.5}});
	local selection_box_data =
		xconnected.construct_node_box_data(
		{{-0.2, -0.5, 0,     0.2,  5/16, 0.5}},
		{{-0.25, -0.5, -0.25, 0.25, 0.5, 0.25 }},
		{{-0.2, -0.5, -0.5,  0.2, 5/16, 0.5}});
	if( not( def )) then
		def = { 
			description = name.." Wall",
			textures = {tiles,tiles,tiles,tiles},
			is_ground_content = false,
			sunlight_propagates = true,
			sounds = default.node_sound_stone_defaults(),
			groups = {cracky=3, stone=1, pane=1},
		};
	end
	xconnected.register( name,
		def,
		node_box_data,
		selection_box_data
		);
end



xconnected.register_fence = function( name, tiles, def )
	local node_box_data = xconnected.construct_node_box_data(
		-- one extension
    		{{-0.06,  0.25, 0, 0.06, 0.4, 0.5},
		 {-0.06, -0.15, 0, 0.06, 0,   0.5}},
		-- the central part
		{{-0.1, -0.5, -0.1, 0.1, 0.5, 0.1}},
		-- neighbours on two opposide sides
    		{{-0.06,  0.25, -0.5, 0.06, 0.4, 0.5},
		 {-0.06, -0.15, -0.5, 0.06, 0,   0.5}});
	-- only the central part acts as a selection box
	local selection_box_data = xconnected.construct_node_box_data(
		{},
		{{-0.2, -0.5, -0.2, 0.2, 0.5, 0.2}},
		{{-0.2, -0.5, -0.2, 0.2, 0.5, 0.2}});
	if( not( def )) then
		def = { 
			description = name.." Wall",
			textures = {tiles,tiles,tiles,tiles},
			is_ground_content = false,
			sunlight_propagates = true,
			sounds = default.node_sound_stone_defaults(),
			groups = {snappy=2, cracky=3, oddly_breakable_by_hand=2, pane=1, flammable=2},
		};
	end
	xconnected.register( name,
		def,
		node_box_data,
		selection_box_data
		);
end

-- TODO make global table, for loops, and recipes.

xconnected.register_pane("xconnected:bar", "xconnected_bar.png")
minetest.register_craft({
	output = "xconnected:bar_c4 16",
	recipe = {
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"}
	}
})

xconnected.register_pane('xconnected:pane_glass_white', 'default_glass.png')
minetest.register_craft({
	output = "xconnected:pane_glass_white_c4 16",
	recipe = {
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_gray", "default_glass.png^[colorize:gray")
minetest.register_craft({
	output = "xconnected:pane_glass_gray_c4 16",
	recipe = {
		{"dye:grey", "dye:grey", "dye:grey"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_darkgray", "default_glass.png^[colorize:darkgray")
minetest.register_craft({
	output = "xconnected:pane_glass_darkgray_c4 16",
	recipe = {
		{"dye:dark_grey", "dye:dark_grey", "dye:dark_grey"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_black", "default_glass.png^[colorize:black")
minetest.register_craft({
	output = "xconnected:pane_glass_black_c4 16",
	recipe = {
		{"dye:black", "dye:black", "dye:black"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_violet", "default_glass.png^[colorize:violet")
minetest.register_craft({
	output = "xconnected:pane_glass_violet_c4 16",
	recipe = {
		{"dye:violet", "dye:violet", "dye:violet"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_blue", "default_glass.png^[colorize:blue")
minetest.register_craft({
	output = "xconnected:pane_glass_blue_c4 16",
	recipe = {
		{"dye:blue", "dye:blue", "dye:blue"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_cyan", "default_glass.png^[colorize:cyan")
minetest.register_craft({
	output = "xconnected:pane_glass_cyan_c4 16",
	recipe = {
		{"dye:cyan", "dye:cyan", "dye:cyan"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_darkgreen", "default_glass.png^[colorize:darkgreen")
minetest.register_craft({
	output = "xconnected:pane_glass_darkgreen_c4 16",
	recipe = {
		{"dye:dark_green", "dye:dark_green", "dye:dark_green"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_green", "default_glass.png^[colorize:green")
minetest.register_craft({
	output = "xconnected:pane_glass_green_c4 16",
	recipe = {
		{"dye:green", "dye:green", "dye:green"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_yellow", "default_glass.png^[colorize:yellow")
minetest.register_craft({
	output = "xconnected:pane_glass_yellow_c4 16",
	recipe = {
		{"dye:yellow", "dye:yellow", "dye:yellow"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_brown", "default_glass.png^[colorize:brown")
minetest.register_craft({
	output = "xconnected:pane_glass_brown_c4 16",
	recipe = {
		{"dye:brown", "dye:brown", "dye:brown"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_orange", "default_glass.png^[colorize:orange")
minetest.register_craft({
	output = "xconnected:pane_glass_orange_c4 16",
	recipe = {
		{"dye:orange", "dye:orange", "dye:orange"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_red", "default_glass.png^[colorize:red")
minetest.register_craft({
	output = "xconnected:pane_glass_red_c4 16",
	recipe = {
		{"dye:red", "dye:red", "dye:red"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_magenta", "default_glass.png^[colorize:magenta")
minetest.register_craft({
	output = "xconnected:pane_glass_magenta_c4 16",
	recipe = {
		{"dye:magenta", "dye:magenta", "dye:magenta"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})
xconnected.register_pane("xconnected:pane_glass_pink", "default_glass.png^[colorize:pink")
minetest.register_craft({
	output = "xconnected:pane_glass_pink_c4 16",
	recipe = {
		{"dye:pink", "dye:pink", "dye:pink"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:glass", "default:glass", "default:glass"}
	}
})

-- TODO match xdecor's worktable, add hedges to worktable
xconnected.register_wall( 'xconnected:wall_tree',               'default_tree.png' )
xconnected.register_wall( 'xconnected:wall_wood',               'default_wood.png' )
xconnected.register_wall( 'xconnected:wall_stone',              'default_stone.png' )
minetest.register_craft({
	output = "xconnected:wall_stone_c4 6",
	recipe = {
		{"default:stone", "default:stone", "default:stone"},
		{"default:stone", "default:stone", "default:stone"}
	}
})
xconnected.register_wall( 'xconnected:wall_cobble',             'default_cobble.png' )
minetest.register_craft({
	output = "xconnected:wall_cobble_c4 6",
	recipe = {
		{"default:cobble", "default:cobble", "default:cobble"},
		{"default:cobble", "default:cobble", "default:cobble"}
	}
})
xconnected.register_wall("xconnected:wall_mossycobble", "default_mossycobble.png")
minetest.register_craft({
	output = "xconnected:wall_mossycobble_c4 6",
	recipe = {
		{"default:mossycobble", "default:mossycobble", "default:mossycobble"},
		{"default:mossycobble", "default:mossycobble", "default:mossycobble"}
	}
})
xconnected.register_wall( "xconnected:wall_brick",              "default_brick.png" )
minetest.register_craft({
	output = "xconnected:wall_brick_c4 6",
	recipe = {
		{"default:brick", "default:brick", "default:brick"},
		{"default:brick", "default:brick", "default:brick"}
	}
})
xconnected.register_wall( "xconnected:wall_stone_brick",        "default_stone_brick.png" )
xconnected.register_wall( "xconnected:wall_sandstone_brick",    "default_sandstone_brick.png" )
xconnected.register_wall( "xconnected:wall_desert_stone_brick", "default_desert_stone_brick.png" )
xconnected.register_wall( "xconnected:wall_obsidian_brick",     "default_obsidian_brick.png" )
xconnected.register_wall( "xconnected:wall_hedge",              "default_leaves.png" )
xconnected.register_wall( "xconnected:wall_clay",               "default_clay.png" )
xconnected.register_wall( "xconnected:wall_coal_block",         "default_coal_block.png" )

-- default:fence_wood replaced
xconnected.register_fence('xconnected:fence',        'xdecor_wood.png')
xconnected.register_fence('xconnected:fence_pine',   'default_pine_wood.png')
xconnected.register_fence('xconnected:fence_jungle', 'default_junglewood.png')
xconnected.register_fence('xconnected:fence_acacia', 'default_acacia_wood.png')

-- XPanes aliases
minetest.register_alias("xpanes:pane", "xconnected:pane_glass_white_c4")
minetest.register_alias("xpanes:pane_gray", "xconnected:pane_glass_gray_c4")
minetest.register_alias("xpanes:pane_darkgray", "xconnected:pane_glass_darkgray_c4")
minetest.register_alias("xpanes:pane_black", "xconnected:pane_glass_black_c4")
minetest.register_alias("xpanes:pane_violet", "xconnected:pane_glass_violet_c4")
minetest.register_alias("xpanes:pane_blue", "xconnected:pane_glass_blue_c4")
minetest.register_alias("xpanes:pane_cyan", "xconnected:pane_glass_cyan_c4")
minetest.register_alias("xpanes:pane_darkgreen", "xconnected:pane_glass_darkgreen_c4")
minetest.register_alias("xpanes:pane_green", "xconnected:pane_glass_green_c4")
minetest.register_alias("xpanes:pane_yellow", "xconnected:pane_glass_yellow_c4")
minetest.register_alias("xpanes:pane_brown", "xconnected:pane_glass_brown_c4")
minetest.register_alias("xpanes:pane_orange", "xconnected:pane_glass_orange_c4")
minetest.register_alias("xpanes:pane_red", "xconnected:pane_glass_red_c4")
minetest.register_alias("xpanes:pane_magenta", "xconnected:pane_glass_magenta_c4")
minetest.register_alias("xpanes:pane_pink", "xconnected:pane_glass_pink_c4")


--[[
-- this innocent loop creates quite a lot of nodes - but only if you have the stained_glass mod installed
if(    minetest.get_modpath( "stained_glass" )
   and minetest.global_exists( stained_glass_hues)
   and minetest.global_exists( stained_glass_shade)) then

	for _,hue in ipairs( stained_glass_hues ) do
		for _,shade in ipairs( stained_glass_shade ) do
			xconnected.register_pane( 'xconnected:pane_'..shade[1]..hue[1],        'stained_glass_'..shade[1]..hue[1]..'.png');
		end
	end
end
--]]
