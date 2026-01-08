# HyprReadiness Tool

The HyprReadiness Tool is a cross-platform Flutter application designed to verify if a machine meets the requirements for HYPR deployment. It performs a series of system, network, and security checks on both macOS and Windows.

## Deployment Prerequisites

### Supported Operating Systems
- **macOS**: 13 (Ventura), 14.1+ (Sonoma), or 15+ (Sequoia)
- **Windows**: Windows 10 Pro or Windows 11 Pro

---

## Checks Performed

The tool runs the following categories of checks. Some are OS-specific.

### Common Checks
- **OS Version Compatibility**: Verifies the operating system version matches the supported versions listed above.
- **Network Connectivity**: 
  - Connects to `show.gethypr.com` via HTTPS.
  - **SSL Pinning**: Validates the server's public key hash against known valid pinnings to ensure a secure, intercepted-free connection.
- **Certificate Template Availability**: (Interactive)
  - Connects to a specified Active Directory Certificate Services (ADCS) server.
  - Submits a test CSR (Certificate Signing Request).
  - Verifies the issued certificate contains required Extended Key Usages (EKUs):
    - Client Authentication (`1.3.6.1.5.5.7.3.2`)
    - Smart Card Logon (`1.3.6.1.4.1.311.20.2.2`)

### macOS Specific Checks
- **Secure Element Detection**: 
  - Verifies presence of **Apple Silicon** or **T2 Security Chip** (Secure Enclave).
  - Warns if running on Intel hardware without a T2 chip.
- **Environment Information**:
  - **FileVault**: Verifies Full Disk Encryption is ON.
  - **Personal Recovery Key**: Checks if a personal recovery key exists (requires Admin).
  - **Recovery Key Usage**: Verifies the system is NOT currently using the recovery key for login.
  - **Plist Configuration**: Checks specific system preferences:
    - Screen Saver Token Removal (`tokenRemovalAction = 0`)
    - Automatic Login (Disabled)
  - **AD Binding**: Checks `dsconfigad` for Directory Domain binding.
  - **JAMF**: Reports the configured JAMF JSS URL.

### Windows Specific Checks
- **Secure Element Detection**:
  - Verifies **TPM (Trusted Platform Module)** is detected and enabled via WMI.
- **Windows Security Standards**:
  - **Device Status**: Checks `dsregcmd /status` for:
    - Domain Joined
    - Azure AD Joined
    - Enterprise Joined
    - SSO PRT Status (Azure/Enterprise)
  - **Registry Policies**:
    - Smart Card Removal Policy (`ScRemoveOption`)
    - Smart Card Force Logon (`scforceoption`)
    - Cached Credential Count (`CachedLogonsCount`)
  - **DC Trust**: Verifies Domain Controller trust using `nltest /SC_VERIFY:%USERDNSDOMAIN%`.
  - **.NET Framework**: Verifies the presence of the .NET Framework folder.

---

## Installation & Development

This project is built with [Flutter](https://flutter.dev/).

### Prerequisites
- **Flutter SDK**: [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Git**: For cloning the repository.
- **Visual Studio** (Windows): Required for Windows desktop development (C++ workload).
- **Xcode** (macOS): Required for macOS desktop development.

### Setup and Run

1. **Clone the repository:**
   ```bash
   git clone <repository_url>
   cd hyprready-tool-flutter/hyprready
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the application:**
   - **macOS:**
     ```bash
     flutter run -d macos
     ```
   - **Windows:**
     ```bash
     flutter run -d windows
     ```

### Building for Production

To create a release build (executable/app bundle):

- **macOS:**
  ```bash
  flutter build macos --release
  ```
  The application bundle will be found in `build/macos/Build/Products/Release/hyprready.app`.

- **Windows:**
  ```bash
  flutter build windows --release
  ```
  The executable will be found in `build/windows/runner/Release/hyprready.exe`.

## Project Structure

- `lib/checks/`: Contains the logic for individual system checks.
- `lib/ui/`: Contains the user interface code (screens and widgets).
- `lib/utils/`: Helper utilities (e.g., command execution).
- `macos/`: macOS native configuration and runner code.
- `windows/`: Windows native configuration and runner code.

## Troubleshooting

- **"Failed to run dsregcmd" (Windows)**: Ensure you are running the application with appropriate permissions, although standard user rights should suffice for status reads.
- **"Missing Personal Recovery Key" (macOS)**: This check attempts to escalate privileges using `osascript`. If you deny the admin prompt, the check will skip or fail.
- **SSL Pinning Failures**: Ensure you are not behind a corporate proxy that performs SSL termination/inspection without the appropriate root CA, or that the `show.gethypr.com` certificate has not rotated to a key not in the pinning list.
