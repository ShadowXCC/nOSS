class_name WorkerJob
extends RefCounted
## Work on the WorkerThreadPool with a timeout (NFR-04: parsing never blocks the main thread).
## The result comes back on the main thread, to a callback that is dropped if whoever asked has
## gone (left the screen meanwhile); a result after the timeout is thrown away (its `discard`).

var task := -1
var on_done: Callable
var discard: Callable
var done := false
var waited := false

## Jobs still on a worker: WorkerJob -> true. A job whose result nobody can wait for held its
## worker inside native calls past the GDExtension's own teardown (D253).
static var _running := {}


## Runs `work` () -> Variant on a worker; `on_done` (result) gets the result, or `on_timeout`
## () -> Variant's after `timeout_s`. `discard` (result) cleans up an unused one.
static func start(owner: Node, work: Callable, on_done: Callable, timeout_s: float, on_timeout: Callable, discard := Callable()) -> WorkerJob:
	var job := WorkerJob.new()
	job.on_done = on_done
	job.discard = discard
	job.task = WorkerThreadPool.add_task(func() -> void:
		var result: Variant = work.call()
		job._finish.call_deferred(result))
	_running[job] = true
	owner.get_tree().create_timer(timeout_s).timeout.connect(func() -> void: job._time_out(on_timeout))
	return job


## Waits for every job still on a worker, serving their RenderingServer calls meanwhile, and drops
## what they made (the game quitting, D253). Nothing waits for these jobs otherwise, so a worker
## still inside a native call when the GDExtension is taken down crashes the exit.
static func finish_all() -> void:
	for job: WorkerJob in _running.keys():
		job._wait()
		job.done = true
	_running.clear()


## True if `c` can still be called: a lambda's owner may have been freed meanwhile, which
## is_valid() alone doesn't see.
static func alive(c: Callable) -> bool:
	if not c.is_valid():
		return false
	var id := c.get_object_id()
	return id == 0 or is_instance_id_valid(id)


## Waits for the worker, serving the RenderingServer meanwhile: a glTF load reads a texture back
## on the main thread, so spinning without it would deadlock.
func _wait() -> void:
	if waited:
		return
	while not WorkerThreadPool.is_task_completed(task):
		RenderingServer.force_sync()
		OS.delay_msec(1)
	WorkerThreadPool.wait_for_task_completion(task)
	waited = true


func _finish(result: Variant) -> void:
	_running.erase(self)
	_wait()
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
