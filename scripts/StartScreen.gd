extends Control

signal game_started(config: Dictionary)

# Configuration
var selected_map_size: Vector2i = Vector2i(15, 15)
var enable_wrapping: bool = false

# Map size options
var map_sizes = [
    {"name": "10x10", "size": Vector2i(10, 10)},
    {"name": "15x15", "size": Vector2i(15, 15)},
    {"name": "25x25", "size": Vector2i(25, 25)},
    {"name": "35x35", "size": Vector2i(35, 35)},
    {"name": "50x50", "size": Vector2i(50, 50)}
]

func _ready():
    setup_ui()

func setup_ui():
    var vbox = VBoxContainer.new()
    add_child(vbox)
    
    # Center horizontally, position at top with 50px margin
    vbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    vbox.position = Vector2(get_viewport().size.x / 2 - 200, 50)
    vbox.custom_minimum_size = Vector2(400, 300)
    
    # Title
    var title = Label.new()
    title.text = "XBATTLE"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 48)
    vbox.add_child(title)
    
    add_spacer(vbox, 30)
    
    # Map size
    var map_label = Label.new()
    map_label.text = "Map Size:"
    map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    vbox.add_child(map_label)
    
    var map_dropdown = OptionButton.new()
    for map_option in map_sizes:
        map_dropdown.add_item(map_option.name)
    map_dropdown.selected = 1  # Default to 15x15
    map_dropdown.item_selected.connect(_on_map_size_selected)
    vbox.add_child(map_dropdown)
    
    add_spacer(vbox, 20)
    
    # Edge wrapping
    var wrap_checkbox = CheckBox.new()
    wrap_checkbox.text = "Edge Wrapping"
    wrap_checkbox.button_pressed = enable_wrapping
    wrap_checkbox.toggled.connect(_on_wrapping_toggled)
    vbox.add_child(wrap_checkbox)
    
    add_spacer(vbox, 30)
    
    # Game info
    var info_label = Label.new()
    info_label.text = "• 2 Players\n• Hexagonal Tiles\n• 10% Hills, 5% Sea, 10% Towns"
    info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    info_label.add_theme_font_size_override("font_size", 14)
    vbox.add_child(info_label)
    
    add_spacer(vbox, 20)
    
    # Start button
    var start_button = Button.new()
    start_button.text = "START GAME"
    start_button.custom_minimum_size = Vector2(200, 50)
    start_button.pressed.connect(_on_start_game)
    vbox.add_child(start_button)

func add_spacer(parent: Control, height: int):
    var spacer = Control.new()
    spacer.custom_minimum_size = Vector2(0, height)
    parent.add_child(spacer)

func _on_map_size_selected(index: int):
    if index >= 0 and index < map_sizes.size():
        selected_map_size = map_sizes[index].size

func _on_wrapping_toggled(enabled: bool):
    enable_wrapping = enabled

func _on_start_game():
    var config = {
        "map_size": selected_map_size,
        "enable_wrapping": enable_wrapping,
        "hill_density": 10,
        "sea_density": 5,
        "town_density": 10,
        "player_count": 2
    }
    
    game_started.emit(config)

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
            _on_start_game()
        elif event.keycode == KEY_ESCAPE:
            get_tree().quit()
