extends GdUnitTestSuite
## The runtime validator agrees with the Python jsonschema check on every fixture.

const FIXTURES := "res://tests/schemas/fixtures/"


func test_fixtures_match_expectations() -> void:
	var checked := 0
	for schema_name in DirAccess.get_directories_at(FIXTURES):
		var schema := JsonSchema.load_schema(schema_name)
		assert_dict(schema).is_not_empty()
		for file in DirAccess.get_files_at(FIXTURES + schema_name):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + schema_name + "/" + file))
			var errors := JsonSchema.validate(data, schema)
			if file.begins_with("valid_"):
				assert_array(errors).override_failure_message("%s/%s rejected: %s" % [schema_name, file, errors]).is_empty()
			else:
				assert_array(errors).override_failure_message("%s/%s accepted" % [schema_name, file]).is_not_empty()
			checked += 1
	assert_int(checked).is_greater(10)


func test_basic_keywords() -> void:
	var schema := {
		"type": "object",
		"additionalProperties": false,
		"required": ["n"],
		"properties": {
			"n": { "type": "integer", "minimum": 1 },
			"s": { "type": "string", "pattern": "^a+$" },
			"v": { "oneOf": [{ "type": "null" }, { "type": "array", "minItems": 2 }] },
		},
	}
	assert_array(JsonSchema.validate({ "n": 3.0 }, schema)).is_empty()
	assert_array(JsonSchema.validate({ "n": 3.5 }, schema)).is_not_empty()
	assert_array(JsonSchema.validate({ "n": 0 }, schema)).is_not_empty()
	assert_array(JsonSchema.validate({}, schema)).is_not_empty()
	assert_array(JsonSchema.validate({ "n": 1, "x": 1 }, schema)).is_not_empty()
	assert_array(JsonSchema.validate({ "n": 1, "s": "aab" }, schema)).is_not_empty()
	assert_array(JsonSchema.validate({ "n": 1, "v": null }, schema)).is_empty()
	assert_array(JsonSchema.validate({ "n": 1, "v": [1] }, schema)).is_not_empty()
