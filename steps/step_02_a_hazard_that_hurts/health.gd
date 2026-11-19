extends Node
## The health of the node it is a child of. It only counts: whatever hurts calls hurt(),
## and whoever cares listens to the signals. It never asks what it belongs to.

signal changed(health: int) ## After every hit and after reset().
signal died(cause: String) ## The hit that took the last point. cause names what dealt it.

@export var max_health := 100

var health := 0
var dead := false ## From the last hit until reset(): a dead body takes no more hits.

func _ready() -> void:
	reset()

## Takes amount off, never below 0. The hit that reaches 0 sends died() once, with its cause.
func hurt(amount: int, cause: String) -> void:
	if dead or amount <= 0:
		return
	health = maxi(health - amount, 0)
	changed.emit(health)
	if health == 0:
		dead = true
		died.emit(cause)

## Full health again: a new run.
func reset() -> void:
	health = max_health
	dead = false
	changed.emit(health)
