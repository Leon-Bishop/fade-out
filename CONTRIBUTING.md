# Contributing

Thanks for helping make Fade Out quieter and more reliable.

1. Open an issue describing the user-visible problem or proposed change.
2. Keep changes focused and dependency-free. Explain any Core Audio lifetime or real-time behavior in comments.
3. Run `swift test` with full Xcode, build the `FadeOut` scheme, and perform a manual audio check for routing changes.
4. Include the macOS version and output device type when reporting audio issues. Never attach captured audio without the owner's consent.

Pull requests should describe the behavior, test evidence, and any compatibility limits.
