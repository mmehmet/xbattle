extends Control

# Game state
enum GameState { SETUP, JOINING, IN_LOBBY }
var current_state: GameState = GameState.SETUP

# Configuration
var selected_map_size: Vector2i = Vector2i(Cell.DEFAULT_BOARD, Cell.DEFAULT_BOARD)
var enable_wrapping: bool = false
var show_troop_numbers: bool = false
var terrain: Dictionary

# Networking
var network_manager: NetworkManager:
    set(value):
        network_manager = value
        if network_manager:
            network_manager.lobby_updated.connect(_on_lobby_updated)
            network_manager.player_joined.connect(_on_player_joined)
            network_manager.player_left.connect(_on_player_left)

var is_host: bool = false
var players: Array = []
var player_name: String = ""

# UI References
var left_panel: VBoxContainer
var right_panel: VBoxContainer
var lobby_container: Control
var player_list: VBoxContainer
var start_button: Button
var join_address_input: LineEdit
var player_name_input: LineEdit
var host_button: Button
var join_button: Button

# Map options
const map_sizes = [
    {"name": "10x10", "size": Vector2i(10, 10)},
    {"name": "15x15", "size": Vector2i(15, 15)},
    {"name": "25x25", "size": Vector2i(25, 25)},
    {"name": "35x35", "size": Vector2i(35, 35)},
    {"name": "50x50", "size": Vector2i(50, 50)}
]
const TERRAIN_LIMITS = {
    "hill": {"max": 30, "min": 10},
    "sea": {"max": 20, "min": 5}, 
    "town": {"max": 12, "min": 6},
    "forest": {"max": 20, "min": 5},
}

func _ready():
    setup_ui()

func setup_ui():
    # Set fixed window size
    get_window().size = Vector2i(1152, 648)
    get_window().move_to_center()

    terrain = {
        "hill": randi_range(TERRAIN_LIMITS.hill.min, TERRAIN_LIMITS.hill.max),
        "forest": randi_range(TERRAIN_LIMITS.forest.min, TERRAIN_LIMITS.forest.max),
        "sea": randi_range(TERRAIN_LIMITS.sea.min, TERRAIN_LIMITS.sea.max),
        "town": randi_range(TERRAIN_LIMITS.town.min, TERRAIN_LIMITS.town.max),
    }
    
    # Main horizontal container
    var margin = MarginContainer.new()
    add_child(margin)
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 50)
    margin.add_theme_constant_override("margin_right", 50)
    margin.add_theme_constant_override("margin_top", 50)
    margin.add_theme_constant_override("margin_bottom", 50)
    var hbox = HBoxContainer.new()
    margin.add_child(hbox)
    hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    hbox.add_theme_constant_override("separation", 20)

    # Left panel
    left_panel = VBoxContainer.new()
    hbox.add_child(left_panel)
    left_panel.custom_minimum_size = Vector2(350, 300)
    left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    
    # Right panel
    right_panel = VBoxContainer.new()
    hbox.add_child(right_panel)
    right_panel.custom_minimum_size = Vector2(350, 300)
    right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    
    # Populate left panel
    show_setup_screen()
    
    # Populate right panel
    show_lobby()

func show_join_screen():
    clear_main_content(right_panel)
    current_state = GameState.JOINING
    update_buttons()
    
    var title = Label.new()
    title.text = "JOIN GAME"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 32)
    right_panel.add_child(title)
    
    add_spacer(right_panel, 30)
    
    var address_label = Label.new()
    address_label.text = "Host Address:"
    right_panel.add_child(address_label)
    
    join_address_input = LineEdit.new()
    join_address_input.text = "127.0.0.1"
    join_address_input.placeholder_text = "Enter host IP address"
    right_panel.add_child(join_address_input)
    
    add_spacer(right_panel, 20)
    
    var connect_button = Button.new()
    connect_button.text = "CONNECT"
    connect_button.custom_minimum_size = Vector2(200, 50)
    connect_button.pressed.connect(_on_connect_to_host)
    right_panel.add_child(connect_button)
    
    add_spacer(right_panel, 20)
    
    var back_button = Button.new()
    back_button.text = "CANCEL JOINING"
    back_button.pressed.connect(_on_cancel_joining)
    right_panel.add_child(back_button)

func show_lobby():
    clear_main_content(right_panel)
    current_state = GameState.IN_LOBBY
    update_buttons()
    
    var title = Label.new()
    title.text = "GAME LOBBY"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 28)
    right_panel.add_child(title)
    
    add_spacer(right_panel, 30)
    
    # Players list
    var players_label = Label.new()
    players_label.text = "Players:"
    right_panel.add_child(players_label)
    
    var panel = Panel.new()
    panel.custom_minimum_size = Vector2(0, 100)
    var style = StyleBoxFlat.new()
    style.bg_color = Color.BLACK
    panel.add_theme_stylebox_override("panel", style)
    var margin = MarginContainer.new()
    margin.custom_minimum_size = Vector2(0, 100)
    margin.add_theme_constant_override("margin_left", 10)
    margin.add_theme_constant_override("margin_right", 10) 
    margin.add_theme_constant_override("margin_top", 5)
    margin.add_theme_constant_override("margin_bottom", 5)

    player_list = VBoxContainer.new()
    player_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_child(player_list)
    panel.add_child(margin)
    right_panel.add_child(panel)
    
    add_spacer(right_panel, 30)
    
    # Start button (host only)
    if is_host:
        start_button = Button.new()
        start_button.text = "START GAME"
        start_button.custom_minimum_size = Vector2(200, 50)
        start_button.disabled = true  # Disabled until 2+ players
        start_button.pressed.connect(_on_start_multiplayer_game)
        right_panel.add_child(start_button)
    
        add_spacer(right_panel, 10)
    
    if players.size() > 0:
        var cancel_button = Button.new()
        cancel_button.text = "CANCEL HOSTING" if is_host else "DISCONNECT"
        cancel_button.pressed.connect(_on_cancel_host if is_host else _on_leave_lobby)
        right_panel.add_child(cancel_button)

    update_player_list()

func show_setup_screen():
    clear_main_content(left_panel)
    current_state = GameState.SETUP
    
    # Title
    var title = Label.new()
    title.text = "XBATTLE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 48)
    left_panel.add_child(title)
    
    add_spacer(left_panel, 30)
    
    # Player name input
    var name_label = Label.new()
    name_label.text = "Player Name:"
    left_panel.add_child(name_label)
    
    player_name_input = LineEdit.new()
    player_name_input.text = "Player"
    player_name_input.placeholder_text = "Enter your name"
    left_panel.add_child(player_name_input)
    
    add_spacer(left_panel, 20)
    
    # Map size
    var map_label = Label.new()
    map_label.text = "Map Size:"
    left_panel.add_child(map_label)
    
    var map_dropdown = OptionButton.new()
    for map_option in map_sizes:
        map_dropdown.add_item(map_option.name)
    map_dropdown.selected = 1  # Default to 15x15
    map_dropdown.item_selected.connect(_on_map_size_selected)
    left_panel.add_child(map_dropdown)
    
    add_spacer(left_panel, 20)
    
    # Game info
    var info_label = Label.new()
    info_label.text = "• %d%% Hills\n• %d%% Forest\n• %d%% Sea\n• %d%% Towns" % [terrain.hill, terrain.forest, terrain.sea, terrain.town]
    left_panel.add_child(info_label)
    
    add_spacer(left_panel, 30)
    
    # Multiplayer buttons
    host_button = Button.new()
    host_button.text = "HOST GAME"
    host_button.custom_minimum_size = Vector2(200, 50)
    host_button.pressed.connect(_on_host_game)
    left_panel.add_child(host_button)
    
    add_spacer(left_panel, 10)
    
    join_button = Button.new()
    join_button.text = "JOIN GAME"
    join_button.custom_minimum_size = Vector2(200, 50)
    join_button.pressed.connect(_on_join_game)
    left_panel.add_child(join_button)

func update_player_list():
    if not player_list or not network_manager:
        return
    
    # Clear existing list
    for child in player_list.get_children():
        child.queue_free()
    
    for player_info in players:
        var player_label = Label.new()
        var suffix = " [HOSTING]" if player_info.is_host else ""
        player_label.text = "%d: %s%s" % [player_info.side, player_info.name, suffix]
        
        if player_info.side < Board.player_colors.size():
            var player_colour = Board.player_colors[player_info.side]
            player_label.modulate = player_colour.lerp(Color.WHITE, 0.3)

        player_list.add_child(player_label)
    
    # Update start button
    if start_button:
        start_button.disabled = players.size() < 2

func clear_main_content(container: VBoxContainer):
    for child in container.get_children():
        child.queue_free()

func add_spacer(parent: Control, height: int):
    var spacer = Control.new()
    spacer.custom_minimum_size = Vector2(0, height)
    parent.add_child(spacer)

# Event handlers
func update_buttons():
    var should_disable = players.size() > 0
    host_button.disabled = should_disable
    join_button.disabled = should_disable

func _on_map_size_selected(index: int):
    if index >= 0 and index < map_sizes.size():
        selected_map_size = map_sizes[index].size

func _on_cancel_host():
    if players.size() > 1:
        # Show confirmation dialog
        var dialog = ConfirmationDialog.new()
        dialog.dialog_text = "Other players are in the lobby. Are you sure you want to stop hosting?"
        dialog.confirmed.connect(_confirm_cancel_host)
        get_tree().root.add_child(dialog)
        dialog.popup_centered()
    else:
        _confirm_cancel_host()

func _on_cancel_joining():
    show_lobby()

func _confirm_cancel_host():
    network_manager.stop_hosting()
    is_host = false
    players.clear()
    show_lobby()

func _on_host_game():
    player_name = player_name_input.text.strip_edges()
    if player_name.is_empty():
        player_name = "Host"
    
    if network_manager.host_game(player_name):
        is_host = true
        players = [{"name": player_name, "is_host": true, "side": 0}]
        show_lobby()

func _on_join_game():
    player_name = player_name_input.text.strip_edges()
    if player_name.is_empty():
        player_name = "Player"
    
    show_join_screen()

func _on_connect_to_host():
    var address = join_address_input.text.strip_edges()
    if address.is_empty():
        return
    
    player_name = player_name_input.text.strip_edges()
    if player_name.is_empty():
        player_name = "Anonymous"

    network_manager.join_game(player_name, address)
    players = [{"name": player_name, "is_host": false, "side": -1}]
    show_lobby()

func _on_leave_lobby():
    network_manager.disconnect_from_game()
    players.clear()
    is_host = false
    show_lobby()

func _on_player_joined(player_info: Dictionary):
    update_player_list()

func _on_player_left(player_info: Dictionary):
    players = players.filter(func(p): return p.peer_id != player_info.peer_id)
    update_player_list()

func _on_lobby_updated(player_list: Array):
    players = player_list
    update_player_list()

func _on_start_multiplayer_game():
    if players.size() < 2:
        return
    
    var config = {
        "map_size": selected_map_size,
        "enable_wrapping": enable_wrapping,
        "show_troop_numbers": show_troop_numbers,
        "player_count": 2,
        "hill_density": terrain.hill,
        "forest_density": terrain.forest,
        "sea_density": terrain.sea,
        "town_density": terrain.town,
    }
    
    network_manager.start_network_game(config)

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
            match current_state:
                GameState.SETUP:
                    _on_host_game()
                GameState.JOINING:
                    _on_connect_to_host()
                GameState.IN_LOBBY:
                    if is_host and start_button and not start_button.disabled:
                        _on_start_multiplayer_game()
        elif event.keycode == KEY_ESCAPE:
            match current_state:
                GameState.SETUP:
                    get_tree().quit()
                GameState.JOINING, GameState.IN_LOBBY:
                    show_setup_screen()
