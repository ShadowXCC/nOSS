class_name NetAuth
extends RefCounted
## Joining a server (docs/NETWORKING.md §4–5, D81): the server sends a fresh nonce; the client
## answers with its public key, the nonce signed with its key, and, for a password, an HMAC of
## the nonce keyed with the password's hash. The password itself never travels.

const NONCE_BYTES := 32
const CONTEXT := "noss-auth/1:"


static func nonce() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(NONCE_BYTES)


## What a client signs: SHA-256 of a fixed context and the nonce.
static func signed_digest(nonce_bytes: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(CONTEXT.to_utf8_buffer())
	h.update(nonce_bytes)
	return h.finish()


## The client's proof that it knows `password` (empty for no password).
static func password_proof(password: String, nonce_bytes: PackedByteArray) -> PackedByteArray:
	if password.is_empty():
		return PackedByteArray()
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(password.to_utf8_buffer())
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, h.finish(), nonce_bytes)


## Whether `proof` shows the client knows the server's `password` (anything passes without one).
static func check_password(password: String, nonce_bytes: PackedByteArray, proof: PackedByteArray) -> bool:
	if password.is_empty():
		return true
	var want := password_proof(password, nonce_bytes)
	return proof.size() == want.size() and Crypto.new().constant_time_compare(want, proof)
