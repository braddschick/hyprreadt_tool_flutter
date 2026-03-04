#!/bin/bash
# --- GitLab Runner & Flutter macOS Dependencies Bootstrap ---

LOG_FILE="/tmp/terraform_bootstrap.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "Starting macOS ARM Bootstrap..."

# AWS EC2 Mac instances require patience and reboots for some setups, 
# but we will try to script the essentials here.

# 1. Install Homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/ec2-user/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# 2. Install dependencies (Git, CocoaPods etc)
brew install git cocoapods

# 3. Install Xcode Command Line Tools
# Note: Full Xcode is required for compiling macOS desktop apps.
# Automating full Xcode installation via script is difficult because it requires an Apple ID check, Mac App Store login, and sometimes license acceptance.
# Typical workflow is to use a community utility like 'xcodes' via brew.
brew install xcodesorg/made/xcodes
xcodes install 15.4 # Specify an exact xcode version you want
xcode-select -s /Applications/Xcode-15.4.app/Contents/Developer
xcodebuild -runFirstLaunch
xcodebuild -license accept

# 4. Install Flutter
cd /opt
curl -Lo flutter_macos_arm64.zip "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.24.0-stable.zip"
unzip flutter_macos_arm64.zip
rm flutter_macos_arm64.zip
export PATH="$PATH:/opt/flutter/bin"
echo 'export PATH="$PATH:/opt/flutter/bin"' >> /Users/ec2-user/.zprofile

# Precaching specifically for macos
flutter config --enable-macos-desktop
flutter precache --macos

# 5. Install GitLab Runner
sudo curl --output /usr/local/bin/gitlab-runner "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-darwin-arm64"
sudo chmod +x /usr/local/bin/gitlab-runner

# Register the Runner
gitlab-runner register \
  --non-interactive \
  --url "${gitlab_url}" \
  --token "${runner_token}" \
  --executor "shell" \
  --description "Terraform macOS ARM Builder" \
  --tag-list "macos-arm,flutter,macos" \
  --run-untagged="false"

# Install as service
cd ~
gitlab-runner install
gitlab-runner start

echo "macOS ARM Bootstrap Complete!"
