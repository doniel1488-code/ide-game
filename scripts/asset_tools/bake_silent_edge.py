"""Bake the original Silent Edge spacecraft and relay models into importable GLB."""
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models"
PALETTE = [
    ("Ceramic ivory", (.78, .79, .73), .25, .46),
    ("Graphite frame", (.045, .062, .074), .52, .48),
    ("Rescue orange", (.85, .245, .045), .22, .5),
    ("Cockpit glass", (.048, .20, .24), .58, .18),
    ("Machined titanium", (.33, .39, .41), .63, .42),
    ("Photovoltaic cells", (.055, .11, .22), .47, .32),
    ("White navigation lamp", (.73, .89, .92), .15, .3),
    ("Hunter amber sensor", (.91, .29, .045), .12, .35),
    ("Wisp violet sensor", (.39, .11, .68), .12, .35),
]
parts = defaultdict(list)


def surface(material, polygon, center):
    # Orient convex faces outward independently of the ring traversal.
    a, b, c = polygon[:3]
    u, v = ([p[i] - a[i] for i in range(3)] for p in (b, c))
    normal = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
    outward = sum(normal[i] * (sum(p[i] for p in polygon)/len(polygon)-center[i]) for i in range(3))
    if outward < 0:
        polygon = polygon[::-1]
        normal = tuple(-n for n in normal)
    length = math.sqrt(sum(n*n for n in normal))
    normal = tuple(n/length for n in normal)
    for j in range(1, len(polygon)-1):
        for p in (polygon[0], polygon[j], polygon[j+1]):
            parts[material].append((p, normal))


def loft(rings, material, panels=None, caps=None):
    center = tuple(sum(p[i] for ring in rings for p in ring) / sum(map(len, rings)) for i in range(3))
    surface(material if caps is None else caps[0], rings[0], center)
    surface(material if caps is None else caps[1], rings[-1], center)
    for station, (front, rear) in enumerate(zip(rings, rings[1:])):
        for i in range(len(front)):
            j = (i+1) % len(front)
            surface(material if panels is None else panels(station, i), [front[i], front[j], rear[j], rear[i]], center)


def fuselage(profiles, material, panels=None, x=0):
    sides = [(-.67,1),(.67,1),(1,.38),(1,-.32),(.56,-1),(-.56,-1),(-1,-.32),(-1,.38)]
    loft([[(x+w*dx, y+h*dy, z) for dx,dy in sides] for z,w,y,h in profiles], material, panels)


def prism(points, bottom, material, sides=None):
    loft([[(x,y-bottom,z) for x,y,z in points], points], sides if sides is not None else material,
         caps=(sides if sides is not None else material, material))


def disk(x, y, profile, material, segments=12, caps=None):
    loft([[(x+r*math.cos(i*math.tau/segments), y+r*math.sin(i*math.tau/segments), z)
           for i in range(segments)] for z,r in profile], material, caps=caps)


def block(x, y, z, width, height, length, material):
    prism([(x-width/2,y+height/2,z-length/2),(x+width/2,y+height/2,z-length/2),
           (x+width/2,y+height/2,z+length/2),(x-width/2,y+height/2,z+length/2)], height, material)


def kepler():
    fuselage([(-2.89,.16,.56,.09),(-2.32,.39,.57,.19),(-1.35,.65,.59,.31),
              (.18,.79,.59,.34),(1.29,.69,.59,.28),(1.87,.46,.55,.21)], 0,
             lambda station, face: 1 if face in (3,4,5) else (2 if station==0 and face in (1,2,6,7) else 0))
    fuselage([(-1.96,.19,.78,.05),(-1.29,.38,.92,.22),(-.53,.43,1.04,.25),
              (.36,.39,.99,.20),(.85,.29,.84,.05)], 3,
             lambda station, face: 1 if face in (3,4,5) or station==3 else 3)
    for side in (-1,1):
        def wing(points, thickness, mat, edge=1):
            prism([(side*x,y,z) for x,y,z in points], thickness, mat, edge)
        wing([(.57,.57,-.91),(1.54,.45,-.53),(2.76,.32,.54),(2.25,.34,1.36),
              (1.53,.43,1.54),(.65,.55,1.03)], .19, 0)
        wing([(1.61,.46,-.40),(2.68,.35,.56),(2.25,.37,1.22),(1.72,.42,.72)], .05, 2)
        wing([(.94,.62,.94),(1.53,.61,1.06),(1.66,.91,1.72),(1.30,.77,1.87)], .12, 0, 1)
        x = side*1.35
        fuselage([(-.68,.17,.48,.10),(-.33,.32,.49,.25),(.70,.41,.50,.31),
                  (1.29,.40,.50,.30),(1.62,.33,.50,.25)], 0,
                 lambda station, face: 1 if face in (3,4,5) else (2 if station==2 else 0), x)
        disk(x,.50,[(1.59,.287),(1.73,.287),(1.87,.222)],4,caps=(4,1))
        disk(x,.50,[(1.87,.132),(1.895,.123)],6)
        for i in range(5):
            block(x,.813,.02+i*.13,.41,.033,.057,1)
        for i in range(3):
            block(side*(.24+i*.06),.925,.67+i*.13,.042,.018,.095,4)
        block(side*2.51,.348,.62,.088,.066,.13,6)
        block(side*.57,.85,-1.35,.026,.027,.41,1)
    block(0,.652,-2.54,.23,.054,.15,4)
    block(0,.41,1.82,.64,.21,.18,1)


def relay():
    fuselage([(-.77,.42,.65,.31),(-.38,.63,.67,.47),(.53,.62,.67,.47),(.88,.42,.67,.31)],
             4, lambda j, i: 0 if i in (0,1,7) else 1)
    for side in (-1,1):
        block(side*.82,.81,0,.77,.14,.20,4)
        block(side*1.39,.78,0,.78,.12,1.47,1)
        for i in range(6):
            for j in range(2):
                block(side*(1.215+j*.345),.852,-.604+i*.242,.285,.027,.193,5)
        block(side*.39,1.18,.52,.17,.44,.18,2)
    block(0,1.44,-.26,.26,1.1,.25,4)
    block(0,2.47,-.26,.115,1.5,.115,4)
    disk(0,2.10,[(-.69,.28),(-.49,.54),(-.39,.54),(-.30,.24)],0,caps=(3,4))
    disk(0,2.10,[(-.72,.127),(-.69,.127)],6)
    block(0,3.27,-.26,.14,.11,.14,6)


def hunter():
    fuselage([(-.82,.30,.17,.12),(-.39,.51,.13,.24),(.31,.47,.10,.20),(.60,.26,.11,.12)],
             1, lambda j,i: 4 if i in (0,1,7) else 1)
    disk(0,.18,[(-.88,.115),(-.82,.16)],7)
    for side in (-1,1):
        prism([(side*.32,.18,.24),(side*.86,.15,.12),(side*1.05,.06,-.58),
               (side*.76,.08,-.47),(side*.55,.18,-.10)], .12, 4, 1)
        block(side*.46,.05,.52,.25,.23,.42,1)
        disk(side*.46,.05,[(.73,.088),(.78,.08)],7)


def wisp():
    fuselage([(-.68,.11,.20,.09),(-.28,.37,.25,.21),(.26,.36,.25,.19),(.59,.24,.20,.10)], 1)
    disk(0,.22,[(-.7,.10),(-.64,.12)],8)
    for side in (-1,1):
        prism([(side*.17,.32,-.38),(side*.9,.13,.14),(side*.57,.11,.63),
               (side*.30,.24,.29)], .09, 1,4)
        prism([(side*.46,.18,.09),(side*.82,.14,.21),(side*.59,.14,.42)],.035,8)
    prism([(-.09,.65,.27),(.09,.65,.27),(.16,.36,-.12),(-.16,.36,-.12)],.14,4)


def wreck():
    fuselage([(-1.79,.50,.36,.27),(-1.22,1.55,.37,.47),(.71,1.53,.34,.49),
              (1.36,1.24,.29,.32),(1.69,.74,.27,.18)], 1,
             lambda j,i: 4 if i in (0,1,7) else 1)
    for side in (-1,1):
        reach = 3.8 if side == 1 else 2.8
        prism([(side*1.06,.68,-1.06),(side*(reach-.18),.45,-.66),(side*reach,.35,.42),
               (side*2.02,.54,.72),(side*1.15,.67,.48)], .23,4,1)
        for station in range(5):
            block(side*(1.70+station*.19),.645,-.34,.09,.035,.55,1)
        block(side*1.16,.64,-.58,.12,.03,.58,2)
    for side in (-1,1):
        disk(side*.65,.25,[(1.15,.31),(1.43,.34),(1.71,.23)],1,caps=(1,4))
    block(0,.98,-.48,.68,.19,.65,1)


def save(name):
    doc = {"asset":{"version":"2.0","generator":"Lumen Drift original asset bake"},
           "scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0}],
           "meshes":[{"primitives":[]}],"materials":[],
           "buffers":[],"bufferViews":[],"accessors":[]}
    for index,(label,color,metal,rough) in enumerate(PALETTE):
        item = {"name":label,"pbrMetallicRoughness":{"baseColorFactor":[*color,1],"metallicFactor":metal,"roughnessFactor":rough}}
        if index >= 6: item["emissiveFactor"] = [v * .68 for v in color]
        doc["materials"].append(item)
    data = bytearray()
    for material,vertices in sorted(parts.items()):
        attrs = {}
        for index, label in enumerate(("POSITION","NORMAL")):
            offset = len(data)
            for v in vertices:
                data.extend(struct.pack("<3f",*v[index]))
            view = len(doc["bufferViews"])
            doc["bufferViews"].append({"buffer":0,"byteOffset":offset,"byteLength":len(data)-offset,"target":34962})
            accessor = {"bufferView":view,"componentType":5126,"count":len(vertices),"type":"VEC3"}
            if not index:
                accessor["min"] = [min(v[0][i] for v in vertices) for i in range(3)]
                accessor["max"] = [max(v[0][i] for v in vertices) for i in range(3)]
            attrs[label] = len(doc["accessors"])
            doc["accessors"].append(accessor)
        doc["meshes"][0]["primitives"].append({"attributes":attrs,"material":material})
    doc["buffers"].append({"byteLength":len(data)})
    meta = json.dumps(doc,separators=(",",":")).encode()
    meta += b" " * (-len(meta)%4)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/f"{name}.glb").write_bytes(struct.pack("<4sII",b"glTF",2,28+len(meta)+len(data)) +
        struct.pack("<I4s",len(meta),b"JSON")+meta+struct.pack("<I4s",len(data),b"BIN\0")+data)
    parts.clear()


if __name__ == "__main__":
    for model in (kepler, relay, hunter, wisp, wreck):
        model()
        save(model.__name__)
