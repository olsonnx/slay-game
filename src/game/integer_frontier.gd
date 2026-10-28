extends RefCounted
## Dijkstra frontier for positive integer costs. Equal costs retain the original
## discovery order, including decrease-key, so saved/replayed paths stay stable.
var buckets: Array[Array] = []
var heads: Array[int] = []
var order: Dictionary = {}
var cost := 0

func push(coord: Vector2i, distance: int) -> void:
	if not order.has(coord): order[coord] = order.size()
	while buckets.size() <= distance:
		buckets.append([])
		heads.append(0)
	var bucket: Array = buckets[distance]
	var rank: int = order[coord]
	if bucket.is_empty() or order[bucket.back()] < rank:
		bucket.append(coord)
		return
	var low: int = heads[distance]
	var high := bucket.size()
	while low < high:
		var middle := (low + high) / 2
		if order[bucket[middle]] < rank: low = middle + 1
		else: high = middle
	bucket.insert(low, coord)

func is_empty() -> bool:
	while cost < buckets.size() and heads[cost] >= buckets[cost].size(): cost += 1
	return cost >= buckets.size()

func pop() -> Vector2i:
	var coord: Vector2i = buckets[cost][heads[cost]]
	heads[cost] += 1
	return coord
