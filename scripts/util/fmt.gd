class_name Fmt
extends RefCounted
## Number formatting. Static-only — never instantiated.


## Compact money: $4,250 → $18K → $2.40M → $1.06B
static func money(value: float) -> String:
	var sign_str := "-" if value < -0.5 else ""
	var v := absf(value)
	if v >= 1000000000.0:
		return "%s$%.2fB" % [sign_str, v / 1000000000.0]
	if v >= 1000000.0:
		return "%s$%.2fM" % [sign_str, v / 1000000.0]
	if v >= 10000.0:
		return "%s$%.0fK" % [sign_str, v / 1000.0]
	return "%s$%s" % [sign_str, grouped(int(roundf(v)))]


## 1234567 → "1,234,567"
static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out


static func percent(fraction: float, decimals: int = 1) -> String:
	return String.num(fraction * 100.0, decimals) + "%"


static func weeks(count: float) -> String:
	if count < 0.0:
		return "cash-flow positive"
	if count < 1.0:
		return "runs dry this week"
	var n := int(count)
	return "%d wk left" % n if n == 1 else "%d wks left" % n
