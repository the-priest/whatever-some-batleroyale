Gobkit Free Animal Pack Vol.3 — 10 CC0 rigged & animated low-poly farm animals (GLB)
https://gobkit.com/freebies

Animals: HolsteinCow, HighlandCow, Bull, Calf, Pig, SpottedPig, Piglet, Sheep, BlackSheep, Lamb
Each .glb is one model with its texture baked in, plus the shared atlas Texture001.png.

Animation: 4 clips per model @ 24 fps:
  idle (loop) | attack (loop) | dead (play once, hold) | walk (loop)
  Play by name — do not slice by frame range.

Three.js quick start:
  import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
  new GLTFLoader().load('Pig.glb', (g) => { scene.add(g.scene);
    const mixer = new THREE.AnimationMixer(g.scene);
    mixer.clipAction(THREE.AnimationClip.findByName(g.animations, 'walk')).play(); });

License: CC0 1.0 (public domain) — any use, commercial or personal, no attribution required.
More free CC0 assets: https://gobkit.com/freebies
