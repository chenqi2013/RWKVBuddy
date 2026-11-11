# rwkvbuddy

A new Flutter project.

## macOS builds

Run `flutter build macos --debug` for development or
`flutter build macos --release` for a universal macOS application.
The project and Runner deployment targets are set to macOS 14.6.

The Flutter Assemble phase uses `macos/Flutter/tool_overrides/lipo` to
verify architectures individually. This works around Xcode 27.2 rejecting
Flutter 3.41's multi-architecture `lipo -verify_arch` invocation while
preserving both arm64 and x86_64 output. Other lipo operations pass through
to the selected Xcode toolchain.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
