class_name WorkerJob
extends RefCounted
## Work on the WorkerThreadPool with a timeout (NFR-04: parsing never blocks the main thread).
## The result comes back on the main thread, to a callback that is dropped if whoever asked has
## gone (left the screen meanwhile); a result after the timeout is thrown away (its `discard`).

var task := -1
var on_done: Callable
var discard: Callable
var done := false


## Runs `work` () -> Variant on a worker; `on_done` (result) gets the result, or `on_timeout`
## () -> Variant's after `timeout_s`. `discard` (result) cleans up an unused one.
static func start(owner: Node, work: Callable, on_done: Callable, timeout_s: float, on_timeout: Callable, discard := Callable()) -> WorkerJob:
	var job := WorkerJob.new()
	job.on_done = on_done
	job.discard = discard
	job.task = WorkerThreadPool.add_task(func() -> void:
		var result: Variant = work.call()
		job._finish.call_deferred(result))
	owner.get_tree().create_timer(timeout_s).timeout.connect(func() -> void: job._time_out(on_timeout))
	return job


## True if `c` can still be called: a lambda's owner may have been freed meanwhile, which
## is_valid() alone doesn't see.
static func alive(c: Callable) -> bool:
	if not c.is_valid():
		return false
	var id := c.get_object_id()
	return id == 0 or is_instance_id_valid(id)


func _finish(result: Variant) -> void:
	WorkerThreadPool.wait_for_task_completion(task)
	if done or not alive(on_done):
		done = true
		if alive(discard):
			discard.call(result)
		return
	done = true
	on_done.call(result)


func _time_out(on_timeout: Callable) -> void:
	if done:
		return
	done = true
	if alive(on_done):
		on_done.call(on_timeout.call())
