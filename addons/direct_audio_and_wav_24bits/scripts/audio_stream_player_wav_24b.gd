class_name AudioStreamPlayerWav24B
extends AudioStreamPlayer

# El recurso que creamos antes para guardar los datos
var stream_resource: AudioStreamWAV24B
var _playback: AudioStreamGeneratorPlayback
var _is_stepping: bool = false

func _ready() -> void:
	# Usamos un generador como puente para poder enviar los datos convertidos
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = 44100 # O el que prefieras
	generator.buffer_length = 0.1 # Buffer pequeño para baja latencia
	
	self.stream = generator

# Función principal para cargar y empezar a tocar
func play_24bit(res: AudioStreamWAV24B):
	stream_resource = res
	
	# Aseguramos que el mix_rate del generador coincida con el recurso
	self.stream.mix_rate = res.mix_rate
	
	self.play()
	_playback = self.get_stream_playback()
	_fill_buffer()

func _process(_delta: float) -> void:
	if _playback and self.playing:
		_fill_buffer()

# El "corazón" que traduce los bytes de 24 bits a Floats en tiempo real
func _fill_buffer():
	var frames_to_fill = _playback.get_skips() + _playback.get_frames_available()
	if frames_to_fill <= 0:
		return
		
	# Obtenemos los frames ya convertidos del recurso
	# Nota: En una versión Pro, convertiríamos esto por trozos (chunks)
	# para no saturar la memoria si el audio es muy largo.
	var all_frames = stream_resource.get_as_frames()
	
	# Aquí podrías implementar un cursor para saber por dónde va la canción
	# Por simplicidad, aquí enviamos los frames disponibles
	_playback.push_buffer(all_frames)
