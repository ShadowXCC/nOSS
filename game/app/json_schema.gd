class_name JsonSchema
extends RefCounted
## Validates parsed JSON against the JSON Schema subset used in data/schemas/ (draft 2020-12).
## Supports type, const, enum, string/number/array/object limits, pattern, properties,
## additionalProperties, propertyNames, items, prefixItems, uniqueItems, local $ref,
## allOf/anyOf/oneOf. Unknown keywords are ignored.

const SCHEMA_DIR := "res://data/schemas/"

static var _cache := {}
static var _regex_cache := {}
## Packages load on worker threads (several cars at once): the caches are shared.
static var _lock := Mutex.new()


## Loads data/schemas/<name>.schema.json. Returns {} if it's missing or broken.
static func load_schema(name: String) -> Dictionary:
	_lock.lock()
	var cached: Variant = _cache.get(name)
	_lock.unlock()
	if cached != null:
		return cached
	var text := FileAccess.get_file_as_string(SCHEMA_DIR + name + ".schema.json")
	var schema: Variant = JSON.parse_string(text) if text else null
	if not schema is Dictionary:
		push_error("Schema missing or invalid: " + name)
		return {}
	_lock.lock()
	_cache[name] = schema
	_lock.unlock()
	return schema


## Returns the list of errors ("path: message"); empty means valid.
static func validate(data: Variant, schema: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	_check(data, schema, schema, "$", errors)
	return errors


static func _check(data: Variant, schema: Dictionary, root: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("$ref"):
		var target := _resolve(schema["$ref"], root)
		if target.is_empty():
			errors.append("%s: bad $ref %s" % [path, schema["$ref"]])
			return
		_check(data, target, root, path, errors)

	if schema.has("type") and not _type_ok(data, schema["type"]):
		errors.append("%s: expected %s" % [path, schema["type"]])
		return
	if schema.has("const") and not _equal(data, schema["const"]):
		errors.append("%s: must be %s" % [path, JSON.stringify(schema["const"])])
	if schema.has("enum") and not schema["enum"].any(func(v: Variant) -> bool: return _equal(data, v)):
		errors.append("%s: must be one of %s" % [path, JSON.stringify(schema["enum"])])

	if data is String:
		_check_string(data, schema, path, errors)
	elif _is_number(data):
		_check_number(data, schema, path, errors)
	elif data is Array:
		_check_array(data, schema, root, path, errors)
	elif data is Dictionary:
		_check_object(data, schema, root, path, errors)

	for sub: Dictionary in schema.get("allOf", []):
		_check(data, sub, root, path, errors)
	if schema.has("anyOf"):
		if not schema["anyOf"].any(func(sub: Dictionary) -> bool: return _passes(data, sub, root)):
			errors.append("%s: matches none of anyOf" % path)
	if schema.has("oneOf"):
		var matches: int = schema["oneOf"].filter(func(sub: Dictionary) -> bool: return _passes(data, sub, root)).size()
		if matches != 1:
			errors.append("%s: matches %d of oneOf, needs exactly 1" % [path, matches])


static func _check_string(data: String, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("minLength") and data.length() < schema["minLength"]:
		errors.append("%s: shorter than %d" % [path, schema["minLength"]])
	if schema.has("maxLength") and data.length() > schema["maxLength"]:
		errors.append("%s: longer than %d" % [path, schema["maxLength"]])
	if schema.has("pattern") and not _regex(schema["pattern"]).search(data):
		errors.append("%s: doesn't match %s" % [path, schema["pattern"]])


static func _check_number(data: float, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("minimum") and data < schema["minimum"]:
		errors.append("%s: below %s" % [path, schema["minimum"]])
	if schema.has("maximum") and data > schema["maximum"]:
		errors.append("%s: above %s" % [path, schema["maximum"]])
	if schema.has("exclusiveMinimum") and data <= schema["exclusiveMinimum"]:
		errors.append("%s: must be above %s" % [path, schema["exclusiveMinimum"]])
	if schema.has("exclusiveMaximum") and data >= schema["exclusiveMaximum"]:
		errors.append("%s: must be below %s" % [path, schema["exclusiveMaximum"]])


static func _check_array(data: Array, schema: Dictionary, root: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("minItems") and data.size() < schema["minItems"]:
		errors.append("%s: fewer than %d items" % [path, schema["minItems"]])
	if schema.has("maxItems") and data.size() > schema["maxItems"]:
		errors.append("%s: more than %d items" % [path, schema["maxItems"]])
	var prefix: Array = schema.get("prefixItems", [])
	for i in mini(prefix.size(), data.size()):
		_check(data[i], prefix[i], root, "%s[%d]" % [path, i], errors)
	if schema.get("items") is Dictionary:
		for i in range(prefix.size(), data.size()):
			_check(data[i], schema["items"], root, "%s[%d]" % [path, i], errors)
	elif schema.get("items") == false and data.size() > prefix.size():
		errors.append("%s: too many items" % path)
	if schema.get("uniqueItems", false):
		var seen := {}
		for item: Variant in data:
			var key := JSON.stringify(item, "", true)
			if seen.has(key):
				errors.append("%s: duplicate item %s" % [path, key])
				break
			seen[key] = true


static func _check_object(data: Dictionary, schema: Dictionary, root: Dictionary, path: String, errors: PackedStringArray) -> void:
	for key: String in schema.get("required", []):
		if not data.has(key):
			errors.append("%s: missing %s" % [path, key])
	if schema.has("minProperties") and data.size() < schema["minProperties"]:
		errors.append("%s: fewer than %d properties" % [path, schema["minProperties"]])
	if schema.has("maxProperties") and data.size() > schema["maxProperties"]:
		errors.append("%s: more than %d properties" % [path, schema["maxProperties"]])
	var properties: Dictionary = schema.get("properties", {})
	var additional: Variant = schema.get("additionalProperties", true)
	for key: Variant in data:
		var child_path := "%s.%s" % [path, key]
		if schema.has("propertyNames"):
			_check(key, schema["propertyNames"], root, child_path + " (name)", errors)
		if properties.has(key):
			_check(data[key], properties[key], root, child_path, errors)
		elif additional is Dictionary:
			_check(data[key], additional, root, child_path, errors)
		elif additional == false:
			errors.append("%s: unknown property" % child_path)


static func _passes(data: Variant, schema: Dictionary, root: Dictionary) -> bool:
	var errors := PackedStringArray()
	_check(data, schema, root, "", errors)
	return errors.is_empty()


static func _resolve(ref: String, root: Dictionary) -> Dictionary:
	if not ref.begins_with("#"):
		return {}
	var node: Variant = root
	for token in ref.substr(1).split("/", false):
		var key := token.replace("~1", "/").replace("~0", "~")
		if not node is Dictionary or not node.has(key):
			return {}
		node = node[key]
	return node if node is Dictionary else {}


static func _type_ok(data: Variant, type: Variant) -> bool:
	if type is Array:
		return type.any(func(t: String) -> bool: return _type_ok(data, t))
	match type:
		"object": return data is Dictionary
		"array": return data is Array
		"string": return data is String
		"boolean": return data is bool
		"null": return data == null
		"number": return _is_number(data)
		"integer": return _is_number(data) and is_equal_approx(data, roundf(data))
	return false


static func _is_number(data: Variant) -> bool:
	return data is float or data is int


static func _equal(a: Variant, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


static func _regex(pattern: String) -> RegEx:
	_lock.lock()
	if not _regex_cache.has(pattern):
		_regex_cache[pattern] = RegEx.create_from_string(pattern)
	var re: RegEx = _regex_cache[pattern]
	_lock.unlock()
	return re
