extends RefCounted

static func valid(p: Variant) -> bool:
	if not p is Dictionary or p.size() != 2 or not text(p.get("display_name"),80) or not p.get("soul") is Dictionary: return false
	var soul: Dictionary = p.soul
	if soul.size() != 5 or not text(soul.get("speech_style"),500): return false
	for field in ["traits","values"]:
		if not soul.get(field) is Array or soul[field].size() > 32: return false
		for entry in soul[field]:
			if not text(entry,160): return false
	if not number(soul.get("risk_tolerance"),0,1): return false
	var social: Variant = soul.get("social_profile")
	if not social is Dictionary or social.size() != 5: return false
	return integer(social.get("age"),1,150) and social.get("gender") in ["female","male","unspecified"] and integer(social.get("romance_interest"),0,100) and integer(social.get("accept_affinity_threshold"),0,100) and text(social.get("relationship_style"),1000)

static func text(v: Variant, limit: int) -> bool:
	return v is String and not v.strip_edges().is_empty() and v.length() <= limit

static func number(v: Variant, low: float, high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v >= low and v <= high

static func integer(v: Variant, low: int, high: int) -> bool:
	return number(v,low,high) and floorf(float(v)) == float(v)
