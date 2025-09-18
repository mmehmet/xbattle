class_name GameManager
extends Node

var network_manager: NetworkManager
var music: AudioStreamPlayer
var track: int = 0
var loops: int = 0
var target: int = 0 

# Game state
@export var board: Board
@export var current_player: int = 0
@export var player_count: int = 2
@export var game_speed: float = 1.0
@export var is_paused: bool = false

# Signals for UI updates
signal cell_changed(cell: Cell)

func _ready():
    print("GameManager ready")

# Initialize a new game
func start_new_game(config: Dictionary):
    var width = config.map_size.x
    var height = config.map_size.y
    player_count = config.player_count

    print("Starting new game: %dx%d board, %d players" % [width, height, player_count])
    if network_manager and network_manager.is_host and not config.has("board_data"):
        # Host generates and sends board data to clients
        board = Board.new(width, height)
        board.generate_terrain(config.hill_density, config.sea_density, config.forest_density)
        board.place_random_towns(config.town_density)
        var bases = board.place_player_bases(player_count)
        print("Host generated board, playing as side %d" % current_player)
        
        var board_data = network_manager.serialize_board(board, bases)
        network_manager.rpc_all_clients("_receive_board_data", board_data)
        config["board_data"] = board_data  # So we take client path below
    
    # Get MY player side from network manager
    current_player = 0
    if network_manager:
        var my_info = network_manager.get_my_player_info()
        current_player = my_info.get("side", 0)
    
    if not config.has("board_data"):
        return
    
    is_paused = false

    # Client: receive board from host
    board = _deserialize_board(config.board_data)
    if board:
        print("PLAYER %d received board from host" % current_player)
        board.update_fog(current_player, board.get_cells_for_side(current_player)[0])

    start_music()

func _deserialize_board(data: Dictionary) -> Board:
    if (network_manager and network_manager.is_host and board):
        return board

    print("Deserializing board with %d cells" % data.cells.size())
    var temp = Board.new(data.width, data.height)
    for cell_data in data.cells:
        var cell = temp.get_cell_by_index(cell_data.index)
        cell.side = cell_data.side
        cell.troop_values = cell_data.troops
        cell.level = cell_data.level
        cell.growth = cell_data.growth
        cell.direction_vectors = cell_data.directions
    
    return temp

func on_cell_click(cell: Cell, direction_mask: int):
    if cell.side != current_player:
        return
    
    # Toggle the clicked direction
    for i in Cell.MAX_DIRECTIONS:
        if (direction_mask & (1 << i)) != 0:
            var current_state = cell.direction_vectors[i]
            cell.set_direction(i, not current_state)
    
    network_manager.send_click(cell)

func on_cell_command(command: int, target: Cell, source: Cell):
    network_manager.send_command(command, target, source, current_player)

# Game control functions
func pause_game():
    is_paused = true
    print("Game paused")

func resume_game():
    is_paused = false
    print("Game resumed")

func set_game_speed(speed: float):
    game_speed = clamp(speed, 0.1, 5.0)
    print("Game speed set to %fx" % game_speed)

func setup_network(nm: NetworkManager):
    network_manager = nm
    print("DEBUG: GameManager.setup_network, nm.is_host=%s" % nm.is_host)
    nm.set_game_manager(self)

# Get game statistics
func get_game_stats() -> Dictionary:
    if not board:
        return {}
    
    var stats = board.get_stats()
    stats["current_player"] = current_player
    stats["player_count"] = player_count
    stats["is_paused"] = is_paused
    stats["game_speed"] = game_speed
    
    return stats

# Misc
func play_success_sound():
   var audio = AudioStreamPlayer.new()
   add_child(audio)
   audio.stream = load("res://assets/dirt.mp3")
   audio.play()
   audio.finished.connect(func(): audio.queue_free())

func start_music():
    if not is_inside_tree():
        call_deferred("start_music")
        return

    if not music:
        music = AudioStreamPlayer.new()
        add_child(music)
        music.volume_db = -10
        music.finished.connect(_on_music_done)

    music.stream = load("res://assets/destiny_awaits.mp3")
    target = randi_range(3, 8)
    music.play()

func toggle_music():
    if music:
        if music.playing:
            music.stop()
        else:
            music.play()

func _on_music_done():
    loops += 1
    
    if track == 0 and loops >= target:
        track = 1
        loops = 0
        target = randi_range(2, 5)
        music.stream = load("res://assets/march_to_freedom.mp3")
    elif track == 1 and loops >= target:
        track = 0
        loops = 0
        target = randi_range(3, 8)
        music.stream = load("res://assets/destiny_awaits.mp3")
    
    music.play()
