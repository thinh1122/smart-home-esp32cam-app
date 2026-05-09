@echo off
echo 🚀 Deploying Smart Home App to GitHub...
echo.

echo 📋 Checking Flutter project...
if not exist "pubspec.yaml" (
    echo ❌ Error: Not in Flutter project directory
    echo Please run this script from FLUTTER folder
    pause
    exit /b 1
)

echo ✅ Flutter project detected
echo.

echo 🔧 Initializing Git repository...
git init
if %errorlevel% neq 0 (
    echo ❌ Git init failed
    pause
    exit /b 1
)

echo 📦 Adding all files...
git add .
if %errorlevel% neq 0 (
    echo ❌ Git add failed
    pause
    exit /b 1
)

echo 💾 Creating initial commit...
git commit -m "🏠 Smart Home ESP32-CAM App - Initial commit with GitHub Actions"
if %errorlevel% neq 0 (
    echo ❌ Git commit failed
    pause
    exit /b 1
)

echo 🌿 Setting main branch...
git branch -M main
if %errorlevel% neq 0 (
    echo ❌ Branch rename failed
    pause
    exit /b 1
)

echo.
echo 🔗 NEXT STEPS:
echo 1. Create a new repository on GitHub
echo 2. Copy the repository URL (e.g., https://github.com/username/repo-name.git)
echo 3. Run: git remote add origin YOUR_REPO_URL
echo 4. Run: git push -u origin main
echo.
echo 📝 Example commands:
echo git remote add origin https://github.com/yourusername/smart-home-esp32cam-app.git
echo git push -u origin main
echo.
echo ✅ Git repository initialized successfully!
echo Ready to push to GitHub when you add the remote origin.
pause