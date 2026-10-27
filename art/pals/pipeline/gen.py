# python gen.py shape NAME SEED [SEED...]   shapes from ~/job/in/NAME.png, one per seed
# python gen.py paint NAME SEED [SEED...]   the PBR texture for each of those shapes
# (run from ~/H21; results go to ~/job/out). Hunyuan3D-2.1: the shape at 50 steps and octree 512,
# the paint from eight views at 768.
import sys, os, time, torch
sys.path.insert(0, './hy3dshape'); sys.path.insert(0, './hy3dpaint')
from PIL import Image

J = os.path.expanduser('~/job')
step, name, seeds = sys.argv[1], sys.argv[2], [int(s) for s in sys.argv[3:]]
rgba = f'{J}/out/{name}-rgba.png'

if step == 'shape':
    from hy3dshape.rembg import BackgroundRemover
    from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
    from hy3dshape.postprocessors import FloaterRemover, DegenerateFaceRemover, FaceReducer
    import numpy as np
    img = np.array(BackgroundRemover()(Image.open(f'{J}/in/{name}.png').convert('RGB')))
    # The cut-out leaves a faint haze over the white background, which comes out as a floor plate:
    # keep only the clearly solid part, with a narrow soft edge.
    img[:, :, 3] = np.clip((img[:, :, 3].astype(float) - 96) * 4, 0, 255).astype(np.uint8)
    img = Image.fromarray(img)
    img.save(rgba)
    shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained('tencent/Hunyuan3D-2.1')
    for seed in seeds:
        t = time.time()
        m = shape(image=img, num_inference_steps=50, octree_resolution=512, num_chunks=200000, guidance_scale=5.0,
                  generator=torch.manual_seed(seed), output_type='trimesh')[0]
        m = FloaterRemover()(m); m = DegenerateFaceRemover()(m)
        m = FaceReducer()(m, max_facenum=60000)
        m.export(f'{J}/out/{name}-s{seed}.obj')
        print('shape', name, seed, len(m.faces), 'faces', round(time.time() - t, 1), 's', flush=True)
else:
    # (The paint pipeline imports Blender's bpy for its own GLB export, which isn't used here.)
    import types; sys.modules.setdefault('bpy', types.ModuleType('bpy'))
    from textureGenPipeline import Hunyuan3DPaintPipeline, Hunyuan3DPaintConfig
    paint = Hunyuan3DPaintPipeline(Hunyuan3DPaintConfig(max_num_view=8, resolution=768))
    # Decode the views one at a time: all at once ran out of a 24 GB card's memory on a full figure.
    paint.models['multiview_model'].pipeline.vae.enable_slicing()
    for seed in seeds:
        t = time.time()
        os.makedirs(f'{J}/out/{name}-p{seed}', exist_ok=True)
        paint(mesh_path=f'{J}/out/{name}-s{seed}.obj', image_path=rgba,
              output_mesh_path=f'{J}/out/{name}-p{seed}/textured.obj', use_remesh=False, save_glb=False)
        print('paint', name, seed, round(time.time() - t, 1), 's', flush=True)
        torch.cuda.empty_cache()
print('GEN_DONE', flush=True)
