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
        ('file limit', png(), 524288, True), ('oversize bytes', png(), 524289, False),
        ('TREX proportions', png(300, 280), 37276, True),
        ('square PNG', png(360, 360), 54, True),
        ('portrait PNG', png(272, 480), 54, True),
        ('wide area boundary', png(512, 255), 54, True),
        ('tall area boundary', png(255, 512), 54, True),
        ('wide pixel overflow', png(512, 256), 54, False),
        ('tall pixel overflow', png(256, 512), 54, False),
        ('square pixel overflow', png(362, 362), 54, False),
        ('large square', png(512, 512), 54, False),
        ('wide edge overflow', png(513, 1), 54, False),
        ('tall edge overflow', png(1, 513), 54, False),
        ('zero PNG', png(0), 54, False),
        ('multiplication overflow', png(65536, 65536), 54, False),
        ('negative PNG', png(0xffffffff), 54, False), ('short PNG', png()[:24], 24, False),
        ('overflow DIB size', bytes(oversized_dib), 54, False),
        ('BMP', bmp(), 54, True), ('top-down BMP', bmp(height=-272), 54, True),
        ('core BMP', bmp(core=True), 54, True),
        ('square BMP', bmp(360, 360), 54, True),
        ('portrait core BMP', bmp(272, 480, core=True), 54, True),
        ('top-down TREX BMP', bmp(300, -280), 54, True),
        ('32-bit BMP file budget', bmp(512, 255), 54 + 512 * 255 * 4, True),
        ('wide BMP', bmp(513, 1), 54, False),
        ('tall BMP', bmp(1, -513), 54, False),
        ('BMP pixel overflow', bmp(512, -256), 54, False),
        ('core BMP pixel overflow', bmp(512, 512, core=True), 54, False),
        ('BMP multiplication overflow', bmp(65536, 65536), 54, False),
        ('negative BMP width', bmp(width=-1), 54, False),
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
 reads=reads+1;assert(count<=54,"header read must be bounded");return string.sub(current,1,count)
end}
'''
    for label, data, size, expected in cases:
        body += 'current=' + quoted(data) + ';size=' + str(size) + ';reads=0\n'
        body += f'assert(checkImage("test")=={str(expected).lower()},"{label}")\n'
        if size > 524288:
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
