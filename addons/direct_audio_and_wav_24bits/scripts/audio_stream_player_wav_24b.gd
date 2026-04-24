@tool
class_name AudioStreamPlayerWav24B
extends AudioStreamPlayer

## A specialized player for 24-bit WAV audio resources.
## It uses an AudioStreamGenerator to stream and decode 24-bit data in real-time
## chunks, ensuring high performance and low memory usage.

# --- Properties ---

## The 24-bit resource to be played.
var stream_resource: AudioStreamWAV24B

# --- Internal State ---
var _playback: AudioStreamGeneratorPlayback
var _current_frame_index: int = 0
var _is_initialized: bool = false
var _was_pushed_completely: bool = false

# --- Built-in Node Methods ---

func _ready() -> void:
	_setup_generator()

func _process(_delta: float) -> void:
	if _playback and playing:
		_fill_buffer()

# --- Public Interface ---

## Loads a 24-bit resource and begins playback from the start.
func play_24bit(res: AudioStreamWAV24B) -> void:
	if res == null or res.data.is_empty():
		push_error("AudioStreamPlayerWav24B: Cannot play an empty or null resource.")
		return
		
	stream_resource = res
	_current_frame_index = 0
	_was_pushed_completely = false # Resetear estado
	
	# Ensure the generator's mix rate matches the resource
	if stream.mix_rate != res.mix_rate:
		stream.mix_rate = res.mix_rate
	
	self.play()
	_playback = get_stream_playback()
	
	# Initial buffer fill to prevent immediate underrun
	_fill_buffer()

## Resets the playback cursor to the beginning.
func seek_start() -> void:
	_current_frame_index = 0
	_was_pushed_completely = false

# --- Internal Methods ---

## Initializes the AudioStreamGenerator which acts as a bridge for the raw data.
func _setup_generator() -> void:
	var generator = AudioStreamGenerator.new()
	
	generator.mix_rate = 44100 # Default, will be updated on play
	generator.buffer_length = 0.1 # 100ms buffer for low latency
	
	self.stream = generator
	_is_initialized = true

## The streaming engine. Decodes and pushes only the required chunks of audio.
func _fill_buffer() -> void:
	if not _playback or not stream_resource:
		return

	# Determine how much space is available in the generator's buffer
	var frames_available = _playback.get_frames_available()
	if frames_available <= 0:
		return

	# Calculate how many frames are left in the actual audio data
	var total_resource_frames = stream_resource.data.size() / (6 if stream_resource.stereo else 3)

	# 1. ¿Ya enviamos todo al buffer?
	if _current_frame_index >= total_resource_frames:
		_was_pushed_completely = true
		
		# 2. Esperar a que el buffer del AudioServer se vacíe
		# Si los frames disponibles son iguales al tamaño total del buffer, es que ya no hay nada sonando
		var buffer_capacity = stream.buffer_length * stream.mix_rate
		if frames_available >= buffer_capacity - 1: # -1 por margen de error de redondeo
			_finalize_playback()
		return
		
	if frames_available <= 0:
		return
	
	var frames_to_process = min(frames_available, total_resource_frames - _current_frame_index)

	if frames_to_process <= 0:
		if _current_frame_index >= total_resource_frames:
			# End of file reached
			stop()
		return
		
	# --- DECODING LOOP ---
	# Create a temporary buffer for the chunk
	var chunk = PackedVector2Array()
	chunk.resize(frames_to_process)
	
	var data_bytes = stream_resource.data
	var is_stereo = stream_resource.stereo
	var bytes_per_frame = 6 if is_stereo else 3

	# --- REAL-TIME DECODING LOOP ---
	# We decode only the frames needed for this specific buffer update
	for i in range(frames_to_process):
		var byte_idx = (_current_frame_index + i) * bytes_per_frame
		
		# Decode Left/Mono (3 bytes -> Signed 64-bit Int -> Float)
		var l_int = data_bytes[byte_idx] | (data_bytes[byte_idx+1] << 8) | (data_bytes[byte_idx+2] << 16)
		l_int = (l_int << 40) >> 40 # Sign extension
		var left_float = float(l_int) / 0x7FFFFF
		
		var right_float = left_float
		if is_stereo:
			# Decode Right
			var r_idx = byte_idx + 3
			var r_int = data_bytes[r_idx] | (data_bytes[r_idx+1] << 8) | (data_bytes[r_idx+2] << 16)
			r_int = (r_int << 40) >> 40
			right_float = float(r_int) / 0x7FFFFF
			
		chunk[i] = Vector2(left_float, right_float)

	# Push the decoded chunk to the AudioServer
	_playback.push_buffer(chunk)
	_current_frame_index += frames_to_process
	
func _finalize_playback() -> void:
	stop()
	_current_frame_index = 0
	_was_pushed_completely = false
	finished.emit()
