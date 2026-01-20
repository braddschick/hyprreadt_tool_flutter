#!/bin/bash
set -e

# Ensure we are in the root of the project
if [ ! -f pubspec.yaml ]; then
  echo "Error: pubspec.yaml not found. Please run this from the project root."
  exit 1
fi

# Run version check
echo "Verifying version..."
dart run tool/ensure_version.dart

# Extract version
VERSION=$(grep 'version:' pubspec.yaml | sed 's/version: //')
TAG="v$VERSION"
ARCH=$(uname -m)

echo "Detected version: $VERSION"
echo "Architecture: $ARCH"
echo "Tag to create: $TAG"

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists. Skipping git tag creation..."
else
  echo "Creating git tag..."
  git tag "$TAG"
  git push origin "$TAG"
fi

# Build the application
echo "Building macOS application..."
flutter build macos --release

# Zip the artifact
ARTIFACT_NAME="hyprready-${TAG}-${ARCH}.zip"
echo "Zipping artifact to $ARTIFACT_NAME..."
cd build/macos/Build/Products/Release
zip -r "$ARTIFACT_NAME" HyprReady.app
mv "$ARTIFACT_NAME" ../../../../../
cd - > /dev/null

echo "Artifact created: $ARTIFACT_NAME"

# Determine if we should create a release
# Logic: release if minor version changes.
# We need to find the previous tag to compare.
# Sort tags by version (semantic versioning) and pick the one before the current one.
PREV_TAG=$(git tag --sort=-v:refname | grep -v "$TAG" | head -n 1)

CREATE_RELEASE=false

if [ -z "$PREV_TAG" ]; then
  echo "No previous tag found. logic defaults to creating a release for the first tag."
  CREATE_RELEASE=true
else
  # Extract major.minor from tags
  CURRENT_MAJOR_MINOR=$(echo "$VERSION" | cut -d. -f1,2)
  # Remove 'v' prefix if present for version parsing
  PREV_VERSION=${PREV_TAG#v}
  PREV_MAJOR_MINOR=$(echo "$PREV_VERSION" | cut -d. -f1,2)

  echo "Current Major.Minor: $CURRENT_MAJOR_MINOR"
  echo "Previous Major.Minor: $PREV_MAJOR_MINOR"

  if [ "$CURRENT_MAJOR_MINOR" != "$PREV_MAJOR_MINOR" ]; then
    echo "Minor (or Major) version change detected."
    CREATE_RELEASE=true
  else
    echo "Only patch version change detected. Skipping full release creation."
  fi
fi

if [ "$CREATE_RELEASE" = true ]; then
  echo "Creating GitHub release..."
  # Check if gh is installed
  if ! command -v gh &> /dev/null; then
      echo "Error: 'gh' (GitHub CLI) is not installed."
      exit 1
  fi

  gh release create "$TAG" "$ARTIFACT_NAME" --generate-notes --title "Release $TAG"
  echo "Release $TAG created successfully with asset $ARTIFACT_NAME!"
else
  echo "Skipping GitHub release creation."
fi
