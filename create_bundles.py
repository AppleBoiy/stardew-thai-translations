import os
import zipfile
import glob
import re

def get_mod_info(mod_path):
    # Try to find manifest.json
    manifests = glob.glob(os.path.join(mod_path, '**', 'manifest.json'), recursive=True)
    if not manifests:
        return None, None, None
    
    with open(manifests[0], 'r', encoding='utf-8') as f:
        content = f.read()
        
    name = re.search(r'"Name"\s*:\s*"([^"]+)"', content)
    author = re.search(r'"Author"\s*:\s*"([^"]+)"', content)
    nexus = re.search(r'"Nexus:(\d+)[^"]*"', content)
    
    mod_name = name.group(1) if name else os.path.basename(mod_path)
    mod_author = author.group(1) if author else "Original Author"
    nexus_url = f"https://www.nexusmods.com/stardewvalley/mods/{nexus.group(1)}" if nexus else "N/A"
    
    return mod_name, mod_author, nexus_url

def generate_readme_text(mod_name, author, nexus_url):
    return f"""=========================================
 ไฟล์แปลภาษาไทยสำหรับม็อด: {mod_name}
=========================================

ขอบคุณที่ดาวน์โหลดแพตช์แปลภาษาไทยครับ!

--- วิธีการติดตั้ง ---
1. คุณต้องติดตั้งม็อดต้นฉบับก่อนเสมอ สามารถดาวน์โหลดได้ที่:
   {nexus_url}
2. นำโฟลเดอร์ข้างในไฟล์ Zip นี้ (เช่น โฟลเดอร์ [CP] หรือชื่อม็อด) 
   ไปวางทับในแฟ้ม 'Stardew Valley/Mods' ได้เลย
3. เข้าเกม และตรวจสอบให้แน่ใจว่าตัวเกมตั้งค่าเป็นภาษาไทยแล้ว

--- เครดิต (Credits) ---
ม็อดต้นฉบับสร้างโดย: {author}
สิทธิ์และทรัพย์สินทั้งหมดของม็อดต้นฉบับเป็นของ {author}
ไฟล์นี้เป็นเพียงส่วนเสริมสำหรับการแปลภาษา เพื่อให้ผู้เล่นชาวไทยเข้าถึงม็อดได้ง่ายขึ้นเท่านั้น

หากชื่นชอบม็อดนี้ อย่าลืมเข้าไปกด Endorse เพื่อสนับสนุน {author} ที่หน้า Nexus Mods ด้วยนะครับ!
"""

def main():
    bundles_dir = 'bundles'
    os.makedirs(bundles_dir, exist_ok=True)
    
    mods_dir = 'mods'
    
    for mod_name in os.listdir(mods_dir):
        mod_path = os.path.join(mods_dir, mod_name)
        if not os.path.isdir(mod_path):
            continue
            
        th_json_files = glob.glob(os.path.join(mod_path, '**', 'th.json'), recursive=True)
        th_folder_files = glob.glob(os.path.join(mod_path, '**', 'th', '*.*'), recursive=True)
        
        all_translation_files = set(th_json_files + th_folder_files)
        
        if not all_translation_files:
            continue
            
        actual_name, author, nexus_url = get_mod_info(mod_path)
        if not actual_name:
            actual_name = mod_name
            author = "Original Author"
            nexus_url = "N/A"
            
        zip_filename = os.path.join(bundles_dir, f"{mod_name} - Thai Translation.zip")
        print(f"Creating {zip_filename}...")
        
        with zipfile.ZipFile(zip_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
            # Write the translation files
            for file_path in all_translation_files:
                arcname = os.path.relpath(file_path, mods_dir)
                zipf.write(file_path, arcname)
                print(f"  Added {arcname}")
                
            # Generate and write the README string directly into the zip
            readme_content = generate_readme_text(actual_name, author, nexus_url)
            zipf.writestr('คำแนะนำและเครดิต (README).txt', readme_content.encode('utf-8'))
            print(f"  Added คำแนะนำและเครดิต (README).txt")
                
    print(f"\\n✅ All bundles created successfully in the '{bundles_dir}' folder!")

if __name__ == '__main__':
    main()
