# Signing and notarization

The release workflow builds a universal `arm64` and `x86_64` app and uploads an **unsigned** ZIP. That artifact is useful for testing and is not a notarized public download.

For distribution, configure an Apple Developer ID Application certificate in CI, build with the `Developer ID` signing identity and hardened runtime, then submit the ZIP with `xcrun notarytool submit --wait`. Staple the resulting ticket with `xcrun stapler staple FadeOut.app`, verify with `spctl --assess --type execute -v FadeOut.app`, and create the final ZIP from the stapled app. Keep credentials in encrypted repository secrets. Do not publish a download as signed until verification succeeds.

The bundle identifier is `com.howldev.fadeout`. Use it unchanged for the app, permission state, and launch-at-login registration. The audio capture usage string is in `Info.plist`.
