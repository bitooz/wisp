# python trellis.py NAME TYPE SEED [SEED...]   (in the t2 env, from ~/T2; results go to ~/job/out)
# TRELLIS.2-4B from ~/job/out/NAME-rgba.png (the cut-out gen.py made for Hunyuan, so both get the same
# picture), one textured GLB per seed. TYPE is the pipeline: 1024_cascade or 1536_cascade.
import os, sys, time
os.environ['OPENCV_IO_ENABLE_OPENEXR'] = '1'
os.environ['PYTORCH_CUDA_ALLOC_CONF'] = 'expandable_segments:True'
sys.path.insert(0, os.path.expanduser('~/T2'))
import torch
from PIL import Image
from trellis2.pipelines import Trellis2ImageTo3DPipeline
import o_voxel

J = os.path.expanduser('~/job')
name, kind, seeds = sys.argv[1], sys.argv[2], [int(s) for s in sys.argv[3:]]
pipe = Trellis2ImageTo3DPipeline.from_pretrained(os.path.expanduser('~/T2W'))
pipe.cuda()
img = Image.open(f'{J}/out/{name}-rgba.png').convert('RGBA')
for seed in seeds:
    t = time.time()
    mesh = pipe.run(img, seed=seed, pipeline_type=kind)[0]
    mesh.simplify(16777216)
    glb = o_voxel.postprocess.to_glb(
        vertices=mesh.vertices, faces=mesh.faces, attr_volume=mesh.attrs, coords=mesh.coords,
        attr_layout=mesh.layout, voxel_size=mesh.voxel_size, aabb=[[-0.5, -0.5, -0.5], [0.5, 0.5, 0.5]],
        decimation_target=300000, texture_size=2048, remesh=True, remesh_band=1, remesh_project=0)
    tag = 't' if kind == '1024_cascade' else 'T'
    glb.export(f'{J}/out/{name}-{tag}{seed}.glb')
    print('trellis', name, kind, seed, round(time.time() - t, 1), 's', torch.cuda.max_memory_allocated() >> 20, 'MB', flush=True)
    torch.cuda.empty_cache()
print('T2_DONE', flush=True)
