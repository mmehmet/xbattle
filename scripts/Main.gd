extends Control

# Game configuration passed between scenes
var game_config = {
    "map_size": Vector2i(15, 15),
    "enable_wrapping": false,
    "hill_density": 10,
    "sea_density": 5,
    "town_density": 10,
    "player_count": 2
}

func _ready():
    show_start_screen()

func show_start_screen():
    clear_scene()
    var start_screen = preload("res://StartScreen.tscn").instantiate()
    start_screen.game_started.connect(_on_game_started)
    add_child(start_screen)

func show_game_screen():
    clear_scene()
    var game_scene = preload("res://Game.tscn").instantiate()
    game_scene.setup_game(game_config)
    game_scene.game_ended.connect(_on_game_ended)
    add_child(game_scene)

func clear_scene():
    for child in get_children():
        child.queue_free()

func _on_game_started(config: Dictionary):
    game_config = config
    show_game_screen()

func _on_game_ended():
    show_start_screen()
