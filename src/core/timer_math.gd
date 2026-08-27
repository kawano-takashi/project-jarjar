class_name TimerMath
extends RefCounted


const TIME_EPSILON_SECONDS: float = 0.000000001


static func advance_clamped(elapsed: float, interval: float, delta: float) -> float:
	var next: float = minf(interval, elapsed + delta)
	if next >= interval - TIME_EPSILON_SECONDS:
		return interval
	return next


static func is_ready(elapsed: float, interval: float) -> bool:
	return elapsed >= interval - TIME_EPSILON_SECONDS


static func countdown(remaining: float, delta: float) -> float:
	var next: float = maxf(0.0, remaining - delta)
	return 0.0 if next <= TIME_EPSILON_SECONDS else next


static func consume_repeating(
	accumulator: float,
	interval: float,
	delta: float,
	max_events: int = 16
) -> Dictionary:
	var remaining_accumulator: float = maxf(0.0, accumulator + delta)
	var event_count: int = 0
	while (
		event_count < max_events
		and remaining_accumulator >= interval - TIME_EPSILON_SECONDS
	):
		remaining_accumulator = maxf(0.0, remaining_accumulator - interval)
		if remaining_accumulator <= TIME_EPSILON_SECONDS:
			remaining_accumulator = 0.0
		event_count += 1
	return {
		"events": event_count,
		"accumulator": remaining_accumulator,
	}
