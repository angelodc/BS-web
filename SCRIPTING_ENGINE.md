# Godot Card Game Scripting Engine

The ScriptingEngine (ScEng) of the Card Game Framework is a way to allow complex interactions and manipulations of the board to be encoded in objects in the game through a simple json dictionary.

Please check the [basic information in the wiki](https://github.com/db0/godot-card-gaming/wiki/ScriptDefinitions) first.

## Connecting new objects to the ScriptingEngine

The ScriptingEngine has been created in such a way so as to allow even non-card objects to make use of its capabilities. 

To achieve that, you need to prepare you object in the following way:

1. Add the object to the "scriptables" group. Objects in this group are checked whenever looking for effects that modify automatic intereactions with the board
1. Add a "canonical_name" variable to your object's script and set it so that it has a human-readable value which refers to that object. This is used in dialogues to the player and for filtering effects
1. Add an `execute_scripts()` method to the object. This will be called automatically due to signals and should be called with manual intereactions. It should behave similar to the `execute_scripts()` 
in the Card object, checking filters, checking confirmations and finally invoking the ScriptingEngine with a list of tasks. The best approach would be to copy `execute_scripts()` and modify it.
1. Add a `get_state_exec()` method to the object. This should return a string of one of the various states the object can be in, which are used to filter the correct scripts for execution.
1. Add a `retrieve_scripts()` method to the object. This should retrieve all of the object's scripts, from wherever they are stored.

## Multiplayer

Multiplayer no longer lives in this document. The LAN v1 is implemented: mirrored
board and opponent movements, remote cursor, central phase indicator, host
authority for start/dice/phases/public state, checkpoints and resume. The online
relay and Netlify lobby are implemented but not deployed; web-client integration
is pending.

See [MULTIPLAYER.md](./MULTIPLAYER.md) for behavior and limitations, and
[ONLINE_HOSTING.md](./ONLINE_HOSTING.md) for the online deployment plan.
