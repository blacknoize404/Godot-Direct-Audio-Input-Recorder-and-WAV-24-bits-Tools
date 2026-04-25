@tool
@icon("res://addons/direct_audio_and_wav_24bits/icons/direct_audio_input_recorder.svg")
class_name DirectAudioInputRecorder
extends Node

## A high-performance audio capture node designed for Godot 4.6+.
##
## This node specifically addresses long-standing engine issues regarding 
## input desynchronization, lag, and audio garbling (see GitHub issues #80173, #76797).
## By utilizing direct low-level access to the audio input buffer (PR #113288),
## it provides a stable alternative to the standard capture bus system.
## It supports 8-bit, 16-bit, and external 24-bit formatting for WAV audio formats, 
## as well as real-time volume monitoring.

# --- Internal Variables ---
var _is_recording: bool = false
var _recording_buffer: PackedVector2Array = PackedVector2Array()
var _last_recording: AudioStreamWAV
var _last_audio_samples: PackedVector2Array = PackedVector2Array()
var _last_peak_volume_db : Vector2 = Vector2(-80, -80)
var _last_rms_volume_db : int = 0

# --- Exported Properties ---

## The audio depth format. 0 is 8-Bits, 1 is 16-Bits.
@export_enum("8 Bits", "16 Bits", "24 Bits") var format: int = 1:
	set(value):
		if value in [0, 1, 2]:
			format = value
		else:
			push_error("Format value must be 0 (8-bit), 1 (16-bit) o 2 (24-bit).")

## The sample rate of the recording (e.g., 44100 Hz).
@export var mix_rate: float = 44100.0

## If true, uses the system's default microphone sample rate instead of the custom mix_rate.
@export var use_input_mix_rate: bool = true

## If true, records in two channels (Left and Right). If false, records in mono.
@export var stereo: bool = true

# --- Signals ---

## Emitted when the microphone starts capturing audio.
signal on_recording_start
## Emitted when the microphone stops capturing audio.
signal on_recording_end
## Emitted every frame with the raw audio data currently captured by the microphone.
signal on_input_frame_captured(last_input_frames: PackedVector2Array, delta: float)

# --- Built-in Node Methods ---
	
func _ready() -> void:
	# Enable the microphone input in the Godot AudioServer
	AudioServer.set_input_device_active(true)

func _process(delta: float) -> void:
	# Fetch the available frames from the microphone buffer
	_last_audio_samples = AudioServer.get_input_frames(AudioServer.get_input_frames_available())
	on_input_frame_captured.emit(_last_audio_samples, delta)
	
	if _is_recording:
		# Store the raw audio data continuously while recording is active
		_recording_buffer.append_array(_last_audio_samples)

# --- Public Interface ---

## Returns true if the node is currently capturing audio to the buffer.
func is_recording() -> bool:
	return _is_recording

## Returns an array of the native formats supported by Godot's AudioStreamWAV.
func available_formats() -> Array[String]:
	return ["8 Bits", "16 Bits", "24 Bits"]
	
## Starts capturing microphone input and clears any previous recordings.
func start_capturing() -> void:
	_last_recording = null
	_recording_buffer.clear()
	_is_recording = true
	on_recording_start.emit()
	
## Stops capturing microphone input and finalizes the buffer.
func stop_capturing() -> void:
	_is_recording = false
	on_recording_end.emit()
	
# --- Formatting Methods ---

## Converts the raw floating-point audio frames into an 8-bit byte array.
func _format_to_8_bits(data: PackedVector2Array) -> PackedByteArray:
	var byte_array = PackedByteArray()
	# Stereo = 2 bytes per frame. Mono = 1 byte per frame.
	var bytes_per_frame = 2 if stereo else 1
	byte_array.resize(data.size() * bytes_per_frame)
	
	var byte_offset = 0
	
	for frame in data:
		# Convert float (-1.0 to 1.0) to 8-bit signed integer (-128 to 127).
		# We use clampf to prevent integer overflow if the mic peaks above 1.0.
		var left_sample: int = int(clampf(frame.x, -1.0, 1.0) * 0x7f)
		byte_array.encode_s8(byte_offset, left_sample)
		byte_offset += 1
		
		# Right Channel (only if stereo is enabled)
		if stereo:
			var right_sample: int = int(clampf(frame.y, -1.0, 1.0) * 0x7f)
			byte_array.encode_s8(byte_offset, right_sample)
			byte_offset += 1
	
	return byte_array

## Converts the raw floating-point audio frames into a 16-bit byte array.
func _format_to_16_bits(data: PackedVector2Array) -> PackedByteArray:
	var byte_array = PackedByteArray()
	# Stereo = 4 bytes per frame (2+2). Mono = 2 bytes per frame.
	var bytes_per_frame = 4 if stereo else 2
	byte_array.resize(data.size() * bytes_per_frame)
	
	var byte_offset = 0
	
	for frame in data:
		# Convert float (-1.0 to 1.0) to 16-bit signed integer (-32768 to 32767).
		var left_sample: int = int(clampf(frame.x, -1.0, 1.0) * 0x7fff)
		byte_array.encode_s16(byte_offset, left_sample)
		byte_offset += 2
		
		# Right Channel (only if stereo is enabled)
		if stereo:
			var right_sample: int = int(clampf(frame.y, -1.0, 1.0) * 0x7fff)
			byte_array.encode_s16(byte_offset, right_sample)
			byte_offset += 2
	
	return byte_array

# --- Resource Generation ---

## Generates and returns a standard Godot AudioStreamWAV resource from the recorded buffer.
func get_recording() -> AudioStreamWAV:
	if _last_recording != null:
		return _last_recording
	
	var wav_audio = AudioStreamWAV.new()
	
	# Configure the resource properties
	wav_audio.format = AudioStreamWAV.FORMAT_16_BITS if format == 1 else AudioStreamWAV.FORMAT_8_BITS
	wav_audio.mix_rate = int(AudioServer.get_input_mix_rate()) if use_input_mix_rate else int(mix_rate)
	wav_audio.stereo = stereo
	
	# Process the bytes based on the selected format
	var byte_array: PackedByteArray
	if format == 0:
		byte_array = _format_to_8_bits(_recording_buffer)
	elif format == 1:
		byte_array = _format_to_16_bits(_recording_buffer)
	else:
		push_error("Use get_recording_as_wav24b method to export as 24 bits")
	
	wav_audio.data = byte_array
	_last_recording = wav_audio
	
	return wav_audio

## Generates and returns a custom 24-bit AudioStreamWAV24B resource.
func get_recording_as_wav24b() -> AudioStreamWAV24B:
	var target_mix_rate = int(AudioServer.get_input_mix_rate() if use_input_mix_rate else mix_rate)
	return AudioStreamWAV24B.load_from_buffer(_recording_buffer, target_mix_rate, stereo)

## Takes an existing stereo AudioStreamWAV and returns a new mono version of it.
func convert_to_mono(original_stream: AudioStreamWAV) -> AudioStreamWAV:
	if not original_stream.stereo:
		return original_stream # Already mono

	var stereo_data: PackedByteArray = original_stream.data
	var mono_data: PackedByteArray = PackedByteArray()
	
	# Determine byte size based on the audio format (1 byte for 8-bit, 2 for 16-bit)
	var bytes_per_sample: int = 2 if original_stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var frame_size: int = bytes_per_sample * 2 # Left + Right
	
	# Extract only the left channel from the raw data
	for i in range(0, stereo_data.size(), frame_size):
		for byte_index in range(bytes_per_sample):
			if i + byte_index < stereo_data.size():
				mono_data.append(stereo_data[i + byte_index])
	
	var mono_stream = AudioStreamWAV.new()
	mono_stream.format = original_stream.format
	mono_stream.mix_rate = original_stream.mix_rate
	mono_stream.stereo = false
	mono_stream.data = mono_data
	
	return mono_stream

# --- Volume Monitoring ---

## Calculates the linear volume (0.0 to 1.0) using Root Mean Square (RMS).
func _get_input_volume_rms(frames: PackedVector2Array) -> float:
	if frames.is_empty():
		return _last_rms_volume_db
		
	var sum_of_squares: float = 0.0
	
	for frame in frames:
		# Square both channels (Left and Right)
		sum_of_squares += frame.x * frame.x
		sum_of_squares += frame.y * frame.y
		
	# Calculate the mean (average). 
	# We multiply frames.size() by 2 because each frame has 2 channels.
	var mean_square: float = sum_of_squares / (frames.size() * 2)
	
	# Return the square root of the mean
	_last_rms_volume_db = sqrt(mean_square)
	
	return _last_rms_volume_db

## Returns the current average input volume in linear scale (0.0 to 1.0).
func get_input_volume_lineal() -> float:
	return _get_input_volume_rms(_last_audio_samples)

## Returns the current average input volume in Decibels (dB).
func get_input_volume_db() -> float:
	var linear_vol = _get_input_volume_rms(_last_audio_samples)
	return linear_to_db(linear_vol)

## Internal helper to calculate peak volume in Decibels. Returns Vector2(Left dB, Right dB).
func _get_peak_volume_db(frames: PackedVector2Array) -> Vector2:
	if frames.is_empty():
		return _last_peak_volume_db
		
	var peak_left: float = 0.0
	var peak_right: float = 0.0
	
	for frame in frames:
		# Extract the absolute amplitude value using absf()
		var abs_l: float = absf(frame.x)
		var abs_r: float = absf(frame.y)
		
		# Update the peak if this frame is louder than our recorded peak
		if abs_l > peak_left:
			peak_left = abs_l
		if abs_r > peak_right:
			peak_right = abs_r
			
	# Convert linear peaks to Decibels
	var db_left: float = linear_to_db(peak_left)
	var db_right: float = linear_to_db(peak_right)
	
	_last_peak_volume_db = Vector2(db_left, db_right)
	
	return _last_peak_volume_db

## Returns the peak volume of the current frame in Decibels as a Vector2 (X = Left, Y = Right).
func get_peak_volume_db() -> Vector2:
	return _get_peak_volume_db(_last_audio_samples)
