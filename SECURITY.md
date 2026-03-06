# Security Considerations

## macOS App Sandbox

The HYPR Readiness Tool does **not** use the macOS App Sandbox. This decision was intentionally made to allow the application to perform system-level operations required for its core functionality.

Specifically, the application requires the ability to:
1. Run system-level diagnostics using command line tools like `ping`, `curl`, and `osascript` (to gain root permissions).
2. Install, configure, and manage system background daemons (via `launchctl` and placing Plist files in `/Library/LaunchDaemons`).
3. Analyze network certificates and configurations outside the isolated sandbox environment.

Enabling the App Sandbox would severely restrict the tool from accessing the system paths, administrative privileges, and external applications required to determine if a machine is ready for HYPR deployment.

### Mitigating Risks
To mitigate the risks associated with running outside the sandbox, the tool adheres to the following security practices:
- Uses safe invocation techniques (e.g., parameter arrays instead of shell interpolation) for all spawned processes (`lib/utils/cmd.dart`) to prevent command injection.
- Extracts elevated commands into discrete temporary shell scripts (e.g. `MacOSTaskManager`) reducing the surface area of potential input manipulation.
- Communicates exclusively over verified TLS connections unless specifically required for debugging purposes.
- Never logs sensitive credentials locally. Credentials used for NTLM certificate enrollment are written temporarily using `curl --config` and immediately deleted.
