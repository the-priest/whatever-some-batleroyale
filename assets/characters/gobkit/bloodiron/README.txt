Gobkit Free Character Pack Vol.10 — 8 CC0 rigged & animated low-poly characters (GLB)
https://gobkit.com/freebies

Characters: Bloodiron Knight, Bloodiron Shieldwall, Bloodiron Smith, Orc Pyromancer, Bloodiron Juggernaut, Bloodiron Halberdier, Bloodiron Grunt, Orc Chain Brute
Each .glb has its texture baked in, plus the shared atlas Texture001.png.
All of them share one skeleton, so their clips play on each other.

Animation: 7 clips per character @ 30 fps (some characters have more, listed below), each its own named clip:
  Idle | Walk | Run (loops) | Death (play once, hold) | Hit | Attack | Special
  Every character's clips are made for what it holds (one-handed, long weapon, pistol / bow, rifle, its own props). Special:
  BloodironKnight.glb  one-handed    Special = cheer
  BloodironShieldwall.glb one-handed    Special = jump
  BloodironSmith.glb   one-handed    Special = cheer
  OrcPyromancer.glb    one-handed    Special = cheer
  BloodironJuggernaut.glb long weapon   Special = jump
  BloodironHalberdier.glb long weapon   Special = jump
  BloodironGrunt.glb   one-handed    Special = jump
  OrcChainBrute.glb    one-handed    Special = jump
  Play by name — do not slice by frame range.

Three.js quick start:
  import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
  new GLTFLoader().load('BloodironKnight.glb', (g) => { scene.add(g.scene);
    const mixer = new THREE.AnimationMixer(g.scene);
    mixer.clipAction(THREE.AnimationClip.findByName(g.animations, 'Walk')).play(); });

How to put it in your game
--------------------------
Each .glb holds the whole model: one mesh, its skeleton, its texture and its clips. Y is up, the model faces +Z and
stands on its origin. Sizes are in glTF units (1 unit = 1 metre in Unity, Godot and Unreal); scale each model to the
size your game needs. Play the clips that come with each model, by name.

  Unity     Package Manager > + > Add package by name > com.unity.cloud.gltfast, then drop the .glb into Assets.
            In its Inspector set Animation Method to Mecanim (Animator) or Legacy (Animation); the clips keep their names.
  Godot 4   Drop the .glb into the FileSystem dock and drag it into a scene; the clips are in its AnimationPlayer:
            $AnimationPlayer.play("Walk"). To loop a clip: select the .glb > Import dock > Advanced... > the clip >
            Loop Mode: Linear > Reimport.
  Unreal 5  Drag the .glb into the Content Browser (glTF import is built in). On 5.8 set Skeletal Meshes > Combine
            Skeletal Meshes to "Combine All That Use Same Skeleton".
  Blender   File > Import > glTF 2.0 (.glb/.gltf); the clips are Actions (Dope Sheet > Action Editor).
  Three.js  The quick start above; to make a model h units tall:
            const b = new THREE.Box3().setFromObject(g.scene, true); g.scene.scale.multiplyScalar(h / (b.max.y - b.min.y));

Sizes in the rest pose (height x width x length, units):
  BloodironGrunt 2.1 x 4.5 x 1.8  |  BloodironHalberdier 2.6 x 4.3 x 2.8  |  BloodironJuggernaut 2.5 x 4.2 x 2.3
  BloodironKnight 3.0 x 4.3 x 3.6  |  BloodironShieldwall 2.3 x 5.7 x 2.0  |  BloodironSmith 2.4 x 4.3 x 2.5
  OrcChainBrute 2.0 x 4.4 x 1.6  |  OrcPyromancer 2.2 x 4.2 x 2.5

License: CC0 1.0 (public domain) — any use, commercial or personal, no attribution required.
More free CC0 assets: https://gobkit.com/freebies
