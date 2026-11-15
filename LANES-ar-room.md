DONE (AR room lane, branch ar-room, CI compile green: run 43716732372, build.yml publish=false app_group=true; not published, not merged)

## Built (PLDev/Sections/Labs/LabAR.swift only; no PLDevCore import; Info.plist unchanged)
1. **Wrap the room's real shape + tap on any surface.** SpatialTrackingSession.Configuration(tracking: [.camera, .plane], sceneUnderstanding: [.occlusion, .collision, .shadow], camera: .back). A tap = RealityViewCameraContent.ray(through:) then Scene.raycast(origin:direction:length:query:.nearest, mask: .sceneUnderstanding); the tile is placed on an AnchorEntity(world:) turned so its y is CollisionCastHit.normal. Fallback without LiDAR: the first pass's plane probes. Docs: realitykit-scene-understanding, SpatialTrackingSession, Scene.raycast, CollisionGroup.sceneUnderstanding, CollisionCastHit.
2. **Hide behind real things.** The `.occlusion` capability above; no extra code (Apple: virtual content experiences occlusion from the real-world meshes).
3. **Draw in the air.** Mode "Draw": while a finger is held, each frame (SceneEvents.Update) samples AnchorEntity(.camera) transformMatrix(relativeTo: nil), point = lens + 35 cm forward (needs the `.camera` capability, checked). Points >= 1.2 cm apart become a round tube (MeshDescriptor + MeshResource.generate(from:), 8 sides, 7 mm radius, both windings) in The Direction's colour #5b54e6, rebuilt every 3 points.
4. **Record.** ReplayKit RPScreenRecorder: startRecording(handler:) with isMicrophoneEnabled = false, stopRecording(withOutput:), then a ShareLink ("Save or share the video") so he can save to Photos. Checked at developer.apple.com data API: **these are deprecated in iOS 27 ("use ScreenCaptureKit")**; they compile (warnings only) and should still run. Moving to ScreenCaptureKit/SCRecordingEditor is the follow-up if the phone pass shows recording failing.
5. **Art switch.** Tile (his gallery PNG) / Direction (PracticeMapArt strokes + colour, rendered transparent, Catmull-Rom, read only; Practice untouched).
6. Controls: one glass row at the bottom (art, Place/Draw, record, clear), 44 pt, above the home indicator; the note capsule moved up in room mode. No LiDAR: a line says what still works. Reduce Motion unchanged (only the coaching pulse animates).

## Only his phone can test
- Done-list 1: tap on a sofa arm / table edge lands the tile there, flush to the surface (normal from the LiDAR mesh).
- 2: occlusion quality (people moving fast may cut out poorly).
- 3: air curve position/feel (35 cm ahead, sample spacing), mesh rebuild cost on long strokes; whether the drag gesture conflicts with the system edge gestures.
- 4: recording start/stop, the file saving to Photos, whether the recording includes the camera feed under RealityView.
- 5: The Direction tile reads right (1 m square, strokes extend past the frame as in the piece). [CONFIRM art choice per spec drill 3.]
- Unproven: MeshResource.generate(from:) deprecation warnings; tile placed on mesh anchors that drift slightly (world anchors, not plane anchors).

## Not done
Texture painted over the whole scanned mesh (not offered by RealityView; said so in the spec). Undo of a single curve (Clear removes everything placed). No shared-file lines needed.
