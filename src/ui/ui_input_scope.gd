class_name UiInputScope
extends RefCounted

## Cursor/input ownership, shared by menus and popups. Closing an underlying
## screen cannot recapture the mouse from the screen above it. The owner
## releases in _exit_tree as well as on a normal close. No autoload needed.
static var _stack: Array[UiInputScope] = []
static var _mouse_before := Input.MOUSE_MODE_VISIBLE

var _owner: WeakRef
var _focus_before: WeakRef


static func acquire(owner: Node) -> UiInputScope:
	_prune()
	for scope in _stack:
		if scope._owner.get_ref() == owner:
			return scope
	if _stack.is_empty():
		_mouse_before = Input.get_mouse_mode()
	var scope := UiInputScope.new()
	scope._owner = weakref(owner)
	var focus := owner.get_viewport().gui_get_focus_owner()
	if focus != null:
		scope._focus_before = weakref(focus)
		owner.get_viewport().gui_release_focus()
	_stack.append(scope)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return scope


func is_top() -> bool:
	_prune()
	return not _stack.is_empty() and _stack.back() == self


static func available_to(owner: Node) -> bool:
	_prune()
	return _stack.is_empty() or _stack.back()._owner.get_ref() == owner


func release() -> void:
	if not self in _stack:
		return
	var was_top: bool = not _stack.is_empty() and _stack.back() == self
	_stack.erase(self)
	_prune()
	if _stack.is_empty():
		Input.set_mouse_mode(_mouse_before)
	if was_top and _focus_before != null:
		var previous := _focus_before.get_ref() as Control
		if is_instance_valid(previous) and previous.is_inside_tree() and previous.is_visible_in_tree():
			var owner: Node = _stack.back()._owner.get_ref() if not _stack.is_empty() else null
			if owner == null or owner == previous or owner.is_ancestor_of(previous):
				previous.grab_focus()


static func _prune() -> void:
	var had_owners := not _stack.is_empty()
	for i in range(_stack.size() - 1, -1, -1):
		if not is_instance_valid(_stack[i]._owner.get_ref()):
			_stack.remove_at(i)
	if had_owners and _stack.is_empty():
		Input.set_mouse_mode(_mouse_before)
