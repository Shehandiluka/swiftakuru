# Swift dictionary literals with duplicate keys crash at runtime: check all [..: ..] literals in Shared/ and Keyboard/
import re, sys, glob
bad = 0
for f in glob.glob('**/*.swift', recursive=True):
    src = open(f, encoding='utf8').read()
    for m in re.finditer(r'static let (\w+)\s*:\s*\[[^=\n]*:[^=\n]*\]\s*=\s*\[', src):
        i = m.end(); depth = 1; j = i
        while depth and j < len(src):
            c = src[j]
            if c == '[': depth += 1
            elif c == ']': depth -= 1
            j += 1
        body = src[i:j-1]
        # top-level keys: string literal followed by ':' at depth 0
        keys = []; d = 0; k = 0
        for mm in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*:|[\[\]()]', body):
            t = mm.group(0)
            if t in '[(': d += 1
            elif t in '])': d -= 1
            elif d == 0: keys.append(mm.group(1))
        dups = {x for x in keys if keys.count(x) > 1}
        if dups: bad += 1; print('DUP', f, m.group(1), dups)
        else: print('ok ', f, m.group(1), len(keys), 'keys')
sys.exit(1 if bad else 0)
