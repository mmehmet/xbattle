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
    show_start_screen()
