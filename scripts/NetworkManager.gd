class_name NetworkManager
extends Node

signal player_joined(player_info: Dictionary)
signal player_left(player_info: Dictionary)
signal lobby_updated(players: Array)
signal connection_failed(error: String)
signal game_started(config: Dictionary)
signal game_over(winner: String)

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 11

# Command constants
const CMD_ATTACK = 3
const CMD_DIG = 6
const CMD_FILL = 8
const CMD_BUILD = 10
const CMD_SCUTTLE = 12
const CMD_PARATROOPS = 14
const CMD_ARTILLERY = 16

var multiplayer_peer: MultiplayerPeer
var is_host: bool = false
var connected: bool = false
var players: Dictionary = {}  # peer_id -> player_info
var game_config: Dictionary = {}
var host_player_name: String = ""

# Game state synchronization
var game_manager: GameManager
var host_manager: HostManager

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
    connected = true
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
    host_manager = HostManager.new()
    add_child(host_manager)
    
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
        connected = false
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
        if is_host:
            stop_hosting()
        else:
            rpc_id(1, "_notify_leaving")
        
        multiplayer.multiplayer_peer = null
        connected = false
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
    connected = true
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

@rpc("any_peer", "call_local", "reliable")
func _player_left(player_info: Dictionary):
    if players.has(player_info.peer_id):
        players.erase(player_info.peer_id)
        lobby_updated.emit(_get_player_list())
        if is_host:
            check_victory()

@rpc("any_peer", "call_local", "reliable")
func _on_host_disconnected():
    if not is_host:
        connected = false
        players.clear()
        connection_failed.emit("Host disconnected")

# GAME START/STOP
func start_network_game(config: Dictionary):
    if not is_host or game_config.size() > 0:
        return
    
    game_config = config
    game_config["player_count"] = players.size()
    
    # Start game for all players
    rpc_all_clients("_game_starting", game_config)

@rpc("any_peer", "call_local", "reliable")
func _game_starting(config: Dictionary):
    game_config = config
    
    if is_host:
        # Host generates board and sends to clients, then starts
        _generate_and_send_board(config)

func _generate_and_send_board(config: Dictionary):
    game_started.emit(config)

func serialize_board(board: Board, bases: Array[Cell]) -> Dictionary:
    if host_manager:
        host_manager.setup(self, board, bases)

    var data = []
    for cell in board.cell_list:
        data.append({
            "x": cell.x,
            "y": cell.y,
            "index": cell.index,
            "side": cell.side,
            "troops": cell.troop_values.duplicate(),
            "level": cell.level,
            "growth": cell.growth,
            "directions": cell.direction_vectors
        })
    
    return {
        "width": board.width,
        "height": board.height,
        "cells": data
    }

@rpc("any_peer", "call_local", "reliable")
func _receive_board_data(board_data: Dictionary):
    if is_host:
        print("Host can just use its own board...")
        return

    if game_config.has("board_data"):
        return  # Already received

    game_config["board_data"] = board_data
    print("Client received board data with %d cells" % board_data.cells.size())
    game_started.emit(game_config)

func set_game_manager(gm: GameManager):
    if game_manager != null:
        return

    game_manager = gm

# PLAYER INPUT SYNCHRONIZATION
func send_click(cell: Cell):
    if not connected:
        return
    
    var data = {
        "cell_index": cell.index,
        "side": cell.side,
        "troops": cell.troop_values,
        "level": cell.level,
        "growth": cell.growth,
        "directions": cell.direction_vectors,
    }
    
    rpc_id(1, "_receive_cell_click", data)

@rpc("any_peer", "call_local", "reliable") 
func _receive_cell_click(data: Dictionary):
    if not is_host or not host_manager:
        return

    host_manager.update_cell(data)

func send_command(cell: Cell, command: int, side: int):
    if not connected:
        return
    
    var data = {
        "idx": cell.index,
        "command": command,
        "side": side,
    }
    
    rpc_id(1, "_receive_cell_command", data)

@rpc("any_peer", "call_local", "reliable")
func _receive_cell_command(data: Dictionary):
    if not is_host or not host_manager:
        return

    match data.command:
        CMD_ATTACK: host_manager.execute_attack(data.idx, data.side)
        CMD_DIG: host_manager.execute_dig(data.idx, data.side)
        CMD_FILL: host_manager.execute_fill(data.idx, data.side)
        CMD_BUILD: host_manager.execute_build(data.idx, data.side)
        CMD_SCUTTLE: host_manager.execute_scuttle(data.idx, data.side)
        CMD_PARATROOPS: host_manager.execute_paratroops(data.idx, data.side)
        CMD_ARTILLERY: host_manager.execute_artillery(data.idx, data.side)

func send_cell_delta(cell: Cell, play_sound: bool = false):
    if not is_host:
        return

    var data = {
        "index": cell.index,
        "side": cell.side, 
        "troops": cell.troop_values,
        "level": cell.level,
        "growth": cell.growth,
        "play_sound": play_sound,
    }
    
    for player in players.values():
        rpc_id(player.peer_id, "_receive_cell_delta", data)

@rpc("any_peer", "call_local", "reliable")
func _receive_cell_delta(data: Dictionary):
    if not game_manager or not game_manager.board:
        return
    
    var cell = game_manager.board.get_cell_by_index(data.index)
    if cell:
        cell.side = data.side
        cell.troop_values = data.troops
        cell.level = data.level
        cell.growth = data.growth

        game_manager.board.update_fog(data.side, cell)
        game_manager.board.queue_redraw()
        
        if data.get("play_sound", false):
            game_manager.play_success_sound()

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
    return connected and players.size() >= 2

# CONNECTION EVENT HANDLERS
func _on_peer_connected(peer_id: int):
    print("Peer %d connected" % peer_id)

func _on_peer_disconnected(peer_id: int):
    print("Peer %d disconnected" % peer_id)
    
    if players.has(peer_id):
        var player_info = players[peer_id]
        players.erase(peer_id)
        if is_host:
            rpc_all_clients("_player_left", player_info)

func _on_connection_failed():
    connection_failed.emit("Connection failed")
    multiplayer.multiplayer_peer = null

func _on_connected_to_server():
    print("Connected to server")
    connected = true

func _on_server_disconnected():
    print("Server disconnected")
    connected = false
    players.clear()
    connection_failed.emit("Server disconnected")

func update_active(active: Array):
    for peer_id in players.keys():
        if players[peer_id].side not in active:
            players.erase(peer_id)

func check_victory():
    if players.values().size() < 2:
        var winner = ""
        if players.size() == 1:
            winner = players.values()[0].name
        rpc_all_clients("_game_over", winner)

@rpc("any_peer", "call_local", "reliable")
func _game_over(winner: String):
    game_over.emit(winner)

func rpc_all_clients(method: String, arg1 = null, arg2 = null, arg3 = null):
    if arg3 != null:
        rpc(method, arg1, arg2, arg3)
    elif arg2 != null:
        rpc(method, arg1, arg2)
    elif arg1 != null:
        rpc(method, arg1)
    else:
        rpc(method)
