"""Spec-faithful GBK/gb18030 reference codec for differential classification.

encoding.bs (whatwg/encoding @ 2c3853e) and CPython genuinely diverge in
several corners: byte 0x80 decode (spec: U+20AC, CPython raises), 0xA3A0
(spec: U+3000, CPython: U+E5E5), U+E5E5 encode (spec: error, CPython: a3a0),
the PUA side table, and pointer 7457 (spec: U+E7C7 special case).

Only samples where BOTH this reference and CPython agree become test vectors;
everything else is counted and skipped. The spec-only behavior is covered by
hand-written unit tests in chinese_wbtest.mbt.
"""

SIDE_TABLE = {
    0xE78D: (0xA6, 0xD9), 0xE78E: (0xA6, 0xDA), 0xE78F: (0xA6, 0xDB),
    0xE790: (0xA6, 0xDC), 0xE791: (0xA6, 0xDD), 0xE792: (0xA6, 0xDE),
    0xE793: (0xA6, 0xDF), 0xE794: (0xA6, 0xEC), 0xE795: (0xA6, 0xED),
    0xE796: (0xA6, 0xF3), 0xE81E: (0xFE, 0x59), 0xE826: (0xFE, 0x61),
    0xE82B: (0xFE, 0x66), 0xE82C: (0xFE, 0x67), 0xE832: (0xFE, 0x6D),
    0xE843: (0xFE, 0x7E), 0xE854: (0xFE, 0x90), 0xE864: (0xFE, 0xA0),
}


def ranges_code_point(pointer: int, ranges):
    """encoding.bs: index gb18030 ranges code point (decoder side)."""
    if (39419 < pointer < 189000) or pointer > 1237575:
        return None
    if pointer == 7457:
        return 0xE7C7
    best = None
    for ptr, cp in ranges:
        if ptr <= pointer:
            best = (ptr, cp)
        else:
            break
    return best[1] + (pointer - best[0])


def ranges_pointer(code_point: int, ranges):
    """encoding.bs: index gb18030 ranges pointer (encoder side)."""
    if code_point == 0xE7C7:
        return 7457
    best = None
    for ptr, cp in ranges:
        if cp <= code_point:
            best = (ptr, cp)
        else:
            break
    if best is None:
        return None
    return best[0] + (code_point - best[1])


def ref_decode(data, index, ranges) -> str:
    """encoding.bs gb18030 decoder (== GBK decoder), incl. end-of-queue."""
    out = []
    first = second = third = 0
    q = list(data)
    i = 0
    while i < len(q):
        b = q[i]
        i += 1
        if third:
            if not (0x30 <= b <= 0x39):
                q[i - 1:i] = [second, third, b]
                first = second = third = 0
                out.append(0xFFFD)
            else:
                pointer = ((first - 0x81) * 12600) + ((second - 0x30) * 1260) + \
                    ((third - 0x81) * 10) + (b - 0x30)
                first = second = third = 0
                cp = ranges_code_point(pointer, ranges)
                out.append(0xFFFD if cp is None else cp)
        elif second:
            if 0x81 <= b <= 0xFE:
                third = b
            else:
                q[i - 1:i] = [second, b]
                first = second = 0
                out.append(0xFFFD)
        elif first:
            if 0x30 <= b <= 0x39:
                second = b
            else:
                lead, first = first, 0
                pointer = None
                if 0x40 <= b <= 0x7E or 0x80 <= b <= 0xFE:
                    offset = 0x40 if b < 0x7F else 0x41
                    pointer = (lead - 0x81) * 190 + (b - offset)
                cp = None
                if pointer is not None and pointer < len(index):
                    cp = index[pointer]
                if cp is not None:
                    out.append(cp)
                else:
                    if b < 0x80:
                        q[i - 1:i] = [b]
                    out.append(0xFFFD)
        elif b < 0x80:
            out.append(b)
        elif b == 0x80:
            out.append(0x20AC)
        elif 0x81 <= b <= 0xFE:
            first = b
        else:
            out.append(0xFFFD)
    if first or second or third:
        out.append(0xFFFD)
    return "".join(chr(c) for c in out)


def ref_encode(text: str, first_ptr, ranges, is_gbk):
    """encoding.bs gb18030 encoder (GBK = is_gbk True). None = unmappable."""
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if cp < 0x80:
            out.append(cp)
            continue
        if cp == 0xE5E5:
            return None
        if is_gbk and cp == 0x20AC:
            out.append(0x80)
            continue
        if cp in SIDE_TABLE:
            out += bytes(SIDE_TABLE[cp])
            continue
        pointer = first_ptr.get(cp)
        if pointer is not None:
            lead = pointer // 190 + 0x81
            trail = pointer % 190
            offset = 0x40 if trail < 0x3F else 0x41
            out += bytes([lead, trail + offset])
            continue
        if is_gbk:
            return None
        p = ranges_pointer(cp, ranges)
        if p is None:
            return None
        b1 = p // 12600
        p %= 12600
        b2 = p // 1260
        p %= 1260
        b3 = p // 10
        b4 = p % 10
        out += bytes([b1 + 0x81, b2 + 0x30, b3 + 0x81, b4 + 0x30])
    return bytes(out)


def samples(rng, n_random: int):
    """Byte samples mixing every shape the state machine cares about."""
    out = [[b] for b in range(256)]  # full single-byte sweep
    for _ in range(n_random):
        kind = rng.randrange(6)
        if kind == 0:
            out.append([rng.randrange(0x20, 0x7F) for _ in range(rng.randrange(1, 12))])
        elif kind == 1:  # plausible double-byte
            out.append([
                rng.choice([0x81, 0x90, 0xA1, 0xD6, 0xFE]),
                rng.choice(list(range(0x40, 0x7F)) + list(range(0x80, 0xFF))),
            ])
        elif kind == 2:  # plausible four-byte
            out.append([rng.randrange(0x81, 0xFF), rng.randrange(0x30, 0x3A),
                        rng.randrange(0x81, 0xFF), rng.randrange(0x30, 0x3A)])
        elif kind == 3:  # broken sequences that exercise Restore
            out.append([rng.choice([0x81, 0xFE]), rng.choice([0x20, 0x30, 0x41, 0xFF]),
                        rng.choice([0x20, 0x81, 0x41])])
        elif kind == 4:
            out.append([0x80] if rng.random() < 0.5 else [0xFF])
        else:
            out.append([rng.randrange(256) for _ in range(rng.randrange(1, 8))])
    return out


def gen_vectors(indexes, rng):
    """Classify samples against CPython; return per-encoding stats + vectors."""
    index = indexes["gb18030"]
    ranges = indexes["gb18030-ranges"]
    first_ptr = {}
    for pointer, cp in enumerate(index):
        if cp is not None and cp not in first_ptr:
            first_ptr[cp] = pointer

    results = []
    for name, is_gbk in (("GBK", True), ("gb18030", False)):
        codec = "gbk" if name == "GBK" else "gb18030"
        dec_vecs, enc_vecs = [], []
        skipped = divergent = 0
        pool_cps = set(range(0x20, 0x7F))
        for sample in samples(rng, 150):
            data = bytes(sample)
            try:
                py_text = data.decode(codec)
            except UnicodeDecodeError:
                skipped += 1
                continue
            if ref_decode(sample, index, ranges) != py_text:
                divergent += 1
                continue
            dec_vecs.append((sample, py_text))
            pool_cps.update(ord(c) for c in py_text)
        specials = [0x00AC, 0x00A9, 0x20AC, 0x3000, 0x4E02, 0x4E2D, 0x6587,
                    0xFE10, 0xE78D, 0xE7C7, 0xE5E5, 0x10000, 0x10034]
        for cp in sorted(pool_cps | set(specials)):
            text = chr(cp)
            try:
                py_bytes = text.encode(codec)
            except UnicodeEncodeError:
                skipped += 1
                continue
            ref_bytes = ref_encode(text, first_ptr, ranges, is_gbk)
            if ref_bytes is None or ref_bytes != py_bytes:
                divergent += 1
                continue
            enc_vecs.append((text, py_bytes))
        for _ in range(60):
            text = "".join(chr(rng.choice(sorted(pool_cps)))
                           for _ in range(rng.randrange(1, 20)))
            try:
                py_bytes = text.encode(codec)
            except UnicodeEncodeError:
                skipped += 1
                continue
            ref_bytes = ref_encode(text, first_ptr, ranges, is_gbk)
            if ref_bytes is None or ref_bytes != py_bytes:
                divergent += 1
                continue
            enc_vecs.append((text, py_bytes))
        stats = (name, codec, len(dec_vecs), len(enc_vecs), skipped, divergent)
        results.append((stats, dec_vecs, enc_vecs))
        print(
            f"gen_vectors chinese: {name}: {len(dec_vecs)} decode / {len(enc_vecs)} encode "
            f"({skipped} CPython-error skips, {divergent} divergent)"
        )
    return results
