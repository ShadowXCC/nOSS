class_name NetIdentity
extends RefCounted
## This install's identity online (docs/NETWORKING.md §4, D81): an RSA key pair kept in
## user://identity/. The SHA-256 of the public key is the fingerprint that servers ban,
## whitelist and make admin. There are no accounts. Servers check a client owns its key by
## having it sign a fresh nonce.

const KEY_BITS := 2048
const KEY_FILE := "key.pem"
## Most bytes a public key in PEM may take on the wire.
const MAX_PUBLIC_PEM := 1024

## Where the key lives (Settings.use_folder points tests and --instance runs elsewhere).
static var dir := "user://identity/"

var key: CryptoKey
var public_pem := ""
## 64 hex characters.
var fingerprint := ""


## The saved identity, or a new one saved now (only the owner can read the key file).
static func load_or_create(folder := dir) -> NetIdentity:
	var path := folder.path_join(KEY_FILE)
	var key := CryptoKey.new()
	if not FileAccess.file_exists(path) or key.load(path) != OK:
		key = Crypto.new().generate_rsa(KEY_BITS)
		DirAccess.make_dir_recursive_absolute(folder)
		if key.save(path) == OK:
			FileAccess.set_unix_permissions(ProjectSettings.globalize_path(path), FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	return from_key(key)


## A fresh identity that isn't saved (bots, tests).
static func throwaway() -> NetIdentity:
	return from_key(Crypto.new().generate_rsa(KEY_BITS))


static func from_key(k: CryptoKey) -> NetIdentity:
	var id := NetIdentity.new()
	id.key = k
	id.public_pem = k.save_to_string(true)
	id.fingerprint = fingerprint_of(id.public_pem)
	return id


static func fingerprint_of(pem: String) -> String:
	return PlatformLoader.sha256_hex(pem.strip_edges().to_utf8_buffer())


## The first 16 hex digits in groups of four, for people to compare: "3f2a-91c0-77de-0b15".
static func short(fp: String) -> String:
	var parts := PackedStringArray()
	for i in 4:
		parts.append(fp.substr(i * 4, 4))
	return "-".join(parts)


## Signs the server's nonce.
func sign(nonce: PackedByteArray) -> PackedByteArray:
	return Crypto.new().sign(HashingContext.HASH_SHA256, NetAuth.signed_digest(nonce), key)


## Whether `signature` is `nonce` signed by the key in `pem`.
static func verify(pem: String, nonce: PackedByteArray, signature: PackedByteArray) -> bool:
	if pem.length() > MAX_PUBLIC_PEM or not pem.begins_with("-----BEGIN PUBLIC KEY-----") \
			or signature.is_empty() or signature.size() > 1024:
		return false
	var k := CryptoKey.new()
	if k.load_from_string(pem, true) != OK:
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, NetAuth.signed_digest(nonce), signature, k)
