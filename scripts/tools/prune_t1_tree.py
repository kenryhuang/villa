"""Prune complete sapling branch families before reducing needle density."""
import bpy,bmesh
import numpy as np
from mathutils import kdtree

def prune_tree(trunk, leaves):
    mesh=trunk.data
    points=np.empty((len(mesh.vertices),3),dtype=np.float64)
    mesh.vertices.foreach_get('co',points.reshape(-1))
    parents=list(range(len(points)))
    def find(x):
        while parents[x]!=x:
            parents[x]=parents[parents[x]];x=parents[x]
        return x
    for edge in mesh.edges:
        a,b=edge.vertices;parents[find(b)]=find(a)
    groups={}
    for i in range(len(points)):groups.setdefault(find(i),[]).append(i)
    groups=sorted(groups.values(),key=lambda ids:ids[0])
    # Source tubes have eight vertices per ring and are ordered base to tip.
    assert all(len(ids)%8==0 for ids in groups)
    centers=[points[ids].reshape(-1,8,3).mean(axis=1) for ids in groups]
    entries=[(i,ring,p) for i,path in enumerate(centers) for ring,p in enumerate(path)]
    tree=kdtree.KDTree(len(entries))
    for index,(_,_,point) in enumerate(entries):tree.insert(point,index)
    tree.balance()
    hierarchy=[-1]
    attachment_errors=[]
    for i in range(1,len(groups)):
        if len(groups[i])==168:
            # This source's 35 first-order branches all have 21 eight-sided rings.
            # Their roots coincide at whorls; do not mistake a sibling for a parent.
            hierarchy.append(0)
            continue
        candidates=[(entries[index][0],distance) for _,index,distance in tree.find_n(centers[i][0],80)
                    if entries[index][0]<i and entries[index][1]>0]
        assert candidates, f'No parent found for branch {i}'
        parent,distance=candidates[0]
        assert distance<.15, f'Uncertain branch attachment {i}: {distance}'
        hierarchy.append(parent);attachment_errors.append(distance)
    primary=[i for i,parent in enumerate(hierarchy) if parent==0]
    # Remove all three low whorls, including the last tier below the crown.
    # Keep the existing opening on one side of the next whorl.
    removed={i for i in primary if centers[i][0][2]<1.85}
    for low,high in [(2.15,2.4)]:
        whorl=[i for i in primary if low<centers[i][0][2]<high]
        if len(whorl)>=3:removed.add(whorl[-1])
    primary_removed=sorted(removed)
    for i,parent in enumerate(hierarchy):
        if parent in removed:removed.add(i)
    dead_vertices={v for i in removed for v in groups[i]}

    leaf_mesh=leaves.data
    leaf_points=np.empty((len(leaf_mesh.vertices),3),dtype=np.float64)
    leaf_mesh.vertices.foreach_get('co',leaf_points.reshape(-1))
    assert len(leaf_mesh.vertices)==4*len(leaf_mesh.polygons)
    # Needles grow on the source's terminal five-ring twigs, not the main stem.
    # Searching those specifically prevents orphan needles being reassigned to
    # the trunk or another primary branch after their parent is cut.
    twig_entries=[entry for entry in entries if len(groups[entry[0]])==40]
    twig_tree=kdtree.KDTree(len(twig_entries))
    for index,(_,_,point) in enumerate(twig_entries):twig_tree.insert(point,index)
    twig_tree.balance()
    # Needle root is the quad corner nearest an original terminal centreline.
    # Classify before deletion, so needles follow their removed branch family.
    rng=np.random.default_rng(260914)
    keep=[];cut_by_branch=0
    original_needles=len(leaf_mesh.polygons)
    for polygon in leaf_mesh.polygons:
        ids=list(polygon.vertices);quad=leaf_points[ids]
        nearest=[twig_tree.find(point) for point in quad]
        corner=min(range(4),key=lambda j:nearest[j][2])
        branch=twig_entries[nearest[corner][1]][0]
        if branch in removed:
            cut_by_branch+=1;continue
        height=float(quad.mean(axis=0)[2])
        probability=.48 if height<3 else .62
        if rng.random()>probability:continue
        # Widen surviving needles slightly, without extending their length or roots.
        # This retains readable foliage as individual needle count is reduced.
        edges=[np.linalg.norm(quad[(j+1)%4]-quad[j]) for j in range(4)]
        short=int(np.argmin(edges))
        for a,b in [(short,(short+1)%4),((short+2)%4,(short+3)%4)]:
            middle=(quad[a]+quad[b])*.5
            quad[a]=middle+(quad[a]-middle)*1.18
            quad[b]=middle+(quad[b]-middle)*1.18
        leaf_points[ids]=quad
        keep.extend(ids)
    leaf_mesh.vertices.foreach_set('co',leaf_points.reshape(-1))
    for obj,discard in [(trunk,dead_vertices),(leaves,set(range(len(leaf_points)))-set(keep))]:
        bm=bmesh.new();bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm,geom=[bm.verts[i] for i in discard],context='VERTS')
        bm.to_mesh(obj.data);bm.free();obj.data.update()
    bpy.context.view_layer.objects.active=trunk
    modifier=trunk.modifiers.new('Reduce pruned branch tubes','DECIMATE')
    modifier.ratio=.38
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return {'branches_before':len(groups)-1,'branches_after':len(groups)-1-len(removed),
            'primary_branches_before':len(primary),'primary_branches_removed':primary_removed,
            'lowest_remaining_primary_height_m':float(min(centers[i][0][2] for i in primary if i not in removed)),
            'needles_before':original_needles,'needles_removed_with_branches':cut_by_branch,
            'needles_after':len(leaf_mesh.polygons),'max_parent_attachment_error_m':max(attachment_errors),
            'trunk_decimate_ratio':.38,'needle_width_multiplier':1.18}
