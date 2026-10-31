"""Store lossless PNG representations in ICNS; avoid legacy ARGB edge conversion."""
from pathlib import Path
import struct
root=Path(__file__).resolve().parents[1]
iconset=root/'Resources/Icon/NotesPlus.iconset'
representations={
 'ic07':'icon_128x128.png','ic08':'icon_256x256.png','ic09':'icon_512x512.png','ic10':'icon_512x512@2x.png',
 'ic11':'icon_16x16@2x.png','ic12':'icon_32x32@2x.png','ic13':'icon_128x128@2x.png','ic14':'icon_256x256@2x.png'
}
chunks=[]
for kind,name in representations.items():
 data=(iconset/name).read_bytes()
 chunks.append(struct.pack('>4sI',kind.encode(),len(data)+8)+data)
body=b''.join(chunks)
(root/'Resources/AppIcon.icns').write_bytes(struct.pack('>4sI',b'icns',len(body)+8)+body)
