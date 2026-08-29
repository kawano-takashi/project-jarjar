class_name PerformanceMetrics
extends RefCounted


const P95_PERCENTILE: float = 0.95
const P99_PERCENTILE: float = 0.99
const TARGET_AVERAGE_FPS: float = 60.0
const MAX_P95_FRAME_TIME_USEC: int = 16_670
const TARGET_ONE_PERCENT_LOW_FPS: float = 50.0
const MAX_WORST_FRAME_TIME_USEC: int = 33_330
const MEMORY_SAMPLE_COUNT_PER_WINDOW: int = 30
const MAX_MEMORY_GROWTH_RATIO: float = 1.05


static func nearest_rank_usec(
	unsorted_samples: PackedInt64Array,
	percentile: float,
) -> int:
	if unsorted_samples.is_empty() or percentile <= 0.0 or percentile > 1.0:
		return 0
	var sorted_samples: PackedInt64Array = unsorted_samples.duplicate()
	sorted_samples.sort()
	var index := ceili(percentile * float(sorted_samples.size())) - 1
	index = clampi(index, 0, sorted_samples.size() - 1)
	return sorted_samples[index]


static func median_bytes(unsorted_samples: PackedInt64Array) -> float:
	if unsorted_samples.is_empty():
		return 0.0
	var sorted_samples: PackedInt64Array = unsorted_samples.duplicate()
	sorted_samples.sort()
	var middle := floori(float(sorted_samples.size()) / 2.0)
	if sorted_samples.size() % 2 == 1:
		return float(sorted_samples[middle])
	return (float(sorted_samples[middle - 1]) + float(sorted_samples[middle])) / 2.0


static func summarize(
	frame_times_usec: PackedInt64Array,
	early_memory_samples: PackedInt64Array,
	late_memory_samples: PackedInt64Array,
) -> Dictionary:
	var sample_count := frame_times_usec.size()
	var total_frame_time_usec: int = 0
	var worst_frame_time_usec: int = 0
	for frame_time_usec: int in frame_times_usec:
		total_frame_time_usec += frame_time_usec
		worst_frame_time_usec = maxi(worst_frame_time_usec, frame_time_usec)

	var average_fps := 0.0
	if sample_count > 0 and total_frame_time_usec > 0:
		average_fps = 1_000_000.0 * float(sample_count) / float(total_frame_time_usec)
	var p95_frame_time_usec := nearest_rank_usec(frame_times_usec, P95_PERCENTILE)
	var p99_frame_time_usec := nearest_rank_usec(frame_times_usec, P99_PERCENTILE)
	var one_percent_low_fps := 0.0
	if p99_frame_time_usec > 0:
		one_percent_low_fps = 1_000_000.0 / float(p99_frame_time_usec)

	var early_memory_median_bytes := median_bytes(early_memory_samples)
	var late_memory_median_bytes := median_bytes(late_memory_samples)
	var memory_growth_ratio := INF
	if early_memory_median_bytes > 0.0:
		memory_growth_ratio = late_memory_median_bytes / early_memory_median_bytes

	return {
		"sample_count": sample_count,
		"total_frame_time_usec": total_frame_time_usec,
		"average_fps": average_fps,
		"p95_frame_time_usec": p95_frame_time_usec,
		"p99_frame_time_usec": p99_frame_time_usec,
		"one_percent_low_fps": one_percent_low_fps,
		"worst_frame_time_usec": worst_frame_time_usec,
		"early_memory_sample_count": early_memory_samples.size(),
		"late_memory_sample_count": late_memory_samples.size(),
		"early_memory_median_bytes": early_memory_median_bytes,
		"late_memory_median_bytes": late_memory_median_bytes,
		"memory_growth_ratio": memory_growth_ratio,
	}


static func threshold_failures(summary: Dictionary) -> PackedStringArray:
	var failures := PackedStringArray()
	var sample_count: int = int(summary.get("sample_count", 0))
	var total_frame_time_usec: int = int(summary.get("total_frame_time_usec", 0))
	if sample_count <= 0:
		failures.append("measurement_sample_count_zero")
	elif total_frame_time_usec <= 0:
		failures.append("measurement_frame_time_sum_nonpositive")
	if float(summary.get("average_fps", 0.0)) < TARGET_AVERAGE_FPS:
		failures.append("average_fps_below_60")
	if int(summary.get("p95_frame_time_usec", 0)) > MAX_P95_FRAME_TIME_USEC:
		failures.append("p95_frame_time_above_16_67ms")
	if float(summary.get("one_percent_low_fps", 0.0)) < TARGET_ONE_PERCENT_LOW_FPS:
		failures.append("one_percent_low_fps_below_50")
	if int(summary.get("worst_frame_time_usec", 0)) > MAX_WORST_FRAME_TIME_USEC:
		failures.append("worst_frame_time_above_33_33ms")

	var early_sample_count: int = int(summary.get("early_memory_sample_count", 0))
	var late_sample_count: int = int(summary.get("late_memory_sample_count", 0))
	var early_median: float = float(summary.get("early_memory_median_bytes", 0.0))
	var late_median: float = float(summary.get("late_memory_median_bytes", 0.0))
	if early_sample_count != MEMORY_SAMPLE_COUNT_PER_WINDOW:
		failures.append("early_memory_sample_count_not_30")
	if late_sample_count != MEMORY_SAMPLE_COUNT_PER_WINDOW:
		failures.append("late_memory_sample_count_not_30")
	if early_median <= 0.0 or late_median <= 0.0:
		failures.append("static_memory_median_nonpositive")
	elif late_median > early_median * MAX_MEMORY_GROWTH_RATIO:
		failures.append("static_memory_growth_above_105_percent")
	return failures
