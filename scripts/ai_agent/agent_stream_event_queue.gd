extends RefCounted

var _events: Array[Dictionary] = []


func push_many(events: Array) -> bool:
	for event in events:
		if not event is Dictionary:
			return false
	for event in events:
		_events.append((event as Dictionary).duplicate(true))
	return true


func drain(limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for _index in range(mini(maxi(0, limit), _events.size())):
		result.append(_events.pop_front())
	return result


func is_empty() -> bool:
	return _events.is_empty()


func size() -> int:
	return _events.size()
