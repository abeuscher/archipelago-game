## Loads a picture so it works both from the project folder and in an
## exported game. An export holds only Godot's imported copies (the raw PNG
## or JPG isn't packed), so the resource loader comes first. A checkout that
## has never been opened in the editor has no imported copies, so it falls
## back to reading the file itself. Missing pictures are reported once.
extends RefCounted


static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	push_warning("Picture not found: " + path)
	return null
