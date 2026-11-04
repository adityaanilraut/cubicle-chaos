class_name OfficeDialogue
extends CanvasLayer

# Short, automatic exchanges. Only the current speaker has a speech bubble.
const TURN_SECONDS := 2.5
# Each coworker has recurring interests, with a matching automatic reply and closer.
const PROFILES := {
	"Alex": ["💼 Welcome to my team!", "📊 How is the shift?", "👏 Good work today!", "☕ Even bosses need coffee.", "📌 Teamwork comes first!", "📅 Let’s keep meetings short."],
	"Maya": ["🌱 My plant waved!", "☀️ Nice day inside!", "🥤 Water break?", "🌿 Plants need pep talks.", "🌸 Desk garden update!", "😊 You made my day!"],
	"Jordan": ["🎨 This needs color!", "🖍️ I drew the printer.", "✨ Fancy a doodle?", "🖼️ Art break!", "🌈 More color, please!", "✏️ My pen is inspired."],
	"Sam": ["☕ Coffee o'clock!", "☕ Is this my fifth?", "🥐 Snack emergency!", "🫖 Coffee needs coffee.", "🍪 Did you see a cookie?", "☕ I run on beans."],
	"Taylor": ["📚 Plot twist: work!", "📖 One more chapter?", "🔎 Have you read this?", "📕 Books beat meetings.", "📚 My desk has a sequel.", "🤓 I brought footnotes!"],
	"Morgan": ["💻 Try turning it off!", "🔧 I fixed the thing!", "🖥️ The printer blinked.", "🤖 My code said hello.", "🔌 Who unplugged lunch?", "💾 Saving the day!"],
	"Casey": ["🎤 Welcome to the briefing!", "📈 Our numbers are up!", "💡 Any bright ideas?", "📊 One more slide!", "🙋 Questions, anyone?", "👏 Thanks for joining us!"],
	"Riley": ["📝 I took good notes!", "🙋 I have a question!", "📈 That chart looks good!", "💡 Let’s try that idea!", "👏 Nice presentation!", "☕ Is there a coffee slide?"],
	"Jamie": ["📊 I like the green bar!", "🤔 What is our next step?", "📝 Adding that to my notes!", "🙌 Great team effort!", "💡 I have a suggestion!", "👏 Count me in!"]
}
const REPLIES := {
	"Alex": ["👋 Happy to be here!", "👍 Going well, boss!", "😊 Thanks, Alex!", "☕ I’ll put a pot on!", "💪 We’ve got this!", "🎉 Best idea all day!"],
	"Maya": ["🌱 Say hi for me!", "☀️ Windows count!", "💧 I'm in!", "😊 So do I!", "🌿 I'm rooting for it!", "💛 Right back at you!"],
	"Jordan": ["🌈 All the colors!", "😂 Frame it!", "✏️ Absolutely!", "🎨 I'm an admirer!", "🖍️ Coming right up!", "✨ Let it create!"],
	"Sam": ["☕ My favorite time!", "😳 Who's counting?", "🍪 I'm on it!", "😂 A bean-ception!", "🔎 Check your hand!", "🏃 Bean power!"],
	"Taylor": ["😱 Didn't see that coming!", "📖 Just one!", "🤓 Tell me more!", "📚 Every time!", "😂 A desk trilogy!", "📝 Naturally!"],
	"Morgan": ["🔌 The classic!", "🙌 Office hero!", "😳 It knows!", "👋 Hello, code!", "🥪 Not again!", "💾 And a backup!"],
	"Casey": ["👋 Glad to join!", "📈 Looking good!", "💡 Plenty of them!", "😄 Make it a good one!", "🙋 I have one!", "👏 Thanks, Casey!"],
	"Riley": ["📝 Share them with me!", "👂 Let’s hear it!", "📊 Agreed!", "👍 Let’s do it!", "👏 Absolutely!", "☕ The best slide!"],
	"Jamie": ["🌱 Very on brand!", "💪 Let’s find out!", "📝 Good thinking!", "🙌 Teamwork!", "👂 I’m listening!", "🎉 Welcome aboard!"]
}
const CLOSERS := ["😊 Back to it!", "👋 See you around!", "😄 You get me!", "✨ Good chat!"]
const FALLBACK := ["👋 Hello there!", "☕ Break time?", "😄 Nice to see you!", "💼 Busy day!"]
const FALLBACK_REPLIES := ["😊 Welcome!", "☕ Count me in!", "👋 You too!", "💪 We've got this!"]
# Single source for the first-day quest giver; all quest branches use this.
const QUEST_GIVER_NAME := "Maya"

static func is_quest_giver(worker: OfficeWorker) -> bool:
	return is_instance_valid(worker) and worker.worker_name == QUEST_GIVER_NAME
var player: OfficePlayer
var speaker: OfficeWorker
var is_open := false
var memories: Dictionary = {}
var current_text := ""
var current_topic := "greeting"
var _memory: Dictionary
var _rendered_quest := -1
var _turn := 0
var _turn_time := 0.0
var _worker_line := ""
var _reply_line := ""
var _closer_line := ""

func setup(p_player: OfficePlayer) -> void:
	player = p_player
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _memory_for(worker: OfficeWorker) -> Dictionary:
	var key := worker.get_instance_id()
	if not memories.has(key):
		memories[key] = {"visits": 0, "rapport": 0, "water_thanked": false}
	return memories[key]

func get_memory(worker: OfficeWorker) -> Dictionary:
	return _memory_for(worker).duplicate(true)

func get_talk_label(worker: OfficeWorker) -> String:
	return "Talk to boss" if worker.is_boss else "Talk"

func open(worker: OfficeWorker) -> bool:
	if is_open and speaker == worker:
		return true
	if not is_instance_valid(worker) or worker == player or worker.combat.is_engaged() or player.combat.is_engaged() or player.seated or is_instance_valid(player.grabbed_furniture):
		return false
	if not player._can_reach_interaction(worker):
		return false
	close()
	if not worker.begin_player_conversation(player):
		return false
	speaker = worker
	_memory = _memory_for(worker)
	var lines: Array = PROFILES.get(worker.worker_name, FALLBACK)
	var visit := int(_memory.visits)
	var replies: Array = REPLIES.get(worker.worker_name, FALLBACK_REPLIES)
	_worker_line = lines[visit % lines.size()]
	_reply_line = replies[visit % replies.size()]
	_closer_line = CLOSERS[(visit + worker.worker_index) % CLOSERS.size()]
	_memory.visits = int(_memory.visits) + 1
	is_open = true
	visible = true
	_turn = 0
	_turn_time = 0.0
	current_topic = "greeting"
	_rendered_quest = player.quest
	player._stop_walking_velocity()
	var direction := worker.global_position - player.global_position
	player.rotation.y = atan2(direction.x, direction.z)
	_show_worker_line()
	if is_instance_valid(player.office.intro):
		player.office.intro.notice_talk()
	player._update_nearby()
	return true

func _show_worker_line() -> void:
	var line := _worker_line
	current_text = line
	player.show_social_speech("")
	speaker.show_social_speech(line)

func refresh_after_quest() -> void:
	if is_open and is_quest_giver(speaker) and _rendered_quest != player.quest:
		_rendered_quest = player.quest
		_turn = 0
		_turn_time = 0.0
		_show_worker_line()

func close() -> void:
	if is_instance_valid(speaker):
		speaker.show_social_speech("")
		speaker.end_player_conversation(player)
	if is_instance_valid(player):
		player.show_social_speech("")
	speaker = null
	is_open = false
	visible = false

func _process(delta: float) -> void:
	if not is_open:
		return
	if not is_instance_valid(player) or not is_instance_valid(speaker) or speaker.is_queued_for_deletion():
		close()
		return
	var menu = player.office.game_menu
	if is_instance_valid(menu) and menu.menu_state == &"title":
		close()
		return
	visible = player.gameplay_visible and not get_tree().paused
	if get_tree().paused:
		return
	if not player.gameplay_visible or speaker.combat.is_engaged() or player.combat.is_engaged() or speaker.player_conversation_partner != player or player.global_position.distance_to(speaker.global_position) > 2.8:
		close()
		return
	_turn_time += delta
	if _turn_time < TURN_SECONDS:
		return
	_turn_time = 0.0
	_turn += 1
	if _turn == 1:
		speaker.show_social_speech("")
		current_text = _reply_line
		player.show_social_speech(current_text)
		OfficeAudio.play_at(player.get_tree(), "pop")
	elif _turn == 2:
		player.show_social_speech("")
		current_text = _closer_line
		speaker.show_social_speech(current_text)
	else:
		close()

func _input(event: InputEvent) -> void:
	if is_open and visible and not get_tree().paused and event is InputEventKey and event.pressed and not event.echo and OfficeInput.matches(event, "interact"):
		get_viewport().set_input_as_handled()
		close()

func _exit_tree() -> void:
	close()
