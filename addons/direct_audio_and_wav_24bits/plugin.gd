@tool
extends EditorPlugin

# Definimos las rutas a los scripts
const RecorderScript = preload("res://addons/wav_24bit_tools/scripts/DirectAudioInputRecorder.gd")
const WAV24Script = preload("res://addons/wav_24bit_tools/scripts/AudioStreamWAV24B.gd")

func _enter_tree() -> void:
	# Registramos el Nodo de grabación con un icono
	add_custom_type(
		"DirectAudioInputRecorder", 
		"Node", 
		RecorderScript, 
		preload("res://addons/wav_24bit_tools/icons/recorder_icon.svg")
	)
	print("WAV 24-Bit Tools: Nodo y Recurso cargados correctamente.")

func _exit_tree() -> void:
	# Limpiamos al desactivar el plugin
	remove_custom_type("DirectAudioInputRecorder")
