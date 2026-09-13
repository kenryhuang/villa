"""Player-only face sculpt and painted albedo, authored on the deform topology."""
import math
import bpy
import numpy as np
from mathutils import Vector


def paint_skin(body):
    # Fresh albedo: the source texture has baked black eye sockets and red lipstick.
    # These shadows must come from the scene lighting, not be painted onto the face.
    n=2048
    v,u=np.mgrid[0:n,0:n].astype(np.float32)/n
    pixels=np.ones((n,n,4),np.float32)
    pixels[:,:,:3]=(.915,.696,.548)
    def glaze(mask,color):
        a=np.clip(mask,0,1)[:,:,None]
        pixels[:,:,:3]=pixels[:,:,:3]*(1-a)+np.array(color)*a
    def oval(x,y,rx,ry):
        return np.exp(-(((u-x)/rx)**2+((v-y)/ry)**2)*2)
    # Broad warm cheeks; restrained nose and lip color, with no eye-bag mask.
    for x in [.687,.813]:
        glaze(oval(x,.490,.033,.037)*.22,(.92,.46,.36))
    glaze(oval(.750,.480,.014,.025)*.15,(.92,.48,.35))
    glaze(oval(.750,.420,.019,.012)*.57,(.68,.36,.29))
    # A shallow, relaxed brow arch. Taper its ends rather than drawing a thick ring.
    for x in [.709,.791]:
        t=(u-x)/.028
        arch=.605+.012*(1-t*t)
        width=.0042*np.sqrt(np.clip(1-t*t,0,1))+.0007
        mask=np.exp(-((v-arch)/width)**2)*np.clip((1-np.abs(t))*5,0,1)
        glaze(mask*.93,(.29,.18,.11))
    image=bpy.data.images.new('player_face_skin',n,n,alpha=False)
    image.pixels.foreach_set(pixels.ravel());image.pack()
    mat=body.data.materials[0].copy();mat.name='Player | warm face and skin'
    for node in mat.node_tree.nodes:
        if node.type=='TEX_IMAGE':node.image=image
    body.data.materials[0]=mat


def sculpt_face(body):
    keys=body.data.shape_keys.key_blocks
    base=keys[0]
    offsets=[]
    for i,vertex in enumerate(base.data):
        x,y,z=vertex.co
        delta=Vector()
        if y<-.04 and z>1.40:
            # Lift and spread the mouth corners; keep a closed, thin relaxed smile.
            mouth=math.exp(-((z-1.456)/.018)**2)
            corners=math.exp(-((abs(x)-.023)/.013)**2)*mouth
            delta.z+=.007*corners
            delta.x+=math.copysign(.0022*corners,x)
            delta.y-=.0015*corners
            # Fill the hollow below the eye without touching the eyelid rim.
            cheek=math.exp(-((abs(x)-.047)/.026)**2-((z-1.497)/.018)**2)
            delta.y-=.004*cheek
            # Smaller nose tip and less protruding lower lip.
            nose=math.exp(-(x/.018)**2-((z-1.492)/.016)**2)
            delta.y+=.003*nose
            lip=math.exp(-(x/.020)**2-((z-1.450)/.006)**2)
            delta.y+=.002*lip
            eyelid=math.exp(-((abs(x)-.039)/.029)**4-((z-1.529)/.022)**4)
            delta.z-=.13*(z-1.529)*eyelid
        front=max(0,min(1,(-y-.025)/.045))
        offsets.append(delta*front*front*(3-2*front))
    for key in keys:
        for vertex,delta in zip(key.data,offsets):vertex.co+=delta
    # bmesh garment cut-outs read Mesh.vertices and write Basis back from them.
    # Keep those coordinates in sync or that later operation silently discards
    # the neutral facial sculpt while retaining only the expression deltas.
    for vertex,basis_vertex in zip(body.data.vertices,base.data):
        vertex.co=basis_vertex.co
    body.data.update()
    paint_skin(body)
