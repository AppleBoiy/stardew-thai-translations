import json
import re
import os
import sys

def patch_east_scarp_translations():
    filepath = "/Users/cj/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods/East Scarp REMASTERED/East Scarp Core/i18n/th.json"
    
    if not os.path.exists(filepath):
        print(f"Error: Could not find East Scarp translation file at: {filepath}")
        print("Please ensure East Scarp is installed and the th.json file exists.")
        sys.exit(1)

    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Regex to match Thai characters followed by a space and an English string in parentheses.
    # Example: "อีไล (Eli)" -> "อีไล"
    # The regex captures the Thai part in group 1, and matches the space and parentheses to remove them.
    pattern = re.compile(r'([\u0E00-\u0E7F]+)\s*\([A-Za-z0-9\s\.\-_\']+\)')

    modified_count = 0
    for key, value in data.items():
        if key.startswith("config."):
            continue
        
        if isinstance(value, str):
            new_value = pattern.sub(r'\1', value)
            if new_value != value:
                data[key] = new_value
                modified_count += 1

    if modified_count > 0:
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        print(f"✅ Successfully patched {modified_count} redundant English parentheses in East Scarp's th.json!")
    else:
        print("✅ No redundant translations found. It may have already been patched.")

if __name__ == '__main__':
    patch_east_scarp_translations()
