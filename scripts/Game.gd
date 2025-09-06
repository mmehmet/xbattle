extends Control

signal game_ended

var game_manager: GameManager
var board_renderer: BoardRenderer

func setup_game(config: Dictionary):
    print("Setting up game with config: %s" % config)
    
    # Create game manager
    game_manager = GameManager.new()
    add_child(game_manager)
    
    # Create board renderer
    board_renderer = BoardRenderer.new()
    add_child(board_renderer)
    
    # Connect signals
    game_manager.board_updated.connect(_on_board_updated)
    game_manager.game_over.connect(_on_game_over)
    
    # Start the game with configuration
    var map_size = config.get("map_size", Vector2i(15, 15))
    var player_count = config.get("player_count", 2)
    
    game_manager.start_new_game(map_size.x, map_size.y, player_count)
    
    # Configure renderer
    board_renderer.game_manager = game_manager
    board_renderer.board = game_manager.board

func _on_board_updated():
    if board_renderer:
        board_renderer._on_board_updated()

func _on_game_over(winner: int):
    print("Game over, winner: %d" % winner)
    # For now, return to start screen after 3 seconds
    await get_tree().create_timer(3.0).timeout
    game_ended.emit()

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            game_ended.emit()
