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
        network_mgr.game_over.connect(_on_game_over)
    
    game_manager.start_new_game(config)
    
    # Use board from game manager
    board = game_manager.board
    add_child(board)
    board.game_manager = game_manager

func _on_game_over(winner: String):
    print("Game over! %s was the winner" % winner)
    
    var viewport = get_window().get_visible_rect().size
    var panel = Panel.new()
    var style = StyleBoxFlat.new()
    panel.size = viewport
    panel.position = Vector2(0, 0)
    style.bg_color = Color(0.5, 0.5, 0.5, 0.5)
    panel.add_theme_stylebox_override("panel", style)
    add_child(panel)
    
    var vbox = VBoxContainer.new()
    if get_window().mode == Window.MODE_FULLSCREEN:
        var s = viewport.x / 1152.0
        vbox.scale = Vector2(s, s)
        vbox.position = Vector2(0, (viewport.y - 648 * s) * 0.5)
        vbox.size = Vector2(1152, 648)
    else:
        get_window().size = Vector2i(1152, 648)
        vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    vbox.add_theme_constant_override("separation", 20)
    panel.add_child(vbox)
    
    var label = Label.new()
    if game_manager.network_manager:
        var check = game_manager.network_manager.get_my_player_info()
        if check.name and check.name == winner:
            winner = "You"
    label.text = "%s won the battle!" % winner if winner != "" else "Draw!"
    label.add_theme_font_size_override("font_size", 48)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(label)

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            game_ended.emit()
        elif event.keycode == KEY_M:
            game_manager.toggle_music()
        elif event.keycode == KEY_Q:
            _concede()

func _concede():
    if game_manager.network_manager:
        game_manager.network_manager.rpc_id(1, "_notify_leaving")
