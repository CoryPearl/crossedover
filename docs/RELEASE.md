# Public release gates

v1.4.0 is the Minecraft release in development, not yet published. Microsoft sign-in, the complete signed-package download/install, and local-world play with controls/sound, save and normal quit have passed on the current Mac. Repeat launch and remaining release checks are still being recorded. It is locally signed and is not a certified game-compatibility or notarized public release. The following public-release gates remain open.

- [ ] Independent source-complete runtime and dependency builds.
- [ ] Every runtime component's license, source, notices, and SBOM delivered.
- [ ] 32/64-bit smoke programs and graphics smoke tests pass on supported hosts.
- [ ] Windows Steam login, Steam Guard, logout/account switching, self-update, and offline behavior tested interactively.
- [ ] The TrackMania Nations Forever demo launches three times, runs smoothly for 30 minutes, saves/reloads, and relaunches.
- [ ] Keyboard, mouse, audio, fullscreen/focus, and supported controllers checked.
- [ ] M1-class and newer M-series hardware, with macOS 15 and 26 represented.
- [ ] Fresh-machine installation without Homebrew, Xcode, or CrossOver.
- [ ] App restart, interrupted setup, disk-full behavior, and runtime rollback tested.
- [ ] Developer ID signatures verified inside out, including Sparkle nested code.
- [ ] Runtime executable entitlements reviewed and validated under hardened runtime.
- [ ] App/runtime notarization and ticket stapling completed.
- [ ] HTTPS update feed and Ed25519 update signing configured and tested.
- [ ] No automatic runtime changes during a game; stable/candidate channels operational.

`scripts/package.py --identity 'Developer ID Application: …' --dmg` creates a locally signed artifact; it does not submit notarization or publish a release. Set both `CROSSEDOVER_UPDATE_FEED` and `CROSSEDOVER_UPDATE_PUBLIC_KEY` to configure Sparkle. The updater stays inactive without these values. Never commit signing credentials.

Publishing, external issue submission, and uploading artifacts are separate actions and are not performed by the build scripts.
