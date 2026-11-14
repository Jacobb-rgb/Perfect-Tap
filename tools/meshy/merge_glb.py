"""Merge several .glb files into one, losslessly.

Every input's nodes, meshes, accessors, buffer views, materials, textures, samplers and images are
copied as they are (indices shifted); the binary chunks are concatenated into one buffer (each part
4-byte aligned). One scene holds every input's root nodes. Images with identical bytes and mime type
are stored once (the textures point at the shared copy). Image and material names that would repeat
get the source file's name in front, so each upload in Studio has its own name.

Made for the owner's Studio import (File -> Import 3D takes the one file; "Merge Meshes" must stay off so
every glTF mesh stays its own MeshPart, which tools/lune/import_meshes.luau finds by name).

  python3 tools/meshy/merge_glb.py NAHRAJ_DO_ROBLOXU/<folder>/<name>.glb <in1.glb> <in2.glb> ...
"""

import hashlib
import json
import os
import struct
import sys

ARRAY_KEYS = ["nodes", "meshes", "accessors", "bufferViews", "materials", "textures", "samplers", "images", "cameras", "skins", "animations"]


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2 and length == len(data), path
    pos = 12
    gltf = None
    binary = b""
    while pos < length:
        clen, ctype = struct.unpack("<II", data[pos : pos + 8])
        chunk = data[pos + 8 : pos + 8 + clen]
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif ctype == 0x004E4942:
            binary = chunk
        pos += 8 + clen
    assert gltf is not None, path
    assert len(gltf.get("buffers", [])) <= 1, path + ": more than one buffer"
    for key in ("cameras", "skins", "animations"):
        assert not gltf.get(key), path + ": has " + key
    assert not gltf.get("extensionsUsed"), path + ": uses extensions"
    return gltf, binary


def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def main():
    out_path = sys.argv[1]
    inputs = sys.argv[2:]
    merged = {k: [] for k in ARRAY_KEYS}
    big = bytearray()
    scene_nodes = []
    image_by_hash = {}
    names_seen = {"images": {}, "materials": {}}
    stems = []

    loaded = [(p, *read_glb(p)) for p in inputs]
    # names used more than once across all inputs get the file name in front
    counts = {"images": {}, "materials": {}}
    for _, g, _ in loaded:
        for key in counts:
            for item in g.get(key, []):
                n = item.get("name")
                if n is not None:
                    counts[key][n] = counts[key].get(n, 0) + 1

    for path, g, binary in loaded:
        stem = os.path.splitext(os.path.basename(path))[0]
        stems.append(stem)
        base = {k: len(merged[k]) for k in ARRAY_KEYS}
        offset = len(big)
        big.extend(pad4(binary))

        # buffer views: one buffer, shifted
        for bv in g.get("bufferViews", []):
            bv = dict(bv)
            bv["buffer"] = 0
            bv["byteOffset"] = bv.get("byteOffset", 0) + offset
            merged["bufferViews"].append(bv)

        for acc in g.get("accessors", []):
            acc = json.loads(json.dumps(acc))
            if "bufferView" in acc:
                acc["bufferView"] += base["bufferViews"]
            if "sparse" in acc:
                acc["sparse"]["indices"]["bufferView"] += base["bufferViews"]
                acc["sparse"]["values"]["bufferView"] += base["bufferViews"]
            merged["accessors"].append(acc)

        # images: identical bytes stored once
        image_map = {}
        for i, img in enumerate(g.get("images", [])):
            img = dict(img)
            assert "bufferView" in img, path + ": image with a uri"
            bv = g["bufferViews"][img["bufferView"]]
            start = bv.get("byteOffset", 0)
            raw = binary[start : start + bv["byteLength"]]
            key = (hashlib.sha256(raw).hexdigest(), img.get("mimeType"))
            if key in image_by_hash:
                image_map[i] = image_by_hash[key]
                continue
            img["bufferView"] += base["bufferViews"]
            n = img.get("name")
            if n is not None and counts["images"][n] > 1:
                img["name"] = stem + "_" + n
            image_map[i] = len(merged["images"])
            image_by_hash[key] = image_map[i]
            merged["images"].append(img)

        for s in g.get("samplers", []):
            merged["samplers"].append(dict(s))

        for t in g.get("textures", []):
            t = dict(t)
            if "source" in t:
                t["source"] = image_map[t["source"]]
            if "sampler" in t:
                t["sampler"] += base["samplers"]
            merged["textures"].append(t)

        def fix_tex(info):
            if info is not None:
                info["index"] += base["textures"]

        for m in g.get("materials", []):
            m = json.loads(json.dumps(m))
            pbr = m.get("pbrMetallicRoughness", {})
            fix_tex(pbr.get("baseColorTexture"))
            fix_tex(pbr.get("metallicRoughnessTexture"))
            fix_tex(m.get("normalTexture"))
            fix_tex(m.get("occlusionTexture"))
            fix_tex(m.get("emissiveTexture"))
            n = m.get("name")
            if n is not None and counts["materials"][n] > 1:
                m["name"] = stem + "_" + n
            merged["materials"].append(m)

        for mesh in g.get("meshes", []):
            mesh = json.loads(json.dumps(mesh))
            for prim in mesh["primitives"]:
                prim["attributes"] = {k: v + base["accessors"] for k, v in prim["attributes"].items()}
                if "indices" in prim:
                    prim["indices"] += base["accessors"]
                if "material" in prim:
                    prim["material"] += base["materials"]
                for target in prim.get("targets", []):
                    for k in target:
                        target[k] += base["accessors"]
            merged["meshes"].append(mesh)

        for node in g.get("nodes", []):
            node = json.loads(json.dumps(node))
            if "mesh" in node:
                node["mesh"] += base["meshes"]
            if "children" in node:
                node["children"] = [c + base["nodes"] for c in node["children"]]
            merged["nodes"].append(node)

        scene = g["scenes"][g.get("scene", 0)]
        scene_nodes.extend(n + base["nodes"] for n in scene["nodes"])

    gltf = {
        "asset": {"generator": "Terra Forge merge_glb.py (" + ", ".join(stems) + ")", "version": "2.0"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": scene_nodes}],
        "buffers": [{"byteLength": len(big)}],
    }
    for k in ARRAY_KEYS:
        if merged[k]:
            gltf[k] = merged[k]

    # images that became duplicates leave their bytes in the buffer unused; that is harmless but
    # wasteful, so rebuild the buffer from the views still referenced
    used = set()
    for acc in gltf.get("accessors", []):
        if "bufferView" in acc:
            used.add(acc["bufferView"])
        if "sparse" in acc:
            used.add(acc["sparse"]["indices"]["bufferView"])
            used.add(acc["sparse"]["values"]["bufferView"])
    for img in gltf.get("images", []):
        used.add(img["bufferView"])
    new_index = {}
    new_views = []
    compact = bytearray()
    for i, bv in enumerate(gltf["bufferViews"]):
        if i not in used:
            continue
        start = bv["byteOffset"]
        chunk = bytes(big[start : start + bv["byteLength"]])
        bv = dict(bv)
        bv["byteOffset"] = len(compact)
        compact.extend(pad4(chunk))
        new_index[i] = len(new_views)
        new_views.append(bv)
    gltf["bufferViews"] = new_views
    for acc in gltf.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = new_index[acc["bufferView"]]
        if "sparse" in acc:
            acc["sparse"]["indices"]["bufferView"] = new_index[acc["sparse"]["indices"]["bufferView"]]
            acc["sparse"]["values"]["bufferView"] = new_index[acc["sparse"]["values"]["bufferView"]]
    for img in gltf.get("images", []):
        img["bufferView"] = new_index[img["bufferView"]]
    gltf["buffers"] = [{"byteLength": len(compact)}]

    js = pad4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    bn = pad4(bytes(compact))
    total = 12 + 8 + len(js) + 8 + len(bn)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bn), 0x004E4942))
        f.write(bn)
    print(
        "wrote %s: %d files, %d nodes, %d meshes, %d materials, %d images (%d shared), %.1f MB"
        % (
            out_path,
            len(inputs),
            len(gltf["nodes"]),
            len(gltf["meshes"]),
            len(gltf.get("materials", [])),
            len(gltf.get("images", [])),
            sum(len(g.get("images", [])) for _, g, _ in loaded) - len(gltf.get("images", [])),
            total / 1e6,
        )
    )


if __name__ == "__main__":
    main()
