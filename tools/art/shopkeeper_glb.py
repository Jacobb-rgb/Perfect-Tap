"""
The owner's shopkeeper model (docs/art/shopkeeper/roblox_miner_shopkeeper.glb,
2026-10-24: "upload exactly this") -> src/shared/Builders/ShopkeeperModel.luau,
the same pieces as Roblox parts: every box a Block, every cylinder a Cylinder,
the round lamp lens a disc, the colours of the file.

    python3 -I tools/art/shopkeeper_glb.py docs/art/shopkeeper/roblox_miner_shopkeeper.glb \
        src/shared/Builders/ShopkeeperModel.luau

The file is Z-up and faces +Y (1 unit = 1 stud). Roblox is Y-up and faces -Z:
roblox (x, y, z) = file (x, z - ground, -y), ground = the boots' soles.
Each piece goes to a rig part (Head, Torso, arms, legs) so Roblox's R6
animations can move it.
"""

import json
import math
import struct
import sys

GLOW = {"lamp_glow", "side_lamp_glow", "chest_device_glow", "lantern_glass"}

# Pieces the file lacks (Roblox space, feet at 0): its torso floats 0.42 above
# the thighs, so a hip block in the trousers' colour closes the gap.
EXTRA = [
    {"name": "hips", "rig": "Torso", "min": (-0.72, 1.9, -0.36), "max": (0.72, 2.42, 0.36), "color": (43, 39, 37)},
]


def rig_of(name):
    if name.startswith("L_") and any(k in name for k in ("shoulder", "arm", "bicep", "forearm", "bracer")):
        return "Left Arm"
    if name.startswith("R_") and any(k in name for k in ("shoulder", "arm", "bicep", "forearm", "bracer")):
        return "Right Arm"
    if name.startswith("L_"):
        return "Left Leg"
    if name.startswith("R_"):
        return "Right Leg"
    head = ("head", "ear", "eye", "smile", "teeth", "helmet", "lamp_mount", "lamp_glow", "side_lamp")
    if name.startswith(head):
        return "Head"
    return "Torso"


def read(path):
    data = open(path, "rb").read()
    clen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20 : 20 + clen])
    boff = 20 + clen + 8
    binary = data[boff:]

    def accessor(i):
        a = j["accessors"][i]
        view = j["bufferViews"][a["bufferView"]]
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        comps = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        fmt = {5126: "f", 5121: "B", 5125: "I", 5123: "H"}[a["componentType"]]
        size = struct.calcsize(fmt)
        stride = view.get("byteStride", size * comps)
        out = []
        for k in range(a["count"]):
            out.append(struct.unpack_from("<" + fmt * comps, binary, start + k * stride))
        return out

    # every mesh, not only the nodes': the file's scene lost 11 mirrored pieces
    # (one eye, ear, eyebrow, apron strap, pouch and flap, backpack tube,
    # harness strap and three SHOP letters) to duplicate names, but their
    # meshes are in it (no node has a transform: the vertices are in place)
    pieces = []
    for mesh in j["meshes"]:
        prim = mesh["primitives"][0]
        verts = [tuple(v) for v in accessor(prim["attributes"]["POSITION"])]
        color = accessor(prim["attributes"]["COLOR_0"])[0][:3]
        pieces.append({"name": mesh["name"], "shape": mesh.get("extras", {}).get("shape", "box"), "extras": mesh.get("extras", {}), "verts": verts, "color": color})
    return pieces


def to_roblox(v, ground):
    return (v[0], v[2] - ground, -v[1])


def principal_axis(points):
    n = len(points)
    c = [sum(p[i] for p in points) / n for i in range(3)]
    cov = [[sum((p[i] - c[i]) * (p[k] - c[k]) for p in points) / n for k in range(3)] for i in range(3)]
    v = [1.0, 0.7, 0.3]
    for _ in range(200):
        w = [sum(cov[i][k] * v[k] for k in range(3)) for i in range(3)]
        norm = math.sqrt(sum(x * x for x in w)) or 1.0
        v = [x / norm for x in w]
    return c, v


def frame(axis):
    # an orthonormal frame whose X is `axis` (a Roblox cylinder's axis is X)
    x = axis
    up = [0.0, 1.0, 0.0] if abs(x[1]) < 0.9 else [1.0, 0.0, 0.0]
    z = [x[1] * up[2] - x[2] * up[1], x[2] * up[0] - x[0] * up[2], x[0] * up[1] - x[1] * up[0]]
    zn = math.sqrt(sum(t * t for t in z))
    z = [t / zn for t in z]
    y = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
    return x, y, z


def fmt(x):
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main(src, dst):
    pieces = read(src)
    ground = min(v[2] for p in pieces for v in p["verts"])
    lines = []
    for p in pieces:
        pts = [to_roblox(v, ground) for v in p["verts"]]
        r, g, b = p["color"]
        name, rig = p["name"], rig_of(p["name"])
        material = "Neon" if name in GLOW else "SmoothPlastic"
        mn = [min(q[i] for q in pts) for i in range(3)]
        mx = [max(q[i] for q in pts) for i in range(3)]
        center = [(mn[i] + mx[i]) / 2 for i in range(3)]
        if p["shape"] == "box":
            for q in pts:  # every box in the file is axis-aligned
                assert all(abs(q[i] - mn[i]) < 1e-4 or abs(q[i] - mx[i]) < 1e-4 for i in range(3)), name
            size = [mx[i] - mn[i] for i in range(3)]
            cf = f"CFrame.new({fmt(center[0])}, {fmt(center[1])}, {fmt(center[2])})"
            shape = "Block"
        elif p["shape"] == "cylinder":
            h, rad = p["extras"]["height"], p["extras"]["radius"]
            c, axis = principal_axis(pts)
            x, y, z = frame(axis)
            size = [h, 2 * rad, 2 * rad]
            cf = "CFrame.fromMatrix(Vector3.new({}), Vector3.new({}), Vector3.new({}))".format(
                ", ".join(fmt(t) for t in c), ", ".join(fmt(t) for t in x), ", ".join(fmt(t) for t in y)
            )
            shape = "Cylinder"
        else:  # the lamp's round lens (a flattened sphere): a disc facing out
            size = [mx[i] - mn[i] for i in range(3)]
            depth = size[2]
            cf = f"CFrame.new({fmt(center[0])}, {fmt(center[1])}, {fmt(center[2])}) * CFrame.Angles(0, math.pi / 2, 0)"
            size = [depth, size[1], size[0]]
            shape = "Cylinder"
        lines.append(
            f'\t{{ Name = "{name}", Rig = "{rig}", Shape = "{shape}", Material = "{material}", '
            f"Size = Vector3.new({fmt(size[0])}, {fmt(size[1])}, {fmt(size[2])}), "
            f"CFrame = {cf}, Color = Color3.fromRGB({r}, {g}, {b}) }},"
        )
    for e in EXTRA:
        c = [(e["min"][i] + e["max"][i]) / 2 for i in range(3)]
        size = [e["max"][i] - e["min"][i] for i in range(3)]
        r, g, b = e["color"]
        lines.append(
            f'\t{{ Name = "{e["name"]}", Rig = "{e["rig"]}", Shape = "Block", Material = "SmoothPlastic", '
            f"Size = Vector3.new({fmt(size[0])}, {fmt(size[1])}, {fmt(size[2])}), "
            f"CFrame = CFrame.new({fmt(c[0])}, {fmt(c[1])}, {fmt(c[2])}), Color = Color3.fromRGB({r}, {g}, {b}) }}, -- (not in the file)"
        )
    height = max(q[1] for p in pieces for q in (to_roblox(v, ground) for v in p["verts"]))
    out = f"""--[[
	GENERATED by tools/art/shopkeeper_glb.py from the owner's model
	docs/art/shopkeeper/roblox_miner_shopkeeper.glb (2026-10-24: "upload exactly
	this"): the miner shopkeeper as {len(lines)} Roblox parts, in studs, feet at
	the origin (the boots' soles at Y 0), facing -Z: all {len(pieces)} meshes of the
	file (its scene lost 11 mirrored ones) and a hip block it lacks (its torso
	floats over the thighs). Do not edit by hand: change the model or the
	script and run it again.
]]

export type Piece = {{
	Name: string,
	Rig: string, -- the rig part it moves with: Head, Torso, Left Arm, Right Arm, Left Leg, Right Leg
	Shape: "Block" | "Cylinder",
	Material: "SmoothPlastic" | "Neon",
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
}}

local ShopkeeperModel = {{}}

ShopkeeperModel.Height = {fmt(height)}

ShopkeeperModel.Pieces = {{
{chr(10).join(lines)}
}} :: {{ Piece }}

return ShopkeeperModel
"""
    open(dst, "w").write(out)
    print(f"{len(lines)} pieces, height {height:.3f}, ground {ground:.3f} -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
