#!/usr/bin/env python3
"""Ensamblado de modelos para MinotaurSatyr con Blender en modo script (sin interfaz).

Requiere el modulo bpy (pip install bpy). Los modelos se exportan del juego con
LSLib/Divine en formato glTF (.glb). Blender 5 ya no lee Collada (.dae).

Ejemplos:
  # Minotauro: cuerpo humano + cabeza y patas de minotauro, escala 1.18
  python3 kitbash.py --body humano.glb --part cabeza_mino.glb --part patas_mino.glb \
      --scale 1.18 --out minotauro.glb --preview minotauro.png

  # Satiro: cuerpo elfo + cuernos + patas
  python3 kitbash.py --body elfo.glb --part cuernos.glb --part patas_mino.glb \
      --out satiro.glb --preview satiro.png

  # Prueba sin archivos del juego (usa figuras simples)
  python3 kitbash.py --demo --preview demo.png

Cada --part se re-asigna al esqueleto del --body (mismos nombres de huesos en los
humanoides de BG3). Las partes con huesos que no existan en el cuerpo se avisan.
"""
import argparse
import sys
from pathlib import Path

import bpy


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_file(path):
    before = set(bpy.data.objects)
    ext = Path(path).suffix.lower()
    if ext == ".dae":
        sys.exit("Blender 5 no lee .dae: exportar desde Divine como .glb")
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    else:
        sys.exit(f"Formato no soportado: {path}")
    return [o for o in bpy.data.objects if o not in before]


def armature_of(objs):
    return next((o for o in objs if o.type == "ARMATURE"), None)


def rebind(part_objs, body_arm):
    """Pasa las mallas de una parte al esqueleto del cuerpo."""
    bones = {b.name for b in body_arm.data.bones}
    for o in part_objs:
        if o.type != "MESH":
            continue
        missing = {g.name for g in o.vertex_groups} - bones
        if missing:
            print(f"AVISO {o.name}: huesos que no existen en el cuerpo: {sorted(missing)[:10]}")
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = body_arm
        if not any(m.type == "ARMATURE" for m in o.modifiers):
            o.modifiers.new("Armature", "ARMATURE").object = body_arm
        o.parent = body_arm
    old = armature_of(part_objs)
    if old and old is not body_arm:
        bpy.data.objects.remove(old, do_unlink=True)


def delete_body_region(body_objs, groups):
    """Borra vertices del cuerpo (ej. cabeza o piernas humanas) por grupo de huesos."""
    for o in body_objs:
        if o.type != "MESH":
            continue
        idx = [o.vertex_groups[g].index for g in groups if g in o.vertex_groups]
        if not idx:
            continue
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for v in o.data.vertices:
            if any(g.group in idx and g.weight > 0.5 for g in v.groups):
                v.select = True
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.delete(type="VERT")
        bpy.ops.object.mode_set(mode="OBJECT")


def demo_scene():
    bpy.ops.object.armature_add()
    arm = bpy.context.object
    bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=1.0, location=(0, 0, 1.0))
    torso = bpy.context.object
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, 1.7))
    head = bpy.context.object
    for side in (-1, 1):
        bpy.ops.mesh.primitive_cone_add(radius1=0.06, depth=0.4, location=(side * 0.25, 0, 1.9),
                                        rotation=(0, side * 0.9, 0))
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.9, location=(-0.12, 0, 0.45))
    bpy.ops.mesh.primitive_cylinder_add(radius=0.09, depth=0.9, location=(0.12, 0, 0.45))
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.parent = arm
    return arm


def render_preview(path):
    scene = bpy.context.scene
    meshes = [o for o in scene.objects if o.type == "MESH"]
    zmax = max((o.matrix_world @ __import__("mathutils").Vector(c)).z
               for o in meshes for c in o.bound_box) if meshes else 2.0
    bpy.ops.object.camera_add(location=(0, -zmax * 2.4, zmax * 0.6), rotation=(1.5708, 0, 0))
    scene.camera = bpy.context.object
    bpy.ops.object.light_add(type="SUN", location=(2, -3, 4))
    bpy.context.object.data.energy = 3
    world = bpy.data.worlds.new("w")
    world.color = (0.08, 0.08, 0.1)
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.resolution_x, scene.render.resolution_y = 600, 900
    scene.render.filepath = str(Path(path).resolve())
    bpy.ops.render.render(write_still=True)
    print("preview:", path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--body")
    ap.add_argument("--part", action="append", default=[])
    ap.add_argument("--remove-groups", nargs="*", default=[],
                    help="grupos de huesos a borrar del cuerpo (ej. Head_M para sacar la cabeza humana)")
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--out")
    ap.add_argument("--preview")
    ap.add_argument("--demo", action="store_true")
    a = ap.parse_args()

    reset()
    if a.demo:
        arm = demo_scene()
    else:
        if not a.body:
            sys.exit("Falta --body (o usa --demo)")
        body = import_file(a.body)
        arm = armature_of(body)
        if arm is None:
            sys.exit("El cuerpo no tiene esqueleto")
        delete_body_region(body, a.remove_groups)
        for p in a.part:
            rebind(import_file(p), arm)

    arm.scale = (a.scale,) * 3
    bpy.context.view_layer.update()

    if a.out:
        out = Path(a.out)
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=str(out.with_suffix(".glb")))
        print("exportado:", out)
    if a.preview:
        render_preview(a.preview)


if __name__ == "__main__":
    main()
