class_name SeedService
extends RefCounted


const MAX_SIGNED_63_BIT: int = 0x7fffffffffffffff


static func derive(base_seed: int, stream_name: StringName) -> int:
	var payload: String = "%d|%s" % [base_seed, String(stream_name)]
	var digest: PackedByteArray = payload.sha256_buffer()
	return digest.decode_u64(0) & MAX_SIGNED_63_BIT


static func generate_run_seed() -> int:
	var entropy: String = "%d|%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var digest: PackedByteArray = entropy.sha256_buffer()
	var generated: int = digest.decode_u64(0) & MAX_SIGNED_63_BIT
	return 1 if generated == 0 else generated
