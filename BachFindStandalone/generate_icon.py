import struct, zlib, math
W=1024
def rgb(x,y):
    d=((x-485)**2+(y-420)**2)**.5
    bg=(int(9+10*y/W),int(19+25*y/W),int(42+32*y/W))
    ring=abs(d-255)<32 and x>175 and y>110 and x<790 and y<760
    handle=abs((x-465)-(y-740))<30 and 670<y<880 and 650<x<850
    glow=d<225
    if ring or handle:return (85,222,252)
    if glow:return (16,70,109)
    return bg
raw=b''.join(b'\0'+b''.join(bytes(rgb(x,y)) for x in range(W)) for y in range(W))
def c(tag,dat):return struct.pack('!I',len(dat))+tag+dat+struct.pack('!I',zlib.crc32(tag+dat)&0xffffffff)
data=b'\x89PNG\r\n\x1a\n'+c(b'IHDR',struct.pack('!2I5B',W,W,8,2,0,0,0))+c(b'IDAT',zlib.compress(raw,6))+c(b'IEND',b'')
open('BachFind/Assets.xcassets/AppIcon.appiconset/AppIcon.png','wb').write(data)
