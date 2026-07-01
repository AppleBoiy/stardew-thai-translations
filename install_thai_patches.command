#!/usr/bin/env python3
import os
import shutil
import glob
import re

# ANSI Color Codes
GREEN = '\033[92m'
YELLOW = '\033[93m'
RED = '\033[91m'
BLUE = '\033[94m'
BOLD = '\033[1m'
ENDC = '\033[0m'

def find_smapi_mods_dir():
    # Common paths for Stardew Valley SMAPI Mods folder on macOS
    home = os.path.expanduser("~")
    common_paths = [
        os.path.join(home, "Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods"),
        os.path.join(home, "Library/Application Support/Steam/steamapps/common/Stardew Valley/Mods")
    ]
    
    for path in common_paths:
        if os.path.exists(path) and os.path.isdir(path):
            return path
            
    return None

def main():
    print(f"{BOLD}{BLUE}==================================================={ENDC}")
    print(f"{BOLD}{BLUE}   Stardew Valley Thai Translation Patch Installer  {ENDC}")
    print(f"{BOLD}{BLUE}==================================================={ENDC}\n")
    
    # 1. Locate Mods directory
    mods_dir = find_smapi_mods_dir()
    
    if not mods_dir:
        print(f"{YELLOW}ไม่พบโฟลเดอร์ Mods ของ Stardew Valley อัตโนมัติ{ENDC}")
        while True:
            user_input = input("กรุณาลากโฟลเดอร์ 'Mods' ของคุณมาวางที่นี่ หรือพิมพ์พาธด้วยตัวเอง:\n> ").strip()
            # Clean up drag-and-drop formatting (remove surrounding quotes or escaped spaces)
            user_input = user_input.replace("\\ ", " ").strip("'\"")
            if os.path.exists(user_input) and os.path.isdir(user_input):
                mods_dir = user_input
                break
            print(f"{RED}พาธไม่ถูกต้องหรือโฟลเดอร์ไม่มีอยู่จริง กรุณาลองใหม่อีกครั้ง{ENDC}")
            
    print(f"{GREEN}พบโฟลเดอร์ Mods ที่:{ENDC} {mods_dir}\n")
    print(f"{BOLD}กำลังเริ่มทำการติดตั้งไฟล์แปลภาษา...{ENDC}\n")
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_mods_dir = os.path.join(script_dir, "mods")
    
    if not os.path.exists(repo_mods_dir):
        print(f"{RED}❌ ไม่พบโฟลเดอร์ 'mods' ในโฟลเดอร์ปัจจุบัน กรุณารันสคริปต์นี้จากโฟลเดอร์โปรเจกต์แปลภาษา{ENDC}")
        input("\nกด Enter เพื่อจบการทำงาน...")
        return

    # Find all directories in the repo containing a manifest.json
    manifest_paths = glob.glob(os.path.join(repo_mods_dir, "**/manifest.json"), recursive=True)
    
    installed_count = 0
    skipped_count = 0
    
    for manifest_path in manifest_paths:
        # Get the directory of the mod inside the repo
        repo_mod_folder = os.path.dirname(manifest_path)
        # Get the actual folder name of the mod (e.g. [CP] Additional Farm Cave)
        mod_folder_name = os.path.basename(repo_mod_folder)
        
        # 1. Check direct relative path (nested structure like Mods/Additional Farm Cave/[CP] Additional Farm Cave)
        rel_mod_path = os.path.relpath(repo_mod_folder, repo_mods_dir)
        target_mod_folder_nested = os.path.join(mods_dir, rel_mod_path)
        
        # 2. Check flat folder name (flat structure like Mods/[CP] Additional Farm Cave)
        target_mod_folder_flat = os.path.join(mods_dir, mod_folder_name)
        
        target_mod_folder = None
        if os.path.exists(target_mod_folder_nested) and os.path.isdir(target_mod_folder_nested):
            target_mod_folder = target_mod_folder_nested
        elif os.path.exists(target_mod_folder_flat) and os.path.isdir(target_mod_folder_flat):
            target_mod_folder = target_mod_folder_flat
            
        if target_mod_folder:
            print(f"📦 พบม็อด: {BOLD}{mod_folder_name}{ENDC}")
            
            # Find th.json or th folder inside repo_mod_folder (escaping wildcards like [CP])
            escaped_repo_mod_folder = glob.escape(repo_mod_folder)
            th_json_files = glob.glob(os.path.join(escaped_repo_mod_folder, "**/th.json"), recursive=True)
            th_folders = glob.glob(os.path.join(escaped_repo_mod_folder, "**/th"), recursive=True)
            
            copied = False
            
            # Copy th.json files
            for file_path in th_json_files:
                rel_path = os.path.relpath(file_path, repo_mod_folder)
                dest_path = os.path.join(target_mod_folder, rel_path)
                
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                shutil.copy2(file_path, dest_path)
                print(f"  {GREEN}✓{ENDC} ติดตั้ง: {rel_path}")
                copied = True
                
            # Copy contents of 'th' folders
            for folder_path in th_folders:
                rel_folder_path = os.path.relpath(folder_path, repo_mod_folder)
                dest_folder_path = os.path.join(target_mod_folder, rel_folder_path)
                
                os.makedirs(dest_folder_path, exist_ok=True)
                for item in os.listdir(folder_path):
                    src_item = os.path.join(folder_path, item)
                    dest_item = os.path.join(dest_folder_path, item)
                    if os.path.isfile(src_item):
                        shutil.copy2(src_item, dest_item)
                        print(f"  {GREEN}✓{ENDC} ติดตั้ง: {os.path.join(rel_folder_path, item)}")
                        copied = True
            
            if copied:
                installed_count += 1
            else:
                print(f"  {YELLOW}! ไม่พบไฟล์แปลภาษาไทยในม็อดนี้{ENDC}")
        else:
            # Skip since the user doesn't have this mod installed
            skipped_count += 1
            
    print(f"\n{BOLD}{BLUE}==================================================={ENDC}")
    print(f"{GREEN}✓ ติดตั้งสำเร็จ: {installed_count} ม็อด{ENDC}")
    print(f"{YELLOW}• ข้าม (ไม่ได้ติดตั้งม็อดต้นฉบับ): {skipped_count} ม็อด{ENDC}")
    print(f"{BOLD}{BLUE}==================================================={ENDC}")
    
    input("\nการติดตั้งเสร็จสิ้น! กด Enter เพื่อปิดหน้าต่างนี้...")

if __name__ == "__main__":
    main()
