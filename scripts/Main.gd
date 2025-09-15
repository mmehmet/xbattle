extends Control

var network_manager: NetworkManager

func _ready():
    network_manager = NetworkManager.new()
    add_child(network_manager)
    network_manager.game_started.connect(_on_network_game_started)
    network_manager.connection_failed.connect(_on_connection_failed)
    show_start_screen()

func show_start_screen():
    clear_scene()
    var start_screen = preload("res://StartScreen.tscn").instantiate()
    start_screen.network_manager = network_manager
    add_child(start_screen)

func show_game_screen(config: Dictionary):
    clear_scene()
    var game_scene = preload("res://Game.tscn").instantiate()
    game_scene.setup_game(config, network_manager)
    game_scene.game_ended.connect(_on_game_ended)
    add_child(game_scene)

func clear_scene():
    for child in get_children():
        if child != network_manager:
            child.queue_free()

func _on_local_game_started(config: Dictionary):
    show_game_screen(config)

func _on_network_game_started(config: Dictionary):
    show_game_screen(config)

func _on_connection_failed(error: String):
    print("Network error: %s" % error)
    show_start_screen()

func _on_game_ended():
    if network_manager.is_connected:
        network_manager.disconnect_from_game()
    get_tree().quit()

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_F11:
            toggle_fullscreen()

func toggle_fullscreen():
    var window = get_window()
    if window.mode == Window.MODE_FULLSCREEN:
        window.mode = Window.MODE_WINDOWED
        window.size = Vector2i(1152, 648)
        window.move_to_center()
        # Call board's window setup if we're in game
        for child in get_children():
            if child is NetworkManager and child.game_manager and child.game_manager.board:
                child.game_manager.board.setup_initial_window()
    else:
        window.mode = Window.MODE_FULLSCREEN

    # trigger scaling update
    await get_tree().process_frame
    get_viewport().emit_signal("size_changed")
