import glob
import subprocess
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
        
    app_executable = os.path.join(MACOS_DIR, "StardewThaiInstaller")
    
    swift_files = glob.glob(os.path.join(project_root, "scripts", "*.swift"))
    print("🛠️ กำลังคอมไพล์โค้ด Swift...")
    swiftc_cmd = ["swiftc"] + swift_files + ["-o", app_executable, "-parse-as-library"]
    result = subprocess.run(swiftc_cmd).returncode
    
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
        print("🎨 กำลังแปลงไฟล์รูปภาพเป็นไอคอนแอปด้วย sips & iconutil...")
        try:
            iconset_dir = os.path.join(project_root, "covers", "icon.iconset")
            os.makedirs(iconset_dir, exist_ok=True)
            
            # Generate required sizes for macOS icon
            sizes = [16, 32, 64, 128, 256, 512, 1024]
            for size in sizes:
                out_path = os.path.join(iconset_dir, f"icon_{size}x{size}.png")
                subprocess.run(["sips", "-z", str(size), str(size), custom_icon, "--out", out_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if size <= 512:
                    out_path_2x = os.path.join(iconset_dir, f"icon_{size}x{size}@2x.png")
                    subprocess.run(["sips", "-z", str(size*2), str(size*2), custom_icon, "--out", out_path_2x], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            # Convert to icns
            subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", app_icon_dest], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            shutil.rmtree(iconset_dir)
        except Exception as e:
            print(f"❌ ไม่สามารถสร้างไอคอนได้: {e}")
            game_icon = os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/Resources/App.icns")
            if os.path.exists(game_icon):
                shutil.copy2(game_icon, app_icon_dest)
    else:
        # Fallback to Stardew Valley icon
        game_icon = os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/Resources/App.icns")
        if os.path.exists(game_icon):
            shutil.copy2(game_icon, app_icon_dest)
            
    # 7. Code Sign the App (Required for Apple Silicon)
    print("🔐 กำลังเซ็นชื่อ (Codesign) แอปพลิเคชัน...")
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", APP_DIR], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
    print(f"✅ สร้าง {APP_DIR} สำเร็จแล้ว!")
    print("✨ ลองเปิดหน้าต่าง Finder ไปที่โฟลเดอร์โปรเจกต์ แล้วดับเบิลคลิกเปิดแอปดูได้เลยครับ")

if __name__ == "__main__":
    create_app_bundle()
