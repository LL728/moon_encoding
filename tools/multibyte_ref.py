"""Spec-faithful Big5 / Shift_JIS reference codecs for differential work.

Implements encoding.bs sections big5 and shift_jis (whatwg/encoding @
2c3853e) as independent Python, used two ways:

1. classification against CPython in gen_vectors.py (only samples both
   agree on become test vectors), and
2. the generators import the encode-map builders here so the *rules*
   (Big5 filtered/first/six-last pointer, Shift_JIS NEC-row exclusion)
   live in exactly one place.

Known spec/CPython divergences handled by exclusion and covered by hand
tests in multibyte_wbtest.mbt: Shift_JIS byte 0x80, the EUDC PUA range
(f040/f9fc), Big5's named two-code-point sequences (8862 etc.), the
Big5 euro extension (a3e1), and 817c (spec: U+FF0D, CPython: U+2212).
"""

BIG5_NAMED = {
    1133: (0x00CA, 0x0304), 1135: (0x00CA, 0x030C),
    1164: (0x00EA, 0x0304), 1166: (0x00EA, 0x030C),
}
BIG5_SIX = {0x2550, 0x255E, 0x2561, 0x256A, 0x5341, 0x5345}
BIG5_ENCODE_MIN_POINTER = (0xA1 - 0x81) * 157  # 5024
SJIS_EXCLUDED_RANGE = range(8272, 8836)  # NEC duplicate rows


def ref_big5_decode(data, index) -> str:
    out = []
    lead = 0
    q = list(data)
    i = 0
    while i < len(q):
        b = q[i]
        i += 1
        if lead:
            lid, lead = lead, 0
            pointer = None
            if 0x40 <= b <= 0x7E or 0xA1 <= b <= 0xFE:
                offset = 0x40 if b < 0x7F else 0x62
                pointer = (lid - 0x81) * 157 + (b - offset)
            if pointer is not None:
                if pointer in BIG5_NAMED:
                    out.extend(BIG5_NAMED[pointer])
                    continue
                if pointer < len(index) and index[pointer] is not None:
                    out.append(index[pointer])
                    continue
            if b < 0x80:
                q[i - 1:i] = [b]
            out.append(0xFFFD)
        elif b < 0x80:
            out.append(b)
        elif 0x81 <= b <= 0xFE:
            lead = b
        else:
            out.append(0xFFFD)
    if lead:
        out.append(0xFFFD)
    return "".join(chr(c) for c in out)


def ref_big5_encode(text, big5_enc):
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if cp < 0x80:
            out.append(cp)
            continue
        pointer = big5_enc.get(cp)
        if pointer is None:
            return None
        lead = pointer // 157 + 0x81
        trail = pointer % 157
        offset = 0x40 if trail < 0x3F else 0x62
        out += bytes([lead, trail + offset])
    return bytes(out)


def ref_sjis_decode(data, jis) -> str:
    out = []
    lead = 0
    q = list(data)
    i = 0
    while i < len(q):
        b = q[i]
        i += 1
        if lead:
            lid, lead = lead, 0
            pointer = None
            if 0x40 <= b <= 0x7E or 0x80 <= b <= 0xFC:
                offset = 0x40 if b < 0x7F else 0x41
                lead_offset = 0x81 if lid < 0xA0 else 0xC1
                pointer = (lid - lead_offset) * 188 + (b - offset)
            if pointer is not None:
                if 8836 <= pointer <= 10715:
                    out.append(0xE000 - 8836 + pointer)
                    continue
                if pointer < len(jis) and jis[pointer] is not None:
                    out.append(jis[pointer])
                    continue
            if b < 0x80:
                q[i - 1:i] = [b]
            out.append(0xFFFD)
        elif b < 0x80 or b == 0x80:
            out.append(b)
        elif 0xA1 <= b <= 0xDF:
            out.append(0xFF61 - 0xA1 + b)
        elif 0x81 <= b <= 0x9F or 0xE0 <= b <= 0xFC:
            lead = b
        else:
            out.append(0xFFFD)
    if lead:
        out.append(0xFFFD)
    return "".join(chr(c) for c in out)


def ref_sjis_encode(text, sjis_enc):
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if cp < 0x80 or cp == 0x80:
            out.append(cp)
        elif cp == 0x00A5:
            out.append(0x5C)
        elif cp == 0x203E:
            out.append(0x7E)
        elif 0xFF61 <= cp <= 0xFF9F:
            out.append(cp - 0xFF61 + 0xA1)
        else:
            if cp == 0x2212:
                cp = 0xFF0D
            pointer = sjis_enc.get(cp)
            if pointer is None:
                return None
            lead = pointer // 188
            lead_offset = 0x81 if lead < 0x1F else 0xC1
            trail = pointer % 188
            offset = 0x40 if trail < 0x3F else 0x41
            out += bytes([lead + lead_offset, trail + offset])
    return bytes(out)


def big5_encode_map(index):
    """encoding.bs index Big5 pointer: filtered (pointer >= 5024), first
    occurrence, except the six code points which take the LAST pointer."""
    first, last = {}, {}
    for ptr in range(BIG5_ENCODE_MIN_POINTER, len(index)):
        cp = index[ptr]
        if cp is None:
            continue
        if cp not in first:
            first[cp] = ptr
        last[cp] = ptr
    enc = dict(first)
    for cp in BIG5_SIX:
        if cp in last:
            enc[cp] = last[cp]
    return enc


def sjis_encode_map(jis):
    """encoding.bs index Shift_JIS pointer: exclude pointers 8272..8835,
    first occurrence over the remaining index."""
    enc = {}
    for ptr, cp in enumerate(jis):
        if ptr in SJIS_EXCLUDED_RANGE:
            continue
        if cp is not None and cp not in enc:
            enc[cp] = ptr
    return enc


def multibyte_samples(rng, n_random: int):
    """Generic structured samples for lead/trail encodings (Big5, Shift_JIS,
    later EUC-KR/EUC-JP): singles, plausible pairs, broken pairs, raw runs."""
    out = [[b] for b in range(256)]
    big5_trails = list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF))
    sjis_trails = list(range(0x40, 0x7F)) + list(range(0x80, 0xFD))
    for _ in range(n_random):
        kind = rng.randrange(6)
        if kind == 0:
            out.append([rng.choice(big5_trails), rng.choice(big5_trails)])
        elif kind == 1:
            out.append([
                rng.choice([0x81, 0x88, 0xA1, 0xA4, 0xFE]),
                rng.choice(big5_trails),
                rng.choice([0x81, 0xFE, 0x20]),
            ])
        elif kind == 2:
            out.append([rng.choice([0x82, 0x90, 0xF0]), rng.choice(sjis_trails)])
        elif kind == 3:
            out.append([rng.randrange(0x20, 0x7F) for _ in range(rng.randrange(1, 10))])
        elif kind == 4:
            out.append([rng.choice([0x81, 0xFE]), rng.choice([0x20, 0x7F, 0xA0, 0xFD])])
        else:
            out.append([rng.randrange(256) for _ in range(rng.randrange(1, 8))])
    return out


def gen_vectors(indexes, rng):
    """Classify samples against CPython; returns per-encoding stats + vectors."""
    big5 = indexes["big5"]
    jis = indexes["jis0208"]
    big5_enc = big5_encode_map(big5)
    sjis_enc = sjis_encode_map(jis)
    results = []
    for name, codec, ref_dec, ref_enc, enc_map in (
        ("Big5", "big5",
         lambda d: ref_big5_decode(d, big5), ref_big5_encode, big5_enc),
        ("Shift_JIS", "shift_jis",
         lambda d: ref_sjis_decode(d, jis), ref_sjis_encode, sjis_enc),
    ):
        dec_vecs, enc_vecs = [], []
        skipped = divergent = 0
        pool_cps = set(range(0x20, 0x7F))
        for sample in multibyte_samples(rng, 170):
            data = bytes(sample)
            try:
                py_text = data.decode(codec)
            except UnicodeDecodeError:
                skipped += 1
                continue
            if ref_dec(sample) != py_text:
                divergent += 1
                continue
            dec_vecs.append((sample, py_text))
            pool_cps.update(ord(c) for c in py_text)
        specials = [0x20AC, 0x3000, 0x5341, 0x2550, 0x4F60, 0x597D, 0x65E5,
                    0x672C, 0x8A9E, 0xFF61, 0xFF9F, 0x00A5, 0x203E, 0x2212,
                    0xFF0D, 0x00A4]
        for cp in sorted(pool_cps | set(specials)):
            text = chr(cp)
            try:
                py_bytes = text.encode(codec)
            except UnicodeEncodeError:
                skipped += 1
                continue
            ref_bytes = ref_enc(text, enc_map)
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
            ref_bytes = ref_enc(text, enc_map)
            if ref_bytes is None or ref_bytes != py_bytes:
                divergent += 1
                continue
            enc_vecs.append((text, py_bytes))
        stats = (name, codec, len(dec_vecs), len(enc_vecs), skipped, divergent)
        results.append((stats, dec_vecs, enc_vecs))
        print(
            f"gen_vectors {name}: {len(dec_vecs)} decode / {len(enc_vecs)} encode "
            f"({skipped} CPython-error skips, {divergent} divergent)"
        )
    return results
