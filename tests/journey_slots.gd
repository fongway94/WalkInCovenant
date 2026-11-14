extends Node
## Run with an isolated HOME: this intentionally exercises user:// save files.
## A replay must not erase the player's original save, including when a slot or
## the selector cannot be read/written. Browser interaction is tested separately.

var checks := 0
var failures := 0


func _ready() -> void:
	_run()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if ok:
		print("PASS journey slots: " + message)
	else:
		failures += 1
		printerr("FAIL journey slots: " + message)


func _run() -> void:
	GameState.erase()
	GameState._load_selected_on_startup()
	_check(not GameState.save_protected() and not GameState.replay_is_active(),
		"a first run with no save is not mistaken for an unreadable one")
	GameState.data["settings"]["sound"] = false
	GameState.data["settings"]["music"] = false
	AudioDirector._muted_by_focus = false
	AudioDirector.apply_settings()
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	_check(music_bus >= 0 and sfx_bus >= 0 and AudioServer.is_bus_mute(music_bus)
		and AudioServer.is_bus_mute(sfx_bus), "the original journey begins with both buses muted")
	GameState.data["level"] = 3
	GameState.data["words"] = ["original_verse"]
	GameState.data["flags"] = {"elah_ended": true, "goliath_down": true, "original_marker": 42}
	GameState.data["progress"] = {"act": "done", "stones": 5, "pos": [16, 44]}
	_check(GameState.save_game(), "a completed original journey is saved")
	var main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main._update_guidance()
	_check(main.hud.objective_lbl.text == I18n.t(main.region.model.objectives["done"]),
		"a completed save names the end rather than offering a false next objective")
	_check(main.act_id() == "done" and not main.runner.running,
		"a completed save resumes free roam, not the aftermath mission")
	main._open_journal()
	var book: Journal = main.journal
	_check(book.is_open() and book._journey_btn.text == book._t("start_replay"),
		"the book offers a replay without changing the save")
	book._on_journey_button()
	_check(book._confirming and book._journey_btn.text == book._t("confirm"),
		"replay first asks for explicit confirmation")
	var current := GameState.data.duplicate(true)
	book._on_journey_button()
	_check(book._confirming and GameState.data == current and not GameState.has_replay(),
		"the same tap cannot also confirm the switch")
	I18n.toggle()
	_check(book._confirming and book._journey_btn.text == book._t("confirm"),
		"switching language keeps the confirmation open and translated")
	book.close_panel()
	_check(book.is_open() and not book._confirming, "cancel returns to the book")
	book.close_panel()
	_check(not book.is_open(), "close returns to the original journey")
	main.queue_free()
	await get_tree().process_frame

	_check(GameState.switch_journey(), "an explicit switch creates a separate replay")
	_check(GameState.replay_is_active() and GameState.has_replay()
		and not bool(GameState.flag("elah_ended")) and int(GameState.data["level"]) == 1,
		"the replay starts at the beginning rather than the completed state")
	_check(not bool(GameState.data["settings"]["sound"]) and AudioServer.is_bus_mute(music_bus)
		and AudioServer.is_bus_mute(sfx_bus), "the replay initially inherits the original mute settings")
	# The slots may later have different settings. A switch/reload changes the
	# whole settings dictionary, not a single HUD setting, and must update both
	# persistent audio buses as well as the save data.
	GameState.data["settings"]["sound"] = true
	GameState.data["settings"]["music"] = true
	AudioDirector.apply_settings()
	_check(not AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus),
		"the replay can independently turn sound on")
	var original := GameState._read_save(GameState.SAVE_PATH)
	_check(bool(original["flags"].get("elah_ended")) and int(original["flags"].get("original_marker")) == 42
		and original["words"] == ["original_verse"], "the original save remains intact in its old location")
	GameState.set_flag("replay_marker", 73)
	GameState.data["progress"] = {"act": "witness", "pos": [12, 41]}
	_check(GameState.save_game(), "the replay has its own persisted progress")
	GameState.active_slot = GameState.ORIGINAL_SLOT
	GameState.new_game()
	GameState.active_slot = GameState._read_selected_slot()
	_check(GameState.replay_is_active() and GameState.load_game()
		and int(GameState.flag("replay_marker", 0)) == 73, "a cold boot selects and resumes the replay")
	_check(GameState.switch_journey() and not GameState.replay_is_active()
		and bool(GameState.flag("elah_ended")) and int(GameState.flag("original_marker", 0)) == 42,
		"returning to the original restores its completion and rewards")
	_check(AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(sfx_bus),
		"returning to the muted original immediately mutes both persistent buses")
	GameState.set_flag("original_later", true)
	_check(GameState.switch_journey() and GameState.replay_is_active()
		and int(GameState.flag("replay_marker", 0)) == 73, "the replay resumes where it stopped")
	_check(not AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus),
		"returning to the unmuted replay immediately restores both buses")
	_check(GameState.switch_journey() and bool(GameState.flag("original_later")),
		"both journeys keep changes made after switching")

	# A selector write failure must leave the active slot and both saves alone.
	var tmp := GameState.SLOT_PATH + ".tmp"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	DirAccess.make_dir_absolute(tmp)
	_check(not GameState.switch_journey() and not GameState.replay_is_active()
		and bool(GameState.flag("original_later")), "a selector write failure keeps the current journey")
	DirAccess.remove_absolute(tmp)
	_check(GameState._read_selected_slot() == GameState.ORIGINAL_SLOT,
		"a failed switch does not persist a different selection")

	# Do not create a new replay over unreadable bytes: they may be recoverable.
	var f := FileAccess.open(GameState.REPLAY_PATH, FileAccess.WRITE)
	f.store_string("not-json-preserve-me")
	f.close()
	if FileAccess.file_exists(GameState.REPLAY_PATH + ".bak"):
		DirAccess.remove_absolute(GameState.REPLAY_PATH + ".bak")
	_check(GameState.has_replay() and not GameState.switch_journey() and not GameState.replay_is_active(),
		"an unreadable replay is not replaced with a fresh one")
	var bad := FileAccess.open(GameState.REPLAY_PATH, FileAccess.READ)
	_check(bad.get_as_text() == "not-json-preserve-me" and bool(GameState.flag("original_later")),
		"failed recovery preserves both the unreadable file and the original journey")
	bad.close()

	# On a cold boot with a damaged replay, keep it and fall back to the intact
	# original rather than silently creating a fresh replay over it.
	GameState._write_json(GameState.SLOT_PATH, {"active": GameState.REPLAY_SLOT})
	GameState._load_selected_on_startup()
	_check(not GameState.replay_is_active() and not GameState.save_protected()
		and bool(GameState.flag("original_later")),
		"an unreadable selected replay falls back to the intact original")
	_check(FileAccess.get_file_as_string(GameState.REPLAY_PATH) == "not-json-preserve-me",
		"the failed cold replay boot preserves its bytes")

	# Loading a good backup, a blocked temporary write, and a later successful
	# repair must never copy a corrupt primary over that good backup.
	GameState.erase()
	GameState.set_flag("backup_marker", 101)
	_check(GameState.save_game(), "the recovery fixture writes a first save")
	GameState.set_flag("backup_marker", 202)
	_check(GameState.save_game(), "the next save creates a previous good backup")
	var good_backup := FileAccess.get_file_as_string(GameState.SAVE_BAK)
	var primary := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	primary.store_string("damaged-primary")
	primary.close()
	GameState._load_selected_on_startup()
	_check(not GameState.save_protected() and int(GameState.flag("backup_marker", 0)) == 101,
		"a cold boot recovers the original journey from its readable backup")
	DirAccess.make_dir_absolute(GameState.SAVE_TMP)
	GameState.set_flag("after_recovery", true)
	_check(not GameState.save_game() and FileAccess.get_file_as_string(GameState.SAVE_BAK) == good_backup
		and FileAccess.get_file_as_string(GameState.SAVE_PATH) == "damaged-primary",
		"a failed replacement preserves both corrupt primary bytes and the good backup")
	DirAccess.remove_absolute(GameState.SAVE_TMP)
	_check(GameState.save_game() and FileAccess.get_file_as_string(GameState.SAVE_BAK) == good_backup
		and bool(GameState._read_save(GameState.SAVE_PATH)["flags"].get("after_recovery", false)),
		"a later repair replaces only the primary and leaves the good backup intact")

	# A failure preparing the *next* backup must not truncate the old one. The
	# main save can still be atomically replaced, while the prior backup survives.
	var backup_tmp := GameState.SAVE_BAK + ".tmp"
	DirAccess.make_dir_absolute(backup_tmp)
	GameState.set_flag("after_backup_failure", true)
	_check(GameState.save_game() and FileAccess.get_file_as_string(GameState.SAVE_BAK) == good_backup
		and bool(GameState._read_save(GameState.SAVE_PATH)["flags"].get("after_backup_failure", false)),
		"a failed backup copy leaves the last good backup intact")
	DirAccess.remove_absolute(backup_tmp)

	# Force a real file-to-directory rename failure, with a good backup in place.
	var blocked := "user://slot-rename-blocked.json"
	var backup := FileAccess.open(blocked + ".bak", FileAccess.WRITE)
	backup.store_string('{"marker":"keep"}')
	backup.close()
	DirAccess.make_dir_absolute(blocked)
	_check(not GameState._write_json(blocked, {"marker": "new"})
		and str(GameState._read_slot_save(blocked).get("marker", "")) == "keep",
		"a failed destination rename is reported and the backup remains readable")
	DirAccess.remove_absolute(blocked + ".tmp")
	DirAccess.remove_absolute(blocked + ".bak")
	DirAccess.remove_absolute(blocked)

	# If neither original nor backup can be read, even lifecycle autosaves must
	# not replace them with a new game. The player is told before they can play.
	GameState.erase()
	var broken := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	broken.store_string("original-needs-recovery")
	broken.close()
	GameState._load_selected_on_startup()
	GameState._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(GameState.save_protected() and not GameState.save_game()
		and FileAccess.get_file_as_string(GameState.SAVE_PATH) == "original-needs-recovery",
		"an unreadable original is protected from normal and lifecycle autosaves")
	I18n.set_lang("en")
	var recovery_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(recovery_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var recovery_book: Journal = recovery_main.journal
	var notice := false
	for row in recovery_book._body.get_children():
		if row is Label and str(row.text).contains("progress this session will not be saved"):
			notice = true
	_check(recovery_book.is_open() and recovery_book._journey_btn.disabled and notice,
		"the book opens with a clear unsaved-progress warning and disables switching")
	recovery_main.queue_free()
	await get_tree().process_frame
	print("journey slots: %d checks, %d failures" % [checks, failures])
	GameState.erase()
	get_tree().quit(0 if failures == 0 else 1)
