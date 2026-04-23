@tool
extends EditorPlugin

## Plugin script for High-Fidelity Audio Recording and WAV 24-Bit Tools.
## Registers custom nodes for direct audio input capture and 24-bit streaming playback.

# --- Constants: Script Paths ---
const RECORDER_SCRIPT = preload("res://addons/direct_audio_and_wav_24bits/scripts/direct_audio_input_recorder.gd")
const PLAYER_SCRIPT   = preload("res://addons/direct_audio_and_wav_24bits/scripts/audio_stream_player_wav_24b.gd")

# --- Constants: Icon Paths ---
# Note: Ensure these files exist in your icons folder or update the paths accordingly.
const RECORDER_ICON = preload("res://addons/direct_audio_and_wav_24bits/icons/direct_audio_input_recorder.svg")
#const PLAYER_ICON   = preload("res://addons/direct_audio_and_wav_24bits/icons/audio_stream_player_wav24b.svg")

## Called when the plugin is enabled.
func _enter_tree() -> void:
	# Register the DirectAudioInputRecorder Node
	# This allows it to appear in the "Create New Node" dialog under the "Node" category.
	add_custom_type(
		"DirectAudioInputRecorder", 
		"Node", 
		RECORDER_SCRIPT, 
		RECORDER_ICON
	)
	
	# Register the AudioStreamPlayerWav24B Node
	# This allows it to appear under the "AudioStreamPlayer" category.
	add_custom_type(
		"AudioStreamPlayerWav24B", 
		"AudioStreamPlayer", 
		PLAYER_SCRIPT, 
		null
	)
	
	print("High-Fidelity Audio Recording and WAV 24-Bit Tools: Plugin initialized successfully. Low-level audio buffer access enabled.")

## Called when the plugin is disabled or the editor is closed.
func _exit_tree() -> void:
	# Always clean up custom types to prevent ghost nodes or editor crashes.
	remove_custom_type("DirectAudioInputRecorder")
	remove_custom_type("AudioStreamPlayerWav24B")
	
	print("High-Fidelity Audio Recording and WAV 24-Bit Tools: Plugin disabled and custom types removed.")

## Returns the human-readable name of the plugin for the editor.
func _get_plugin_name() -> String:
	return "High-Fidelity Audio Recording and WAV 24-Bit Tools"
