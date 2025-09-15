extends CharacterBody2D

# ==== SIGNALS ====
signal player_died

# ==== HEALTH ====
var health: int = 3
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# ==== MOVEMENT ====
@export var speed: float = 175
@export var gravity: float = 1000

# ==== JUMP SETTINGS ====
@export var jump_force: float = -300           # Initial low jump
@export var jump_extra_force: float = -20      # Continuous boost while holding
@export var jump_hold_time: float = 0.2        # Max boost time (seconds)

# ==== COYOTE TIME SETTINGS ====
@export var coyote_time_max: float = 0.15
var coyote_timer: float = 0.0

# ==== JUMP BUFFER SETTINGS ====
@export var jump_buffer_time_max: float = 0.15
var jump_buffer_timer: float = 0.0

var jump_time: float = 0.0
var is_jump_button_held: bool = false
var is_jumping: bool = false

# ==== DASH SETTINGS ====
const dash_speed: float = 500
@export var dash_time: float = 0.5

# ==== FLIP NODE ====
@export var flip_node: Node2D

# ==== ANIMATIONS ====
@onready var anim_tree: AnimationTree = $AnimationTree
var state_machine: AnimationNodeStateMachinePlayback

# ==== BODY PARTS ==== - for flash
@onready var body_parts = [ $Character/Body/Wrist2, $Character/Body/Elbow2, $Character/Body/Shoulder2, $Character/Body/Shoe2, $Character/Body/Knee2, $Character/Body/Hip2, $Character/Body/Shoe1, $Character/Body/Knee1, $Character/Body/Hip1, $Character/Body/Body2, $Character/Body/Head, $Character/Body/Melee, $Character/Body/Wrist1, $Character/Body/Elbow1, $Character/Body/Shoulder1 ]

# ==== CONTROL VARIABLES ====
var _is_flashing: bool = false       # Tracks if flash is running
var _stop_flash: bool = false        # Allows interrupting the flash

# ==== STATES ====
var is_dashing: bool = false
var dash_timer: float = 0.0
var facing_dir: int = 1
var can_dash: bool = true

# ==== HEALTH FUNCTIONS ====
func apply_hit() -> void:
	health -= 1
	print("Player hit! Health: %d" % health)
	if health <= 0:
		die()

func die() -> void:
	print("You Died!!")
	Engine.time_scale = 0.5
	collision_shape.queue_free()
	emit_signal("player_died")

# ==== READY ====
func _ready() -> void:
	# Setup AnimationTree
	if anim_tree == null:
		push_error("AnimationTree not found at $AnimationTree. Update the path or add one.")
	else:
		anim_tree.active = true
		state_machine = anim_tree["parameters/playback"]

	# Auto-detect Flip Node
	if flip_node == null:
		flip_node = get_node_or_null("Skeleton2D")
		if flip_node == null:
			flip_node = get_node_or_null("Sprite2D")
		if flip_node == null:
			flip_node = get_node_or_null("AnimatedSprite2D")

	if flip_node == null:
		push_error("Flip node not set/found. Assign 'Flip Node' to your Skeleton2D in the Inspector.")

# ==== MAIN LOOP ====
func _physics_process(delta: float) -> void:
	# ==== COYOTE TIMER ====
	if is_on_floor():
		coyote_timer = coyote_time_max
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	# ==== JUMP BUFFER TIMER ====
	if Input.is_action_just_pressed("ui_jump"):
		jump_buffer_timer = jump_buffer_time_max
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
		_travel("Jump_D")

	var input_dir := Input.get_axis("ui_left", "ui_right")

	# ==== VARIABLE JUMP ====
	if (jump_buffer_timer > 0.0) and (is_on_floor() or coyote_timer > 0.0):
		velocity.y = jump_force
		is_jumping = true
		is_jump_button_held = true
		jump_time = 0.0
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		_travel("Jump")

	# Holding jump to boost height
	if Input.is_action_pressed("ui_jump") and is_jump_button_held:
		if jump_time < jump_hold_time:
			velocity.y += jump_extra_force
			jump_time += delta

	# Stop boost when released
	if Input.is_action_just_released("ui_jump"):
		is_jump_button_held = false


	# ==== DASH ====
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
		velocity.x = dash_speed * facing_dir
		_travel("Dash")
		if is_on_floor():
			is_jumping = false

	# ==== DUCK ====
	elif Input.is_action_pressed("ui_down") and is_on_floor():
		velocity.x = 0
		_travel("Duck")

	# ==== RUN ====
	elif Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right"):
		velocity.x = input_dir * speed
		_face_direction(input_dir)
		_travel("Run")

	# ==== IDLE ====
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		if is_on_floor():
			_travel("Idle")

	# ==== MELEE ====
	if Input.is_action_pressed("ui_AttackM") and is_on_floor() and input_dir == 0 and not is_dashing:
		_travel("AttackM_2")
	elif Input.is_action_just_pressed("ui_AttackM") and is_on_floor() and input_dir != 0 and not is_dashing:
		_travel("Run_Attack")
	elif Input.is_action_just_pressed("ui_AttackM") and is_dashing:
		_travel("Attack_Air")
	elif Input.is_action_just_pressed("ui_AttackM") and not is_on_floor():
		_travel("Attack_Air")

	# ==== RANGE ATTACK ====
	elif Input.is_action_pressed("ui_AttackR") and is_on_floor():
		velocity.x = 0
		_travel("AttackR")

	# ==== DASH RESET ====
	if is_on_floor():
		can_dash = true

	# ==== DASH START ====
	if Input.is_action_just_pressed("ui_Dash") and not is_dashing:
		if is_on_floor() and can_dash:
			flash()
			is_dashing = true
			dash_timer = dash_time
			if input_dir != 0.0:
				facing_dir = sign(input_dir)
			velocity.x = dash_speed * facing_dir * 3.0
			velocity.y = 0
			_travel("Dash")
			can_dash = false
			if not is_on_floor():
				can_dash = false
		elif not is_on_floor() and can_dash:
			flash()
			is_dashing = true
			dash_timer = dash_time
			if input_dir != 0.0:
				facing_dir = sign(input_dir)
			velocity.x = dash_speed * facing_dir * 3.0
			velocity.y = jump_force / 2.5
			_travel("Dash")
			can_dash = false  # Consume the air dash so it can't be repeated
			
	move_and_slide()


# ==== ANIMATION HELPER ====
func _travel(state: String) -> void:
	if state_machine != null:
		state_machine.travel(state)
		

# ==== FLIP HELPER ====
func _face_direction(dir: float) -> void:
	if dir < 0 and facing_dir != -1:
		facing_dir = -1
		_set_flip_x(-1)
	elif dir > 0 and facing_dir != 1:
		facing_dir = 1
		_set_flip_x(1)

func _set_flip_x(sign_x: int) -> void:
	if flip_node == null: 
		return
	var sx := flip_node.scale.x
	var sy := flip_node.scale.y
	flip_node.scale = Vector2(sign_x * abs(sx if sx != 0.0 else 1.0), sy if sy != 0.0 else 1.0)
	
# ==== FLASH FUNCTION ====
func flash():
	if _is_flashing:
		return # Prevent multiple flashes overlapping
	
	_is_flashing = true
	_stop_flash = false

	# Set hit_effect to 1.0 on all body parts
	for part in body_parts:
		if part.material is ShaderMaterial:
			part.material.set_shader_parameter("hit_effect", 1.0)

	# Animate hit_effect back to 0 smoothly
	var t = 1.0
	while t > 0.0 and not _stop_flash:
		t -= get_process_delta_time() * 10.0 # Fade speed
		for part in body_parts:
			if part.material is ShaderMaterial:
				part.material.set_shader_parameter("hit_effect", max(t, 0.0))
				await get_tree().process_frame

	# Fully reset once done or stopped
	for part in body_parts:
		if part.material is ShaderMaterial:
			part.material.set_shader_parameter("hit_effect", 0.0)

	_is_flashing = false
	_stop_flash = false

# ==== TURN OFF FUNCTION ====
func stop_flash():
	_stop_flash = true
