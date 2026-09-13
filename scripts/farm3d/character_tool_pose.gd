extends RefCounted

## Shared two-bone tool pose. Targets are palm centers, measured from the
## imported skeleton so different body proportions keep their hands on tools.
static func aim_bone(skeleton: Skeleton3D, index: int, direction: Vector3, rests: Dictionary) -> void:
	var rest: Transform3D = rests[index]
	var basis := Basis(Quaternion(rest.basis.y.normalized(), direction.normalized())) * rest.basis
	set_global_basis(skeleton, index, basis)

static func set_global_basis(skeleton: Skeleton3D, index: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(index, (parent_basis.inverse() * basis).get_rotation_quaternion())

static func lean(skeleton: Skeleton3D, rotation: Quaternion, rests: Dictionary) -> void:
	var spine := skeleton.find_bone("spine")
	set_global_basis(skeleton, spine, Basis(rotation) * (rests[spine] as Transform3D).basis)

static func aim_arm(skeleton: Skeleton3D, suffix: String, target_world: Vector3, rests: Dictionary) -> void:
	var upper := skeleton.find_bone("upper_arm." + suffix)
	var fore := skeleton.find_bone("forearm." + suffix)
	var wrist := skeleton.find_bone("hand." + suffix)
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var target := skeleton.to_local(target_world)
	var a := skeleton.get_bone_rest(fore).origin.length()
	var palm_length := .05
	var b := skeleton.get_bone_rest(wrist).origin.length() + palm_length if wrist >= 0 else .235
	var direction := (target - shoulder).normalized()
	var distance := clampf(target.distance_to(shoulder), absf(a - b) + .005, a + b - .005)
	var along := (a * a - b * b + distance * distance) / (2 * distance)
	var outside := Vector3(signf((rests[upper] as Transform3D).origin.x), -.5, -.2)
	var pole := (outside - direction * outside.dot(direction)).normalized()
	var elbow := shoulder + direction * along + pole * sqrt(maxf(0, a * a - along * along))
	aim_bone(skeleton, upper, elbow - shoulder, rests)
	aim_bone(skeleton, fore, shoulder + direction * distance - elbow, rests)
	if wrist < 0:
		return
	aim_bone(skeleton, wrist, shoulder + direction * distance - elbow, rests)
	# Curl around the palm, resetting each joint first so repeated pose updates
	# never accumulate rotations. Keep the thumb partially open around the grip.
	for finger in ["finger_index", "finger_middle", "finger_ring", "finger_pinky", "thumb"]:
		for joint in ["01", "02", "03"]:
			var index := skeleton.find_bone(finger + "." + joint + "." + suffix)
			if index < 0: continue
			skeleton.set_bone_pose_rotation(index, skeleton.get_bone_rest(index).basis.get_rotation_quaternion())
			var axis := skeleton.get_bone_global_pose(wrist).basis.x.normalized()
			var curl := -.35 if finger == "thumb" else -.75
			set_global_basis(skeleton, index, Basis(Quaternion(axis, curl)) * skeleton.get_bone_global_pose(index).basis)
