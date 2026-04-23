@tool
class_name AudioStreamWAV24B
extends Resource

## A custom resource for handling 24-bit WAV audio data.
## Godot does not natively support 24-bit PCM in AudioStreamWAV, so this class
## manages the byte-level encoding, decoding, and RIFF file structure.

# --- Properties ---

## Raw audio data stored as 24-bit bytes (3 bytes per sample).
@export var data: PackedByteArray = PackedByteArray()

## The sample rate (e.g., 44100, 48000).
@export var mix_rate: int = 44100

## If true, the data contains two channels (Left and Right).
@export var stereo: bool = true

# --- Initialization and Factory ---

func _init(audio_samples: PackedVector2Array = PackedVector2Array(), sample_rate: int = 44100, is_stereo: bool = true) -> void:
	## Note: Default values allow the resource to be instantiated by the editor without errors.
	self.mix_rate = sample_rate
	self.stereo = is_stereo
	if not audio_samples.is_empty():
		self.data = _format_to_24_bits(audio_samples)

## Static factory method to create a new 24-bit resource from a buffer of floating-point frames.
static func load_from_buffer(audio_samples: PackedVector2Array, sample_rate: int, is_stereo: bool) -> AudioStreamWAV24B:
	return AudioStreamWAV24B.new(audio_samples, sample_rate, is_stereo)
	
# --- Metadata ---

## Returns the total duration of the audio in seconds.
func get_length() -> float:
	var bytes_per_frame: int = 6 if stereo else 3
	if bytes_per_frame == 0 or data.is_empty():
		return 0.0
	return float(data.size() / bytes_per_frame) / float(mix_rate)

# --- Encoding (Writing Data) ---

## Converts floating-point frames into a 24-bit byte array.
func _format_to_24_bits(frames: PackedVector2Array) -> PackedByteArray:
	var byte_array := PackedByteArray()
	var frame_count := frames.size()
	var bytes_per_frame := 6 if stereo else 3
	
	byte_array.resize(frame_count * bytes_per_frame)
	
	var byte_offset := 0
	for i in range(frame_count):
		var frame := frames[i]
		
		# Encode Left Channel (or Mono)
		_encode_24bit(byte_array, byte_offset, frame.x)
		byte_offset += 3
		
		if stereo:
			# Encode Right Channel
			_encode_24bit(byte_array, byte_offset, frame.y)
			byte_offset += 3
	
	return byte_array

## Encodes a single float sample (-1.0 to 1.0) into 3 bytes (Little-Endian).
func _encode_24bit(target: PackedByteArray, pos: int, sample: float) -> void:
	# Scale float to signed 24-bit integer range (-8388608 to 8388607)
	# 0x7FFFFF is the maximum value for a signed 24-bit integer.
	var int_sample := int(clampf(sample, -1.0, 1.0) * 0x7FFFFF)
	
	# Byte 1: Least Significant Byte (LSB)
	target[pos]     = int_sample & 0xFF
	# Byte 2: Middle Byte
	target[pos + 1] = (int_sample >> 8) & 0xFF
	# Byte 3: Most Significant Byte (MSB)
	target[pos + 2] = (int_sample >> 16) & 0xFF
	
# --- Disk I/O (Exporting) ---

## Exports the stored data as a standard .wav file with a valid 24-bit RIFF header.
func save_to_wav(file_path: String) -> Error:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("AudioStreamWAV24B: Could not open file for writing at: " + file_path)
		return FileAccess.get_open_error()
	
	var num_channels: int = 2 if stereo else 1
	var bits_per_sample: int = 24
	var byte_rate: int = mix_rate * num_channels * 3
	var block_align: int = num_channels * 3
	var data_size: int = data.size()
	# RIFF chunk size is total file size - 8 bytes
	var chunk_size: int = 36 + data_size

	# --- RIFF Header ---
	file.store_8(82); file.store_8(73); file.store_8(70); file.store_8(70) # "RIFF"
	file.store_32(chunk_size)
	file.store_8(87); file.store_8(65); file.store_8(86); file.store_8(69) # "WAVE"

	# --- Format Sub-chunk ("fmt ") ---
	file.store_8(102); file.store_8(109); file.store_8(116); file.store_8(32) # "fmt "
	file.store_32(16)              # Sub-chunk size (16 for PCM)
	file.store_16(1)               # Audio format (1 = Linear PCM)
	file.store_16(num_channels)
	file.store_32(mix_rate)
	file.store_32(byte_rate)
	file.store_16(block_align)
	file.store_16(bits_per_sample)

	# --- Data Sub-chunk ("data") ---
	file.store_8(100); file.store_8(97); file.store_8(116); file.store_8(97) # "data"
	file.store_32(data_size)
	
	# Write raw audio bytes
	file.store_buffer(data)
	file.close()
	
	return OK

# --- Reconstruction (Playback Support) ---

## Reconstructs the 24-bit byte data back into floating-point frames for playback.
## This is required because Godot's AudioStreamGenerator expects Vector2(float) frames.
func get_as_frames() -> PackedVector2Array:
	if data.is_empty():
		return PackedVector2Array()
		
	var frames := PackedVector2Array()
	var bytes_per_frame := 6 if stereo else 3
	var total_frames := int(data.size() / bytes_per_frame)
	frames.resize(total_frames)
	
	for i in range(total_frames):
		var byte_idx := i * bytes_per_frame
		
		# --- Left Channel Reconstruction ---
		# Merge 3 bytes into a single integer
		var l_int: int = data[byte_idx] | (data[byte_idx+1] << 8) | (data[byte_idx+2] << 16)
		
		# SIGN EXTENSION:
		# Since 24-bit is signed but GDScript integers are 64-bit, we must propagate
		# the 24th bit (the sign bit) to the 64th bit.
		# We shift left by 40 (64-24) to put the sign bit at the top, then shift back.
		l_int = (l_int << 40) >> 40
		
		var left_float := float(l_int) / 8388607.0
		var right_float := left_float
		
		if stereo:
			# --- Right Channel Reconstruction ---
			var r_idx := byte_idx + 3
			var r_int: int = data[r_idx] | (data[r_idx+1] << 8) | (data[r_idx+2] << 16)
			
			# Apply sign extension
			r_int = (r_int << 40) >> 40
			right_float = float(r_int) / 8388607.0
			
		frames[i] = Vector2(left_float, right_float)
		
	return frames
