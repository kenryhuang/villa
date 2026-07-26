class_name StorySystem
extends Node

## 故事系统 - 日记碎片收集、章节解锁

signal fragment_collected(fragment_id: String)
signal chapter_revealed(chapter: int)

var collected_fragments: Array[String] = []
var story_revealed_up_to: int = 0

const STORY_MILESTONES := [
	{"fragments_needed": 3, "chapter": 1, "region": "creek", "title": "初到山谷"},
	{"fragments_needed": 6, "chapter": 2, "region": "deep_forest", "title": "植物学家的足迹"},
	{"fragments_needed": 9, "chapter": 3, "region": "mist_peak", "title": "迷雾中的秘密"},
	{"fragments_needed": 12, "chapter": 4, "region": "secret_garden", "title": "最后的守护者"},
]

var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func collect_fragment(fragment_id: String) -> void:
	if fragment_id in collected_fragments:
		return

	collected_fragments.append(fragment_id)

	if _event_bus:
		_event_bus.story_fragment_collected.emit(fragment_id)

	fragment_collected.emit(fragment_id)
	_check_story_progress()


func _check_story_progress() -> void:
	var count = collected_fragments.size()
	for milestone in STORY_MILESTONES:
		if count >= milestone.fragments_needed and story_revealed_up_to < milestone.chapter:
			story_revealed_up_to = milestone.chapter
			_reveal_chapter(milestone)


func _reveal_chapter(milestone: Dictionary) -> void:
	chapter_revealed.emit(milestone.chapter)

	# 解锁对应区域
	var exploration = get_node_or_null("/root/ExplorationSystem")
	if exploration:
		exploration.unlock_region(milestone.region)


func get_current_chapter() -> int:
	return story_revealed_up_to


func get_chapter_title(chapter: int) -> String:
	for m in STORY_MILESTONES:
		if m.chapter == chapter:
			return m.title
	return ""


func get_fragment_count() -> int:
	return collected_fragments.size()


func get_total_fragments() -> int:
	return 12  # 总共12个日记碎片


func is_complete() -> bool:
	return collected_fragments.size() >= 12
