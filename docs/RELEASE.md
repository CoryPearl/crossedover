# Release status and remaining validation

v1.4.1/build 27 adds Settings search to the owner-requested Minecraft release in the existing private GitHub repository. The DMG includes both the Windows runtime and the separate Minecraft backend. Microsoft sign-in, signed-package download/install, and local-world play with controls/sound, saving and normal quit passed on the current Mac. CS2’s latest online test confirmed working matchmaking, sharper visuals and smooth play.

The app is locally signed, not Developer ID signed or notarized. Publishing this version does not complete broader compatibility, clean-machine or source-complete dependency validation. The following work remains open for a broadly validated public distribution; no unchecked item is claimed complete.

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
