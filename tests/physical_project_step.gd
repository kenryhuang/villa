extends RefCounted

static func complete(tree: SceneTree, projects: RefCounted, project_id: String, step_id: String) -> bool:
	for frame in 3600:
		projects.advance()
		var state: Dictionary = projects.projects[project_id].steps[step_id]
		if state.status in ["done", "blocked"]: return state.status == "done"
		await tree.physics_frame
	return false
