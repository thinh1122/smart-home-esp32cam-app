@echo off
echo 🔨 Building Flutter App Locally...
echo.

echo 📦 Cleaning previous builds...
call flutter clean
if %errorlevel% neq 0 (
    echo ❌ Flutter clean failed
    pause
    exit /b 1
)

echo 📥 Getting dependencies...
call flutter pub get
if %errorlevel% neq 0 (
    echo ❌ Flutter pub get failed
    pause
    exit /b 1
)

echo 🔍 Analyzing code...
call flutter analyze --no-fatal-infos
if %errorlevel% neq 0 (
    echo ⚠️ Code analysis has warnings, but continuing...
)

echo 🔨 Building APK (this may take 5-10 minutes)...
call flutter build apk --release --split-per-abi
if %errorlevel% neq 0 (
    echo ❌ APK build failed
    echo.
    echo 🔧 Trying alternative build...
    call flutter build apk --release
    if %errorlevel% neq 0 (
        echo ❌ Alternative build also failed
        pause
        exit /b 1
    )
)

echo.
echo ✅ Build completed successfully!
echo.
echo 📱 APK files location:
echo %cd%\build\app\outputs\flutter-apk\
echo.

echo 📋 Available APK files:
dir build\app\outputs\flutter-apk\*.apk /b

echo.
echo 🎉 You can now use Sideloadly to install the APK!
echo.
echo 📖 Next steps:
echo 1. Download Sideloadly from https://sideloadly.io
echo 2. Connect your Android device with USB debugging enabled
echo 3. Drag the APK file to Sideloadly
echo 4. Click "Start Sideloading"
echo.
pause