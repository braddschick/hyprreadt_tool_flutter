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
VERSION=$(grep 'version:' pubspec.yaml |  sed 's/version: //')
TAG="v$VERSION"

echo "Detected version: $VERSION"
echo "Tag to create: $TAG"

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists. Skipping git tag creation..."
else
  echo "Creating git tag..."
  git tag "$TAG"
  git push origin "$TAG"
fi

echo "Creating GitHub release..."
# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "Error: 'gh' (GitHub CLI) is not installed."
    exit 1
fi

gh release create "$TAG" --generate-notes --title "Release $TAG"

echo "Release $TAG created successfully!"
