class_name NetworkManager
extends Node

signal player_joined(player_info: Dictionary)
signal player_left(player_info: Dictionary)
signal lobby_updated(players: Array)
signal connection_failed(error: String)
signal game_started(config: Dictionary)

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 11

var multiplayer_peer: MultiplayerPeer
var is_host: bool = false
var is_connected: bool = false
var players: Dictionary = {}  # peer_id -> player_info
var game_config: Dictionary = {}
var host_player_name: String = ""

# Game state synchronization
var game_manager: GameManager
var pending_commands: Array = []
var last_sync_time: float = 0.0
var sync_interval: float = 0.1  # 10 FPS for network updates

func _ready():
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

# HOST FUNCTIONS
func host_game(player_name: String, port: int = DEFAULT_PORT) -> bool:
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(port, MAX_PLAYERS)
    
    if error != OK:
        connection_failed.emit("Failed to create server on port %d" % port)
        return false
    
    multiplayer.multiplayer_peer = peer
    multiplayer_peer = peer
    is_host = true
    is_connected = true
    host_player_name = player_name
    
    # Add host as first player
    var host_info = {
        "name": player_name,
        "side": 0,
        "is_host": true,
        "connected": true,
        "peer_id": 1
    }
    players[1] = host_info
    
    print("Server started on port %d" % port)
    player_joined.emit(host_info)
    return true

func stop_hosting():
    if is_host and multiplayer_peer:
        # Notify all clients
        rpc_all_clients("_on_host_disconnected")
        
        # Close the server
        multiplayer_peer.close()
        multiplayer.multiplayer_peer = null
        is_host = false
        is_connected = false
        players.clear()
        print("Stopped hosting")

# CLIENT FUNCTIONS  
func join_game(player_name: String, address: String, port: int = DEFAULT_PORT) -> bool:
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_client(address, port)
    
    if error != OK:
        connection_failed.emit("Failed to connect to %s:%d" % [address, port])
        return false
    
    multiplayer.multiplayer_peer = peer
    multiplayer_peer = peer
    is_host = false
    
    # Send join request when connected
    await multiplayer.connected_to_server
    rpc_id(1, "_request_join", player_name)
    return true

func disconnect_from_game():
    if multiplayer_peer:
        if not is_host:
            rpc_id(1, "_notify_leaving")
        
        multiplayer.multiplayer_peer = null
        is_connected = false
        players.clear()
        print("Disconnected from game")

# LOBBY MANAGEMENT
@rpc("any_peer", "call_local", "reliable")
func _request_join(player_name: String):
    if not is_host:
        return
    
    var peer_id = multiplayer.get_remote_sender_id()
    var side = _find_next_available_side()
    
    if side == -1:
        rpc_id(peer_id, "_join_rejected", "Game is full")
        return
    
    var player_info = {
        "name": player_name,
        "side": side,
        "is_host": false,
        "connected": true,
        "peer_id": peer_id
    }
    
    players[peer_id] = player_info
    
    # Send current lobby state to new player
    rpc_id(peer_id, "_join_accepted", player_info, _get_player_list())
    
    # Notify all other players
    rpc_all_clients("_player_joined", player_info)
    
    player_joined.emit(player_info)
    print("Player %s joined as side %d" % [player_name, side])

@rpc("any_peer", "call_local", "reliable")
func _join_accepted(my_info: Dictionary, player_list: Array):
    is_connected = true
    players.clear()
    
    # Rebuild players dictionary
    for player in player_list:
        players[player.peer_id] = player
    
    print("Joined game as side %d" % my_info.side)
    lobby_updated.emit(player_list)

@rpc("any_peer", "call_local", "reliable")
func _join_rejected(reason: String):
    connection_failed.emit(reason)
    multiplayer.multiplayer_peer = null

@rpc("any_peer", "call_local", "reliable")
func _player_joined(player_info: Dictionary):
    players[player_info.peer_id] = player_info
    player_joined.emit(player_info)
    lobby_updated.emit(_get_player_list())

@rpc("any_peer", "call_local", "reliable")
func _notify_leaving():
    if not is_host:
        return
    
    var peer_id = multiplayer.get_remote_sender_id()
    if players.has(peer_id):
        var player_info = players[peer_id]
        players.erase(peer_id)
        
        # Notify remaining players
        rpc_all_clients("_player_left", player_info)
        player_left.emit(player_info)

@rpc("any_peer", "call_local", "reliable")
func _player_left(player_info: Dictionary):
    if players.has(player_info.peer_id):
        players.erase(player_info.peer_id)
        player_left.emit(player_info)
        lobby_updated.emit(_get_player_list())

@rpc("any_peer", "call_local", "reliable")
func _on_host_disconnected():
    if not is_host:
        is_connected = false
        players.clear()
        connection_failed.emit("Host disconnected")

# GAME START/STOP
func start_network_game(config: Dictionary):
    if not is_host:
        return
    
    game_config = config
    game_config["player_count"] = players.size()
    
    # Start game for all players
    rpc_all_clients("_game_starting", game_config)
    _game_starting(game_config)

@rpc("any_peer", "call_local", "reliable")
func _game_starting(config: Dictionary):
    game_config = config
    game_started.emit(config)

# GAME STATE SYNCHRONIZATION
func set_game_manager(gm: GameManager):
    game_manager = gm
    if game_manager:
        game_manager.board_updated.connect(_on_board_updated)

func _process(delta):
    if not is_connected or not game_manager:
        return
    
    last_sync_time += delta
    if last_sync_time >= sync_interval:
        last_sync_time = 0.0
        
        if is_host:
            _send_board_state()
        
        _process_pending_commands()

# HOST: Send compressed board state to clients
func _send_board_state():
    if not is_host or not game_manager or not game_manager.board:
        return
    
    var changed_cells = []
    for cell in game_manager.board.cell_list:
        if cell.outdated:  # Flag set when cell changes
            changed_cells.append({
                "index": cell.index,
                "side": cell.side,
                "troops": cell.troop_values.duplicate(),
                "level": cell.level,
                "growth": cell.growth,
                "directions": cell.direction_vectors.duplicate(),
                "age": cell.age
            })
            cell.outdated = false
    
    if changed_cells.size() > 0:
        rpc_all_clients("_receive_board_update", changed_cells)

# CLIENT: Receive and apply board state
@rpc("any_peer", "call_local", "unreliable")
func _receive_board_update(changed_cells: Array):
    if is_host or not game_manager or not game_manager.board:
        return
    
    for cell_data in changed_cells:
        var cell = game_manager.board.get_cell_by_index(cell_data.index)
        if cell:
            cell.side = cell_data.side
            cell.troop_values = cell_data.troops
            cell.level = cell_data.level
            cell.growth = cell_data.growth
            cell.direction_vectors = cell_data.directions
            cell.age = cell_data.age
    
    if changed_cells.size() > 0:
        game_manager.board.queue_redraw()

# PLAYER INPUT SYNCHRONIZATION
func send_cell_command(cell: Cell, command: int):
    if not is_connected or not game_manager:
        return
    
    var command_data = {
        "cell_index": cell.index,
        "command": command,
        "timestamp": Time.get_ticks_msec()
    }
    
    if is_host:
        _process_cell_command(command_data)
    else:
        rpc_id(1, "_receive_cell_command", command_data)

func send_cell_click(cell: Cell, direction_mask: int):
    if not is_connected or not game_manager:
        return
    
    var click_data = {
        "cell_index": cell.index,
        "direction_mask": direction_mask,
        "timestamp": Time.get_ticks_msec()
    }
    
    if is_host:
        _process_cell_click(click_data)
    else:
        rpc_id(1, "_receive_cell_click", click_data)

@rpc("any_peer", "call_local", "reliable")
func _receive_cell_command(command_data: Dictionary):
    if not is_host:
        return
    
    pending_commands.append(command_data)

@rpc("any_peer", "call_local", "reliable") 
func _receive_cell_click(click_data: Dictionary):
    if not is_host:
        return
    
    pending_commands.append(click_data)

func _process_pending_commands():
    if not is_host or not game_manager:
        return
    
    for command in pending_commands:
        if command.has("command"):
            _process_cell_command(command)
        else:
            _process_cell_click(command)
    
    pending_commands.clear()

func _process_cell_command(command_data: Dictionary):
    var cell = game_manager.board.get_cell_by_index(command_data.cell_index)
    if cell:
        game_manager.on_cell_command(cell, command_data.command)
        cell.outdated = true

func _process_cell_click(click_data: Dictionary):
    var cell = game_manager.board.get_cell_by_index(click_data.cell_index)
    if cell:
        game_manager.on_cell_click(cell, click_data.direction_mask)
        cell.outdated = true

# UTILITY FUNCTIONS
func _find_next_available_side() -> int:
    for side in range(MAX_PLAYERS):
        var side_taken = false
        for player in players.values():
            if player.side == side:
                side_taken = true
                break
        if not side_taken:
            return side
    return -1

func _get_player_list() -> Array:
    var player_list = []
    for player in players.values():
        player_list.append(player)
    
    # Sort by side for consistent display
    player_list.sort_custom(func(a, b): return a.side < b.side)
    return player_list

func get_my_player_info() -> Dictionary:
    var my_id = multiplayer.get_unique_id()
    return players.get(my_id, {})

func get_player_count() -> int:
    return players.size()

func is_game_ready() -> bool:
    return is_connected and players.size() >= 2

# CONNECTION EVENT HANDLERS
func _on_peer_connected(peer_id: int):
    print("Peer %d connected" % peer_id)

func _on_peer_disconnected(peer_id: int):
    print("Peer %d disconnected" % peer_id)
    
    if players.has(peer_id):
        var player_info = players[peer_id]
        players.erase(peer_id)
        
        if is_host:
            # Notify remaining players
            rpc_all_clients("_player_left", player_info)
        
        player_left.emit(player_info)

func _on_connection_failed():
    connection_failed.emit("Connection failed")
    multiplayer.multiplayer_peer = null

func _on_connected_to_server():
    print("Connected to server")
    is_connected = true

func _on_server_disconnected():
    print("Server disconnected")
    is_connected = false
    players.clear()
    connection_failed.emit("Server disconnected")

func _on_board_updated():
    # Called when game board updates - mark relevant cells as outdated
    # This is handled by individual cell changes in the game manager
    pass

# RPC HELPERS
func rpc_all_clients(method: String, arg1 = null, arg2 = null, arg3 = null):
    if arg3 != null:
        rpc(method, arg1, arg2, arg3)
    elif arg2 != null:
        rpc(method, arg1, arg2)
    elif arg1 != null:
        rpc(method, arg1)
    else:
        rpc(method)
