# The average colour each model shows (its base colour texture sampled over the mesh's surface,
# area weighted, averaged in linear light), for MeshKit's fallback colour: a template's own Color
# is what Roblox draws while its texture can't (not processed yet, a failed upload, a slow phone).
# Without it every such model shows Roblox's default grey (163, 162, 165).
#
# usage: python3 tools/meshy/glb_albedo.py <out.json> <file.glb> [<file.glb> ...]
# Every node with a mesh counts under its own name (the processed files name each node after its
# asset: Ore_Gold, Floor_EmberCavesHD_03, ...). A later file wins for a name seen twice, so list the
# files oldest first. out.json is updated (other names kept): {"Name": [r, g, b]} in sRGB 0..1.
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
DTYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}


def read_glb(path):
    data = open(path, "rb").read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, path + ": not a .glb"
    off, js, binc = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8 : off + 8 + clen]
        off += 8 + clen
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
    return js, binc


def accessor(js, binc, index):
    acc = js["accessors"][index]
    view = js["bufferViews"][acc["bufferView"]]
    dtype = np.dtype(DTYPES[acc["componentType"]])
    comps = COMPONENTS[acc["type"]]
    count = acc["count"]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or dtype.itemsize * comps
    raw = np.frombuffer(binc, dtype=np.uint8, count=stride * (count - 1) + dtype.itemsize * comps, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(count, dtype.itemsize * comps), strides=(stride, 1))
    out = np.ascontiguousarray(rows).view(dtype).reshape(count, comps).astype(np.float64)
    if acc.get("normalized"):
        out /= float(np.iinfo(dtype).max)
    return out


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)


def image_of(js, binc, tex_index, cache):
    src = js["textures"][tex_index]["source"]
    if src not in cache:
        img = js["images"][src]
        view = js["bufferViews"][img["bufferView"]]
        raw = binc[view.get("byteOffset", 0) : view.get("byteOffset", 0) + view["byteLength"]]
        rgb = np.asarray(Image.open(io.BytesIO(raw)).convert("RGB"), dtype=np.float64) / 255.0
        cache[src] = srgb_to_linear(rgb)
    return cache[src]


def mesh_albedo(js, binc, mesh, cache):
    total = np.zeros(3)
    weight = 0.0
    for prim in mesh["primitives"]:
        attrs = prim["attributes"]
        mat = js["materials"][prim["material"]] if "material" in prim else {}
        pbr = mat.get("pbrMetallicRoughness", {})
        factor = srgb_to_linear(np.array(pbr.get("baseColorFactor", [1, 1, 1, 1])[:3], dtype=np.float64))
        pos = accessor(js, binc, attrs["POSITION"])
        idx = accessor(js, binc, prim["indices"]).astype(np.int64).reshape(-1, 3) if "indices" in prim else np.arange(len(pos)).reshape(-1, 3)
        a, b, c = pos[idx[:, 0]], pos[idx[:, 1]], pos[idx[:, 2]]
        area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
        tex = pbr.get("baseColorTexture")
        if tex is not None and "TEXCOORD_%d" % tex.get("texCoord", 0) in attrs:
            uv = accessor(js, binc, attrs["TEXCOORD_%d" % tex.get("texCoord", 0)])
            centre = (uv[idx[:, 0]] + uv[idx[:, 1]] + uv[idx[:, 2]]) / 3.0
            img = image_of(js, binc, tex["index"], cache)
            h, w = img.shape[:2]
            # glTF: texcoord (0, 0) is the image's first (top left) pixel; wrap like REPEAT
            x = np.clip((np.mod(centre[:, 0], 1.0) * w).astype(np.int64), 0, w - 1)
            y = np.clip((np.mod(centre[:, 1], 1.0) * h).astype(np.int64), 0, h - 1)
            colours = img[y, x] * factor
        else:
            colours = np.tile(factor, (len(area), 1))
        total += (colours * area[:, None]).sum(axis=0)
        weight += float(area.sum())
    if weight <= 0:
        return None
    return linear_to_srgb(total / weight)


def main():
    out_path, files = sys.argv[1], sys.argv[2:]
    result = json.load(open(out_path)) if os.path.exists(out_path) else {}
    for path in files:
        js, binc = read_glb(path)
        cache = {}
        for node in js.get("nodes", []):
            if "mesh" not in node or not node.get("name"):
                continue
            colour = mesh_albedo(js, binc, js["meshes"][node["mesh"]], cache)
            if colour is not None:
                result[node["name"]] = [round(float(v), 4) for v in colour]
        print("%s: %d models" % (os.path.basename(path), sum(1 for n in js.get("nodes", []) if "mesh" in n)))
    with open(out_path, "w") as f:
        json.dump(dict(sorted(result.items())), f, indent=1)
        f.write("\n")
    print("wrote %s (%d models)" % (out_path, len(result)))


if __name__ == "__main__":
    main()
