import struct,zlib,math
W=1024
def pixel(x,y):
    r=int(13+20*y/W);g=int(25+20*y/W);b=int(52+35*y/W)
    wave=abs(y-(350+100*math.sin((x-160)/550*math.pi)))<30 and 170<x<850
    wave2=abs(y-(610+100*math.sin((x-160)/550*math.pi)))<30 and 170<x<850
    if wave:return (108,228,248)
    if wave2:return (116,167,255)
    return (r,g,b)
raw=b''.join(b'\0'+b''.join(bytes(pixel(x,y)) for x in range(W)) for y in range(W))
def chunk(k,d):return struct.pack('!I',len(d))+k+d+struct.pack('!I',zlib.crc32(k+d)&0xffffffff)
open('BachSend/Assets.xcassets/AppIcon.appiconset/AppIcon.png','wb').write(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',W,W,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,6))+chunk(b'IEND',b''))
