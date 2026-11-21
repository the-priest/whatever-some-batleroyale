Gobkit Free Insect Pack Vol.2 — 30 CC0 rigged & animated low-poly insects (GLB)
https://gobkit.com/freebies

Insects: Atlas beetle, Caucasus Beetle, Elephant beetle, Neptune Beetle, Golofa Beetle, Five-horned Rhinoceros Beetle, Golden stag beetle, Giraffe stag beetle, Lesser Stag Beetle, Sacred Scarab, Rainbow Scarab, MinotaurBeetle, Moon-horned Dung Beetle, Rose Chafer, Flower chafer, Deer-horned Flower Beetle, Titan beetle, Rosalia longhorn, Asian Long-horned Beetle, Harlequin Beetle, AsianLadyBeetle, TwentyEightSpotLadybird, Spotted Cucumber Beetle, LeafBeetle, AcornWeevil, Leaf-rolling Weevil, JewelBeetle, Eyed Click Beetle, Manticora, Cardinal Beetle
Each .glb is one model with its texture baked in, plus the shared atlas Texture001.png.
All insects in this pack share one skeleton, so their clips play on each other.

Animation: 19 clips in every model @ 24 fps, 30 frames each:
  idle | walk | run | attack
  hit | dead | alert | eat | groom | turnL | turnR | back | sense | sleep
  tripod | push | dig | flip | threat

Each insect also has clips of its own:
  Atlas beetle: + -
  Caucasus Beetle: + -
  Elephant beetle: + -
  Neptune Beetle: + -
  Golofa Beetle: + fly | dart | buzz | perch | takeoff | land | glide | fall
  Five-horned Rhinoceros Beetle: + -
  Golden stag beetle: + -
  Giraffe stag beetle: + -
  Lesser Stag Beetle: + -
  Sacred Scarab: + -
  Rainbow Scarab: + -
  MinotaurBeetle: + -
  Moon-horned Dung Beetle: + -
  Rose Chafer: + -
  Flower chafer: + -
  Deer-horned Flower Beetle: + -
  Titan beetle: + -
  Rosalia longhorn: + -
  Asian Long-horned Beetle: + -
  Harlequin Beetle: + -
  AsianLadyBeetle: + -
  TwentyEightSpotLadybird: + -
  Spotted Cucumber Beetle: + -
  LeafBeetle: + -
  AcornWeevil: + -
  Leaf-rolling Weevil: + -
  JewelBeetle: + -
  Eyed Click Beetle: + -
  Manticora: + -
  Cardinal Beetle: + -
  Every clip except dead / takeoff / land / fall loops. Play by name — do not slice by frame range.

Three.js quick start:
  import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
  new GLTFLoader().load('AtlasBeetle.glb', (g) => { scene.add(g.scene);
    const mixer = new THREE.AnimationMixer(g.scene);
    mixer.clipAction(THREE.AnimationClip.findByName(g.animations, 'walk')).play(); });

How to put it in your game
--------------------------
Each .glb holds the whole model: one mesh, its skeleton, its texture and its clips. Y is up, the model faces +Z and
stands on its origin. Sizes are in glTF units (1 unit = 1 metre in Unity, Godot and Unreal); scale each model to the
size your game needs. Play the clips that come with each model, by name.

  Unity     Package Manager > + > Add package by name > com.unity.cloud.gltfast, then drop the .glb into Assets.
            In its Inspector set Animation Method to Mecanim (Animator) or Legacy (Animation); the clips keep their names.
  Godot 4   Drop the .glb into the FileSystem dock and drag it into a scene; the clips are in its AnimationPlayer:
            $AnimationPlayer.play("walk"). To loop a clip: select the .glb > Import dock > Advanced... > the clip >
            Loop Mode: Linear > Reimport.
  Unreal 5  Drag the .glb into the Content Browser (glTF import is built in). On 5.8 set Skeletal Meshes > Combine
            Skeletal Meshes to "Combine All That Use Same Skeleton".
  Blender   File > Import > glTF 2.0 (.glb/.gltf); the clips are Actions (Dope Sheet > Action Editor).
  Three.js  The quick start above; to make a model h units tall:
            const b = new THREE.Box3().setFromObject(g.scene, true); g.scene.scale.multiplyScalar(h / (b.max.y - b.min.y));

Sizes in the rest pose (height x width x length, units):
  Acornweevil 4.3 x 5.3 x 9.1  |  AsianLongHornedBeetle 5.1 x 5.6 x 8.7  |  Asianladybeetle 3.7 x 5.7 x 6.8
  AtlasBeetle 4.2 x 5.8 x 8.0  |  CardinalBeetle 4.9 x 5.5 x 9.6  |  CaucasusBeetle 5.8 x 5.9 x 8.7
  DeerHornedFlowerBeetle 5.2 x 5.0 x 8.6  |  ElephantBeetle 4.6 x 5.9 x 8.4  |  EyedClickBeetle 4.8 x 5.1 x 7.8
  FiveHornedRhinocerosBeetle 5.9 x 5.7 x 7.6  |  FlowerChafer 4.0 x 5.6 x 7.0  |  GiraffeStagBeetle 3.7 x 5.8 x 11
  GoldenStagBeetle 4.0 x 5.5 x 8.2  |  GolofaBeetle 5.4 x 5.6 x 7.3  |  HarlequinBeetle 6.0 x 6.5 x 11
  Jewelbeetle 3.7 x 5.0 x 10  |  LeafRollingWeevil 5.1 x 5.6 x 9.2  |  Leafbeetle 4.2 x 5.1 x 7.3
  LesserStagBeetle 3.7 x 5.2 x 9.6  |  Manticora 4.7 x 5.7 x 8.9  |  Minotaurbeetle 4.0 x 5.4 x 7.4
  MoonHornedDungBeetle 6.9 x 5.3 x 6.8  |  NeptuneBeetle 4.7 x 5.7 x 9.5  |  RainbowScarab 4.9 x 4.9 x 7.2
  RosaliaLonghorn 4.7 x 6.0 x 8.5  |  RoseChafer 5.2 x 5.7 x 9.5  |  SacredScarab 3.8 x 6.3 x 7.7
  SpottedCucumberBeetle 4.8 x 9.5 x 6.7  |  TitanBeetle 3.7 x 5.7 x 9.6  |  Twentyeightspotladybird 4.2 x 5.4 x 8.0

License: CC0 1.0 (public domain) — any use, commercial or personal, no attribution required.
More free CC0 assets: https://gobkit.com/freebies
