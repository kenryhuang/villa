extends RefCounted

## Need pressure: 0 satisfied, 100 urgent. These are personal state, not money
## or relationship scores. Only actual completed activities satisfy them.
const KEYS := ["hunger", "thirst", "fatigue", "social", "companionship"]
const RATES := {"hunger": 4.0, "thirst": 6.0, "fatigue": 3.5, "social": 1.8, "companionship": .7}

static func initial(actor: String, minute: int) -> Dictionary:
	var result := {"last_minute": minute, "profile_revision": 2}
	for key in KEYS: result[key] = float(10 + absi(hash(actor+key)) % 16)
	return result

static func valid(value: Variant, minute: int) -> bool:
	if not value is Dictionary or value.size() != 7 or value.get("profile_revision") != 2: return false
	var stamp: Variant = value.get("last_minute")
	if not (stamp is int or stamp is float) or not is_finite(stamp) or stamp != floor(stamp) or stamp < 0 or stamp > minute: return false
	for key in KEYS:
		var n: Variant = value.get(key)
		if not (n is int or n is float) or not is_finite(n) or n < 0 or n > 100: return false
	return true

static func advance(needs: Dictionary, actor: String, minute: int) -> Array:
	var hours := maxf(0,minute-int(needs.last_minute))/60.0
	var alerts := []
	for key in KEYS:
		var previous := float(needs[key])
		var preference := .85+float(absi(hash(actor+key))%31)/100.0
		needs[key] = minf(100,previous+hours*float(RATES[key])*preference)
		if previous < 70 and float(needs[key]) >= 70: alerts.append(key)
	needs.last_minute = maxi(int(needs.last_minute),minute)
	return alerts

static func relieve(needs: Dictionary, changes: Dictionary) -> void:
	for key in changes: needs[key] = clampf(float(needs[key])-float(changes[key]),0,100)
