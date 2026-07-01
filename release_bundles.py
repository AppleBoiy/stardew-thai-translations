import os
import glob
import re
import sys
import subprocess
import argparse

def get_mod_info(mod_path):
    manifests = glob.glob(os.path.join(mod_path, '**', 'manifest.json'), recursive=True)
    if not manifests:
        return None, None
    
    with open(manifests[0], 'r', encoding='utf-8') as f:
        content = f.read()
        
    name = re.search(r'"Name"\s*:\s*"([^"]+)"', content)
    version = re.search(r'"Version"\s*:\s*"([^"]+)"', content)
    
    mod_name = name.group(1) if name else os.path.basename(mod_path)
    mod_version = version.group(1) if version else "1.0.0"
    
    return mod_name, mod_version

def sanitize_tag_name(name):
    # Remove brackets
    name = name.replace('[', '').replace(']', '')
    # Replace any non-alphanumeric character with hyphen
    name = re.sub(r'[^a-zA-Z0-9]+', '-', name)
    # Strip leading/trailing hyphens
    return name.strip('-')

def run_command(cmd, dry_run=False):
    if dry_run:
        print(f"[DRY-RUN] Would execute: {' '.join(cmd)}")
        return True, ""
    else:
        print(f"Executing: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  ❌ Error: {result.stderr}")
            return False, result.stderr
        return True, result.stdout

def tag_exists(tag):
    # Check remote tags
    result = subprocess.run(['git', 'ls-remote', '--tags', 'origin', tag], capture_output=True, text=True)
    if tag in result.stdout:
        return True
    
    # Check local tags
    result = subprocess.run(['git', 'tag', '-l', tag], capture_output=True, text=True)
    if tag in result.stdout:
        return True
        
    return False

def main():
    parser = argparse.ArgumentParser(description='Auto release script for Stardew Valley Thai Translations')
    parser.add_argument('--dry-run', action='store_true', help='Simulate actions without modifying git or pushing')
    args = parser.parse_args()

    mods_dir = 'mods'
    bundles_dir = 'bundles'
    
    if not os.path.exists(bundles_dir):
        print("❌ 'bundles' directory not found. Please run create_bundles.py first.")
        sys.exit(1)

    for mod_name in os.listdir(mods_dir):
        mod_path = os.path.join(mods_dir, mod_name)
        if not os.path.isdir(mod_path):
            continue
            
        zip_filename = os.path.join(bundles_dir, f"{mod_name} - Thai Translation.zip")
        if not os.path.exists(zip_filename):
            # Skip if no bundle was created for this mod
            continue
            
        actual_name, version = get_mod_info(mod_path)
        if not actual_name:
            actual_name = mod_name
            version = "1.0.0"
            
        sanitized_name = sanitize_tag_name(actual_name)
        tag_name = f"{sanitized_name}-th-v{version}"
        
        print(f"\\n📦 Processing: {actual_name} (v{version})")
        print(f"  Expected Tag: {tag_name}")
        
        if tag_exists(tag_name):
            print(f"  ⏭️  Tag '{tag_name}' already exists. Skipping release.")
            continue
            
        print(f"  🚀 New version detected! Preparing release...")
        
        title = f"{actual_name} Thai Translation v{version}"
        notes = f"ไฟล์แปลภาษาไทยสำหรับม็อด {actual_name} เวอร์ชัน {version}"
        
        # 1. Create Git Tag
        success, _ = run_command(['git', 'tag', tag_name], dry_run=args.dry_run)
        if not success: continue
        
        # 2. Push Tag
        success, _ = run_command(['git', 'push', 'origin', tag_name], dry_run=args.dry_run)
        if not success: continue
        
        # 3. Create GH Release
        gh_cmd = [
            'gh', 'release', 'create', tag_name, zip_filename, 
            '--title', title, 
            '--notes', notes
        ]
        success, _ = run_command(gh_cmd, dry_run=args.dry_run)
        
        if success and not args.dry_run:
            print(f"  ✅ Successfully released {tag_name}!")

if __name__ == '__main__':
    main()
