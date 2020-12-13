tool
extends Control

onready var ldtkImportDialog = $LDtkFileImport
onready var outputDirDialog = $OutputDir
onready var outputDirTxt = $MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/HBoxContainer/HBoxContainer/OutputDirText

var outputDir = "res://"

class LDtkTileset:
	var uid
	var name
	var grid_size
	var texture
	var tileset
	var path
	
class LDtkLayer:
	var uid
	var grid_size
	var tileset_uid
	var auto_tileset_uid

# Called when the node enters the scene tree for the first time.
func _ready():
	outputDirTxt.text = outputDir
	outputDirDialog.current_dir = outputDir

func _create_assets(projectName, ldtkDefs, ldtkLevels, ldtkHomeDirectory):
	var projectOutputDir = outputDir.plus_file(projectName)
	var tilesetDirPath = projectOutputDir.plus_file("/tilesets/")
	
	var tilesetDir = Directory.new()
	if !tilesetDir.dir_exists(tilesetDirPath):
		tilesetDir.make_dir_recursive(tilesetDirPath)
	
	var tilesets = _create_tilesets(ldtkDefs["tilesets"], ldtkHomeDirectory, tilesetDirPath)
	var layerDefs = _load_layer_defs(ldtkDefs["layers"])
	
	_create_levels(ldtkLevels, layerDefs, tilesets, projectOutputDir)
	
func _create_tilesets(ldtkTilesets, ldtkHomeDirectory, tilesetDirPath):
	var tilesetDict = {}
	for tilesetData in ldtkTilesets:
		# Assume realtive path as this will be the most common case
		var texturePath = ldtkHomeDirectory.plus_file(tilesetData["relPath"])
		
		# Check for an absolute path. 
		# This should only happen if the user selected an image on a diffrent drive
		if tilesetData["relPath"].is_abs_path():
			texturePath = tilesetData["relPath"]
		
		var ldtkTileset = LDtkTileset.new()
		ldtkTileset.uid = tilesetData["uid"]
		ldtkTileset.name = tilesetData["identifier"]
		ldtkTileset.grid_size = tilesetData["tileGridSize"]
		ldtkTileset.texture = load(texturePath)
		ldtkTileset.path = tilesetDirPath.plus_file(tilesetData["identifier"]+".tres")
		
		if ResourceLoader.exists(ldtkTileset.path):
			ldtkTileset.tileset = ResourceLoader.load(ldtkTileset.path)
		else:
			ldtkTileset.tileset = TileSet.new()
		
		tilesetDict[ldtkTileset.uid] = ldtkTileset
		
	return tilesetDict
	
func _load_layer_defs(ldtkLayerDef):
	var layerDict = {}
	for layer in ldtkLayerDef:
		var ldtkLayer = LDtkLayer.new()
		ldtkLayer.uid = layer["uid"]
		ldtkLayer.grid_size = layer["gridSize"]
		ldtkLayer.tileset_uid = layer["tilesetDefUid"]
		ldtkLayer.auto_tileset_uid = layer["autoTilesetDefUid"]
		
		layerDict[ldtkLayer.uid] = ldtkLayer
		
	return layerDict
	
func _create_levels(levels, layersDef, tilesets, outputDir):
	for level in levels:
		var sceneFile = outputDir.plus_file(level["identifier"]+".tscn")
		
		var rootNode = null
		if ResourceLoader.exists(sceneFile):
			rootNode = ResourceLoader.load(sceneFile).instance()
		else:
			rootNode = Node2D.new()
		rootNode.name = level["identifier"]
		
		var entitiesRootNode = rootNode.get_node_or_null("Entities")
		if entitiesRootNode == null:
			entitiesRootNode = Node2D.new()
			entitiesRootNode.name = "Entities"
			rootNode.add_child(entitiesRootNode, true)
			entitiesRootNode.owner = rootNode
		
		var layerRootNode = rootNode.get_node_or_null("Layers")
		if layerRootNode == null:
			layerRootNode = Node2D.new()
			layerRootNode.name = "Layers"
			rootNode.add_child(layerRootNode, true)
			layerRootNode.owner = rootNode
		
		for layer in level["layerInstances"]:
			if layer["__type"] == "Entities":
				var entityLayer = entitiesRootNode.get_node_or_null(layer["__identifier"])
				if entityLayer == null:
					entityLayer = Node2D.new()
					entityLayer.name = layer["__identifier"]
					entitiesRootNode.add_child(entityLayer, true)
					entityLayer.owner = rootNode
				
				entitiesRootNode.move_child(entityLayer, 0)
				for entityInstance in layer["entityInstances"]:
					var entityNode = entityLayer.get_node_or_null(entityInstance["__identifier"])
					var entity = _create_entity(entityInstance, entityNode, rootNode)
					
					if entityNode == null && entity:
						entityLayer.add_child(entity, true)
						entity.owner = rootNode
					
					if entity:
						entityLayer.move_child(entity, 0)
			else:
				var loadedLayerNode = layerRootNode.get_node_or_null(layer["__identifier"])
				var layerNode = _create_layer(layer, layersDef, tilesets, loadedLayerNode)
				
				# Inital node setup
				if loadedLayerNode == null && layerNode:
					layerRootNode.add_child(layerNode, true)
					layerNode.owner = rootNode
				
				if layerNode:
					layerRootNode.move_child(layerNode,0)
			
		if layerRootNode.get_child_count() > 0 || entitiesRootNode.get_child_count() > 0:
			var scene = PackedScene.new()
			scene.pack(rootNode)
			
			ResourceSaver.save(sceneFile, scene)
		
	# Save changes to the tilesets
	for tileset in tilesets.values():
		if len(tileset.tileset.get_tiles_ids()) > 0:
			ResourceSaver.save(tileset.path, tileset.tileset)
			
func _create_entity(entity, entityNode, rootNode):
	# Check if we need to create the entity node
	var node = null
	
	for field in entity["fieldInstances"]:
		if field["__identifier"] == "_Node":
			node = field["__value"]
			
		if node:
			break
			
	var sceneFile = node
	if not sceneFile.get_extension():
		sceneFile = sceneFile+".tscn"
			
	# Create a new node
	if entityNode == null:			
		entityNode = _find_and_load_scene(sceneFile)
		if entityNode == null && node && ClassDB.can_instance(node):
			entityNode = ClassDB.instance(node)
			
		if entityNode == null:
			push_error("Can not instance node "+node+". Skipping creating node")
	else:		
		var updatedNode = _find_and_load_scene(sceneFile)
		if updatedNode == null && node && ClassDB.can_instance(node):
			updatedNode = ClassDB.instance(node)
			
		if updatedNode && (entityNode.get_class() != updatedNode.get_class() || entityNode.filename != updatedNode.filename):
			entityNode.free()
			entityNode = updatedNode
			
		if updatedNode == null:
			push_error("Can not instance node "+node+". Skipping type update")

				
	if entityNode && entityNode.has_method("load_ldtk_entity"):
		entityNode.load_ldtk_entity(entity)
	elif entityNode:
		entityNode.name = entity["__identifier"]
		if not entityNode.set("position", Vector2(entity["px"][0],entity["px"][1])):
			push_warning("No position field on this node")
		
		for field in entity["fieldInstances"]:
			if field["__identifier"] == "_Node" || field["__identifier"] == "_Scene":
				continue
			
			var fieldName = field["__identifier"]
			var fieldValue = field["__value"]
			var fieldType = field["__type"]
			
			if "Point" in fieldType:
				if typeof(fieldValue) == TYPE_ARRAY:
					var newArray = []
					for value in fieldValue:
						newArray.append(Vector2(value["cx"], value["cy"]))
					fieldValue = newArray
				else:
					fieldValue = Vector2(fieldValue["cx"], fieldValue["cy"])
			elif "Color" in fieldType:
				if typeof(fieldValue) == TYPE_ARRAY:
					var newArray = []
					for value in fieldValue:
						newArray.append(Color(value))
					fieldValue = newArray
				else:
					fieldValue = Color(fieldValue)
			
			if not entityNode.set(fieldName, fieldValue):
				push_warning("Field "+fieldName+" does not exsist")
	
	return entityNode
	
func _find_and_load_scene(scene, dir="res://"):
	if scene == null:
		return null
		
	var directory = Directory.new()
	if directory.open(dir) != OK:
		push_error("Could not open "+dir)
		return null
	
	if directory.list_dir_begin(true) != OK:
		push_error("Could not list contents of "+dir)
		return null
		
	var sceneNode = null
	var fileName = directory.get_next()
	while fileName && sceneNode == null:
		var fullPath = dir.plus_file(fileName)
		if directory.current_is_dir():
			sceneNode = _find_and_load_scene(scene, fullPath)
		# TODO: Should find a better way to do this as there is a high possiblity
		# of accidentally loading the wrong file
		elif scene in fullPath:
			sceneNode = ResourceLoader.load(fullPath).instance()
		fileName = directory.get_next()
	
	directory.list_dir_end()
		
	return sceneNode
	
func _create_layer(layer, layersDef, tilesets, tilemap):
	var tiles = layer["autoLayerTiles"]
	if len(tiles) <= 0:
		tiles = layer["gridTiles"]
	
	if len(tiles) <= 0:
		return null		# No tiles no need to create layer
		
	var tileset = null
	var layerDef = layersDef[layer["layerDefUid"]]
	if layerDef.auto_tileset_uid:
		 tileset = tilesets[layerDef.auto_tileset_uid]
	elif layerDef.tileset_uid:
		tileset = tilesets[layerDef.tileset_uid]
	else:
		return null		# No need to create layer if there is no tileset
	
	if tilemap==null:
		tilemap = TileMap.new()
	tilemap.name = layer["__identifier"]
	tilemap.modulate.a = layer["__opacity"]
	tilemap.cell_size = Vector2(layerDef.grid_size, layerDef.grid_size)
	tilemap.tile_set = tileset.tileset

	for tile in tiles:
		var tilePos = Vector2(tile["src"][0], tile["src"][1])
		var region = Rect2(tilePos, tilemap.cell_size)
		var tileId = tile["d"].back()
		_create_tile(tileId, region, tileset.texture, tileset.tileset)
		
		var worldPos = Vector2(tile["px"][0], tile["px"][1])
		var gridPos = tilemap.world_to_map(worldPos)
		var flip = int(tile["f"])
		var flipX = bool(flip & 1)
		var flipY = bool(flip & 2)
		
		tilemap.set_cellv(gridPos, tileId, flipX, flipY)
	
	return tilemap
	
func _create_tile(tileId, region, texture, tileset):
	if not tileId in tileset.get_tiles_ids():
		tileset.create_tile(tileId)
		
	tileset.tile_set_tile_mode(tileId, TileSet.SINGLE_TILE)
	tileset.tile_set_texture(tileId, texture)
	tileset.tile_set_region(tileId, region)

func _on_SelectDir_pressed():
	outputDirDialog.popup_centered()


func _on_Import_pressed():
	ldtkImportDialog.popup_centered()


func _on_OutputDir_dir_selected(dir):
	outputDir = dir
	outputDirTxt.text = outputDir
	outputDirDialog.current_dir = outputDir


func _on_LDtkFileImport_file_selected(path):
	var ldtkFile = File.new()
	ldtkFile.open(path, File.READ)
	var parsedLDtk = JSON.parse(ldtkFile.get_as_text())
	ldtkFile.close()
	
	if parsedLDtk.error == OK:
		_create_assets(path.get_file().split(".")[0], parsedLDtk.result["defs"], parsedLDtk.result["levels"], path.get_base_dir())