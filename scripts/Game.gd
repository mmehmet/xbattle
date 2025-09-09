extends Control

signal game_ended

var game_manager: GameManager
var board: Board

func setup_game(config: Dictionary, network_mgr: NetworkManager = null):
    game_manager = GameManager.new()
    add_child(game_manager)
    
    # Setup network if provided
    if network_mgr:
        game_manager.setup_network(network_mgr)
    
    game_manager.start_new_game(config)
    
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
    
    var viewport = get_window().get_visible_rect().size
    var panel = Panel.new()
    var style = StyleBoxFlat.new()
    panel.size = Vector2(viewport.x, viewport.y)
    panel.position = Vector2(0, 0)
    style.bg_color = Color(0.5, 0.5, 0.5, 0.5)
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    
    var vbox = VBoxContainer.new()
    vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    vbox.add_theme_constant_override("separation", 20)
    panel.add_child(vbox)
    
    var label = Label.new()
    label.text = "Player %d Wins!" % winner if winner >= 0 else "Draw!"
    label.add_theme_font_size_override("font_size", 48)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(label)
    
    var button = Button.new()
    button.text = "Return to Menu"
    button.pressed.connect(func(): game_ended.emit())
    vbox.add_child(button)
    
    await get_tree().create_timer(5.0).timeout
    game_ended.emit()

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            game_ended.emit()
        elif event.keycode == KEY_Q:
            game_manager.concede_defeat()
