extends RefCounted
## Imported 32px action sheets with cached, region-aware kingdom recoloring.
const SHEETS = [null,preload("res://assets/units/scout.png"),preload("res://assets/units/warrior.png"),preload("res://assets/units/knight.png")]
const NORMAL_SHEETS = [null,preload("res://assets/units/scout_normal2.png"),preload("res://assets/units/warrior_n.png"),preload("res://assets/units/knight_n.png")]
const CLOTH_LIGHT := 0x6098e8
const CLOTH_DARK := 0x4058c0
const SCOUT_SLEEVE := 0x5a7b94
const HORSE_TAIL := 0x373757
# These colors are also used by helmets and tack. Restrict the extra masks to
# their locations within each 32px pose, including jumping and collapsed poses.
const SCOUT_SLEEVE_REGIONS := [Rect2i(0,24,32,8), Rect2i(18,23,14,1)]
const HORSE_TAIL_REGION := Rect2i(0,0,12,32)
# Keep every source pixel the same world size across infantry and mounted units.
const PIXEL_SIZE := 0.08
const FOOT_CLIPS := {"idle":[0,4,8.0],"run":[1,6,10.0],"jump":[2,3,10.0],"attack":[3,7,12.0],"hurt":[4,3,12.0],"death":[5,5,10.0]}
const WARRIOR_CLIPS := {
	"idle":[0,4,8.0], "run":[1,6,10.0], "jump":[2,3,10.0],
	"attack":[3,6,12.0], "thrust":[4,6,12.0],
	"hurt":[5,3,12.0], "death":[6,4,10.0],
}
const RIDER_CLIPS := {"idle":[0,8,8.0],"run":[1,6,10.0],"charge":[2,6,12.0],"jump":[3,3,10.0],"attack":[4,7,12.0],"hurt":[5,2,12.0],"death":[6,6,10.0]}
const CLIPS := [{}, FOOT_CLIPS, WARRIOR_CLIPS, RIDER_CLIPS]
var profile_frames := false
var frame_samples: Array = []
var sources: Dictionary = {}
var masks: Dictionary = {}
var sheets: Dictionary = {}
var frames: Dictionary = {}
var portraits: Dictionary = {}

static func clip(tier: int, name: String) -> Array:
	return CLIPS[tier].get(name, CLIPS[tier].idle).duplicate()

static func pixel_size(_tier: int) -> float:
	return PIXEL_SIZE

static func height(tier: int) -> float:
	return ((32.0 if tier == 3 else 20.0)*0.5-1.5)*pixel_size(tier)+0.06

static func duration(tier: int, name: String) -> float:
	var sequence := clip(tier,name)
	return float(sequence[1])/sequence[2]

static func impact_time(tier: int) -> float:
	return (2.0 if tier == 2 else 3.0)/12.0

func sheet(tier: int, color: Color) -> Image:
	var key := "%d:%s" % [tier,color.to_html()]
	if sheets.has(key): return sheets[key]
	if not sources.has(tier):
		var image: Image = SHEETS[tier].get_image()
		image.convert(Image.FORMAT_RGBA8)
		var bytes := image.get_data()
		var light := PackedInt32Array()
		var dark := PackedInt32Array()
		var sleeve := PackedInt32Array()
		var tail := PackedInt32Array()
		for offset in range(0,bytes.size(),4):
			var rgb: int = (bytes[offset] << 16) | (bytes[offset+1] << 8) | bytes[offset+2]
			if rgb == CLOTH_LIGHT:
				light.append(offset)
			elif rgb == CLOTH_DARK:
				dark.append(offset)
			elif tier == 1 and rgb == SCOUT_SLEEVE:
				var pixel := Vector2i((offset/4) % image.get_width(), (offset/4) / image.get_width()) % 32
				for region in SCOUT_SLEEVE_REGIONS:
					if region.has_point(pixel):
						sleeve.append(offset)
						break
			elif tier == 3 and rgb == HORSE_TAIL:
				var pixel := Vector2i((offset/4) % image.get_width(), (offset/4) / image.get_width()) % 32
				if HORSE_TAIL_REGION.has_point(pixel): tail.append(offset)
		sources[tier] = image
		masks[tier] = [light,dark,sleeve,tail]
	var original: Image = sources[tier]
	var bytes := original.get_data()
	var colors := [color.lightened(0.12),color.darkened(0.28),color.darkened(0.42),color.darkened(0.12)]
	for channel in range(colors.size()):
		var replacement: Color = colors[channel]
		for offset in masks[tier][channel]:
			bytes[offset] = replacement.r8
			bytes[offset+1] = replacement.g8
			bytes[offset+2] = replacement.b8
	var image := Image.create_from_data(original.get_width(),original.get_height(),false,Image.FORMAT_RGBA8,bytes)
	sheets[key] = image
	return image

func frame(tier: int, color: Color, animation := "idle", index := 0) -> Dictionary:
	var sequence := clip(tier,animation)
	index = clampi(index,0,int(sequence[1])-1)
	var key := "%d:%s:%s:%d" % [tier,color.to_html(),animation,index]
	if frames.has(key): return frames[key]
	var started := Time.get_ticks_usec() if profile_frames else 0
	# The foot troops have 12 empty pixels above every pose. Crop consistently,
	# keeping weapon reach and the same foot anchor throughout each animation.
	var crop := Rect2i(index*32,int(sequence[0])*32+(0 if tier == 3 else 12),32,32 if tier == 3 else 20)
	var image := sheet(tier,color).get_region(crop)
	var result := {"image":image,"texture":ImageTexture.create_from_image(image)}
	result.texture.set_meta("normal_texture", NORMAL_SHEETS[tier])
	result.texture.set_meta("normal_region", Rect2(Vector2(crop.position) / Vector2(SHEETS[tier].get_size()), Vector2(crop.size) / Vector2(SHEETS[tier].get_size())))
	frames[key] = result
	if profile_frames: frame_samples.append({"frame":Engine.get_process_frames(),"key":key,"ms":(Time.get_ticks_usec()-started)/1000.0})
	return result

func portrait(tier: int, color: Color) -> Texture2D:
	var key := "%d:%s" % [tier,color.to_html()]
	if not portraits.has(key):
		var image: Image = frame(tier,color).image
		portraits[key] = ImageTexture.create_from_image(image.get_region(image.get_used_rect()))
	return portraits[key]
