extends Control

# El nodo que creamos en el plugin
@onready var recorder: DirectAudioInputRecorder = $DirectAudioInputRecorder
@onready var player: AudioStreamPlayer = $AudioStreamPlayer

var last_recorded_wav: AudioStreamWAV24B

func _ready():
	# Configuración inicial
	recorder.stereo = true
	print("Grabador listo. Modo estéreo: ", recorder.stereo)

# 1. Iniciar la grabación
func _on_record_pressed():
	recorder.start_recording()
	print("Grabando...")

# 2. Detener y generar el recurso de 24 bits
func _on_stop_pressed():
	recorder.stop_recording()
	
	# Obtenemos el recurso de 24 bits que creamos en el plugin
	last_recorded_wav = recorder.get_recording_as_wav24b()
	
	if last_recorded_wav:
		print("Grabación finalizada. Duración: ", last_recorded_wav._get_length(), "s")
		
		# Guardamos a disco de forma permanente
		var save_path = "user://test_24bit.wav"
		var error = last_recorded_wav.save_to_wav(save_path)
		
		if error == OK:
			print("Archivo guardado con éxito en: ", ProjectSettings.globalize_path(save_path))

# 3. Reproducir el audio de alta fidelidad
func _on_play_pressed():
	if last_recorded_wav:
		# Para reproducir, usamos el método que convierte 24bit -> Floats
		# que el AudioStreamGenerator puede entender.
		var generator = AudioStreamGenerator.new()
		generator.mix_rate = last_recorded_wav.mix_rate
		
		player.stream = generator
		player.play()
		
		var playback = player.get_stream_playback()
		var frames = last_recorded_wav.get_as_frames()
		
		# Llenamos el buffer del reproductor
		playback.push_buffer(frames)
		print("Reproduciendo 24-bit audio...")
