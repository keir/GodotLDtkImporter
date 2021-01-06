tool
extends EditorImportPlugin

func get_importer_name():
	return "ldtk.mapimporter"

func get_visible_name():
	return "LDtk Map"
	
func get_recognized_extensions():
	return ["ldtk"]
	
func get_save_extension():
	return "tscn"
	
func get_resource_type():
	return "Scenes"
	
func get_import_options(preset):
	return []
	
func import(source_file, save_path, options, platform_variants, gen_files):
	# The import script does some local caching, so always create a new instance.
	var status = preload("ImportEngine.gd").new().run_import(
		source_file, save_path, get_save_extension(), gen_files)
	return status
