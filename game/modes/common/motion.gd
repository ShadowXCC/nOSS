class_name Motion
extends RefCounted
## Motion maths shared by ghosts (D69) and remote cars (D84).


## Cubic Hermite between p0 and p1 with velocities v0 and v1 over `span` seconds, at u in 0..1:
## matches position and velocity at both ends.
static func hermite(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3, span: float, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return p0 * (2.0 * u3 - 3.0 * u2 + 1.0) + v0 * span * (u3 - 2.0 * u2 + u) \
		+ p1 * (-2.0 * u3 + 3.0 * u2) + v1 * span * (u3 - u2)


## `q` turned by angular velocity `w` (rad/s, world axes) for `dt` seconds.
static func rotate(q: Quaternion, w: Vector3, dt: float) -> Quaternion:
	var angle := w.length() * dt
	if angle < 1e-6:
		return q
	return (Quaternion(w.normalized(), angle) * q).normalized()
