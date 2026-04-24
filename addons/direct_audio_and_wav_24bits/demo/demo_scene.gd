extends Control

## Example scene demonstrating the 24-bit high-fidelity recording workflow.
## This script handles UI updates, recording states, and file management.

# --- Constants ---
const ANDROID_RECORDINGS_SUBDIR = "recordings"

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

	_initialize_platform_permissions()
	_setup_ui_initial_state()
	_populate_format_options()
	_load_devices()
	
func _process(delta: float) -> void:
	_update_volume_meter_logic(delta)
	
func _initialize_platform_permissions() -> void:
	if OS.get_name() == "Android":
		# Requesting multiple permissions often needed for audio/storage
		OS.request_permissions()
	
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
			input_devices_option.select(input_devices_option.item_count - 1)
			
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

# --- Logic & Processing ---

func _update_volume_meter_logic(delta: float) -> void:
	var peak_db: float = recorder.get_peak_volume_db().x
	var energy := db_to_linear(peak_db)
	var current_val := volume_progress_bar.value
	
	# Smooth fall-off for the meter visualization
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
	_toggle_playback_controls(true)

func _on_recorder_on_recording_end() -> void:
	start_and_stop_button.text = "Record"
	start_and_stop_button.modulate = Color.WHITE
	
	# Cache recorded resources
	_last_recorded_resource24b = recorder.get_recording_as_wav24b()
	_last_recorded_resource = recorder.get_recording()
	
	_toggle_playback_controls(false)

func _toggle_playback_controls(is_recording: bool) -> void:
	play_stop_button.disabled = is_recording
	save_button.disabled = is_recording

# --- Signal Callbacks: Playback ---

# --- Signal Callbacks: Playback ---

func _on_play_stop_button_pressed() -> void:
	if not _is_playing:
		_start_playback()
	else:
		_stop_playback()

func _start_playback() -> void:
	if _last_recorded_resource24b:
		player_24bit.play_24bit(_last_recorded_resource24b)
		play_stop_button.text = "Stop Playback"
		_is_playing = true

func _stop_playback() -> void:
	player_24bit.stop()
	play_stop_button.text = "Play 24-bit"
	_is_playing = false

func _on_player_24bit_finished() -> void:
	_stop_playback()

# --- File Management & Android Workaround ---

func _on_save_button_pressed() -> void:
	if not _last_recorded_resource:
		push_warning("No recording available to save.")
		return
	
	var file_name := "rec_%s.wav" % _generate_short_id()
	var temp_path := "user://" + file_name
	var save_error: Error
	
	# 1. High-speed internal save (Direct IO)
	if recorder.format == 2: # 24-bit format index
		save_error = _last_recorded_resource24b.save_to_wav(temp_path)
	else:
		save_error = _last_recorded_resource.save_to_wav(temp_path)
	
	if save_error != OK:
		push_error("Failed to save temporary file. Error: ", save_error)
		return

	# 2. Android Scoped Storage Workaround
	if OS.get_name() == "Android":
		_export_to_android_documents(temp_path, file_name)
	else:
		print("File saved to user data: ", ProjectSettings.globalize_path(temp_path))

# Moves a file from internal storage to the public Documents folder on Android.
func _export_to_android_documents(source_path: String, file_name: String) -> void:
	var docs_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join(ANDROID_RECORDINGS_SUBDIR)
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute(docs_dir):
		DirAccess.make_dir_recursive_absolute(docs_dir)
	
	var destination_path := docs_dir.path_join(file_name)
	var dir := DirAccess.open("user://")
	
	if dir and dir.copy(source_path, destination_path) == OK:
		print("Successfully exported to Documents: ", destination_path)
		dir.remove(source_path) # Clean up temp file
	else:
		push_error("Android Export Failed. Path: ", destination_path)

func _on_option_button_item_selected(index: int) -> void:
	recorder.format = index

# --- Helpers ---

## Generates a short random ID using crypto-safe bytes.
func _generate_short_id() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(4).hex_encode()

func _on_input_devices_option_item_selected(index: int) -> void:
	AudioServer.input_device = input_devices_option.get_item_text(index)

func _on_output_devices_option_item_selected(index: int) -> void:
	AudioServer.output_device = output_devices_option.get_item_text(index)
