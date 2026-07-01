import os
import glob
import re
import json

# Mod info table - fallback data for mods with non-standard manifest.json
MOD_DATA = {
    "Additional Farm Cave": {
        "name": "[CP] Additional Farm Cave",
        "author": "Tikamin557",
        "version": "4.0",
        "nexus_id": "14109",
        "description": "เพิ่มถ้ำฟาร์มแบบใหม่หลายแบบให้เลือก พร้อมกับของที่สุ่มจากถ้ำ"
    },
    "BetterCrafting": {
        "name": "Better Crafting",
        "author": "Khloe Leclair",
        "version": "2.18.0",
        "nexus_id": "11115",
        "description": "ปรับปรุงระบบการคราฟต์ให้ใช้งานง่ายขึ้น รองรับแท็บ, ค้นหา, และรับวัสดุจากลังใกล้เคียงได้"
    },
    "ConvenientInventory": {
        "name": "Convenient Inventory",
        "author": "gaussfire",
        "version": "1.6.1",
        "nexus_id": "10384",
        "description": "เพิ่มฟีเจอร์จัดการกระเป๋าสัมภาระอย่างสะดวก เช่น เติมลัง, จัดเรียงไอเทม"
    },
    "DeluxeJournal": {
        "name": "Deluxe Journal",
        "author": "kauf0",
        "version": "1.4.1",
        "nexus_id": "43805",
        "description": "อัปเกรดสมุดบันทึกให้แสดงข้อมูลเพิ่มเติม เช่น เควสต์, สัมพันธภาพ, และสถิติ"
    },
    "FarmTypeManager": {
        "name": "Farm Type Manager (FTM)",
        "author": "Esca",
        "version": "1.26.1",
        "nexus_id": "3231",
        "description": "เฟรมเวิร์กสำหรับสร้างสัตว์ประหลาด ของตกหล่น และแร่ในฟาร์มและโลเคชันต่างๆ"
    },
    "GI Extra Locations - Redux": {
        "name": "GI Extra locations - ContentPatcher",
        "author": "mistyspring",
        "version": "1.5.1",
        "nexus_id": None,
        "description": "เพิ่มสถานที่ใหม่บนเกาะ Ginger Island"
    },
    "ItemExtensions": {
        "name": "Item extensions",
        "author": "mistyspring",
        "version": "1.16.0",
        "nexus_id": "20357",
        "description": "เฟรมเวิร์กที่ช่วยให้ม็อดอื่นๆ สามารถเพิ่มความสามารถให้ไอเทมได้หลากหลายขึ้น"
    },
    "StardewHack": {
        "name": "StardewHack",
        "author": "bcmpinc",
        "version": "7.4",
        "nexus_id": "3213",
        "description": "ชุดการปรับปรุงประสิทธิภาพและเพิ่มฟีเจอร์พื้นฐานให้เกม"
    },
    "TDIT - Portraits for Extras": {
        "name": "TDIT - Portraits for Extras",
        "author": "cresolyn & Dolphin Is Not a Fish",
        "version": "1.3.0",
        "nexus_id": "35358",
        "description": "เพิ่มรูปหน้า (Portrait) ให้ตัวละครเสริมในเกมที่ปกติไม่มีรูป"
    },
    "Tiny Totem Statue Obelisks": {
        "name": "Tiny Totem Statue Obelisks",
        "author": "JennaJuffuffles",
        "version": "2.2.1",
        "nexus_id": "23118",
        "description": "เพิ่มรูปปั้นโทเทมขนาดเล็กที่ทำงานเหมือนโอเบลิสก์ ช่วยเดินทางได้สะดวก"
    },
    "TrinketTinker": {
        "name": "TrinketTinker",
        "author": "mushymato",
        "version": "1.7.3",
        "nexus_id": "29073",
        "description": "เฟรมเวิร์กสำหรับสร้างเครื่องประดับ (Trinket) แบบใหม่ที่มีความสามารถกำหนดเองได้"
    },
    "UIInfoSuite2Alt": {
        "name": "UI Info Suite 2 Alternative",
        "author": "DazUki",
        "version": "2.8.32",
        "nexus_id": "43127",
        "description": "เพิ่มข้อมูลบน UI เช่น วันเกิด NPC, สภาพอากาศ, โอกาสเจอสัตว์ต่างๆ"
    },
    "Unlockable Bundles": {
        "name": "Unlockable Bundles",
        "author": "DeLiXx",
        "version": "4.3.1",
        "nexus_id": "17265",
        "description": "เพิ่มชุด Bundle ใหม่ที่สามารถปลดล็อกได้จากการทำสิ่งพิเศษต่างๆ ในเกม"
    },
    "WearMoreRings": {
        "name": "Wear More Rings",
        "author": "bcmpinc",
        "version": "7.9",
        "nexus_id": "3214",
        "description": "ให้ตัวละครสวมแหวนได้หลายวงมากขึ้นในเวลาเดียวกัน"
    },
    "World Navigator": {
        "name": "World Navigator",
        "author": "pneuma163",
        "version": "1.4.2",
        "nexus_id": "28256",
        "description": "เพิ่มระบบแผนที่นำทางขั้นสูง ช่วยให้หาตำแหน่ง NPC และสิ่งต่างๆ ในเกมได้ง่ายขึ้น"
    },
    "[CP] RSV Seasonal Outfits": {
        "name": "[CP] RSV Seasonal Outfits",
        "author": "Rafseazz",
        "version": "1.0",
        "nexus_id": None,
        "description": "เพิ่มชุดตามฤดูกาลให้กับชาว Ridgeside Village"
    },
}

README_TEMPLATE = """\
<p align="center">
  <img src="{banner_url}" alt="{name} Thai Translation" width="400">
</p>

---

<p align="center">
  ไฟล์แปลภาษาไทยสำหรับม็อด <strong>{name}</strong> สร้างโดย <strong>{author}</strong>
</p>

---

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/mods_banner.png" alt="รายการม็อด" width="350">
</p>

**{name}** (เวอร์ชัน {version})

{description}

{nexus_link}

---

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/install_banner.png" alt="วิธีติดตั้ง" width="350">
</p>

1. **ติดตั้งม็อดต้นฉบับก่อน** — ดาวน์โหลดจากลิงก์ข้างบน
2. **ดาวน์โหลดไฟล์แปลภาษาไทยนี้** จาก [Releases](https://github.com/AppleBoiy/stardew-thai-translations/releases) หรือ [GitHub](https://github.com/AppleBoiy/stardew-thai-translations)
3. **วางไฟล์ทับ** — แตกไฟล์ zip แล้วนำโฟลเดอร์ไปวางทับใน `Stardew Valley/Mods`
4. **ตั้งค่าภาษาในเกม** — เปลี่ยนเป็น **ภาษาไทย** ในหน้าตั้งค่าเกม
5. เข้าเกมและเพลิดเพลินกับภาษาไทย! 🌾

---

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/credits_banner.png" alt="เครดิต" width="350">
</p>

- ม็อดต้นฉบับสร้างโดย **{author}** — สิทธิ์และทรัพย์สินทุกอย่างของม็อดต้นฉบับเป็นของผู้สร้าง
- แปลภาษาไทยโดย **AppleBoiy**
- หากชื่นชอบม็อดนี้ อย่าลืมไปกด **Endorse** ที่หน้า Nexus Mods ต้นฉบับด้วยนะครับ! 💛

พบคำแปลผิดพลาดหรือมีปัญหา? รายงานได้ที่:
👉 [GitHub Issues](https://github.com/AppleBoiy/stardew-thai-translations/issues)
"""

def main():
    mods_dir = "mods"
    for folder_name, data in MOD_DATA.items():
        mod_path = os.path.join(mods_dir, folder_name)
        if not os.path.exists(mod_path):
            print(f"⚠️  Skipping {folder_name} (folder not found)")
            continue

        nexus_link = (
            f"🔗 **ม็อดต้นฉบับ:** [Nexus Mods](https://www.nexusmods.com/stardewvalley/mods/{data['nexus_id']})"
            if data['nexus_id'] else "🔗 **ม็อดต้นฉบับ:** ไม่มีลิงก์ Nexus Mods"
        )
        
        banner_slug = folder_name.lower().replace(" ", "_").replace("[cp]_", "").strip("_")
        banner_filename = f"{banner_slug}_banner.png"
        if os.path.exists(os.path.join("banners", banner_filename)):
            banner_url = f"https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/{banner_filename}"
        else:
            banner_url = "https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/main_banner.png"

        readme_content = README_TEMPLATE.format(
            name=data['name'],
            author=data['author'],
            version=data['version'],
            description=data['description'],
            nexus_link=nexus_link,
            banner_url=banner_url,
        )

        readme_path = os.path.join(mod_path, "README.md")
        with open(readme_path, "w", encoding="utf-8") as f:
            f.write(readme_content)
        print(f"✅ Created README.md for {data['name']}")

if __name__ == "__main__":
    main()
