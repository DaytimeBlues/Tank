extends RefCounted
# Original Tank implementation. Fixed existing eight voices and -20 dB mix.
const CAP := 8
var voices: Array[AudioStreamPlayer3D] = []
var cursor := 0
var source: AudioStream
func initialize(parent: Node, stream: AudioStream) -> void:
 if not voices.is_empty(): return
 source = stream
 for i in range(CAP):
  var voice := AudioStreamPlayer3D.new()
  _reset_voice(voice)
  parent.add_child(voice)
  voices.append(voice)
func _reset_voice(voice: AudioStreamPlayer3D) -> void:
 voice.stop()
 voice.stream = source
 voice.pitch_scale = 1.0
 voice.volume_db = -20.0
 voice.max_db = -20.0
 voice.max_distance = 180.0
 voice.unit_size = 20.0
func play_at(position: Vector3) -> bool:
 if voices.is_empty() or source == null or not position.is_finite(): return false
 var voice := voices[cursor]
 cursor = (cursor + 1) % CAP
 _reset_voice(voice)
 voice.position = position
 voice.play()
 return true
func clear() -> void:
 cursor = 0
 for voice in voices: _reset_voice(voice)
