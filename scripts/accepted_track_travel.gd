class_name AcceptedTrackTravel
extends RefCounted
# Presentation-only odometry. Call reset on authoritative discontinuity/rejoin/model change.
var previous_position := Vector3.ZERO
var previous_yaw := 0.0
var initialized := false
var left_metres := 0.0
var right_metres := 0.0
var half_width := 1.65
var generation := 0
func reset() -> void:
	generation += 1
	initialized=false
	left_metres=0.0
	right_metres=0.0
func sample(position:Vector3,yaw:float,alive:bool=true,discontinuity:bool=false) -> Vector2:
	if not position.is_finite() or not is_finite(yaw):
		reset()
		return Vector2.ZERO
	if not alive or discontinuity:
		reset()
	if not initialized:
		previous_position=position
		previous_yaw=yaw
		initialized=alive
		return Vector2.ZERO
	var delta:=position-previous_position
	var turn:=wrapf(yaw-previous_yaw,-PI,PI)
	var forward:=Vector3(sin(previous_yaw+turn*0.5),0,cos(previous_yaw+turn*0.5))
	previous_position=position
	previous_yaw=yaw
	# Conservative discontinuity guard for this bounded3m/s fixture; not network acceptance.
	if delta.length()>3.0 or abs(turn)>1.2:
		generation += 1
		left_metres=0.0
		right_metres=0.0
		return Vector2.ZERO
	var advance:=delta.dot(forward)
	left_metres+=advance+half_width*turn
	right_metres+=advance-half_width*turn
	return Vector2(left_metres,right_metres)
