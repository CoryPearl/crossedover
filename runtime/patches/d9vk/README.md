These two patches are from the independent TrackMania-MacOS project:
https://github.com/vakesz/TrackMania-MacOS/tree/main/patches/d9vk

They correct promoted volume texture slice offsets and legacy reflection coordinates. D9VK is built from the exact revision in source-lock.json. Its upstream zlib license is preserved in the runtime. The local build is an altered version, not an upstream release.

0005-frame-rate-logging.patch is original CrossedOver diagnostic code. It logs the HUD presentation rate at most once every five seconds when CROSSEDOVER_FRAME_LOG=1. It does not change rendering or infer race responsiveness.
