DONE (AR wrap lane, branch ar-wrap, CI compile green: run 43720985401, build.yml publish=false app_group=true; not published, not merged). First run 43720666872 failed on 3 things (Cancellable needs Combine, multi-var declarations under @Observable, main-actor class default); fixed in one pass.

## Which API, and why (docs checked at developer.apple.com via context7)
ARView + ARSessionDelegate + ARPlaneAnchor, NOT RealityView + SpatialTrackingSession. SpatialTrackingSession(.plane) only lets AnchorEntity(.plane(alignment, classification, minimumBounds)) bind content to "a plane"; it never hands back the plane's extent or centre, so it cannot size a wrap. ARPlaneAnchor exposes planeExtent (width, height, rotationOnYAxis), center and alignment, and ARKit grows the extent as planes merge. Other APIs checked: ARView(frame:cameraMode:automaticallyConfigureSession:), ARView.renderOptions (only disablePersonOcclusion confirmed in the docs text; the other disable* names are from memory, but they compiled), environment.sceneUnderstanding.options [.occlusion], UnlitMaterial.textureCoordinateTransform (iOS 18), MaterialParameters.Texture(_:sampler:), Sampler(MTLSamplerDescriptor), TextureResource.CreateOptions(semantic:mipmapsMode:), ARView.raycast.

## Built (PLDev/Sections/Labs/LabARWrap.swift new; LabAR.swift lost its old room code and one .ignoresSafeArea(); no PLDevCore import)
1. Auto wrap: every horizontal and vertical plane gets one ModelEntity sharing one unit plane mesh, scaled to the plane's extent, posed from anchor transform + center + rotation, 3 mm off the surface. The texture repeats at 1 m per repeat (UV scale = extent in metres, repeat sampler, mipmaps). Art switch (Tile / Direction) swaps materials only. Extent changes under 4 cm or 3 cm of move are ignored. Wrap on/off button. Tap adds an extra 1 m patch (ARKit raycast, existing plane then estimated plane).
2. Debugger (ladybug button, top left, remembered): tracking state + reason, floor/table and wall counts, mesh anchors (LiDAR), render fps and camera fps, heaviest work in the last half second (texture, planes, tube, in ms), last error. Lines go to the house channel through AppModel.shared.debug.note("ar", ...) (DebugLog, which sends to pl-cron /api/debug only while Settings Debug is on): events at once, a summary every 5 s.
3. CPU: texture decoded and uploaded once per art; no mesh or texture rebuilt per frame; collision and shadow scene-understanding dropped (only occlusion on LiDAR); person occlusion, blur, DoF, grain, HDR, grounding shadows off; camera video format capped at 30 fps; air curves built in 48-point chunks rebuilt every 4 points (was one growing mesh every 3). Recording unchanged (ReplayKit, cheap in the report).

## What the recording and report showed
Recording (11 s, frames at 1 fps): a dark corner room; the tile is stacked in overlapping rotated patches over the wall and floor, each from a manual tap, so the wall and floor are never covered evenly and the pieces pile up. Report: cpu_resource, 90 s of CPU over 138 s (65 %, limit 50 %). Main thread is inside CoreRE render (about 26 of 27 samples), plus ImageIO decode stacks under a PLDev frame, which fits TextureResource being rebuilt per tap. I cannot symbolise those frames here, so the texture cause is inferred, not proven.

## Only his phone can test
- Floor and walls wrap on their own, tile size looks like about 1 m, growth as the plane grows, no z-fighting or flicker.
- Whether the 30 fps cap and the cheaper render settings bring CPU under 50 % (watch the debugger fps and work lines; send the next cpu_resource report if it still trips).
- Wall planes on a LiDAR phone vs ARKit merging planes (many small tiles vs one big one).
- Occlusion with only .occlusion on; whether ARView draws the depth mesh as expected without collision.
- Air drawing joins between chunks; recording still includes the camera under ARView.
- The coaching capsule now sits mid-screen; debugger panel clearance under the top bar.
- Rotation sign of rotationOnYAxis on walls (Apple's sample applies it as eulerAngles.y, as here), unverified on device.

## Not done
No unit test (needs a device). Public-repo scan not run. Texture decode could move off the main actor only through a different path; not attempted.
