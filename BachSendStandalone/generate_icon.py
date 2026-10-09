# Offline app icon generator (stdlib only). Brand: B + PRODUCT.
import math, struct, zlib
SIZE=1024
LABEL="SEND"
font={
"B":["11110","10001","10001","11110","10001","10001","11110"],
"F":["11111","10000","10000","11110","10000","10000","10000"],
"I":["11111","00100","00100","00100","00100","00100","11111"],
"N":["10001","11001","10101","10101","10011","10001","10001"],
"D":["11110","10001","10001","10001","10001","10001","11110"],
"S":["01111","10000","10000","01110","00001","00001","11110"],
"E":["11111","10000","10000","11110","10000","10000","11111"]
}
def letter_on(letter,x,y,origin_x,origin_y,pixel):
    if letter not in font: return False
    i=(x-origin_x)//pixel
    j=(y-origin_y)//pixel
    return 0<=i<5 and 0<=j<7 and font[letter][j][i]=="1"

scale=32
word_w=(len(LABEL)*6-1)*scale
word_x=(SIZE-word_w)//2
big_scale=67
big_x=(SIZE-5*big_scale)//2
buf=bytearray()
for y in range(SIZE):
    row=bytearray([0])
    for x in range(SIZE):
        dx=x-512;dy=y-410
        glow=max(0.0,1-math.hypot(dx,dy)/620)
        v=y/SIZE
        r=int(8+13*v+5*glow)
        g=int(22+24*v+35*glow)
        b=int(52+34*v+59*glow)
        # round translucent brand tile around initial
        if 240<=x<785 and 112<=y<674:
            edge=min(x-240,784-x,y-112,673-y)
            if edge>33 or (edge>=0 and math.hypot(max(34-edge,0),max(34-edge,0))<=35):
                r=min(255,r+7);g=min(255,g+13);b=min(255,b+29)
        # large bold initial with spectral colored rim
        if letter_on("B",x,y,big_x,150,big_scale):
            r=int(45+50*x/SIZE);g=int(203+37*y/SIZE);b=255
        # product wordmark
        for k,ch in enumerate(LABEL):
            if letter_on(ch,x,y,word_x+k*6*scale,750,scale):
                r,g,b=236,247,255
                break
        row.extend((r,g,b))
    buf.extend(row)
def chunk(tag,data):
    return struct.pack("!I",len(data))+tag+data+struct.pack("!I",zlib.crc32(tag+data)&0xffffffff)
png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack("!2I5B",SIZE,SIZE,8,2,0,0,0))+chunk(b"IDAT",zlib.compress(buf,7))+chunk(b"IEND",b"")
with open("BachSend/Assets.xcassets/AppIcon.appiconset/AppIcon.png","wb") as f:f.write(png)
print("Brand icon",LABEL,"bytes",len(png))
