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

func send_cell_delta(cell: Cell):
    if is_host:
        var cell_data = {
            "index": cell.index,
            "side": cell.side, 
            "troops": cell.troop_values,
            "level": cell.level,
            "growth": cell.growth
        }
        rpc("_receive_cell_delta", cell_data)

@rpc("any_peer", "reliable")
func _receive_cell_delta(cell_data: Dictionary):
    if is_host or not game_manager or not game_manager.board:
        return
    
    var cell = game_manager.board.get_cell_by_index(cell_data.index)
    if cell:
        cell.side = cell_data.side
        cell.troop_values = cell_data.troops
        cell.level = cell_data.level
        cell.growth = cell_data.growth
        game_manager.board.queue_redraw()

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

func serialize_board(board: Board) -> Dictionary:
    if host_manager:
        host_manager.setup(self, board)

    var cell_data = []
    for cell in board.cell_list:
        cell_data.append({
            "x": cell.x, "y": cell.y, "index": cell.index,
            "side": cell.side, "troops": cell.troop_values.duplicate(),
            "level": cell.level, "growth": cell.growth
        })
    
    return {
        "width": board.width,
        "height": board.height,
        "cells": cell_data
    }

@rpc("any_peer", "call_local", "reliable")
func _receive_board_data(board_data: Dictionary):
    if is_host:
        return  # Host doesn't need its own board data

    if game_config.has("board_data"):
        return  # Already received

    game_config["board_data"] = board_data
    print("Client received board data with %d cells" % board_data.cells.size())
    game_started.emit(game_config)

func set_game_manager(gm: GameManager):
    if game_manager != null:
        return

    game_manager = gm

@rpc("any_peer", "call_local", "reliable")
func _track_cells(visible, side):
    if not is_host or not game_manager:
        return

    var reality = game_manager.board_of_truth.cell_list
    var new_info = []
    var updates = {}
    var player_vals = players.values()
    var peer_id = multiplayer.get_remote_sender_id()

    for player in player_vals:
        updates[player.peer_id] = []

    for cell in visible:
        var truth = reality[cell.index]
        if cell.side == side:
            truth.side = cell.side
            truth.troop_values = cell.troop_values
            truth.level = cell.level
            truth.growth = cell.growth
            truth.seen_by = cell.seen_by
        else:
            truth.seen_by[side] = true

        for player in player_vals:
            if truth.is_seen_by(player.side):
                updates[player.peer_id].append({
                    "index": truth.index,
                    "side": truth.side,
                    "troop_values": truth.troop_values,
                    "level": truth.level,
                    "growth": truth.growth,
                    "seen_by": truth.seen_by,
                })

    for peer in updates:
        var update = updates[peer]
        if update.size():
            rpc_id(peer, "_receive_fog_update", update)

@rpc("any_peer", "call_local", "unreliable")
func _receive_fog_update(data):
    if not game_manager or not game_manager.board:
        return

    for cell in data:
        var truth = game_manager.board.cell_list[cell.index]
        truth.index = cell.index
        truth.side = cell.side
        truth.troop_values = cell.troop_values
        truth.level = cell.level
        truth.growth = cell.growth
        truth.seen_by = cell.seen_by

    game_manager.board.queue_redraw()

@rpc("any_peer", "call_local", "unreliable")
func _receive_board_update(updates):
    if is_host or not game_manager or not game_manager.board:
        return
    
    for cell_data in updates:
        var cell = game_manager.board.get_cell_by_index(cell_data.index)
        if cell:
            cell.side = cell_data.side
            cell.troop_values = cell_data.troops
            cell.level = cell_data.level
            cell.growth = cell_data.growth
            cell.direction_vectors = cell_data.directions
            cell.age = cell_data.age
    
    if updates.size() > 0:
        game_manager.board.queue_redraw()

@rpc("any_peer", "call_local", "unreliable")
func _receive_cell_update(cell_data: Dictionary):
    if not game_manager or not game_manager.board:
        return
    
    print("received update from player %d" % cell_data.side)
    var cell = game_manager.board.get_cell_by_index(cell_data.index)
    if cell:
        cell.side = cell_data.side
        cell.troop_values = cell_data.troops
        cell.level = cell_data.level
        cell.growth = cell_data.growth
        cell.direction_vectors = cell_data.directions
        cell.age = cell_data.age
        game_manager.board.queue_redraw()

# PLAYER INPUT SYNCHRONIZATION
func send_cell_command(cell: Cell, command: int):
    if not connected or not game_manager:
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
    if not connected or not game_manager:
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
    _process_cell_command(command_data)

@rpc("any_peer", "call_local", "reliable") 
func _receive_cell_click(click_data: Dictionary):
    if not is_host:
        return
    _process_cell_click(click_data)

func _process_cell_command(command_data: Dictionary):
    var cell = game_manager.board.get_cell_by_index(command_data.cell_index)
    if cell:
        game_manager.on_cell_command(cell, command_data.command)

func _process_cell_click(click_data: Dictionary):
    var cell = game_manager.board.get_cell_by_index(click_data.cell_index)
    if cell:
        game_manager.on_cell_click(cell, click_data.direction_mask)

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
            # Check for victory condition
            if game_manager and players.size() == 1:
                var winner = players.values()[0].side
                game_manager.game_over.emit(winner)
        
        player_left.emit(player_info)

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

@rpc("any_peer", "reliable")
func _game_over(winner: int):
    game_manager.game_over.emit(winner)

func rpc_all_clients(method: String, arg1 = null, arg2 = null, arg3 = null):
    if arg3 != null:
        rpc(method, arg1, arg2, arg3)
    elif arg2 != null:
        rpc(method, arg1, arg2)
    elif arg1 != null:
        rpc(method, arg1)
    else:
        rpc(method)
