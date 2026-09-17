"""Read Project Zomboid's compiled Java classes without a JDK.

PZ ships no javap, so this parses class files straight out of projectzomboid.jar. It answers the
questions that kept costing research time: does a method exist, what are its overloads, and what
does its body call or read.

    python tools/pz_bytecode.py methods  zombie/Lua/Event
    python tools/pz_bytecode.py disasm   zombie/Lua/Event trigger
    python tools/pz_bytecode.py refs     zombie/characters/IsoGameCharacter leepingTablet
    python tools/pz_bytecode.py strings  'zombie/Lua/LuaManager$GlobalObject' sendServer

Class names use slashes, with no .class suffix. Quote names containing `$`.
disasm prints only calls, field reads/writes, constants, branches and returns -- enough to follow
control flow, not a full disassembly. Set PZ_JAR to point somewhere other than the default.
"""

import os
import re
import struct
import sys
import zipfile

JAR = os.environ.get("PZ_JAR", r"D:\SteamLibrary\steamapps\common\ProjectZomboid\projectzomboid.jar")

# Instruction lengths for fixed-size opcodes; tableswitch/lookupswitch/wide are handled inline.
LEN = {op: 1 for op in range(256)}
for op in (0x10, 0x12, 0x15, 0x16, 0x17, 0x18, 0x19, 0x36, 0x37, 0x38, 0x39, 0x3A, 0xA9, 0xBC):
    LEN[op] = 2
for op in (0x11, 0x13, 0x14, 0x84, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xBB, 0xBD, 0xC0, 0xC1,
           0xC6, 0xC7, *range(0x99, 0xA9)):
    LEN[op] = 3
for op in (0xB9, 0xBA, 0xC8, 0xC9):
    LEN[op] = 5
LEN[0xC5] = 4

REF_OPS = {
    0xB2: "getstatic", 0xB3: "putstatic", 0xB4: "getfield", 0xB5: "putfield",
    0xB6: "invokevirtual", 0xB7: "invokespecial", 0xB8: "invokestatic",
    0xB9: "invokeinterface", 0xBA: "invokedynamic", 0x12: "ldc", 0x13: "ldc_w",
    0xBB: "new", 0xC0: "checkcast", 0xC1: "instanceof",
}


def u2(b, o):
    return struct.unpack(">H", b[o:o + 2])[0]


def s4(b, o):
    return struct.unpack(">i", b[o:o + 4])[0]


def u4(b, o):
    return struct.unpack(">I", b[o:o + 4])[0]


def read_class(name):
    with zipfile.ZipFile(JAR) as jar:
        return jar.read(name + ".class")


def parse(data):
    """Returns (methods, refname, utf8_strings); methods are (name, descriptor, code bytes or None)."""
    o = 8
    count = u2(data, o)
    o += 2
    cp = [None] * count
    i = 1
    while i < count:
        tag = data[o]
        if tag == 1:
            length = u2(data, o + 1)
            cp[i] = ("utf8", data[o + 3:o + 3 + length].decode("utf8", "replace"))
            o += 3 + length
        elif tag in (3, 4):
            cp[i] = ("num",)
            o += 5
        elif tag in (5, 6):
            cp[i] = ("num",)
            o += 9
            i += 1
        elif tag in (7, 8, 16):
            cp[i] = ({7: "class", 8: "str", 16: "mt"}[tag], u2(data, o + 1))
            o += 3
        elif tag in (9, 10, 11):
            cp[i] = ("ref", u2(data, o + 1), u2(data, o + 3))
            o += 5
        elif tag == 12:
            cp[i] = ("nat", u2(data, o + 1), u2(data, o + 3))
            o += 5
        elif tag == 15:
            cp[i] = ("mh",)
            o += 4
        elif tag in (17, 18):
            cp[i] = ("dyn", u2(data, o + 1), u2(data, o + 3))
            o += 5
        elif tag in (19, 20):
            cp[i] = ("mod",)
            o += 3
        else:
            raise ValueError("unknown constant pool tag %d" % tag)
        i += 1

    def utf(index):
        return cp[index][1]

    def refname(index):
        e = cp[index]
        if e[0] == "ref":
            owner = utf(cp[e[1]][1]).split("/")[-1]
            nat = cp[e[2]]
            return "%s.%s %s" % (owner, utf(nat[1]), utf(nat[2]))
        if e[0] == "dyn":
            return "indy:" + utf(cp[e[2]][1])
        if e[0] == "str":
            return '"%s"' % utf(e[1])
        if e[0] == "class":
            return "class:" + utf(e[1])
        return str(e[0])

    o += 6
    interfaces = u2(data, o)
    o += 2 + 2 * interfaces
    members = []
    for _ in range(2):  # fields, then methods
        n = u2(data, o)
        o += 2
        members = []
        for _ in range(n):
            name, desc, attrs = utf(u2(data, o + 2)), utf(u2(data, o + 4)), u2(data, o + 6)
            o += 8
            code = None
            for _ in range(attrs):
                attr_name, attr_len = utf(u2(data, o)), u4(data, o + 2)
                if attr_name == "Code":
                    code_len = u4(data, o + 10)
                    code = data[o + 14:o + 14 + code_len]
                o += 6 + attr_len
            members.append((name, desc, code))
    strings = [e[1] for e in cp if e and e[0] == "utf8"]
    return members, refname, strings


def instructions(code):
    pc = 0
    while pc < len(code):
        op = code[pc]
        if op == 0xAA:
            p = (pc + 4) & ~3
            length = p + 12 + 4 * (s4(code, p + 8) - s4(code, p + 4) + 1) - pc
        elif op == 0xAB:
            p = (pc + 4) & ~3
            length = p + 8 + 8 * s4(code, p + 4) - pc
        elif op == 0xC4:
            length = 6 if code[pc + 1] == 0x84 else 4
        else:
            length = LEN[op]
        yield pc, op
        pc += length


def disasm(code, refname):
    for pc, op in instructions(code):
        if op in REF_OPS:
            index = code[pc + 1] if op == 0x12 else u2(code, pc + 1)
            try:
                target = refname(index)
            except Exception:
                target = "#%d" % index
            print("  %5d %-15s %s" % (pc, REF_OPS[op], target))
        elif 0x99 <= op <= 0xA8 or op in (0xC6, 0xC7):
            print("  %5d branch 0x%02x -> %d" % (pc, op, pc + struct.unpack(">h", code[pc + 1:pc + 3])[0]))
        elif 0xAC <= op <= 0xB1:
            print("  %5d return" % pc)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("methods", "disasm", "refs", "strings"):
        print(__doc__)
        return 1
    command, class_name = argv[1], argv[2]
    methods, refname, strings = parse(read_class(class_name))

    if command == "methods":
        for name, desc, _ in methods:
            print(name, desc)
    elif command == "strings":
        needle = argv[3] if len(argv) > 3 else ""
        for s in sorted(set(strings)):
            if needle in s and re.match(r"^[A-Za-z_$][\w$/;()\[<>.]*$", s):
                print(s)
    elif command == "disasm":
        for name, desc, code in methods:
            if name == argv[3] and code is not None:
                print("== %s%s" % (name, desc))
                disasm(code, refname)
    elif command == "refs":
        needle = argv[3]
        for name, desc, code in methods:
            if code is None:
                continue
            hits = set()
            for pc, op in instructions(code):
                if op in REF_OPS and op not in (0x12,):
                    try:
                        target = refname(u2(code, pc + 1))
                    except Exception:
                        continue
                    if needle in target:
                        hits.add("%s %s" % (REF_OPS[op], target))
            if hits:
                print("%s%s" % (name, desc))
                for hit in sorted(hits):
                    print("    " + hit)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
