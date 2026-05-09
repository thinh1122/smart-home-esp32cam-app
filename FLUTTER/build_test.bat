@echo off
echo 🚀 Testing Flutter Build Process...
echo.

echo 📦 Getting dependencies...
call flutter pub get
if %errorlevel% neq 0 (
    echo ❌ Failed to get dependencies
    pause
    exit /b 1
)

echo.
echo 🔍 Analyzing code...
call flutter analyze --no-fatal-infos
if %errorlevel% neq 0 (
    echo ❌ Code analysis failed
    pause
    exit /b 1
)

echo.
echo 🧪 Running tests...
call flutter test --no-pub
if %errorlevel% neq 0 (
    echo ⚠️ Tests failed, but continuing...
)

echo.
echo 🔨 Building APK...
call flutter build apk --release --split-per-abi
if %errorlevel% neq 0 (
    echo ❌ APK build failed
    pause
    exit /b 1
)

echo.
echo ✅ Build completed successfully!
echo 📱 APK files are in: build\app\outputs\flutter-apk\
echo.
echo 📋 Files created:
dir build\app\outputs\flutter-apk\*.apk /b

echo.
echo 🎉 Ready for GitHub Actions and Sideloadly!
pause