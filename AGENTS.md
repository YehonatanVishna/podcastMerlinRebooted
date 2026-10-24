# Agent Guidelines & Verification Protocol

## Mandatory Verification Before Completion
Always check and verify your work thoroughly before marking any task or job as done:
- **Build Verification**: Run target platform builds (e.g., `flutter build macos --debug` or the relevant platform build command) to verify native compilation and toolchain compatibility.
- **Static Analysis**: Run `flutter analyze` and resolve all analyzer warnings and errors.
- **Automated Tests**: Run `flutter test` and ensure all unit, widget, and integration tests pass cleanly.
- **Executable Validation**: Never assume code works theoretically or mark a job as done without running executable verification checks.
