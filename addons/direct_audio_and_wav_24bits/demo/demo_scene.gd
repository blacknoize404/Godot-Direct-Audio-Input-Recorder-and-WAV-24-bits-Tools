extends Control

## Example scene demonstrating the 24-bit high-fidelity recording workflow.
## This script handles UI updates, recording states, and file management.

# --- UI References ---
@onready var start_and_stop_button: Button = %StartAndStopButton
@onready var play_stop_button: Button = %PlayStopButton
@onready var save_button: Button = %SaveButton
@onready var format_option_button: OptionButton = %OptionButton
@onready var volume_progress_bar: ProgressBar = %ProgressBar
@onready var input_hz_label: Label = %InputHz
@onready var output_hz_label: Label = %OutputHz
@onready var input_devices_option: OptionButton = %InputDevicesOption
@onready var output_devices_option: OptionButton = %OutputDevicesOption


# --- Audio References ---
@onready var recorder: DirectAudioInputRecorder = $DirectAudioInputRecorder
@onready var player_24bit: AudioStreamPlayerWav24B = $AudioStreamPlayerWav24B

# --- Settings ---
@export var meter_smooth_speed: float = 20.0

# --- Internal State ---
var _is_playing: bool = false
var _last_recorded_resource24b: AudioStreamWAV24B
var _last_recorded_resource: AudioStreamWAV

# --- Initialization ---

func _ready() -> void:

	if OS.get_name() == "Android":
		OS.request_permissions()
		
	_setup_ui_initial_state()
	_populate_format_options()
	_load_devices()
	
func _setup_ui_initial_state() -> void:
	input_hz_label.text = str(AudioServer.get_input_mix_rate())
	output_hz_label.text = str(AudioServer.get_mix_rate())
	play_stop_button.disabled = true
	save_button.disabled = true
	
func _load_devices():
	input_devices_option.clear()
	for device in AudioServer.get_input_device_list():
		input_devices_option.add_item(device)
		if AudioServer.input_device == device:
			input_devices_option.select(output_devices_option.item_count - 1)
			
	output_devices_option.clear()
	for device in AudioServer.get_output_device_list():
		output_devices_option.add_item(device)
		if AudioServer.output_device == device:
			output_devices_option.select(output_devices_option.item_count - 1)

func _populate_format_options() -> void:
	format_option_button.clear()
	for format_name in recorder.available_formats():
		format_option_button.add_item(format_name)
	
	format_option_button.selected = recorder.format

# --- Main Loop ---

func _process(delta: float) -> void:
	# Update the peak meter in real-time
	var peak_db = recorder.get_peak_volume_db().x
	_update_volume_meter(peak_db, delta)

# --- UI Logic ---

func _update_volume_meter(peak_db: float, delta: float) -> void:
	var energy = db_to_linear(peak_db)
	var current_val = volume_progress_bar.value
	
	# Instant rise, smooth fall (classic peak meter behavior)
	#if energy > current_val:
		#volume_progress_bar.value = energy
	#else:
	volume_progress_bar.value = lerp(current_val, energy, meter_smooth_speed * delta)

# --- Signal Callbacks: Recorder ---

func _on_start_and_stop_button_pressed() -> void:
	if not recorder.is_recording():
		recorder.start_capturing()
	else:
		recorder.stop_capturing()

func _on_recorder_on_recording_start() -> void:
	start_and_stop_button.text = "Stop Recording"
	start_and_stop_button.modulate = Color.RED
	play_stop_button.disabled = true
	save_button.disabled = true

func _on_recorder_on_recording_end() -> void:
	start_and_stop_button.text = "Record"
	start_and_stop_button.modulate = Color.WHITE
	
	# Generate the 24-bit resource immediately after recording
	_last_recorded_resource24b = recorder.get_recording_as_wav24b()
	_last_recorded_resource = recorder.get_recording()
	
	play_stop_button.disabled = false
	save_button.disabled = false

# --- Signal Callbacks: Playback ---

func _on_play_stop_button_pressed() -> void:
	if not _is_playing:
		_start_playback()
	else:
		_stop_playback()

func _start_playback() -> void:
	if _last_recorded_resource:
		player_24bit.play_24bit(_last_recorded_resource24b)
		play_stop_button.text = "Stop Playback"
		_is_playing = true

func _stop_playback() -> void:
	player_24bit.stop()
	play_stop_button.text = "Play 24-bit"
	_is_playing = false

func _on_player_24bit_finished() -> void:
	_stop_playback()

# --- Signal Callbacks: File Management ---

func _on_save_button_pressed() -> void:
	if not _last_recorded_resource:
		return
	
	var file_name = "recording_%s.wav" % _generate_uuid().substr(0, 8)
	
	var file_path = "user://" + file_name
	
	if OS.get_name() == "Android":
		file_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS) + "/recordings/" + file_name
	
	var error
	
	if (recorder.format == 2):
		error = _last_recorded_resource24b.save_to_wav(file_path)
	else:
		error = _last_recorded_resource.save_to_wav(file_path)
	
	if error == OK:
		print("Success: %s audio saved at: " % recorder.available_formats()[recorder.format], ProjectSettings.globalize_path(file_path))
	else:
		push_error("Failed to save audio. Error code: ", error)

func _on_option_button_item_selected(index: int) -> void:
	recorder.format = index

# --- Helpers ---

## Generates a unique identifier for file naming.
func _generate_uuid() -> String:
	var crypto = Crypto.new()
	var b = crypto.generate_random_bytes(16)
	
	# UUID v4 specific bit manipulation
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	
	var hex = b.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), 
		hex.substr(12, 4), hex.substr(16, 4), 
		hex.substr(20, 12)
	]

func _on_input_devices_option_item_selected(index: int) -> void:
	var s = input_devices_option.get_item_text(index)
	AudioServer.input_device = s
	

func _on_output_devices_option_item_selected(index: int) -> void:
	var e = output_devices_option.get_item_text(index)
	AudioServer.output_device = e
