class_name Pca
extends RefCounted
## Principal axes of a point cloud (3x3 covariance, Jacobi eigen solver).


## Unit direction in which the points spread least, e.g. the normal of a disc.
static func smallest_axis(points: PackedVector3Array) -> Vector3:
	var mean := Vector3.ZERO
	for p in points:
		mean += p
	mean /= points.size()
	var c := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in points:
		var d := p - mean
		for i in 3:
			for j in 3:
				c[i][j] += d[i] * d[j]
	var e := eigen_symmetric(c)
	var best := 0
	for i in 3:
		if e.values[i] < e.values[best]:
			best = i
	return e.vectors[best].normalized()


## Eigen decomposition of a symmetric 3x3 matrix (rows of floats).
## Returns {values: [3 floats], vectors: [3 Vector3]}.
static func eigen_symmetric(m: Array) -> Dictionary:
	var a := [m[0].duplicate(), m[1].duplicate(), m[2].duplicate()]
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	for sweep in 32:
		var off: float = absf(a[0][1]) + absf(a[0][2]) + absf(a[1][2])
		if off < 1e-12:
			break
		for pq: Array in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			if absf(a[p][q]) < 1e-15:
				continue
			var theta: float = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
			var t: float = signf(theta) / (absf(theta) + sqrt(theta * theta + 1.0)) if theta != 0.0 else 1.0
			var cs := 1.0 / sqrt(t * t + 1.0)
			var sn := t * cs
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = cs * akp - sn * akq
				a[k][q] = sn * akp + cs * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = cs * apk - sn * aqk
				a[q][k] = sn * apk + cs * aqk
			for k in 3:
				var vkp: float = v[k][p]
				var vkq: float = v[k][q]
				v[k][p] = cs * vkp - sn * vkq
				v[k][q] = sn * vkp + cs * vkq
	return {
		"values": [a[0][0], a[1][1], a[2][2]],
		"vectors": [Vector3(v[0][0], v[1][0], v[2][0]), Vector3(v[0][1], v[1][1], v[2][1]), Vector3(v[0][2], v[1][2], v[2][2])],
	}
