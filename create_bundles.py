import os
import zipfile
import glob
import re
import json


def get_mod_info(mod_path):
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


def parse_json_with_comments(filepath):
    """Parse SMAPI-style i18n JSON that may contain // comments and trailing commas."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    # Strip single-line comments (but not URLs like https://)
    content = re.sub(r'(?<![:/])//[^\n]*', '', content)
    # Strip trailing commas before } or ]
    content = re.sub(r',(\s*[}\]])', r'\1', content)
    return json.loads(content)


def merge_and_write(base_path, overlay_path, out_path):
    """
    Merge th.json (base) with th-extended.json (overlay).
    Overlay keys take priority — they add new/missing entries.
    Writes result as valid SMAPI i18n JSON to out_path.
    """
    base = parse_json_with_comments(base_path)
    overlay = parse_json_with_comments(overlay_path)

    merged = {**base, **overlay}
    merged.pop('$schema', None)

    lines = [
        '{',
        '  "$schema": "https://smapi.io/schemas/i18n.json",',
        '  // --- Translation Credit ---',
        '  // Translation provided by: GitHub: AppleBoiy',
        '  // --- Merged: th.json + th-extended.json ---',
    ]
    items = list(merged.items())
    for i, (k, v) in enumerate(items):
        comma = ',' if i < len(items) - 1 else ''
        lines.append(f'  {json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)}{comma}')
    lines.append('}')

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


def main():
    bundles_dir = 'bundles'
    os.makedirs(bundles_dir, exist_ok=True)

    mods_dir = 'mods'

    for mod_name in sorted(os.listdir(mods_dir)):
        mod_path = os.path.join(mods_dir, mod_name)
        if not os.path.isdir(mod_path):
            continue

        th_json_files = glob.glob(os.path.join(mod_path, '**', 'th*.json'), recursive=True)
        th_folder_files = glob.glob(os.path.join(mod_path, '**', 'th', '*.*'), recursive=True)

        if not th_json_files and not th_folder_files:
            continue

        actual_name, author, nexus_url = get_mod_info(mod_path)
        if not actual_name:
            actual_name = mod_name
            author = "Original Author"
            nexus_url = "N/A"

        base_th = None
        extended_variants = {}

        for f in th_json_files:
            basename = os.path.basename(f)
            if basename == 'th.json':
                base_th = f
            else:
                m = re.match(r'th-(.+)\.json', basename)
                variant_name = m.group(1) if m else basename.replace('th', '').replace('.json', '')
                extended_variants[variant_name] = f

        def add_common_files(zipf):
            for f in th_folder_files:
                arcname = os.path.relpath(f, mods_dir)
                zipf.write(f, arcname)
                print(f"  Added {arcname}")
            readme = generate_readme_text(actual_name, author, nexus_url)
            zipf.writestr('คำแนะนำและเครดิต (README).txt', readme.encode('utf-8'))

        # Base bundle: th.json only
        if base_th:
            zip_path = os.path.join(bundles_dir, f"{mod_name} - Thai Translation.zip")
            print(f"Creating {zip_path}...")
            with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                add_common_files(zipf)
                arcname = os.path.relpath(base_th, mods_dir)
                zipf.write(base_th, os.path.join(os.path.dirname(arcname), 'th.json'))
                print(f"  Added th.json")

        # Extended bundles: merge base + extended -> single th.json
        for variant_name, ext_path in extended_variants.items():
            zip_path = os.path.join(bundles_dir, f"{mod_name} ({variant_name}) - Thai Translation.zip")
            print(f"Creating {zip_path}...")

            ext_arcname = os.path.relpath(ext_path, mods_dir)
            i18n_dir = os.path.dirname(ext_arcname)

            with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                add_common_files(zipf)

                if base_th:
                    tmp_path = os.path.join(bundles_dir, f'_tmp_{mod_name}_{variant_name}.json')
                    merge_and_write(base_th, ext_path, tmp_path)
                    zipf.write(tmp_path, os.path.join(i18n_dir, 'th.json'))
                    os.remove(tmp_path)
                    print(f"  Added merged th.json  (th.json + th-{variant_name}.json) -> {len(open(tmp_path if os.path.exists(tmp_path) else base_th).read())} chars")
                else:
                    zipf.write(ext_path, os.path.join(i18n_dir, 'th.json'))
                    print(f"  Added th-{variant_name}.json as th.json")

    print(f"\n✅ All bundles created in '{bundles_dir}/'!")


if __name__ == '__main__':
    main()
