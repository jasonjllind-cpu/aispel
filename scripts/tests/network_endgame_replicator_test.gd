extends SceneTree

const REPLICATOR_SCRIPT := preload("res://scripts/network/network_endgame_replicator.gd")
const GRAPH := preload("res://scripts/world/world_graph_generator.gd")
const ACCESS := preload("res://scripts/progression/endgame_region_access.gd")
const BOSSES := preload("res://scripts/progression/boss_progression_contract.gd")
const RELICS := preload("res://scripts/progression/endgame_relic_objectives.gd")
const CHOICES := preload("res://scripts/progression/endgame_choice_consequences.gd")

func _init() -> void:
	var generator: RefCounted = GRAPH.new()
	generator.call("configure", 86082601)
	var graph: Dictionary = generator.call("generate_graph", 64) as Dictionary
	var relic_plan: Dictionary = RELICS.build_plan(graph, ACCESS.build_access_plan(graph))
	var relic_state: Dictionary = RELICS.create_state(relic_plan)
	var boss_state: Dictionary = BOSSES.empty_state()
	var choice_state: Dictionary = CHOICES.create_state("world:test")
	var completed_campaign: Array[String] = ["campaign:frontier_oath", "campaign:blackwood_pact", "campaign:convergence"]
	var world_milestones: Array[String] = ["world_milestone:windscar_beacon"]

	var host := Node.new()
	host.set_script(REPLICATOR_SCRIPT)
	get_root().add_child(host)
	var snapshot: Dictionary = host.call("build_snapshot", completed_campaign, world_milestones, boss_state, relic_plan, relic_state, choice_state, {}, 5)
	if snapshot.is_empty() or not host.call("validate_snapshot", snapshot):
		_fail("Valid authoritative endgame snapshot was rejected")
		return
	var unauthorized: Dictionary = host.call("apply_authoritative_snapshot", snapshot, false)
	if str(unauthorized.get("error", "")) != "not_authority":
		_fail("Non-authority shared endgame snapshot was accepted")
		return
	var accepted: Dictionary = host.call("apply_authoritative_snapshot", snapshot, true)
	if accepted.get("ok", false) != true:
		_fail("Authority could not register shared endgame snapshot")
		return
	var stale: Dictionary = host.call("apply_authoritative_snapshot", snapshot, true)
	if str(stale.get("error", "")) != "stale_revision":
		_fail("Duplicate/stale shared endgame revision was accepted")
		return

	var package: Dictionary = host.call("build_late_join_package", 22)
	if package.is_empty() or str(package.get("package_id", "")).is_empty():
		_fail("Late-join reconstruction package was not built")
		return
	var client := Node.new()
	client.set_script(REPLICATOR_SCRIPT)
	get_root().add_child(client)
	var late_join: Dictionary = client.call("apply_late_join_package", package)
	if late_join.get("ok", false) != true:
		_fail("Late-join endgame reconstruction failed")
		return
	if var_to_str(client.call("current_snapshot")) != var_to_str(snapshot):
		_fail("Late-join client reconstructed different shared endgame state")
		return

	var tampered: Dictionary = snapshot.duplicate(true)
	var tampered_relic: Dictionary = (tampered.get("relic_state", {}) as Dictionary).duplicate(true)
	tampered_relic["plan_id"] = "endgame_relic_plan:tampered"
	tampered["relic_state"] = tampered_relic
	tampered["revision"] = 6
	if host.call("validate_snapshot", tampered):
		_fail("Snapshot accepted relic state from a different deterministic plan")
		return
	var mismatched_package: Dictionary = package.duplicate(true)
	mismatched_package["revision"] = 99
	var mismatch: Dictionary = client.call("apply_late_join_package", mismatched_package)
	if str(mismatch.get("error", "")) != "revision_mismatch":
		_fail("Late-join package revision mismatch was not rejected")
		return

	print("NETWORK_ENDGAME_REPLICATOR_OK revision=%d peer=%d" % [int(snapshot.get("revision", 0)), int(package.get("peer_id", 0))])
	host.queue_free()
	client.queue_free()
	quit(0)

func _fail(message: String) -> void:
	printerr("NETWORK_ENDGAME_REPLICATOR_FAILED: %s" % message)
	quit(1)
