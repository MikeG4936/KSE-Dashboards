#!/usr/bin/env python3
"""Exercise bounded image header checks with the pinned EdgeTX runner."""
import argparse
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def quoted(data):
    return '"' + ''.join('\\%03d' % value for value in data) + '"'


def png(width=480, height=272):
    return b'\x89PNG\r\n\x1a\n' + struct.pack('>I', 13) + b'IHDR' + struct.pack('>II', width, height) + bytes(30)


def bmp(width=480, height=272, core=False):
    data = bytearray(54)
    data[:2] = b'BM'
    struct.pack_into('<I', data, 14, 12 if core else 40)
    struct.pack_into('<HH' if core else '<ii', data, 18, width, height)
    return bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', required=True, type=Path)
    args = parser.parse_args()
    oversized_dib = bytearray(bmp())
    struct.pack_into("<I", oversized_dib, 14, 0x7fffffff)
    cases = [
        ('PNG', png(), 102400, True), ('small PNG', png(1, 1), 54, True),
        ('oversize bytes', png(), 102401, False), ('wide PNG', png(481), 54, False),
        ('tall PNG', png(height=273), 54, False), ('zero PNG', png(0), 54, False),
        ('negative PNG', png(0xffffffff), 54, False), ('short PNG', png()[:24], 24, False),
        ('overflow DIB size', bytes(oversized_dib), 54, False),
        ('BMP', bmp(), 54, True), ('top-down BMP', bmp(height=-272), 54, True),
        ('core BMP', bmp(core=True), 54, True), ('wide BMP', bmp(width=481), 54, False),
        ('tall BMP', bmp(height=-273), 54, False), ('negative BMP width', bmp(width=-1), 54, False),
        ('invalid BMP height', bmp(height=-2147483648), 54, False),
        ('unrecognized', bytes(54), 54, False), ('read truncated', png()[:30], 54, False),
    ]
    for n in (4, 5):
        for name in ('default.png', 'default1.png'):
            data = (ROOT / f'KSE{n}' / name).read_bytes()
            cases.append((f'KSE{n}/{name}', data[:54], len(data), True))
    prefix = '''lcd={RGB=function()return 0 end};model={getInfo=function()return{name="Test"}end}
getTime=function()return 0 end;getValue=function()return 0 end;getFieldInfo=function()end
'''
    body = '''
local current, size, reads
fstat=function()return {size=size}end
io={open=function()return {}end,close=function()end,read=function(_,count)
 reads=reads+1;assert(count<=54,"header read must be bounded");return current:sub(1,count)
end}
'''
    for label, data, size, expected in cases:
        body += 'current=' + quoted(data) + ';size=' + str(size) + ';reads=0\n'
        body += f'assert(checkImage("test")=={str(expected).lower()},"{label}")\n'
        if size > 102400:
            body += 'assert(reads==0,"oversized file must be rejected before reading")\n'
    body += '''
fstat=function()error("removed card")end;assert(checkImage("test")==false)
fstat=nil;assert(checkImage("test")==false)
fstat=function()return{size=54}end;io.open=function()error("read failure")end
assert(checkImage("test")==false)
'''
    for n in (4, 5):
        source = (ROOT / f'KSE{n}/main.lua').read_text()
        marker = source.rindex('\nreturn {')
        source = source[:marker] + '\ncheckImage=modelImageAllowed\n' + body
        with tempfile.TemporaryDirectory(prefix='kse-assets-') as tmp:
            path = Path(tmp) / 'assets.lua'
            path.write_text(prefix + source)
            subprocess.run([str(args.runner.resolve()), str(path)], check=True, timeout=60)
        print(f'PASS KSE{n}: {len(cases)+3} image bounds/header/failure cases')


if __name__ == '__main__':
    main()
