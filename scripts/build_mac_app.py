#!/usr/bin/env python3
import os
import shutil
import plistlib

APP_NAME = "StardewThaiInstaller"
APP_DIR = f"{APP_NAME}.app"
CONTENTS_DIR = os.path.join(APP_DIR, "Contents")
MACOS_DIR = os.path.join(CONTENTS_DIR, "MacOS")
RESOURCES_DIR = os.path.join(CONTENTS_DIR, "Resources")
CORE_DIR = os.path.join(RESOURCES_DIR, "core")

def create_app_bundle():
    print(f"📦 เริ่มสร้าง {APP_DIR}...")
    
    # 1. Clean old build
    if os.path.exists(APP_DIR):
        shutil.rmtree(APP_DIR)
        
    # 2. Create directories
    os.makedirs(MACOS_DIR)
    os.makedirs(CORE_DIR)
    
    # 3. Create Info.plist
    info_plist = {
        "CFBundleExecutable": APP_NAME,
        "CFBundleIdentifier": f"com.appleboiy.{APP_NAME.lower()}",
        "CFBundleName": APP_NAME,
        "CFBundleVersion": "1.0.0",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundlePackageType": "APPL",
        "CFBundleSignature": "????",
        "LSMinimumSystemVersion": "11.0",
        "NSHighResolutionCapable": True,
        "CFBundleIconFile": "AppIcon"
    }
    
    with open(os.path.join(CONTENTS_DIR, "Info.plist"), "wb") as f:
        plistlib.dump(info_plist, f)
        
    # 4. Compile Swift App
    project_root = os.path.abspath(os.path.dirname(__file__))
    if os.path.basename(project_root) == "scripts":
        project_root = os.path.dirname(project_root)
        
    swift_source = os.path.join(project_root, "scripts", "InstallerApp.swift")
    binary_dest = os.path.join(MACOS_DIR, APP_NAME)
    
    print("🛠️ กำลังคอมไพล์โค้ด Swift...")
    compile_cmd = f"swiftc -parse-as-library '{swift_source}' -o '{binary_dest}'"
    result = os.system(compile_cmd)
    
    if result != 0:
        print("❌ เกิดข้อผิดพลาดในการคอมไพล์ Swift")
        return
    
    # 5. Copy Core Files (Mods folder)
    source_mods = os.path.join(project_root, "mods")
    if os.path.isdir(source_mods):
        shutil.copytree(source_mods, os.path.join(CORE_DIR, "mods"))
        
    # 6. Set Custom Game Icon
    custom_icon = os.path.join(project_root, "covers", "AppIcon_NoBg_clean.png")
    app_icon_dest = os.path.join(RESOURCES_DIR, "AppIcon.icns")
    if os.path.exists(custom_icon):
        print("🎨 กำลังแปลงไฟล์รูปภาพเป็นไอคอนแอปด้วย Python...")
        try:
            from PIL import Image
            img = Image.open(custom_icon)
            img.save(app_icon_dest, format='ICNS')
        except ImportError:
            print("❌ ไม่พบโมดูล PIL ข้ามการแปลงไอคอน")
            # Fallback to Stardew Valley icon
            game_icon = os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/Resources/App.icns")
            if os.path.exists(game_icon):
                shutil.copy2(game_icon, app_icon_dest)
    else:
        # Fallback to Stardew Valley icon
        game_icon = os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/Resources/App.icns")
        if os.path.exists(game_icon):
            shutil.copy2(game_icon, app_icon_dest)
        
    print(f"✅ สร้าง {APP_DIR} สำเร็จแล้ว!")
    print("✨ ลองเปิดหน้าต่าง Finder ไปที่โฟลเดอร์โปรเจกต์ แล้วดับเบิลคลิกเปิดแอปดูได้เลยครับ")

if __name__ == "__main__":
    create_app_bundle()
