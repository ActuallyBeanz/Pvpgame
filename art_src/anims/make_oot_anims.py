# Authors OoT-style move animations on the KayKit Adventurers rig (shared by all 5 characters):
#   OoT_Roll, OoT_Backflip, OoT_LedgeHopUp, OoT_LedgeClimb, OoT_LedgeHang (loop), OoT_HookPull (loop), OoT_Swim (loop), OoT_Tread (loop)
# Poses are written as rotations in the character's REST model space (Blender: X = character's
# left, -Y = forward, Z = up) and converted to each bone's local frame, so they read clearly.
# Run: blender --background --factory-startup --python make_oot_anims.py -- <Knight.glb> <out_dir> [preview]
import bpy, math, os, sys
from bpy_extras import anim_utils
from mathutils import Matrix, Vector, Quaternion

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PREVIEW = len(args) > 2 and args[2] == "preview"
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for a in list(bpy.data.actions):           # drop KayKit's own clips; we only export ours
    bpy.data.actions.remove(a)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
arm.animation_data_clear()
sc = bpy.context.scene
sc.render.fps = FPS
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"
info = {"armature": arm.name, "obj_rot": [round(v, 3) for v in arm.rotation_euler],
        "kneeIK.l": [round(v, 3) for v in arm.data.bones["kneeIK.l"].head_local],
        "upperarm.l": [round(v, 3) for v in arm.data.bones["upperarm.l"].head_local]}
print("RIGINFO", info)

D = math.radians
BODY = ["hips", "spine", "chest", "head", "upperarm.l", "lowerarm.l", "wrist.l", "upperarm.r", "lowerarm.r",
        "wrist.r", "upperleg.l", "lowerleg.l", "foot.l", "upperleg.r", "lowerleg.r", "foot.r"]

def R(*rots):
    m = Matrix.Identity(3)
    for axis, deg in rots:
        m = Matrix.Rotation(D(deg), 3, axis) @ m
    return m

def aim(bone, target):
    rest = (arm.data.bones[bone].matrix_local.to_3x3() @ Vector((0, 1, 0))).normalized()
    return rest.rotation_difference(Vector(target).normalized()).to_matrix()

def mirror(v):  # left-arm vector -> right-arm vector
    return (-v[0], v[1], v[2])

def arms(up_l, bend=0.0):
    """Both upper arms aimed (left given, right mirrored); elbows bend forward."""
    return {"upperarm.l": aim("upperarm.l", up_l), "upperarm.r": aim("upperarm.r", mirror(up_l)),
            "lowerarm.l": R(("Z", -bend)), "lowerarm.r": R(("Z", bend))}

def legs(hip_l, knee_l, hip_r=None, knee_r=None):
    hip_r = hip_l if hip_r is None else hip_r
    knee_r = knee_l if knee_r is None else knee_r
    return {"upperleg.l": R(("X", hip_l)), "lowerleg.l": R(("X", knee_l)),
            "upperleg.r": R(("X", hip_r)), "lowerleg.r": R(("X", knee_r))}

def torso(spine=0, chest=0, head=0):
    return {"spine": R(("X", spine)), "chest": R(("X", chest)), "head": R(("X", head))}

def pose(hips_pitch=0.0, drop=0.0, pivot=0.0, **parts):
    """hips_pitch: + = tip forward. pivot: spin around a point this far above the hips (tucked ball)."""
    p = {}
    for d in parts.values():
        p.update(d)
    v = Vector((0, 0, -pivot))
    p["hips"] = R(("X", hips_pitch))
    p["_loc"] = Vector((0, 0, -drop)) + (p["hips"] @ v - v)
    return p

STAND_ARMS = (0.35, -0.05, -0.94)
STAND = dict(a=arms(STAND_ARMS, 10), l=legs(0, 0), t=torso())

SKIN = [o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() is not None]


def lowest_point():
    # evaluate the pose we just set, not the action (detach it while measuring)
    act = arm.animation_data.action if arm.animation_data else None
    slot = arm.animation_data.action_slot if act else None
    if act:
        arm.animation_data.action = None
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    lo = 99.0
    for o in SKIN:
        e = o.evaluated_get(dg)
        m = e.to_mesh()
        mw = e.matrix_world
        for v in m.vertices:
            lo = min(lo, (mw @ v.co).z)
        e.to_mesh_clear()
    if act:
        arm.animation_data.action = act
        if slot is not None:
            arm.animation_data.action_slot = slot
    return lo


def key(action_name, frames, loop=False):
    act = bpy.data.actions.new(action_name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    for entry in frames:
        f, p = entry[0], entry[1]
        ground = len(entry) > 2 and entry[2]
        _apply(p)
        if ground:  # lift the hips so the curled-up body just touches the floor
            p["_loc"] = p["_loc"] + Vector((0, 0, -lowest_point()))
        for name in BODY:
            pb = arm.pose.bones[name]
            A = arm.data.bones[name].matrix_local.to_3x3()
            rot = p.get(name, Matrix.Identity(3))
            delta = A.inverted() @ rot @ A
            pb.rotation_quaternion = delta.to_quaternion()
            pb.location = A.inverted() @ p["_loc"] if name == "hips" else Vector()
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    arm.animation_data.action = act
    # quaternion keys must not flip sign between keys (keeps big spins going the right way)
    bag = anim_utils.action_get_channelbag_for_slot(act, arm.animation_data.action_slot)
    for name in BODY:
        fcs = [bag.fcurves.find('pose.bones["%s"].rotation_quaternion' % name, index=i) for i in range(4)]
        if not all(fcs):
            continue
        prev = None
        for k in range(len(fcs[0].keyframe_points)):
            q = Quaternion([fc.keyframe_points[k].co[1] for fc in fcs])
            if prev is not None and prev.dot(q) < 0:
                q.negate()
                for i, fc in enumerate(fcs):
                    fc.keyframe_points[k].co[1] = q[i]
            prev = q
        for fc in fcs:
            fc.update()
    act.frame_range = (frames[0][0], frames[-1][0])
    print("ACTION", action_name, "frames", frames[-1][0], "=", round(frames[-1][0] / FPS, 3), "s")
    return act

def _apply(p):
    for name in BODY:
        pb = arm.pose.bones[name]
        A = arm.data.bones[name].matrix_local.to_3x3()
        pb.rotation_quaternion = (A.inverted() @ p.get(name, Matrix.Identity(3)) @ A).to_quaternion()
        pb.location = A.inverted() @ p["_loc"] if name == "hips" else Vector()


TUCK_ARMS = arms((0.25, -0.75, -0.6), 70)
# ---- forward roll: crouch, tuck, 360° forward around the ball centre, rise
key("OoT_Roll", [
    (0,  pose(10, 0.06, a=arms((0.3, -0.8, -0.5), 30), l=legs(-50, 80), t=torso(20, 10, 10))),
    (4,  pose(30, 0.17, 0.0, a=TUCK_ARMS, l=legs(-120, 150), t=torso(35, 25, 30)), True),
    (8,  pose(120, 0.17, 0.0, a=TUCK_ARMS, l=legs(-125, 150), t=torso(35, 25, 30)), True),
    (12, pose(210, 0.17, 0.0, a=TUCK_ARMS, l=legs(-125, 150), t=torso(35, 25, 30)), True),
    (16, pose(300, 0.17, 0.0, a=TUCK_ARMS, l=legs(-120, 150), t=torso(35, 25, 30)), True),
    (19, pose(380, 0.12, 0.0, a=arms((0.3, -0.8, -0.5), 30), l=legs(-80, 110), t=torso(25, 15, 15)), True),
    (22, pose(368, 0.05, a=arms((0.35, -0.4, -0.8), 20), l=legs(-30, 45), t=torso(10, 5, 0))),
    (24, pose(360, 0.0, **STAND)),
])
# ---- backflip: crouch, throw arms up, tuck, 360° backwards, land
key("OoT_Backflip", [
    (0,  pose(5, 0.08, a=arms((0.3, 0.5, -0.8), 0), l=legs(-50, 90), t=torso(15, 5, 0))),
    (3,  pose(-10, 0.0, a=arms((0.3, -0.1, 1.0), 0), l=legs(0, 5), t=torso(-12, -8, -10))),
    (6,  pose(-70, 0.1, 0.0, a=TUCK_ARMS, l=legs(-110, 140), t=torso(30, 20, 20)), True),
    (9,  pose(-160, 0.15, 0.0, a=TUCK_ARMS, l=legs(-120, 150), t=torso(35, 25, 30)), True),
    (12, pose(-250, 0.15, 0.0, a=TUCK_ARMS, l=legs(-120, 150), t=torso(35, 25, 30)), True),
    (15, pose(-330, 0.1, 0.0, a=arms((0.8, -0.2, 0.3), 10), l=legs(-60, 80), t=torso(15, 10, 10)), True),
    (17, pose(-360, 0.08, a=arms((0.6, -0.5, -0.4), 10), l=legs(-50, 85), t=torso(20, 10, 5))),
    (20, pose(-360, 0.0, **STAND)),
])
# ---- hop up a waist/chest-high ledge: reach, plant hands, knee up, stand
key("OoT_LedgeHopUp", [
    (0,  pose(5, 0.03, a=arms((0.2, -0.6, 0.8), 10), l=legs(-20, 30), t=torso(5, 0, -5))),
    (4,  pose(25, 0.0, a=arms((0.25, -0.85, -0.35), 5), l=legs(-90, 120), t=torso(25, 10, -10))),
    (9,  pose(30, 0.0, a=arms((0.3, -0.3, -0.9), 0), l=legs(-100, 130, 15, 40), t=torso(30, 10, -10))),
    (12, pose(15, 0.03, a=arms((0.35, -0.3, -0.85), 10), l=legs(-60, 80, -10, 30), t=torso(15, 5, 0))),
    (15, pose(0, 0.0, **STAND)),
])
# ---- climb / pull up from a hang: arms up, pull, elbows over, knee up, stand
key("OoT_LedgeClimb", [
    (0,  pose(0, 0.0, a=arms((0.2, -0.3, 1.0), 10), l=legs(-10, 20), t=torso(0, 0, -10))),
    (8,  pose(5, 0.0, a=arms((0.55, -0.6, 0.35), 100), l=legs(-45, 70), t=torso(-5, -5, -15))),
    (14, pose(35, 0.0, a=arms((0.3, -0.45, -0.85), 15), l=legs(-110, 130, -20, 40), t=torso(40, 15, -15))),
    (19, pose(20, 0.08, a=arms((0.35, -0.35, -0.85), 15), l=legs(-80, 90, -30, 60), t=torso(20, 5, -5))),
    (24, pose(0, 0.0, **STAND)),
])
# ---- hanging from a ledge (loop): arms up, legs dangle with a slow sway
def hang(sway):
    return pose(0, 0.0, a=arms((0.18, -0.25, 1.0), 12), l=legs(-12 - sway, 25 + sway, -12 + sway, 25 - sway),
                t=torso(5, 0, -12))
key("OoT_LedgeHang", [(0, hang(0)), (15, hang(8)), (30, hang(0))], loop=True)

# ---- reeled in by the grapple (loop): launcher arm locked straight out at the claw, other arm
# swept back, legs trailing together with a little flutter. Godot pitches the whole body toward
# the latch point on top of this, so the pose itself stays upright.
def hookpull(flutter):
    p = pose(0, 0.0, l=legs(14 + flutter, 30 - flutter, 22 - flutter, 42 + flutter), t=torso(-4, -6, -14))
    p["upperarm.r"] = aim("upperarm.r", (-0.12, -1.0, 0.12))   # launcher hand: straight ahead
    p["lowerarm.r"] = R(("Z", 4))
    p["upperarm.l"] = aim("upperarm.l", (0.45, 0.45, -0.75))   # free arm: down and back
    p["lowerarm.l"] = R(("Z", -20))
    return p
key("OoT_HookPull", [(0, hookpull(0)), (6, hookpull(6)), (12, hookpull(0))], loop=True)

# ---- swimming (loops). Godot tips the body forward while you swim, so "up" in these poses
# becomes "forward": breaststroke = reach up, sweep out and down, frog kick.
def stroke(arm, bend, hip, knee, chest=0):
    return pose(0, 0.0, a=arms(arm, bend), l=legs(hip, knee), t=torso(0, chest, -25))
key("OoT_Swim", [
    (0,  stroke((0.12, -0.15, 1.0), 5, 2, 8)),
    (8,  stroke((0.9, -0.15, 0.35), 20, -35, 95, 5)),
    (14, stroke((0.45, -0.35, -0.8), 45, 6, 12, -5)),
    (19, stroke((0.3, -0.75, 0.25), 80, 4, 10)),
    (24, stroke((0.12, -0.15, 1.0), 5, 2, 8)),
], loop=True)
# treading water upright: arms sculling at the sides, legs cycling
def tread(t):
    return pose(0, 0.0, a=arms((0.9, -0.2 + 0.35 * t, -0.25), 25),
                l=legs(-30 + 30 * t, 60 - 40 * t, -30 * t, 20 + 40 * t), t=torso(3, 0, -5))
key("OoT_Tread", [(0, tread(0)), (15, tread(1)), (30, tread(0))], loop=True)

arm.animation_data.action = None

if PREVIEW:
    # contact sheet frames: side view (camera on the character's left)
    w = bpy.data.worlds.new("w"); sc.world = w
    w.color = (0.55, 0.65, 0.8)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
    sun.data.energy = 3; sun.rotation_euler = (D(50), 0, D(40))
    bpy.ops.mesh.primitive_plane_add(size=6)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = 3.6
    cam.location = (6, 0.0, 1.0); cam.rotation_euler = (D(90), 0, D(90))
    for o in bpy.data.objects:  # hide the kit KayKit ships in the hands (hidden in game too)
        if o.type == "MESH" and o.parent_type == "BONE" and o.parent_bone.startswith("handslot"):
            o.hide_render = True
    sc.render.resolution_x = sc.render.resolution_y = 220
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "TEXTURE"
    shots = {"OoT_Roll": [0, 4, 8, 12, 16, 20, 24], "OoT_Backflip": [0, 3, 6, 9, 12, 15, 20],
             "OoT_LedgeHopUp": [0, 4, 9, 12, 15], "OoT_LedgeClimb": [0, 8, 14, 19, 24], "OoT_LedgeHang": [0, 15], "OoT_HookPull": [0, 6], "OoT_Swim": [0, 8, 14, 19], "OoT_Tread": [0, 15]}
    for name, frames in shots.items():
        arm.animation_data.action = bpy.data.actions[name]
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = os.path.join(OUT, "preview", "%s_%02d.png" % (name, f))
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
else:
    for o in bpy.data.objects:
        o.select_set(o.type in ("ARMATURE", "MESH"))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "oot_moves.glb"), export_format="GLB",
                              use_selection=True, export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_frame_step=1, export_yup=True)
    print("EXPORTED", os.path.join(OUT, "oot_moves.glb"))
