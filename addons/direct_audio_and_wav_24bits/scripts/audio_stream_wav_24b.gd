class_name AudioStreamWAV24B
extends Resource

# Propiedades similares a AudioStreamWAV
@export var data: PackedByteArray = PackedByteArray()
@export var mix_rate: int = 44100
@export var stereo: bool = true

func _init(audio_samples: PackedVector2Array, sample_rate: int, is_stereo: bool) -> void:
	mix_rate = sample_rate
	stereo = is_stereo
	data = _format_to_24_bits(audio_samples)
	
# Devuelve la duración del audio en segundos
func _get_length() -> float:
	var bytes_per_frame = 6 if stereo else 3
	if bytes_per_frame == 0 or data.is_empty():
		return 0.0
	return float(data.size() / bytes_per_frame) / float(mix_rate)

# --- Funciones de Utilidad (Basadas en tu código) ---

static func load_from_buffer(audio_samples: PackedVector2Array, sample_rate: int, is_stereo: bool) -> AudioStreamWAV24B:
	return AudioStreamWAV24B.new(audio_samples, sample_rate, is_stereo)

func _format_to_24_bits(frames: PackedVector2Array) -> PackedByteArray:
	
	# Create a raw byte array.
	# 1 frame = 2 channels (Left, Right)
	# 1 channel in 24-bits = 3 bytes
	# Total = 6 bytes per frame
	var byte_array = PackedByteArray()
	var frame_count = frames.size()
	byte_array.resize(frame_count * (6 if stereo else 3))
	
	var byte_offset = 0
	
	for i in range(frame_count):
		var frame = frames[i]
		
		# --- Right Channel (3 bytes) ---
		_encode_24bit(byte_array, byte_offset, frame.x)
		byte_offset += 3
		
		if stereo:
			# --- Right Channel (3 bytes) ---
			_encode_24bit(byte_array, byte_offset, frame.y)
			byte_offset += 3
	
	return byte_array

## Helper interno para codificar un float a 3 bytes (Little-Endian)
func _encode_24bit(target: PackedByteArray, pos: int, sample: float):
	# Escalar de [-1.0, 1.0] a un entero de 24 bits firmado
	# Max value is 8388607 (0x7FFFFF).
	var int_sample = int(clampf(sample, -1.0, 1.0) * 0x7FFFFF)
	
	# Godot doesn't have encode_s24(), so we write the 3 bytes manually
	# using Little-Endian format (Least Significant Byte first).
	
	# --- Channel (3 bytes) ---
	# Byte 1: Extract the first 8 bits
	target[pos]     = int_sample & 0xFF
	# Byte 2: Shift 8 bits to the right and extract
	target[pos + 1] = (int_sample >> 8) & 0xFF
	# Byte 3: Shift 16 bits to the right and extract
	target[pos + 2] = (int_sample >> 16) & 0xFF

func save_to_wav(file_path: String) -> Error:
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if not file:
			print("Error: Could not open file for writing")
			return Error.ERR_CANT_OPEN
		
		var num_channels: int = 2 if stereo else 1
		var bits_per_sample: int = 24
		var byte_rate: int = mix_rate * num_channels * 3
		var block_align: int = num_channels * 3
		var data_size: int = data.size()
		var chunk_size: int = 36 + data_size

		# --- ESCRIBIENDO LA CABECERA (Header) ---
		
		# Bloque RIFF
		file.store_8(82)  # R
		file.store_8(73)  # I
		file.store_8(70)  # F
		file.store_8(70)  # F
		file.store_32(chunk_size) # Tamaño total del archivo menos 8 bytes
		file.store_8(87)  # W
		file.store_8(65)  # A
		file.store_8(86)  # V
		file.store_8(69)  # E

		# Sub-bloque "fmt " (Especificaciones técnicas)
		file.store_8(102) # f
		file.store_8(109) # m
		file.store_8(116) # t
		file.store_8(32)  # (espacio)
		file.store_32(16)  # Tamaño de este sub-bloque (16 para PCM)
		file.store_16(1)   # Formato de audio (1 = PCM lineal)
		file.store_16(num_channels)
		file.store_32(mix_rate)
		file.store_32(byte_rate)
		file.store_16(block_align)
		file.store_16(bits_per_sample)

		# Sub-bloque "data" (Los datos reales)
		file.store_8(100) # d
		file.store_8(97)  # a
		file.store_8(116) # t
		file.store_8(97)  # a
		file.store_32(data_size)
		
		# --- ESCRIBIENDO LOS DATOS ---
		file.store_buffer(data)

		file.close()
		print("File saved successfully at: ", file_path)
		# --- Función para convertir de vuelta tus 24 bits a Floats para reproducir ---
		
		return Error.OK
		
func get_as_frames() -> PackedVector2Array:
	if data.is_empty():
		return PackedVector2Array()
		
	var frames = PackedVector2Array()
	var bytes_per_frame := 6 if stereo else 3
	var total_frames = int(data.size() / bytes_per_frame)
	frames.resize(total_frames)
	
	for i in range(total_frames):
		var byte_idx = i * bytes_per_frame
		
		# --- Reconstrucción Canal Izquierdo ---
		var l_int = data[byte_idx] | (data[byte_idx+1] << 8) | (data[byte_idx+2] << 16)
		
		# MAGIA PRO: Extensión de signo de 24 a 64 bits sin literales problemáticos
		# Movemos el bit 24 al bit 64 y volvemos.
		l_int = (l_int << 40) >> 40
		
		var left_float = float(l_int) / 8388607.0
		var right_float = left_float
		
		if stereo:
			# --- Reconstrucción Canal Derecho ---
			var r_idx = byte_idx + 3
			var r_int = data[r_idx] | (data[r_idx+1] << 8) | (data[r_idx+2] << 16)
			
			# Aplicamos la misma magia
			r_int = (r_int << 40) >> 40
			
			right_float = float(r_int) / 8388607.0
			
		frames[i] = Vector2(left_float, right_float)
		
	return frames
