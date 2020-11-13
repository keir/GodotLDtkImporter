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
		var ldtkTileset = LDtkTileset.new()
		ldtkTileset.uid = tilesetData["uid"]
		ldtkTileset.name = tilesetData["identifier"]
		ldtkTileset.grid_size = tilesetData["tileGridSize"]
		ldtkTileset.texture = load(ldtkHomeDirectory.plus_file(tilesetData["relPath"]))
		ldtkTileset.path = tilesetDirPath.plus_file(tilesetData["identifier"]+".tres")
		
		if ResourceLoader.exists(ldtkTileset.path):
			ldtkTileset.tileset = ResourceLoader.load(ldtkTileset.path)
		else:
			ldtkTileset.tileset = TileSet.new()
			ResourceSaver.save(ldtkTileset.path, ldtkTileset.tileset)
		
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
		var rootNode = Node2D.new()
		rootNode.name = level["identifier"]
		
		for layer in level["layerInstances"]:
			var layerNode = _create_layer(layer, layersDef, tilesets)
			if layerNode:
				rootNode.add_child(layerNode, true)
				layerNode.owner = rootNode
			
		if rootNode.get_child_count() > 0:
			var scene = PackedScene.new()
			scene.pack(rootNode)
			
			var outputFile = outputDir.plus_file(rootNode.name+".tscn")
			ResourceSaver.save(outputFile, scene)
		
	# Save changes to the tilesets
	for tileset in tilesets.values():
		ResourceSaver.save(tileset.path, tileset.tileset)
	
func _create_layer(layer, layersDef, tilesets):
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
	
	var tilemap = TileMap.new()
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