"""Spec-faithful UTF-8 / UTF-16 reference codecs for differential work.

Implements encoding.bs sections utf-8-decoder, utf-8-encoder and
shared-utf-16-decoder (whatwg/encoding @ 2c3853e) as independent Python,
used to classify samples against CPython in gen_vectors.py: only samples
both agree on become test vectors.

Notes that shape the classification:
- CPython's utf-8 / utf-16-be / utf-16-le codecs are strict: invalid
  UTF-8, lone surrogates and odd lengths all raise, so those samples are
  skipped (counted) rather than compared — our replacement-mode behaviour
  is pinned by the hand-written tests in utf_wbtest.mbt instead.
- CPython's utf-8 encoder never fails, so the UTF-8 encode side gets
  full cross-checked coverage.
- encoding.bs defines NO UTF-16 encoder (§get an encoder asserts
  encoding is not replacement or UTF-16BE/LE), so UTF-16 suites are
  decode-only.
"""

def ref_utf8_decode(data) -> str:
    out = []
    cp = seen = needed = 0
    lower, upper = 0x80, 0xBF
    q = list(data)
    i = 0
    while i < len(q):
        b = q[i]
        i += 1
        if needed == 0:
            if b < 0x80:
                out.append(b)
            elif 0xC2 <= b <= 0xDF:
                needed = 1
                cp = b & 0x1F
            elif 0xE0 <= b <= 0xEF:
                if b == 0xE0:
                    lower = 0xA0
                if b == 0xED:
                    upper = 0x9F
                needed = 2
                cp = b & 0xF
            elif 0xF0 <= b <= 0xF4:
                if b == 0xF0:
                    lower = 0x90
                if b == 0xF4:
                    upper = 0x8F
                needed = 3
                cp = b & 0x7
            else:
                out.append(0xFFFD)
        elif b < lower or b > upper:
            cp = seen = needed = 0
            lower, upper = 0x80, 0xBF
            q[i - 1:i] = [b]
            out.append(0xFFFD)
        else:
            lower, upper = 0x80, 0xBF
            cp = (cp << 6) | (b & 0x3F)
            seen += 1
            if seen == needed:
                out.append(cp)
                cp = seen = needed = 0
    if needed != 0:
        out.append(0xFFFD)
    return "".join(chr(c) for c in out)


def ref_utf8_encode(text: str) -> bytes:
    out = bytearray()
    for ch in text:
        cp = ord(ch)
        if cp < 0x80:
            out.append(cp)
            continue
        if cp <= 0x07FF:
            count, offset = 1, 0xC0
        elif cp <= 0xFFFF:
            count, offset = 2, 0xE0
        else:
            count, offset = 3, 0xF0
        out.append((cp >> (6 * count)) + offset)
        for k in range(count - 1, -1, -1):
            out.append(0x80 | ((cp >> (6 * k)) & 0x3F))
    return bytes(out)


def ref_utf16_decode(data, is_be: bool) -> str:
    out = []
    lead_byte = -1
    lead_sur = -1
    q = list(data)
    i = 0
    while i < len(q):
        b = q[i]
        i += 1
        if lead_byte < 0:
            lead_byte = b
            continue
        unit = ((lead_byte << 8) | b) if is_be else ((b << 8) | lead_byte)
        lead_byte = -1
        if lead_sur >= 0:
            lead, lead_sur = lead_sur, -1
            if 0xDC00 <= unit <= 0xDFFF:
                out.append(0x10000 + ((lead - 0xD800) << 10) + (unit - 0xDC00))
                continue
            # spec: restore the CURRENT unit's two bytes and error
            hi, lo = unit >> 8, unit & 0xFF
            q[i - 1:i] = [hi, lo] if is_be else [lo, hi]
            out.append(0xFFFD)
            continue
        if 0xD800 <= unit <= 0xDBFF:
            lead_sur = unit
            continue
        if 0xDC00 <= unit <= 0xDFFF:
            out.append(0xFFFD)
            continue
        out.append(unit)
    if lead_byte >= 0 or lead_sur >= 0:
        out.append(0xFFFD)
    return "".join(chr(c) for c in out)


def utf8_samples(rng, n_random: int):
    """UTF-8 shapes: valid pieces, broken continuations, bare leads, raw runs."""
    pieces = [
        list("é中".encode("utf-8")),
        list(chr(0x1F600).encode("utf-8")),
        list("Hello ".encode("utf-8")),
        list(chr(0x10000).encode("utf-8")),
        list("߿ࠀ".encode("utf-8")),
    ]
    out = [[b] for b in range(256)]
    for _ in range(n_random):
        kind = rng.randrange(7)
        if kind == 0:
            out.append(list(rng.choice(pieces)))
        elif kind == 1:
            sample = []
            for _ in range(rng.randrange(1, 5)):
                sample += list(rng.choice(pieces))
            out.append(sample)
        elif kind == 2:  # lead byte then out-of-range / non-continuation
            out.append([
                rng.choice([0xE1, 0xED, 0xF0, 0xF4, 0xC3]),
                rng.choice([0x00, 0x41, 0xC0, 0xFF]),
                rng.choice([0x20, 0x80]),
            ])
        elif kind == 3:
            out.append([rng.randrange(0x80, 0x100) for _ in range(rng.randrange(1, 6))])
        elif kind == 4:
            out.append([rng.randrange(0x20, 0x7F) for _ in range(rng.randrange(1, 10))])
        elif kind == 5:  # bare lead at end of stream (truncation)
            out.append([rng.choice([0xC3, 0xE4, 0xF0])])
        else:
            out.append([rng.randrange(256) for _ in range(rng.randrange(1, 8))])
    return out


def _unit_bytes(unit: int, is_be: bool) -> list:
    """Bytes of one UTF-16 code unit. CPython refuses to *encode* lone
    surrogates (surrogates not allowed), so they are assembled here."""
    hi, lo = (unit >> 8) & 0xFF, unit & 0xFF
    return [hi, lo] if is_be else [lo, hi]


def utf16_samples(rng, n_random: int, is_be: bool):
    """UTF-16 shapes per endianness: BMP, astral (surrogate pairs), lone
    surrogates, odd truncations, BOM prefixes, plus the single-byte sweep
    (pending lead byte -> CPython strict raises -> skipped)."""
    enc = "utf-16-be" if is_be else "utf-16-le"
    out = []
    for _ in range(n_random):
        kind = rng.randrange(6)
        if kind == 0:
            out.append(list(chr(rng.randrange(0x20, 0x3000)).encode(enc)))
        elif kind == 1:  # astral -> surrogate pair
            out.append(list(chr(rng.randrange(0x10000, 0x110000)).encode(enc)))
        elif kind == 2:  # lone high surrogate then ASCII
            out.append(_unit_bytes(rng.randrange(0xD800, 0xDC00), is_be)
                       + list(chr(rng.randrange(0x41, 0x5B)).encode(enc)))
        elif kind == 3:  # lone low surrogate
            out.append(_unit_bytes(rng.randrange(0xDC00, 0xE000), is_be))
        elif kind == 4:  # odd truncation of a valid encoding
            sample = list(chr(rng.randrange(0x20, 0x3000)).encode(enc))
            out.append(sample[:-1])
        else:  # BOM prefix
            out.append([0xFF, 0xFE, 0x41, 0x00] if not is_be else [0xFE, 0xFF, 0x00, 0x41])
    out.extend([[b] for b in range(256)])
    return out


def gen_vectors(rng):
    """Returns (stats, decode_vectors, encode_vectors) per UTF encoding."""
    results = []

    # UTF-8: full encode coverage (CPython's utf-8 encoder never fails)
    dec, enc = [], []
    skipped = divergent = 0
    pool_cps = set(range(0x20, 0x7F))
    for sample in utf8_samples(rng, 170):
        data = bytes(sample)
        try:
            py_text = data.decode("utf-8")
        except UnicodeDecodeError:
            skipped += 1
            continue
        if ref_utf8_decode(sample) != py_text:
            divergent += 1
            continue
        dec.append((sample, py_text))
        pool_cps.update(ord(c) for c in py_text)
    specials = [0x0080, 0x07FF, 0x0800, 0xFFFF, 0x10000, 0x10FFFF, 0x4E2D, 0x1F600, 0x0000]
    for cp in sorted(pool_cps | set(specials)):
        text = chr(cp)
        py_bytes = text.encode("utf-8")
        if ref_utf8_encode(text) != py_bytes:
            divergent += 1
            continue
        enc.append((text, py_bytes))
    results.append((("UTF-8", "utf-8", len(dec), len(enc), skipped, divergent), dec, enc))

    # UTF-16BE / UTF-16LE: decode only (spec defines no encoder)
    for name, codec, is_be in (
        ("UTF-16BE", "utf-16-be", True),
        ("UTF-16LE", "utf-16-le", False),
    ):
        dec = []
        skipped = divergent = 0
        for sample in utf16_samples(rng, 170, is_be):
            data = bytes(sample)
            try:
                py_text = data.decode(codec)
            except UnicodeDecodeError:
                skipped += 1
                continue
            if ref_utf16_decode(sample, is_be) != py_text:
                divergent += 1
                continue
            dec.append((sample, py_text))
        results.append(((name, codec, len(dec), 0, skipped, divergent), dec, []))

    for stats, dec, enc in results:
        print(
            f"gen_vectors {stats[0]}: {len(dec)} decode / {len(enc)} encode "
            f"({stats[4]} CPython-error skips, {stats[5]} divergent)"
        )
    return results
