extends Control

signal game_ended

var game_manager: GameManager
var board: Board

func setup_game(config: Dictionary):
    print("Setting up game with config: %s" % config)
    
    # Create game manager
    game_manager = GameManager.new()
    add_child(game_manager)
    
    # Start the game with configuration
    var map_size = config.get("map_size", Vector2i(15, 15))
    var player_count = config.get("player_count", 2)
    
    game_manager.start_new_game(map_size.x, map_size.y, player_count)
    
    # Use board from game manager
    board = game_manager.board
    add_child(board)
    board.game_manager = game_manager
    
    # Connect signals
    game_manager.board_updated.connect(_on_board_updated)
    game_manager.game_over.connect(_on_game_over)

func _on_board_updated():
    if board:
        board.on_board_updated()

func _on_game_over(winner: int):
    print("Game over, winner: %d" % winner)
    # For now, return to start screen after 3 seconds
    await get_tree().create_timer(3.0).timeout
    game_ended.emit()

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            game_ended.emit()
