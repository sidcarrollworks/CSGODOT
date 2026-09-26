class_name KV3
extends RefCounted

## Reads KeyValues3 text, the format of CS2's sound events, sound stacks and
## mixers as SteamDatabase's GameTracking-CS2 publishes them:
##
##     <!-- kv3 encoding:text:... -->
##     {
##         Weapon_AK47.Single =
##         {
##             volume = 1.1
##             vsnd_files_track_01 = [ "sounds/weapons/ak47/ak47_01.vsnd", ]
##         }
##     }
##
## Objects become Dictionaries (keys in file order), arrays Arrays, numbers
## floats, true and false bools, null null, and strings Strings. A string
## with a type prefix (resource_name:"...", soundevent:"...") keeps only the
## string. Only the scripts that write the generated tables use it; nothing
## parses KV3 while the game runs.

var _text: String
var _at: int
var _error: String


## The text parsed, or null with error() saying where it went wrong.
static func parse(text: String) -> Variant:
	var reader := KV3.new()
	return reader._parse(text)


## The last parse's error, empty if it succeeded. Kept per reader, so the
## static parse passes it back through a push_error too.
func error() -> String:
	return _error


func _parse(text: String) -> Variant:
	_text = text
	_at = 0
	_error = ""
	_skip()
	var value: Variant = _value()
	_skip()
	if _error.is_empty() and _at < _text.length():
		_fail("text after the root value")
	if not _error.is_empty():
		push_error("KV3: " + _error)
		return null
	return value


func _fail(what: String) -> void:
	if _error.is_empty():
		var line := _text.substr(0, _at).count("\n") + 1
		_error = "%s at line %d" % [what, line]


## Skips white space, commas, <!-- --> and // or /* */ comments.
func _skip() -> void:
	while _at < _text.length():
		var c := _text[_at]
		if c == " " or c == "\t" or c == "\n" or c == "\r" or c == ",":
			_at += 1
		elif _text.substr(_at, 4) == "<!--":
			var end := _text.find("-->", _at)
			_at = _text.length() if end < 0 else end + 3
		elif _text.substr(_at, 2) == "//":
			var end := _text.find("\n", _at)
			_at = _text.length() if end < 0 else end + 1
		elif _text.substr(_at, 2) == "/*":
			var end := _text.find("*/", _at)
			_at = _text.length() if end < 0 else end + 2
		else:
			return


func _value() -> Variant:
	if _at >= _text.length():
		_fail("value expected")
		return null
	var c := _text[_at]
	if c == "{":
		return _object()
	if c == "[":
		return _array()
	if c == "\"":
		return _string()
	var word := _word()
	if word.is_empty():
		_fail("value expected")
		return null
	# A typed string: resource_name:"path".
	if _at < _text.length() and _text[_at] == ":" and _at + 1 < _text.length() and _text[_at + 1] == "\"":
		_at += 1
		return _string()
	if word == "true":
		return true
	if word == "false":
		return false
	if word == "null":
		return null
	if word.is_valid_float():
		return word.to_float()
	return word


func _object() -> Dictionary:
	var result := {}
	_at += 1
	while _error.is_empty():
		_skip()
		if _at >= _text.length():
			_fail("unclosed {")
			break
		if _text[_at] == "}":
			_at += 1
			break
		var key: String = _string() if _text[_at] == "\"" else _word()
		if key.is_empty():
			_fail("key expected")
			break
		_skip()
		if _at >= _text.length() or _text[_at] != "=":
			_fail("= expected after " + key)
			break
		_at += 1
		_skip()
		result[key] = _value()
	return result


func _array() -> Array:
	var result := []
	_at += 1
	while _error.is_empty():
		_skip()
		if _at >= _text.length():
			_fail("unclosed [")
			break
		if _text[_at] == "]":
			_at += 1
			break
		result.append(_value())
	return result


func _string() -> String:
	# A """ block string runs to the next """.
	if _text.substr(_at, 3) == "\"\"\"":
		var end := _text.find("\"\"\"", _at + 3)
		if end < 0:
			_fail("unclosed \"\"\"")
			return ""
		var block := _text.substr(_at + 3, end - _at - 3)
		_at = end + 3
		return block
	_at += 1
	var parts := PackedStringArray()
	var start := _at
	while _at < _text.length():
		var c := _text[_at]
		if c == "\"":
			parts.append(_text.substr(start, _at - start))
			_at += 1
			return "".join(parts).c_unescape()
		if c == "\\":
			_at += 1
		_at += 1
	_fail("unclosed string")
	return ""


## A bare word: a key (Weapon_AK47.Single), a number, true, false or null.
func _word() -> String:
	var start := _at
	while _at < _text.length():
		var c := _text[_at]
		if c == " " or c == "\t" or c == "\n" or c == "\r" or c == "=" or c == "," \
				or c == "{" or c == "}" or c == "[" or c == "]" or c == "\"" or c == ":":
			break
		_at += 1
	return _text.substr(start, _at - start)
