DONE (AR curves lane, branch ar-realityview, CI compile green: run 43709278972, build.yml publish=false)

## Built (PLDev/Sections/Labs/LabAR.swift only; no PLDevCore import)
1. "Wrap the room" is now SwiftUI RealityView (camera .spatialTracking) + SpatialTrackingSession (tracking [.plane], back camera), checked against Apple's docs (SpatialTrackingSession, RealityViewCamera.spatialTracking, AnchorEntity plane init, Scene.raycast, RealityCoordinateSpaceProjecting.ray). Horizontal AND vertical planes: an invisible collision probe sits on a plane AnchorEntity of each alignment; a tap is a ray through the screen, the tile (his ar-curve-tile.png, unlit, transparent) is parented to the probe's anchor where the ray hits, so it follows the real plane. After a tile lands, a fresh probe of that alignment is added so another surface can be found.
2. Camera permission asked first; denied, or tracking unsupported, calls ar.preview(why): a clear line and the overlay preview, never a black screen.
3. Coaching: RealityView has no ARCoachingOverlayView (it needs an ARSession), so a glass capsule "Finding a surface. Move the phone slowly." shows until a probe anchors.
4. Reduce Motion: the drift stops (phase 0); tilt still moves the overlay.
5. The view/room switch sits at safe-area top + 12 pt, not a fixed 56.
6. Kept: "The view" mode, 44 pt controls, capture start/stop off the main thread.

## Only his phone can test (no device here)
- Tile stays put while walking; tap on floor AND wall anchors.
- Whether ARKit hands each probe a different plane (one AnchorEntity binds one plane); big rooms may need a second tap after the new probe binds.
- Storing RealityViewCameraContent in a box and using it from the tap (ray + scene) is the least-proven line.
- Switching room -> view: SpatialTrackingSession.stop is async and the AVCapture camera restarts at once; a brief camera hiccup is possible.
- Camera-denied path and Reduce Motion in Settings; switch under the Dynamic Island.
- Public-repo scan not run by me (lead's step).

## Not done / out of scope
LiDAR meshes, people occlusion, new tiles. Web /lab/ar pages are WebXR/CSS and stay as they are (Apple's path is native only).
No shared-file lines needed. Not published, not merged.
