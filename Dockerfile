# VulnBank Mobile Build Image
# Pre-installs Android SDK components to speed up builds
#
# Build: docker build -t vulnbank-android .
# Or use: make docker-build

FROM reactnativecommunity/react-native-android:latest

# Accept Android SDK licenses
RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true

# Install required Android SDK components
# These are determined by the project's build.gradle requirements
RUN sdkmanager --install \
    "build-tools;35.0.0" \
    "platforms;android-35" \
    "platforms;android-30" \
    "cmake;3.22.1" \
    "ndk;27.1.12297006" \
    && sdkmanager --update

# Set up npm cache directory with correct permissions
RUN mkdir -p /app/node_modules && chmod 777 /app

WORKDIR /app
