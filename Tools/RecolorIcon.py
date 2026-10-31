"""User-authorized exact native-icon recolor. Never resamples or modifies alpha."""
from pathlib import Path
from PIL import Image
import colorsys
import hashlib
import json
import math

root=Path(__file__).resolve().parents[1]
source=root/'Resources/Icon/NativeSource'
out=root/'Resources/Icon/NotesPlus.iconset'
out.mkdir(parents=True,exist_ok=True)
target_rgb=(0,122,255)
target_h,_,_=colorsys.rgb_to_hsv(*(v/255 for v in target_rgb))
reference=Image.open(source/'native-1024.png').convert('RGBA')
base=reference.getpixel((512,205))
_,base_s,base_v=colorsys.rgb_to_hsv(*(v/255 for v in base[:3]))
files={16:['icon_16x16.png'],32:['icon_16x16@2x.png','icon_32x32.png'],64:['icon_32x32@2x.png'],128:['icon_128x128.png'],256:['icon_128x128@2x.png','icon_256x256.png'],512:['icon_256x256@2x.png','icon_512x512.png'],1024:['icon_512x512@2x.png']}
report={'source':'NSWorkspace native rendering of /System/Applications/Notes.app','targetAccentHex':'#007AFF','anchorSourceRGBA':base,'resampling':False,'geometryChanged':False,'sizes':[]}
for size,names in files.items():
    original=Image.open(source/f'native-{size}.png').convert('RGBA')
    old=list(original.getdata()); new=[]; changed=0; outside_equal=True
    for i,(r,g,b,a) in enumerate(old):
        h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
        yellow=a>0 and .09<=h<=.20 and s>.12 and i//size<math.ceil(size*.31)
        value=(r,g,b,a)
        if yellow:
            rgb=colorsys.hsv_to_rgb(target_h,min(1,s/base_s),min(1,v/base_v))
            value=tuple(round(c*255) for c in rgb)+(a,)
            changed += value!=(r,g,b,a)
        else:
            outside_equal &= value==(r,g,b,a)
        new.append(value)
    result=Image.new('RGBA',original.size);result.putdata(new)
    assert original.getchannel('A').tobytes()==result.getchannel('A').tobytes()
    assert outside_equal
    # The paper body, its horizontal rules and all transparency are byte-identical.
    y=math.ceil(size*.31)
    assert original.crop((0,y,size,size)).tobytes()==result.crop((0,y,size,size)).tobytes()
    for name in names: result.save(out/name)
    report['sizes'].append({'pixels':size,'changedPixels':changed,'alphaIdentical':True,'outsideYellowMaskIdentical':True,'paperBodyAndBindingDotsIdentical':True,'nativeRGBAHash':hashlib.sha256(original.tobytes()).hexdigest(),'recoloredRGBAHash':hashlib.sha256(result.tobytes()).hexdigest()})
    if size==1024:
        result.save(root/'Resources/Icon/NotesPlus-blue-exact.png')
        left=original.resize((384,384),Image.Resampling.LANCZOS)
        right=result.resize((384,384),Image.Resampling.LANCZOS)
        comparison=Image.new('RGBA',(768,384),(0,0,0,0)); comparison.paste(left,(0,0)); comparison.paste(right,(384,0))
        comparison.save(root/'build/icon-comparison.png')
        report['anchorOutputRGBA']=result.getpixel((512,205))
(root/'build/icon-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('7 native sizes recolored. Alpha, geometry and all non-yellow pixels preserved exactly.')
print('Header base:',report['anchorOutputRGBA'],'; target accent:',target_rgb)
