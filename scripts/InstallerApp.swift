import SwiftUI
import Combine

struct PatchTarget: Identifiable {
    let id: String
    let name: String
    let hints: [String]
    var isEnabled: Bool = false
}

struct ModVariant: Hashable {
    let folderName: String
    let name: String
}

struct ModItem: Identifiable {
    let id = UUID()
    let folderName: String
    let variants: [ModVariant]
    var isEnabled: Bool = true
    var selectedVariant: ModVariant
    var displayName: String = ""
    var version: String = ""
    var nexusUrl: String = ""
}

@main
struct StardewThaiInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

struct InstalledModItem: Identifiable {
    let id = UUID()
    let name: String
    let folderName: String
    let version: String
    let nexusUrl: String
    var status: TranslationStatus
}

enum TranslationStatus: String {
    case installed = "ติดตั้งคำแปลแล้ว"
    case availablePending = "มีคำแปล (ยังไม่ได้ติดตั้ง)"
    case notSupported = "ยังไม่มีคำแปล (ใช้ภาษาอังกฤษ)"
}

class InstallerViewModel: ObservableObject {
    @Published var gameDir: String = "" {
        didSet {
            scanInstalledMods()
        }
    }
    @Published var mods: [ModItem] = []
    @Published var installedMods: [InstalledModItem] = []
    @Published var patches: [PatchTarget] = [
        PatchTarget(id: "east_scarp", name: "East Scarp (ลบวงเล็บภาษาอังกฤษหลังชื่อตัวละคร)", hints: ["east scarp"]),
        PatchTarget(id: "eli_and_dylan", name: "Eli and Dylan (ลบวงเล็บภาษาอังกฤษหลังชื่อตัวละคร)", hints: ["eli and dylan", "novanpctest"])
    ]
    @Published var logs: String = ""
    @Published var isWorking: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    
    let fileManager = FileManager.default
    
    init() {
        self.gameDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods")
        self.loadMods()
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs += message + "\n"
        }
    }
    
    func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            self.alertTitle = title
            self.alertMessage = message
            self.showSuccessAlert = true
        }
    }
    
    func selectGameDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let currentURL = URL(string: gameDir) {
            panel.directoryURL = currentURL
        }
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.gameDir = url.path
            }
        }
    }
    
    func loadMods() {
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundlePath
        // In dev it's next to the script, in bundle it's in Resources/core
        var baseDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path
        if bundlePath.hasSuffix(".app") {
            baseDir = (bundlePath as NSString).appendingPathComponent("Contents/Resources/core")
        }
        
        let modsDir = (baseDir as NSString).appendingPathComponent("mods")
        
        guard let dirs = try? fm.contentsOfDirectory(atPath: modsDir) else {
            log("⚠️ ไม่พบโฟลเดอร์ mods ที่ \(modsDir)")
            return
        }
        
        var loadedMods: [ModItem] = []
        for d in dirs {
            if d.hasPrefix(".") { continue }
            let modPath = (modsDir as NSString).appendingPathComponent(d)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: modPath, isDirectory: &isDir) && isDir.boolValue {
                
                // Scan 1-level deep subdirectories to see if they contain a manifest.json
                var subdirsWithManifest: [String] = []
                var otherSubdirs: [String] = []
                
                if let subdirs = try? fm.contentsOfDirectory(atPath: modPath) {
                    for sd in subdirs {
                        if sd.hasPrefix(".") { continue }
                        let sdPath = (modPath as NSString).appendingPathComponent(sd)
                        var sdIsDir: ObjCBool = false
                        if fm.fileExists(atPath: sdPath, isDirectory: &sdIsDir) && sdIsDir.boolValue {
                            let sdManifest = (sdPath as NSString).appendingPathComponent("manifest.json")
                            if fm.fileExists(atPath: sdManifest) {
                                subdirsWithManifest.append(sd)
                            } else {
                                otherSubdirs.append(sd)
                            }
                        }
                    }
                }
                
                if !subdirsWithManifest.isEmpty {
                    // Scenario 1: Submods! Register each one as its own standalone ModItem
                    for sd in subdirsWithManifest {
                        let submodPath = (modPath as NSString).appendingPathComponent(sd)
                        let manifestPath = (submodPath as NSString).appendingPathComponent("manifest.json")
                        
                        var displayName = sd
                        var version = "Unknown"
                        var nexusUrl = ""
                        
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            if let name = json["Name"] as? String {
                                displayName = name
                            }
                            if let ver = json["Version"] as? String {
                                version = ver
                            }
                            if let updateKeys = json["UpdateKeys"] as? [String] {
                                for key in updateKeys {
                                    if key.lowercased().hasPrefix("nexus:") {
                                        let id = key.replacingOccurrences(of: "nexus:", with: "", options: .caseInsensitive)
                                        nexusUrl = "https://www.nexusmods.com/stardewvalley/mods/\(id.trimmingCharacters(in: .whitespacesAndNewlines))"
                                        break
                                    }
                                }
                            }
                        }
                        
                        var variants: [ModVariant] = []
                        variants.append(ModVariant(folderName: "", name: "Default"))
                        
                        let relFolder = "\(d)/\(sd)"
                        loadedMods.append(ModItem(folderName: relFolder, variants: variants, selectedVariant: variants[0], displayName: displayName, version: version, nexusUrl: nexusUrl))
                    }
                } else {
                    // Scenario 2: Standard single mod, possibly with variants
                    var variants: [ModVariant] = []
                    for sd in otherSubdirs {
                        variants.append(ModVariant(folderName: sd, name: sd))
                    }
                    
                    var displayName = d
                    var version = "Unknown"
                    var nexusUrl = ""
                    
                    func findManifest(in dir: String) -> String? {
                        let enumerator = fm.enumerator(atPath: dir)
                        while let file = enumerator?.nextObject() as? String {
                            if file.hasSuffix("manifest.json") {
                                return (dir as NSString).appendingPathComponent(file)
                            }
                        }
                        return nil
                    }
                    
                    if let manifestPath = findManifest(in: modPath),
                       let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                       let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let name = json["Name"] as? String {
                            displayName = name
                        }
                        if let ver = json["Version"] as? String {
                            version = ver
                        }
                        if let updateKeys = json["UpdateKeys"] as? [String] {
                            for key in updateKeys {
                                if key.lowercased().hasPrefix("nexus:") {
                                    let id = key.replacingOccurrences(of: "nexus:", with: "", options: .caseInsensitive)
                                    nexusUrl = "https://www.nexusmods.com/stardewvalley/mods/\(id.trimmingCharacters(in: .whitespacesAndNewlines))"
                                    break
                                }
                            }
                        }
                    }
                    
                    if !variants.isEmpty {
                        loadedMods.append(ModItem(folderName: d, variants: variants, selectedVariant: variants[0], displayName: displayName, version: version, nexusUrl: nexusUrl))
                    } else {
                        variants.append(ModVariant(folderName: "", name: "Default"))
                        loadedMods.append(ModItem(folderName: d, variants: variants, selectedVariant: variants[0], displayName: displayName, version: version, nexusUrl: nexusUrl))
                    }
                }
            }
        }
        self.mods = loadedMods.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        self.scanInstalledMods()
    }
    
    func scanInstalledMods() {
        let fm = FileManager.default
        guard !gameDir.isEmpty && fm.fileExists(atPath: gameDir) else {
            self.installedMods = []
            return
        }
        
        guard let dirs = try? fm.contentsOfDirectory(atPath: gameDir) else {
            self.installedMods = []
            return
        }
        
        var list: [InstalledModItem] = []
        
        for d in dirs {
            if d.hasPrefix(".") { continue }
            let fullPath = (gameDir as NSString).appendingPathComponent(d)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue {
                var displayName = d
                var version = "Unknown"
                var nexusUrl = ""
                
                let manifestPath = (fullPath as NSString).appendingPathComponent("manifest.json")
                if fm.fileExists(atPath: manifestPath),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    if let name = json["Name"] as? String {
                        displayName = name
                    }
                    if let ver = json["Version"] as? String {
                        version = ver
                    }
                    if let updateKeys = json["UpdateKeys"] as? [String] {
                        for key in updateKeys {
                            if key.lowercased().hasPrefix("nexus:") {
                                let id = key.replacingOccurrences(of: "nexus:", with: "", options: .caseInsensitive)
                                nexusUrl = "https://www.nexusmods.com/stardewvalley/mods/\(id.trimmingCharacters(in: .whitespacesAndNewlines))"
                                break
                            }
                        }
                    }
                }
                
                var matchedTranslation: ModItem? = nil
                for t in self.mods {
                    let transFolder = (t.folderName as NSString).lastPathComponent
                    if transFolder.lowercased() == d.lowercased() || t.displayName.lowercased() == displayName.lowercased() {
                        matchedTranslation = t
                        break
                    }
                }
                
                var status: TranslationStatus = .notSupported
                if matchedTranslation != nil {
                    var hasTh = false
                    let enumerator = fm.enumerator(atPath: fullPath)
                    while let file = enumerator?.nextObject() as? String {
                        let bn = (file as NSString).lastPathComponent
                        if bn == "th.json" || bn.hasPrefix("th-") && bn.hasSuffix(".json") || bn == "th" {
                            hasTh = true
                            break
                        }
                    }
                    status = hasTh ? .installed : .availablePending
                }
                
                list.append(InstalledModItem(name: displayName, folderName: d, version: version, nexusUrl: nexusUrl, status: status))
            }
        }
        
        self.installedMods = list.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func startInstall() {
        isWorking = true
        logs = ""
        log("🚀 เริ่มการทำงาน...")
        
        let selectedMods = mods.filter { $0.isEnabled }
        let selectedPatches = patches.filter { $0.isEnabled }
        
        let gDir = self.gameDir
        
        DispatchQueue.global(qos: .userInitiated).async {
            var okCount = 0
            
            // 1. Install Mods
            if !selectedMods.isEmpty {
                self.log("📦 ติดตั้งไฟล์แปล \(selectedMods.count) ม็อด...")
                for mod in selectedMods {
                    if self.doInject(gameDir: gDir, mod: mod) {
                        okCount += 1
                    }
                }
                self.log("✅ ติดตั้งไฟล์แปลสำเร็จ \(okCount)/\(selectedMods.count) ม็อด")
            }
            
            // 2. Apply Patches
            if !selectedPatches.isEmpty {
                self.log("🛠️ กำลังสแกนและแพตช์ลบข้อความภาษาอังกฤษในวงเล็บ...")
                self.patchRedundantTranslations(gameDir: gDir, selectedPatches: selectedPatches)
            }
            
            DispatchQueue.main.async {
                self.isWorking = false
                self.scanInstalledMods()
                self.log("🎉 การดำเนินการเสร็จสิ้น! เริ่มเกมได้เลยครับ 🌾")
                self.showAlert(title: "สำเร็จ!", message: "ดำเนินการติดตั้งไฟล์แปลม็อดและเครื่องมือเสริมเสร็จสมบูรณ์\nดูรายละเอียดเพิ่มเติมได้ที่หน้า 'บันทึกการทำงาน'")
            }
        }
    }
    
    func doInject(gameDir: String, mod: ModItem) -> Bool {
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundlePath
        var baseDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent().path
        if bundlePath.hasSuffix(".app") {
            baseDir = (bundlePath as NSString).appendingPathComponent("Contents/Resources/core")
        }
        
        let srcBase = (baseDir as NSString).appendingPathComponent("mods")
        var srcDir = (srcBase as NSString).appendingPathComponent(mod.folderName)
        var targetFolderName = mod.folderName
        if !mod.selectedVariant.folderName.isEmpty {
            srcDir = (srcDir as NSString).appendingPathComponent(mod.selectedVariant.folderName)
            targetFolderName = mod.selectedVariant.folderName
        }
        
        let searchFolder = (targetFolderName as NSString).lastPathComponent
        guard let destBase = findInstalledMod(gameDir: gameDir, folderName: searchFolder) else {
            self.log("❌ ข้ามคำแปล \(searchFolder): ไม่พบโฟลเดอร์ม็อดต้นฉบับในเครื่องของคุณ (กรุณาติดตั้งม็อดต้นฉบับก่อน)")
            return false
        }
        
        guard let items = try? fm.contentsOfDirectory(atPath: srcDir) else {
            self.log("❌ ข้ามคำแปล \(mod.folderName): ไม่พบไฟล์คำแปลต้นฉบับในตัวติดตั้ง")
            return false
        }
        
        var hasError = false
        for item in items {
            if item.hasPrefix(".") { continue }
            let srcPath = (srcDir as NSString).appendingPathComponent(item)
            let destPath = (destBase as NSString).appendingPathComponent(item)
            
            do {
                try copyItemReplacing(from: srcPath, to: destPath)
            } catch {
                self.log("❌ ก๊อปปี้ \(item) ไม่สำเร็จ: \(error.localizedDescription)")
                hasError = true
            }
        }
        
        if !hasError {
            self.log("  ✅ ลงไฟล์แปลสำเร็จ: \(mod.folderName) -> \(mod.selectedVariant.name)")
        }
        return !hasError
    }
    
    func findInstalledMod(gameDir: String, folderName: String) -> String? {
        let fm = FileManager.default
        
        // 1. Check flat folder name (e.g. gameDir/folderName)
        let flatPath = (gameDir as NSString).appendingPathComponent(folderName)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: flatPath, isDirectory: &isDir) && isDir.boolValue {
            return flatPath
        }
        
        // 2. Fuzzy search by comparing directory names under gameDir (1 level deep)
        guard let contents = try? fm.contentsOfDirectory(atPath: gameDir) else { return nil }
        for entry in contents {
            if entry.hasPrefix(".") { continue }
            let entryPath = (gameDir as NSString).appendingPathComponent(entry)
            var entryIsDir: ObjCBool = false
            if fm.fileExists(atPath: entryPath, isDirectory: &entryIsDir) && entryIsDir.boolValue {
                // Check flat match case-insensitive
                if entry.lowercased() == folderName.lowercased() {
                    return entryPath
                }
                
                // Check if manifest.json exists
                let manifestPath = (entryPath as NSString).appendingPathComponent("manifest.json")
                if fm.fileExists(atPath: manifestPath) {
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
                       let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let name = json["Name"] as? String {
                        if name.lowercased() == folderName.lowercased() {
                            return entryPath
                        }
                    }
                }
                
                // Check subdirectories (nested mods) 1 level down
                if let subContents = try? fm.contentsOfDirectory(atPath: entryPath) {
                    for subEntry in subContents {
                        if subEntry.hasPrefix(".") { continue }
                        let subEntryPath = (entryPath as NSString).appendingPathComponent(subEntry)
                        var subEntryIsDir: ObjCBool = false
                        if fm.fileExists(atPath: subEntryPath, isDirectory: &subEntryIsDir) && subEntryIsDir.boolValue {
                            if subEntry.lowercased() == folderName.lowercased() {
                                return subEntryPath
                            }
                            
                            let subManifestPath = (subEntryPath as NSString).appendingPathComponent("manifest.json")
                            if fm.fileExists(atPath: subManifestPath) {
                                if let data = try? Data(contentsOf: URL(fileURLWithPath: subManifestPath)),
                                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                                   let name = json["Name"] as? String {
                                    if name.lowercased() == folderName.lowercased() {
                                        return subEntryPath
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    func copyItemReplacing(from src: String, to dest: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: src, isDirectory: &isDir) && isDir.boolValue {
            if !fm.fileExists(atPath: dest) {
                try fm.createDirectory(atPath: dest, withIntermediateDirectories: true, attributes: nil)
            }
            let items = try fm.contentsOfDirectory(atPath: src)
            for item in items {
                let srcItem = (src as NSString).appendingPathComponent(item)
                let destItem = (dest as NSString).appendingPathComponent(item)
                try copyItemReplacing(from: srcItem, to: destItem)
            }
        } else {
            if fm.fileExists(atPath: dest) {
                try fm.removeItem(atPath: dest)
            }
            try fm.copyItem(atPath: src, toPath: dest)
        }
    }
    
    func patchRedundantTranslations(gameDir: String, selectedPatches: [PatchTarget]) {
        let fm = FileManager.default
        let enumerator = fm.enumerator(atPath: gameDir)
        var thFiles: [String] = []
        
        while let file = enumerator?.nextObject() as? String {
            if file.contains("i18n/th") && file.hasSuffix(".json") {
                thFiles.append(file)
            }
        }
        
        let regexPattern = "([\\u0E00-\\u0E7F]+)\\s*\\([A-Za-z0-9\\s\\.\\-_\\']+\\)"
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else { return }
        
        var filesPatched = 0
        var itemsPatched = 0
        
        for file in thFiles {
            let fullPath = (gameDir as NSString).appendingPathComponent(file)
            let lowerPath = fullPath.lowercased()
            
            // Check if matches any selected patch target
            var shouldPatch = false
            for patch in selectedPatches {
                for hint in patch.hints {
                    if lowerPath.contains(hint) {
                        shouldPatch = true
                        break
                    }
                }
                if shouldPatch { break }
            }
            
            if !shouldPatch { continue }
            
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                let nsString = content as NSString
                let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                
                if !matches.isEmpty {
                    let newContent = regex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "$1")
                    do {
                        try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                        filesPatched += 1
                        itemsPatched += matches.count
                    } catch {
                        self.log("❌ ไม่สามารถบันทึกไฟล์ \(file)")
                    }
                }
            }
        }
        
        if itemsPatched > 0 {
            self.log("  ✨ แพตช์สำเร็จ: พบและลบวงเล็บไปทั้งหมด \(itemsPatched) จุด (ใน \(filesPatched) ไฟล์)")
        } else {
            self.log("  ⚠️ ไม่พบข้อความที่ต้องแพตช์ในม็อดที่เลือก")
        }
    }
    
    func injectGMCMDescriptions(style: Int) {
        isWorking = true
        logs = ""
        
        let fm = FileManager.default
        let gDir = self.gameDir
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.log("🛠️ กำลังสแกนหาไฟล์ manifest.json ในโฟลเดอร์ Mods...")
            
            let enumerator = fm.enumerator(atPath: gDir)
            var manifestFiles: [String] = []
            
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix("manifest.json") {
                    manifestFiles.append(file)
                }
            }
            
            var foundCount = 0
            var injectedCount = 0
            var rollbackCount = 0
            
            let isRollback = (style == 3)
            let dict = (style == 1) ? GMCMInjector.gamerDesc : GMCMInjector.normalDesc
            
            guard let nameRegex = try? NSRegularExpression(pattern: "\"Name\"\\s*:\\s*\"([^\"]+)\"", options: []),
                  let descRegex = try? NSRegularExpression(pattern: "(\"Description\"\\s*:\\s*\")[^\"\\\\]*(?:\\\\.[^\"\\\\]*)*(\")", options: []),
                  let insertRegex = try? NSRegularExpression(pattern: "(\"Name\"\\s*:\\s*\"[^\"]+\"\\s*,)", options: []) else {
                return
            }
            
            if isRollback {
                self.log("↩️ เริ่มคืนค่าเดิม (Rollback)...")
                for file in manifestFiles {
                    let fullPath = (gDir as NSString).appendingPathComponent(file)
                    let backupPath = fullPath + ".bak"
                    if fm.fileExists(atPath: backupPath) {
                        do {
                            if fm.fileExists(atPath: fullPath) {
                                try fm.removeItem(atPath: fullPath)
                            }
                            try fm.moveItem(atPath: backupPath, toPath: fullPath)
                            
                            // Try to extract name for logging
                            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                                let nsContent = content as NSString
                                if let match = nameRegex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) {
                                    let modName = nsContent.substring(with: match.range(at: 1))
                                    self.log("  ✅ คืนค่าเดิม: \(modName)")
                                }
                            }
                            rollbackCount += 1
                        } catch {
                            self.log("❌ คืนค่าล้มเหลวที่ \(file)")
                        }
                    }
                }
                self.log("🎉 คืนค่าเดิมสำเร็จทั้งหมด: \(rollbackCount) ตัว")
                self.showAlert(title: "สำเร็จ!", message: "คืนค่าคำอธิบายภาษาอังกฤษของ GMCM เรียบร้อยแล้ว")
            } else {
                let styleName = (style == 1) ? "เกมเมอร์ (เน้นสนุกสนาน)" : "ทางการ (เน้นเรียบร้อย)"
                self.log("🇹🇭 เริ่มอัปเดตคำอธิบายภาษาไทยในหน้าตั้งค่า GMCM (\(styleName))...")
                
                for file in manifestFiles {
                    let fullPath = (gDir as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
                    
                    let nsContent = content as NSString
                    guard let nameMatch = nameRegex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) else { continue }
                    
                    let modName = nsContent.substring(with: nameMatch.range(at: 1))
                    
                    if let thaiDesc = dict[modName] {
                        foundCount += 1
                        
                        var currentDesc = ""
                        if let descMatch = descRegex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: nsContent.length)) {
                            // Extract just the value inside quotes
                            let fullMatch = nsContent.substring(with: descMatch.range)
                            currentDesc = fullMatch // We'll just compare roughly or replace anyway
                        }
                        
                        // We replace if not already replaced
                        if !content.contains("\"\(thaiDesc)\"") {
                            let backupPath = fullPath + ".bak"
                            if !fm.fileExists(atPath: backupPath) {
                                try? fm.copyItem(atPath: fullPath, toPath: backupPath)
                            }
                            
                            let escapedThaiDesc = thaiDesc.replacingOccurrences(of: "\"", with: "\\\"")
                            
                            var newContent = content
                            let descMatches = descRegex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
                            
                            if !descMatches.isEmpty {
                                newContent = descRegex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length), withTemplate: "$1\(escapedThaiDesc)$2")
                                do {
                                    try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                                    self.log("  ✅ แปลคำอธิบายสำเร็จ: \(modName)")
                                    injectedCount += 1
                                } catch {}
                            } else {
                                // Inject below Name
                                let newTemplate = "$1\n  \"Description\": \"\(escapedThaiDesc)\","
                                newContent = insertRegex.stringByReplacingMatches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length), withTemplate: newTemplate)
                                do {
                                    try newContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
                                    self.log("  ✅ แทรกคำอธิบายสำเร็จ: \(modName)")
                                    injectedCount += 1
                                } catch {}
                            }
                        }
                    }
                }
                self.log("=============================")
                self.log("✨ พบม็อดที่รองรับ: \(foundCount) ตัว")
                self.log("✨ ทำการแก้ไขสำเร็จ: \(injectedCount) ตัว")
                self.log("🎉 การแปล GMCM เสร็จสิ้น!")
                self.showAlert(title: "สำเร็จ!", message: "อัปเดตคำแปลคำอธิบายม็อดในเมนู GMCM เสร็จสมบูรณ์\nดูรายละเอียดเพิ่มเติมได้ที่หน้า 'บันทึกการทำงาน'")
            }
            
            DispatchQueue.main.async {
                self.isWorking = false
            }
        }
    }
}

struct ContentView: View {
    @StateObject var vm = InstallerViewModel()
    @State private var selection: String? = "Home"
    
    var body: some View {
        VStack(spacing: 0) {
            // Global Header
            HStack {
                Label("ตำแหน่งโฟลเดอร์ Mods ของเกม:", systemImage: "folder.fill")
                    .font(Font.programmerFont(size: 13).bold())
                    .foregroundColor(.secondary)
                TextField("Game Directory", text: $vm.gameDir)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(Font.programmerFont(size: 13))
                Button(action: { vm.selectGameDir() }) {
                    Label("เลือก...", systemImage: "magnifyingglass")
                        .font(Font.programmerFont(size: 13))
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            NavigationView {
                // Sidebar
                List(selection: $selection) {
                    NavigationLink(destination: HomeView(vm: vm), tag: "Home", selection: $selection) {
                        Label("หน้าแรก", systemImage: "house.fill")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                    }
                    NavigationLink(destination: ModsInstallView(vm: vm), tag: "Install", selection: $selection) {
                        Label("ติดตั้งไฟล์แปล", systemImage: "shippingbox.fill")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                    }
                    NavigationLink(destination: ToolsView(vm: vm), tag: "Tools", selection: $selection) {
                        Label("ปรับแต่ง/เครื่องมือเสริม", systemImage: "wrench.and.screwdriver.fill")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                    }
                    NavigationLink(destination: LogsView(vm: vm), tag: "Logs", selection: $selection) {
                        Label("บันทึกการทำงาน", systemImage: "doc.text.fill")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                
                // Default View
                HomeView(vm: vm)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .font(Font.programmerFont(size: 13))
        .accentColor(.secondary)
        .alert(isPresented: $vm.showSuccessAlert) {
            Alert(
                title: Text(vm.alertTitle),
                message: Text(vm.alertMessage),
                dismissButton: .default(Text("ตกลง"))
            )
        }
    }
}

struct ModsInstallView: View {
    @ObservedObject var vm: InstallerViewModel
    
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .foregroundColor(.secondary)
                        Text("เลือกไฟล์แปลม็อดที่จะติดตั้ง")
                    }
                    .font(Font.programmerFont(size: 18).bold())
                    
                    Spacer()
                    Button("เลือกทั้งหมด") { for i in 0..<vm.mods.count { vm.mods[i].isEnabled = true } }
                        .font(Font.programmerFont(size: 12))
                    Button("ยกเลิก") { for i in 0..<vm.mods.count { vm.mods[i].isEnabled = false } }
                        .font(Font.programmerFont(size: 12))
                }
                
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.secondary)
                    Text("หมายเหตุ: โปรแกรมนี้ติดตั้งเฉพาะ 'ไฟล์แปลภาษาไทย' ลงในม็อดต้นฉบับที่คุณลงไว้แล้วเท่านั้น (ไม่ใช่การติดตั้งตัวม็อดหลักแต่อย่างใด)")
                }
                .font(Font.programmerFont(size: 12))
                .foregroundColor(.secondary)
                
                if vm.mods.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "shippingbox.circle")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.secondary)
                        Text("ไม่พบไฟล์แปลม็อดในโฟลเดอร์ mods/")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let colToggleWidth: CGFloat = 50
                    let colFolderWidth: CGFloat = 60
                    let availableWidth = geo.size.width - 32 - 24 - colToggleWidth - colFolderWidth
                    let colNameWidth = availableWidth * 0.40
                    let colVersionWidth = availableWidth * 0.12
                    let colLinkWidth = availableWidth * 0.12
                    let colVariantWidth = availableWidth * 0.36
                    
                    VStack(spacing: 0) {
                        // Table Header
                        HStack(spacing: 0) {
                            Text("ติดตั้ง").frame(width: colToggleWidth, alignment: .leading)
                            Text("ชื่อคำแปลม็อด").frame(width: colNameWidth, alignment: .leading)
                            Text("เวอร์ชัน").frame(width: colVersionWidth, alignment: .leading)
                            Text("ลิงก์").frame(width: colLinkWidth, alignment: .leading)
                            Text("เวอร์ชันแปล").frame(width: colVariantWidth, alignment: .leading)
                            Text("โฟลเดอร์").frame(width: colFolderWidth, alignment: .center)
                        }
                        .font(Font.programmerFont(size: 12).bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        
                        Divider().padding(.vertical, 4)
                        
                        // Table Rows
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach($vm.mods) { $mod in
                                    VStack(spacing: 0) {
                                        HStack(spacing: 0) {
                                            // Column 1: Toggle
                                            Toggle("", isOn: $mod.isEnabled)
                                                .labelsHidden()
                                                .frame(width: colToggleWidth, alignment: .leading)
                                            
                                            // Column 2: Name
                                            Text(mod.displayName)
                                                .font(Font.programmerFont(size: 13).bold())
                                                .frame(width: colNameWidth, alignment: .leading)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            
                                            // Column 3: Version
                                            Text(mod.version)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: colVersionWidth, alignment: .leading)
                                            
                                            // Column 4: Link
                                            Group {
                                                if !mod.nexusUrl.isEmpty {
                                                    Button(action: {
                                                        if let url = URL(string: mod.nexusUrl) {
                                                            NSWorkspace.shared.open(url)
                                                        }
                                                    }) {
                                                        Label("Nexus", systemImage: "arrow.up.right.square")
                                                            .font(Font.programmerFont(size: 11))
                                                    }
                                                    .buttonStyle(PlainButtonStyle())
                                                    .foregroundColor(.secondary)
                                                } else {
                                                    Text("-")
                                                        .font(Font.programmerFont(size: 13))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .frame(width: colLinkWidth, alignment: .leading)
                                            
                                            // Column 5: Variant Picker
                                            Group {
                                                if mod.variants.count > 1 && !mod.variants[0].folderName.isEmpty {
                                                    Picker("", selection: $mod.selectedVariant) {
                                                        ForEach(mod.variants, id: \.self) { v in
                                                            Text(v.name).tag(v)
                                                        }
                                                    }
                                                    .pickerStyle(MenuPickerStyle())
                                                    .labelsHidden()
                                                    .font(Font.programmerFont(size: 11))
                                                } else {
                                                    Text("มาตรฐาน")
                                                        .font(Font.programmerFont(size: 11))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .frame(width: colVariantWidth, alignment: .leading)
                                            
                                            // Column 6: Folder
                                            Group {
                                                let folderToOpen = (mod.folderName as NSString).lastPathComponent
                                                let installedPath = vm.findInstalledMod(gameDir: vm.gameDir, folderName: folderToOpen)
                                                Button(action: {
                                                    if let path = installedPath {
                                                        let url = URL(fileURLWithPath: path)
                                                        NSWorkspace.shared.open(url)
                                                    }
                                                }) {
                                                    Image(systemName: "folder")
                                                        .font(.system(size: 11))
                                                }
                                                .buttonStyle(BorderedButtonStyle())
                                                .controlSize(.small)
                                                .disabled(installedPath == nil)
                                                .help("เปิดโฟลเดอร์ใน Finder")
                                            }
                                            .frame(width: colFolderWidth, alignment: .center)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                
                if #available(macOS 12.0, *) {
                    Button(action: { vm.startInstall() }) {
                        Label(vm.isWorking ? "กำลังทำงาน..." : "ดำเนินการติดตั้งไฟล์แปลภาษาไทย", systemImage: vm.isWorking ? "hourglass" : "play.fill")
                            .font(Font.programmerFont(size: 14).bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.isWorking || vm.mods.filter({$0.isEnabled}).isEmpty)
                } else {
                    Button(action: { vm.startInstall() }) {
                        Text(vm.isWorking ? "กำลังทำงาน..." : "ดำเนินการติดตั้งไฟล์แปลภาษาไทย")
                            .font(Font.programmerFont(size: 14).bold())
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(vm.isWorking || vm.mods.filter({$0.isEnabled}).isEmpty)
                }
            }
            .padding()
        }
    }
}

struct ToolsView: View {
    @ObservedObject var vm: InstallerViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundColor(.secondary)
                    Text("ปรับแต่ง & เครื่องมือเสริม")
                }
                .font(Font.programmerFont(size: 20).bold())
                
                GroupBox(label: Label("แพตช์ลบข้อความภาษาอังกฤษในวงเล็บ", systemImage: "bandage.fill").font(Font.programmerFont(size: 14).bold()).foregroundColor(.secondary)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ลบชื่อภาษาอังกฤษในวงเล็บหลังชื่อไทย (เช่น เปลี่ยนจาก 'เอลี (Eli)' เป็น 'เอลี') ในไฟล์แปลภาษาไทยที่คุณติดตั้งแล้ว เพื่อให้ภาษาไทยดูสะอาดตายิ่งขึ้น")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                        
                        ForEach($vm.patches) { $patch in
                            Toggle(isOn: $patch.isEnabled) {
                                Text(patch.name)
                                    .font(Font.programmerFont(size: 13))
                            }
                        }
                        
                        Button(action: { vm.startInstall() }) {
                            Label("ดำเนินการแพตช์ลบวงเล็บภาษาอังกฤษ", systemImage: "bandage")
                                .font(Font.programmerFont(size: 13).bold())
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                        }
                        .disabled(vm.isWorking || vm.patches.filter({$0.isEnabled}).isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox(label: Label("แปลรายละเอียดม็อดในเมนู GMCM (GMCM Injector)", systemImage: "gearshape.2.fill").font(Font.programmerFont(size: 14).bold()).foregroundColor(.secondary)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("เขียนทับรายละเอียด/คำอธิบายม็อดต่าง ๆ ในเมนูตั้งค่าม็อดในเกม (Generic Mod Config Menu) ให้เป็นคำแนะนำภาษาไทย เพื่อให้อ่านเข้าใจง่ายและตั้งค่าได้สะดวก")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 15) {
                            Button(action: { vm.injectGMCMDescriptions(style: 1) }) {
                                Label(vm.isWorking ? "กำลังทำงาน..." : "แปลสไตล์เกมเมอร์ (เน้นสนุกสนาน)", systemImage: vm.isWorking ? "hourglass" : "gamecontroller.fill")
                                    .font(Font.programmerFont(size: 12).bold())
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .disabled(vm.isWorking)
                            
                            Button(action: { vm.injectGMCMDescriptions(style: 2) }) {
                                Label(vm.isWorking ? "กำลังทำงาน..." : "แปลสไตล์ทางการ (เน้นเรียบร้อย)", systemImage: vm.isWorking ? "hourglass" : "briefcase.fill")
                                    .font(Font.programmerFont(size: 12).bold())
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .disabled(vm.isWorking)
                            
                            Button(action: { vm.injectGMCMDescriptions(style: 3) }) {
                                Label(vm.isWorking ? "กำลังทำงาน..." : "คืนค่าคำอธิบายภาษาอังกฤษ", systemImage: vm.isWorking ? "hourglass" : "arrow.uturn.backward")
                                    .font(Font.programmerFont(size: 12).bold())
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .disabled(vm.isWorking)
                        }
                        .padding(.top, 8)
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }
}

struct LogsView: View {
    @ObservedObject var vm: InstallerViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text("บันทึกการทำงาน")
            }
            .font(Font.programmerFont(size: 18).bold())
            .padding(.bottom, 5)
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(vm.logs.isEmpty ? "ยังไม่มีบันทึกการทำงาน..." : vm.logs)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(vm.logs.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("LogBottom")
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .onChange(of: vm.logs) { _ in
                    withAnimation {
                        proxy.scrollTo("LogBottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding()
    }
}

struct HomeView: View {
    @ObservedObject var vm: InstallerViewModel
    
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "house.fill")
                        .foregroundColor(.secondary)
                    Text("หน้าแรก & ตรวจสอบม็อดในเครื่อง").font(Font.programmerFont(size: 18).bold())
                }
                
                // Summary Cards
                HStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ม็อดทั้งหมดในเครื่อง").font(Font.programmerFont(size: 11)).foregroundColor(.secondary)
                        Text("\(vm.installedMods.count)").font(Font.programmerFont(size: 24).bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ติดตั้งคำแปลแล้ว").font(Font.programmerFont(size: 11)).foregroundColor(.secondary)
                        Text("\(vm.installedMods.filter { $0.status == .installed }.count)").font(Font.programmerFont(size: 24).bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("มีคำแปลใหม่พร้อมลง").font(Font.programmerFont(size: 11)).foregroundColor(.secondary)
                        Text("\(vm.installedMods.filter { $0.status == .availablePending }.count)").font(Font.programmerFont(size: 24).bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.secondary)
                    Text("รายการม็อดที่พบในเครื่อง")
                }
                .font(Font.programmerFont(size: 14).bold())
                
                if vm.installedMods.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "shippingbox.circle")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.secondary)
                        Text("ไม่พบม็อดติดตั้งในเครื่อง (โปรดตรวจสอบโฟลเดอร์ Mods ด้านบน)")
                            .font(Font.programmerFont(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Table of Installed Mods
                    let colFolderWidth: CGFloat = 60
                    let availableWidth = geo.size.width - 32 - 24 - colFolderWidth
                    let colNameWidth = availableWidth * 0.40
                    let colVersionWidth = availableWidth * 0.15
                    let colLinkWidth = availableWidth * 0.15
                    let colStatusWidth = availableWidth * 0.30
                    
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("ชื่อม็อดในเครื่อง").frame(width: colNameWidth, alignment: .leading)
                            Text("เวอร์ชัน").frame(width: colVersionWidth, alignment: .leading)
                            Text("ลิงก์").frame(width: colLinkWidth, alignment: .leading)
                            Text("สถานะแปลไทย").frame(width: colStatusWidth, alignment: .leading)
                            Text("โฟลเดอร์").frame(width: colFolderWidth, alignment: .center)
                        }
                        .font(Font.programmerFont(size: 12).bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        
                        Divider().padding(.vertical, 4)
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(vm.installedMods) { mod in
                                    VStack(spacing: 0) {
                                        HStack(spacing: 0) {
                                            Text(mod.name)
                                                .font(Font.programmerFont(size: 13).bold())
                                                .frame(width: colNameWidth, alignment: .leading)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            
                                            Text(mod.version)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: colVersionWidth, alignment: .leading)
                                            
                                            Group {
                                                if !mod.nexusUrl.isEmpty {
                                                    Button(action: {
                                                        if let url = URL(string: mod.nexusUrl) {
                                                            NSWorkspace.shared.open(url)
                                                        }
                                                    }) {
                                                        Label("Nexus", systemImage: "arrow.up.right.square")
                                                            .font(Font.programmerFont(size: 11))
                                                    }
                                                    .buttonStyle(PlainButtonStyle())
                                                    .foregroundColor(.secondary)
                                                } else {
                                                    Text("-")
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .frame(width: colLinkWidth, alignment: .leading)
                                            
                                            Group {
                                                switch mod.status {
                                                case .installed:
                                                    Text(mod.status.rawValue)
                                                        .foregroundColor(.secondary)
                                                case .availablePending:
                                                    Text(mod.status.rawValue)
                                                        .foregroundColor(.primary)
                                                        .bold()
                                                case .notSupported:
                                                    Text(mod.status.rawValue)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .font(Font.programmerFont(size: 12))
                                            .frame(width: colStatusWidth, alignment: .leading)
                                            
                                            // Column 5: Folder
                                            Group {
                                                let folderToOpen = (mod.folderName as NSString).lastPathComponent
                                                let installedPath = vm.findInstalledMod(gameDir: vm.gameDir, folderName: folderToOpen)
                                                Button(action: {
                                                    if let path = installedPath {
                                                        let url = URL(fileURLWithPath: path)
                                                        NSWorkspace.shared.open(url)
                                                    }
                                                }) {
                                                    Image(systemName: "folder")
                                                        .font(.system(size: 11))
                                                }
                                                .buttonStyle(BorderedButtonStyle())
                                                .controlSize(.small)
                                                .disabled(installedPath == nil)
                                                .help("เปิดโฟลเดอร์ใน Finder")
                                            }
                                            .frame(width: colFolderWidth, alignment: .center)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

extension Font {
    static func programmerFont(size: CGFloat) -> Font {
        return .system(size: size)
    }
}
