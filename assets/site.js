/* MachOKnife 主页脚本：语言、主题、下载直链、解剖图交互、终端回放 */
(function () {
  "use strict";

  var doc = document.documentElement;
  var query = new URLSearchParams(location.search);
  var reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
  var $ = function (sel, root) {
    return (root || document).querySelector(sel);
  };
  var $$ = function (sel, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel));
  };

  /* ---------- 文案：简体从 DOM 读取，英文与繁体在此维护 ---------- */
  var I18N = {
    en: {
      "meta.title": "MachOKnife — Mach-O browser and editor for macOS",
      "meta.desc": "MachOKnife is a native macOS app for inspecting and editing Mach-O binaries: a MachOView-style structure browser for executables, dylibs, frameworks, universal binaries and static libraries, plus retag, XCFramework packaging, merge / split / remove architectures and contamination checks. The same tools ship as machoe-cli.",
      "nav.anatomy": "Anatomy", "nav.browser": "Browser", "nav.tools": "Tools", "nav.cli": "CLI", "nav.download": "Download",
      "hero.tag": "Mach-O browser and editor for macOS",
      "hero.h1": "Dissect a Mach-O<br><span class=\"stroke\">layer</span> by layer",
      "hero.lead": "MachOKnife is a native macOS app that walks executables, dylibs, frameworks, universal binaries and static libraries field by field in a MachOView-style structure tree. It also retags platforms, packages XCFrameworks, merges, splits and removes architectures, and checks for contaminated slices. The same tools ship as the command-line utility <code>machoe-cli</code>.",
      "dl.arm": "Download for Apple silicon", "dl.intel": "Download for Intel",
      "hero.meta": "macOS 13 or later · Developer ID signed and notarized by Apple · Sparkle updates",
      "hero.all": "All releases",
      "tb.title": "Specimen",
      "tb.note": "The specimen below is machoe-cli itself, the command-line tool bundled with the app. Every byte, offset and field value comes from the real file.",
      "plate.mode": "RAW · little-endian",
      "layer.hdr": "File header", "layer.lc": "Load commands", "layer.seg": "Segments · file layout", "layer.sect": "Sections in __TEXT",
      "insp.off": "Offset", "insp.field": "Field", "insp.size": "Size", "insp.val": "Value",
      "plate.hint": "Hover any layer on the left or any byte on the right to see where it lives in the file and what it means. When idle, the scanner walks the fields one by one.",
      "br.tag": "Structure browser",
      "br.h": "Every field, with its offset and raw bytes",
      "br.p": "A structure tree on the left; a field-level Detail table and a hex Data view on the right, laid out like MachOView.",
      "br.cap": "The main workspace: browse the structure tree on the left and inspect every field with its raw offset and bytes on the right.",
      "c1.h": "The whole structure", "c1.p": "Mach header, load commands, segments and sections, dyld info / chained fixups, export trie, symbol / indirect symbol / string tables, code signature, Objective-C metadata and relocations.",
      "c2.h": "Every container", "c2.p": "Thin and universal (fat) binaries, static libraries (<code>.a</code>), and dyld shared caches.",
      "c3.h": "RAW and RVA", "c3.p": "Switch between two address modes at any time, with a field-level Detail table next to a hex Data view.",
      "c4.h": "Large files stay responsive", "c4.p": "Symbols, strings and other heavy groups are decoded on demand, so big binaries open smoothly.",
      "c5.h": "Search and copy", "c5.p": "Structure search, ⌘C to copy the selected rows, and copy or export from the context menu.",
      "c6.h": "Open it your way", "c6.p": "Drag and drop, File › Open…, Finder “Open With”, or File › Open Recent. Recent files survive relaunches.",
      "tl.tag": "Tools menu", "tl.h": "Rewrite, package, merge, split, check",
      "tl.p": "Every tool opens pre-filled with the file currently open in the workspace.",
      "t1.h": "Retag", "t1.p": "Rewrite platform, minimum OS and SDK metadata — for example, turn an iOS slice into a Mac Catalyst slice.",
      "t2.h": "Build XCFramework", "t2.p": "Package iOS device and simulator static libraries with headers into an XCFramework, optionally generating Mac Catalyst slices automatically.",
      "t3.h": "Check binary contamination", "t3.p": "Find slices whose platform or architecture doesn't match what you expect, such as simulator slices before an App Store upload.",
      "t4.h": "Merge / split Mach-O", "t4.p": "Merge slices into a universal file, split a fat file per architecture, or strip architectures you don't need.",
      "t5.h": "Mach-O summary", "t5.p": "A one-page report for a binary or archive. Analysis runs in the background, so large files never freeze the window.",
      "p1.h": "Three UI languages", "p1.p": "English, 简体中文 and 繁體中文, switched instantly in Preferences.",
      "p2.h": "Appearance and updates", "p2.p": "Follow the system, or pick light or dark. Check for updates manually, daily or at launch.",
      "p3.h": "One-click CLI install", "p3.p": "Install or uninstall the bundled <code>machoe-cli</code> into a directory of your choice from Preferences › CLI.",
      "cli.h": "The same tools, in your scripts and CI",
      "cli.p": "The replay below is real output from machoe-cli v1.7.0 run on a copy of /bin/ls: find the extra architectures, strip them, then check again.",
      "term.replay": "Replay",
      "sc.thin": "Strip archs", "sc.info": "Inspect slices", "sc.deps": "Deps & validate",
      "term.note": "Pick a tab to switch scenes. The replay pauses while the terminal is off screen.",
      "cmd.c": "Command", "cmd.d": "What it does",
      "cmd.info": "Per-slice metadata for a Mach-O or archive; --json supported",
      "cmd.summary": "A concise overview; --json supported",
      "cmd.list": "Dylib dependencies and LC_RPATH entries; --json supported",
      "cmd.check": "Detect platform or architecture slices that don't match a target; exits 1 on mismatches",
      "cmd.validate": "Validate structure and signature metadata; exits 1 on problems",
      "cmd.merge": "Merge slices, or split by architecture",
      "cmd.remove": "Remove architectures from a universal binary or fat static library",
      "cmd.retag": "Rewrite platform, minimum OS and SDK versions",
      "cmd.xcf": "Package static libraries and headers into an XCFramework",
      "cmd.setid": "Change a dylib's install name; rewrite matching LC_RPATH entries",
      "cmd.strip": "Remove the code signature load command",
      "cmd.fix": "Normalize dyld-cache-style dylibs so they load normally",
      "rule.1": "Reports go to stdout and errors to stderr. Usage errors exit with 64; failed checks exit with 1.",
      "rule.2": "Editing commands never overwrite their input implicitly: <code>--output</code> must differ from the input, and <code>remove-arch</code> needs an explicit <code>--in-place</code> to rewrite a file.",
      "rule.3": "A single-value option given twice is rejected instead of silently picking one.",
      "cli.install": "In the app, open Preferences › CLI and install into a directory on your <code>PATH</code> (such as <code>/usr/local/bin</code>). Then run <code>machoe-cli help &lt;command&gt;</code> for every option.",
      "dl.tag": "Download", "dl.h": "Pick the build for your chip",
      "dl.p": "Each release ships one DMG per architecture, so downloads stay small. In-app updates automatically serve the build that matches your Mac.",
      "dl.rec": "Recommended", "dl.armh": "Apple silicon", "dl.armp": "Macs with M1 or later.", "dl.btn": "Download DMG",
      "dl.intelh": "Intel", "dl.intelp": "Macs with an Intel processor.",
      "req.h": "Requirements and install",
      "req.1": "macOS 13.0 or later", "req.2": "Apple silicon or Intel Mac (pick the matching DMG)",
      "req.how": "Not sure? Open the Apple menu › About This Mac: “Chip: Apple M…” means Apple silicon, “Processor: Intel…” means Intel.",
      "req.install": "Open the DMG, drag MachOKnife into Applications, then launch it. Builds are Developer ID signed and notarized by Apple, and keep themselves up to date through Sparkle.",
      "req.old": "All previous releases →",
      "ft.desc": "Mach-O browser and editor for macOS", "ft.more": "More", "ft.vanjay": "More apps by VanJay", "ft.src": "Project", "ft.fb": "Feedback",
      "a.home": "MachOKnife home", "a.nav": "Page sections", "a.lang": "Language", "a.theme": "Appearance",
      "a.light": "Light", "a.dark": "Dark", "a.system": "Match system", "a.gh": "GitHub repository",
      "a.tb": "Specimen details", "a.hex": "Hex data", "a.scenes": "Replay scenes", "a.term": "Terminal output",
      "alt.icon": "MachOKnife icon",
      "alt.main": "MachOKnife main window: structure tree on the left, the load commands of Sparkle.framework on the right",
      "alt.retag": "The Retag tool window", "alt.xcf": "The Build XCFramework tool window", "alt.cont": "The binary contamination check window",
      "js.outside": "beyond the first {n} bytes shown here",
      "js.count": "{n} commands",
      "js.vmonly": "VM only, 0 B in file",
      "js.more": "+ {n} more: {list} …",
      "js.sect": "section header"
    },
    "zh-TW": {
      "meta.title": "MachOKnife — macOS 上的 Mach-O 檢視與編輯工具",
      "meta.desc": "MachOKnife 是原生 macOS 應用程式：以 MachOView 式結構樹逐欄位檢視 Mach-O、通用二進位檔與靜態函式庫，並提供 Retag、XCFramework 打包、合併／拆分／移除架構、污染檢查，同樣的功能也以命令列工具 machoe-cli 提供。",
      "nav.anatomy": "解剖", "nav.browser": "結構瀏覽", "nav.tools": "工具", "nav.cli": "命令列", "nav.download": "下載",
      "hero.tag": "macOS 上的 Mach-O 檢視與編輯工具",
      "hero.h1": "把 Mach-O<br><span class=\"stroke\">一層層</span>拆開",
      "hero.lead": "MachOKnife 是原生 macOS 應用程式：以 MachOView 式結構樹逐欄位檢視執行檔、dylib、Framework、通用二進位檔與靜態函式庫，並附帶 Retag、XCFramework 打包、合併／拆分／移除架構、污染檢查等工具；同一套功能也以命令列工具 <code>machoe-cli</code> 提供。",
      "dl.arm": "下載 Apple 晶片版", "dl.intel": "下載 Intel 版",
      "hero.meta": "macOS 13 以上 · 以 Developer ID 簽署並經 Apple 公證 · Sparkle 自動更新",
      "hero.all": "所有版本",
      "tb.title": "樣本",
      "tb.note": "下方解剖的是隨 App 附帶的命令列工具 machoe-cli 本身：位元組、偏移與欄位值都取自真實檔案。",
      "plate.mode": "RAW · 小端序",
      "layer.hdr": "檔案標頭", "layer.lc": "載入命令", "layer.seg": "區段 · 檔案配置", "layer.sect": "__TEXT 內的節",
      "insp.off": "偏移", "insp.field": "欄位", "insp.size": "長度", "insp.val": "數值",
      "plate.hint": "將游標移到左側任一層或右側任一位元組，查看它在檔案中的位置與意義；閒置時會自動逐一掃描欄位。",
      "br.tag": "結構瀏覽器",
      "br.h": "每個欄位都標出偏移與原始位元組",
      "br.p": "左側為結構樹，右側為欄位層級的 Detail 表格與十六進位 Data 檢視，配置方式與 MachOView 一致。",
      "br.cap": "主要工作區：左側瀏覽結構樹，右側檢視每個欄位的原始偏移與資料。",
      "c1.h": "完整結構", "c1.p": "Mach 標頭、載入命令、區段與節、dyld info／chained fixups、匯出 trie、符號表／間接符號表／字串表、程式碼簽章、Objective-C 中繼資料與重定位。",
      "c2.h": "各種容器", "c2.p": "單一架構與通用（fat）二進位檔、靜態函式庫 <code>.a</code>，以及 dyld shared cache。",
      "c3.h": "RAW／RVA 雙位址", "c3.p": "兩種位址模式隨時切換，欄位層級的 Detail 表格與十六進位 Data 檢視並列。",
      "c4.h": "大型檔案依然流暢", "c4.p": "符號、字串等重量級分組按需解碼，開啟大型二進位檔依然順暢。",
      "c5.h": "搜尋與拷貝", "c5.p": "結構搜尋，⌘C 拷貝選取列，並可從右鍵選單拷貝或輸出。",
      "c6.h": "順手的開啟方式", "c6.p": "拖放、「檔案 › 開啟」、Finder「打開檔案的應用程式」與「打開最近使用過的」，最近使用的檔案在重新啟動後仍保留。",
      "tl.tag": "Tools 選單", "tl.h": "改寫、打包、拆合與排查",
      "tl.p": "每個工具開啟時都會自動帶入工作區中目前開啟的檔案。",
      "t1.h": "Retag", "t1.p": "改寫平台、最低系統版本與 SDK 中繼資料，例如把 iOS 切片轉成 Mac Catalyst 切片。",
      "t2.h": "建構 XCFramework", "t2.p": "把 iOS 實機／模擬器靜態函式庫與標頭檔打包成 XCFramework，可選擇自動產生 Mac Catalyst 切片。",
      "t3.h": "二進位污染檢查", "t3.p": "找出平台或架構與預期不符的切片，例如上架前混入的模擬器切片。",
      "t4.h": "合併／拆分 Mach-O", "t4.p": "把多個切片合併為通用檔案，依架構拆分 fat 檔案，或直接移除不需要的架構。",
      "t5.h": "Mach-O 摘要", "t5.p": "為二進位檔或靜態函式庫產生一頁式報告，分析在背景進行，大型檔案也不會卡住介面。",
      "p1.h": "三種介面語言", "p1.p": "English、简体中文、繁體中文，在偏好設定中即時切換。",
      "p2.h": "外觀與更新", "p2.p": "外觀可跟隨系統、淺色或深色；更新檢查可選手動、每天或啟動時。",
      "p3.h": "一鍵安裝 CLI", "p3.p": "在「偏好設定 › CLI」中把隨附的 <code>machoe-cli</code> 安裝到你選擇的目錄，也可以解除安裝。",
      "cli.h": "同樣的功能，寫進腳本與 CI",
      "cli.p": "下方的終端機回放是 machoe-cli v1.7.0 對 /bin/ls 副本的真實輸出：先找出多餘的架構，移除後再複查。",
      "term.replay": "重播",
      "sc.thin": "移除架構", "sc.info": "檢視切片", "sc.deps": "相依與驗證",
      "term.note": "點選上方標籤切換場景；終端機離開畫面時回放會自動暫停。",
      "cmd.c": "命令", "cmd.d": "用途",
      "cmd.info": "依切片檢視 Mach-O 或靜態函式庫中繼資料，支援 --json",
      "cmd.summary": "輸出簡明概覽，支援 --json",
      "cmd.list": "列出相依的 dylib 與 LC_RPATH，支援 --json",
      "cmd.check": "偵測與目標不符的平台或架構切片，不符時結束碼為 1",
      "cmd.validate": "驗證結構與簽章中繼資料，有問題時結束碼為 1",
      "cmd.merge": "合併多個切片，或依架構拆分",
      "cmd.remove": "從通用二進位檔或 fat 靜態函式庫中移除架構",
      "cmd.retag": "改寫平台、最低系統與 SDK 版本",
      "cmd.xcf": "把靜態函式庫與標頭檔打包成 XCFramework",
      "cmd.setid": "修改 dylib 的 install name，改寫相符的 LC_RPATH",
      "cmd.strip": "移除程式碼簽章載入命令",
      "cmd.fix": "把 dyld cache 風格的 dylib 修正為可正常載入",
      "rule.1": "報告寫到 stdout，錯誤寫到 stderr；用法錯誤結束碼為 64，檢查未通過結束碼為 1。",
      "rule.2": "編輯類命令不會默默覆寫輸入：<code>--output</code> 必須與輸入不同，<code>remove-arch</code> 需明確加上 <code>--in-place</code> 才會就地改寫。",
      "rule.3": "單值選項重複給出會直接報錯，不會任意挑選其中一個。",
      "cli.install": "在 App 的「偏好設定 › CLI」中選擇一個位於 <code>PATH</code> 上的目錄（如 <code>/usr/local/bin</code>）安裝，之後執行 <code>machoe-cli help &lt;command&gt;</code> 查看每個命令的完整選項。",
      "dl.tag": "下載", "dl.h": "依晶片選擇安裝檔",
      "dl.p": "每個版本依架構分別提供 DMG，檔案更小；App 內更新會自動推送與本機相符的版本。",
      "dl.rec": "推薦", "dl.armh": "Apple 晶片", "dl.armp": "M1 及之後的 Mac。", "dl.btn": "下載 DMG",
      "dl.intelh": "Intel", "dl.intelp": "使用 Intel 處理器的 Mac。",
      "req.h": "系統需求與安裝",
      "req.1": "macOS 13.0 或更新版本", "req.2": "Apple 晶片或 Intel Mac（選擇對應的 DMG）",
      "req.how": "不確定是哪一種？打開左上角蘋果選單 › 「關於這台 Mac」：顯示「晶片 Apple M…」為 Apple 晶片，顯示「處理器 Intel…」為 Intel。",
      "req.install": "打開 DMG，把 MachOKnife 拖進「應用程式」後啟動。安裝檔以 Developer ID 簽署並經 Apple 公證，之後透過 Sparkle 自動更新。",
      "req.old": "查看所有歷史版本 →",
      "ft.desc": "macOS 上的 Mach-O 檢視與編輯工具", "ft.more": "更多作品", "ft.vanjay": "VanJay 的更多作品", "ft.src": "專案", "ft.fb": "意見回饋",
      "a.home": "MachOKnife 首頁", "a.nav": "頁面導覽", "a.lang": "語言", "a.theme": "外觀",
      "a.light": "淺色", "a.dark": "深色", "a.system": "跟隨系統", "a.gh": "GitHub 儲存庫",
      "a.tb": "解剖樣本資訊", "a.hex": "十六進位資料", "a.scenes": "回放場景", "a.term": "終端機輸出",
      "alt.icon": "MachOKnife 圖示",
      "alt.main": "MachOKnife 主視窗：左側為結構樹，右側為 Sparkle.framework 的載入命令列表",
      "alt.retag": "Retag 工具視窗", "alt.xcf": "建構 XCFramework 工具視窗", "alt.cont": "二進位污染檢查視窗",
      "js.outside": "超出此處展示的前 {n} 位元組",
      "js.count": "共 {n} 條",
      "js.vmonly": "僅虛擬記憶體，檔案中 0 B",
      "js.more": "另有 {n} 個：{list} …",
      "js.sect": "節標頭"
    },
    "zh-CN": {
      "js.outside": "超出此处展示的前 {n} 字节",
      "js.count": "共 {n} 条",
      "js.vmonly": "仅虚拟内存，文件中 0 B",
      "js.more": "另有 {n} 个：{list} …",
      "js.sect": "节头"
    }
  };

  // 简体文案以页面原文为准，启动时收集
  (function collectChinese() {
    var zh = I18N["zh-CN"];
    $$("[data-i]").forEach(function (el) {
      zh[el.dataset.i] = el.textContent;
    });
    $$("[data-ih]").forEach(function (el) {
      zh[el.dataset.ih] = el.innerHTML;
    });
    $$("[data-ia]").forEach(function (el) {
      zh[el.dataset.ia] = el.getAttribute("aria-label");
    });
    $$("[data-ialt]").forEach(function (el) {
      zh[el.dataset.ialt] = el.getAttribute("alt");
    });
    zh["meta.title"] = document.title;
    zh["meta.desc"] = $('meta[name="description"]').content;
  })();

  var lang = "zh-CN";
  function t(key, vars) {
    var s = (I18N[lang] && I18N[lang][key]) || I18N["zh-CN"][key] || key;
    if (vars) {
      Object.keys(vars).forEach(function (k) {
        s = s.replace("{" + k + "}", vars[k]);
      });
    }
    return s;
  }

  function detectLang() {
    var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
    for (var i = 0; i < list.length; i++) {
      var l = String(list[i]).toLowerCase();
      if (/^zh-(tw|hk|mo|hant)/.test(l)) {
        return "zh-TW";
      }
      if (l.indexOf("zh") === 0) {
        return "zh-CN";
      }
      if (l.indexOf("en") === 0) {
        return "en";
      }
    }
    return "en";
  }

  function normLang(v) {
    if (!v) {
      return null;
    }
    v = String(v).toLowerCase();
    if (v === "en" || v.indexOf("en-") === 0) {
      return "en";
    }
    if (/^zh-(tw|hk|mo|hant)/.test(v) || v === "tw") {
      return "zh-TW";
    }
    if (v.indexOf("zh") === 0 || v === "cn") {
      return "zh-CN";
    }
    return null;
  }

  var langListeners = [];
  function applyLang(next, persist) {
    lang = next;
    doc.lang = next;
    $$("[data-i]").forEach(function (el) {
      el.textContent = t(el.dataset.i);
    });
    $$("[data-ih]").forEach(function (el) {
      el.innerHTML = t(el.dataset.ih);
    });
    $$("[data-ia]").forEach(function (el) {
      el.setAttribute("aria-label", t(el.dataset.ia));
    });
    $$("[data-ialt]").forEach(function (el) {
      el.setAttribute("alt", t(el.dataset.ialt));
    });
    document.title = t("meta.title");
    $('meta[name="description"]').content = t("meta.desc");
    $('meta[property="og:title"]').content = t("meta.title");
    $('meta[property="og:description"]').content = t("meta.desc");
    $$("#lang button").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.lang === next));
    });
    if (persist) {
      try {
        localStorage.setItem("mk.lang", next);
      } catch (e) {}
    }
    langListeners.forEach(function (fn) {
      fn();
    });
  }

  var stored = null;
  try {
    stored = localStorage.getItem("mk.lang");
  } catch (e) {}
  lang = normLang(query.get("lang")) || normLang(stored) || detectLang();
  $("#lang").addEventListener("click", function (e) {
    var b = e.target.closest("button[data-lang]");
    if (b) {
      applyLang(b.dataset.lang, true);
    }
  });

  /* ---------- 主题：浅色 / 深色 / 跟随系统 ---------- */
  var darkMQ = matchMedia("(prefers-color-scheme: dark)");
  function applyTheme(pref, persist) {
    var dark = pref === "dark" || (pref === "system" && darkMQ.matches);
    doc.dataset.theme = dark ? "dark" : "light";
    doc.dataset.themePref = pref;
    $('meta[name="theme-color"]').content = dark ? "#0a1a33" : "#f5f7fa";
    $$("#theme button").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.themeSet === pref));
    });
    if (persist) {
      try {
        localStorage.setItem("mk.theme", pref);
      } catch (e) {}
    }
  }
  applyTheme(doc.dataset.themePref || "system", false);
  $("#theme").addEventListener("click", function (e) {
    var b = e.target.closest("button[data-theme-set]");
    if (b) {
      applyTheme(b.dataset.themeSet, true);
    }
  });
  var onScheme = function () {
    if (doc.dataset.themePref === "system") {
      applyTheme("system", false);
    }
  };
  if (darkMQ.addEventListener) {
    darkMQ.addEventListener("change", onScheme);
  } else if (darkMQ.addListener) {
    darkMQ.addListener(onScheme);
  }

  /* ---------- 下载：识别芯片 + Release API 换直链 ---------- */
  function markIntel() {
    var cta = $("#cta");
    var intel = $(".dl-intel", cta);
    var arm = $(".dl-arm", cta);
    intel.classList.add("primary");
    arm.classList.remove("primary");
    cta.insertBefore(intel, arm);
    $("#card-intel").classList.add("rec");
    $("#card-arm").classList.remove("rec");
    $("#card-intel .btn").classList.add("primary");
    $("#card-arm .btn").classList.remove("primary");
    $("#card-intel").parentNode.insertBefore($("#card-intel"), $("#card-arm"));
  }
  (function detectArch() {
    // Chromium 可直接给出架构；其他浏览器用 WebGL 渲染器名称粗略判断，无法判断时默认 Apple 芯片
    if (navigator.userAgentData && navigator.userAgentData.getHighEntropyValues) {
      navigator.userAgentData.getHighEntropyValues(["architecture"]).then(function (v) {
        if (v.architecture === "x86" && /mac/i.test(navigator.platform || "")) {
          markIntel();
        }
      }).catch(function () {});
      return;
    }
    try {
      var gl = document.createElement("canvas").getContext("webgl");
      var info = gl && gl.getExtension("WEBGL_debug_renderer_info");
      var r = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : "";
      if (/Intel|AMD|Radeon/i.test(r) && !/Apple/i.test(r)) {
        markIntel();
      }
    } catch (e) {}
  })();

  function fmtMB(n) {
    return (n / 1048576).toFixed(1) + " MB";
  }
  fetch("https://api.github.com/repos/wangwanjie/MachOKnife/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
    .then(function (r) {
      return r.ok ? r.json() : null;
    })
    .then(function (rel) {
      if (!rel) {
        return;
      }
      if (rel.tag_name) {
        $$(".ver").forEach(function (el) {
          el.textContent = rel.tag_name;
        });
      }
      (rel.assets || []).forEach(function (a) {
        var kind = /_arm64\.dmg$/i.test(a.name) ? "arm" : /_x86_64\.dmg$/i.test(a.name) ? "intel" : null;
        if (!kind) {
          return;
        }
        $$(".dl-" + kind).forEach(function (el) {
          el.href = a.browser_download_url;
        });
        $$(".dl-name-" + kind).forEach(function (el) {
          el.textContent = a.name;
        });
        $$(".dl-file-" + kind).forEach(function (el) {
          el.textContent = (kind === "arm" ? "arm64" : "x86_64") + " · DMG · " + fmtMB(a.size);
        });
      });
    })
    .catch(function () {});

  /* ---------- 渐入 ---------- */
  if ("IntersectionObserver" in window && !reduceMotion.matches) {
    var rvIO = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          en.target.classList.add("in");
          rvIO.unobserve(en.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px" });
    $$(".rv").forEach(function (el) {
      rvIO.observe(el);
    });
  } else {
    $$(".rv").forEach(function (el) {
      el.classList.add("in");
    });
  }

  /* ---------- 指针十字准线 ---------- */
  (function crosshair() {
    var box = $(".crosshair");
    if (!matchMedia("(pointer: fine)").matches || reduceMotion.matches) {
      return;
    }
    var x = 0, y = 0, raf = 0;
    var cx = $(".ch-x", box), cy = $(".ch-y", box), tag = $(".ch-tag", box);
    function hex4(n) {
      return ("000" + Math.max(0, Math.round(n)).toString(16).toUpperCase()).slice(-4);
    }
    function draw() {
      raf = 0;
      cx.style.transform = "translateY(" + y + "px)";
      cy.style.transform = "translateX(" + x + "px)";
      tag.style.transform = "translate(" + (x + 6) + "px," + (y + 4) + "px)";
      tag.textContent = "X 0x" + hex4(x) + "  Y 0x" + hex4(y + scrollY);
    }
    addEventListener("pointermove", function (e) {
      x = e.clientX;
      y = e.clientY;
      box.classList.add("on");
      if (!raf) {
        raf = requestAnimationFrame(draw);
      }
    }, { passive: true });
    document.addEventListener("pointerleave", function () {
      box.classList.remove("on");
    });
  })();

  /* ---------- 解剖图 ---------- */
  var anatomy = (function () {
    var A = window.MK_ANATOMY;
    if (!A) {
      return null;
    }
    var hex = A.hex;
    var N = hex.length / 2;
    var bytes = new Array(N);
    for (var i = 0; i < N; i++) {
      bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
    }
    var fields = A.fields;
    var byteField = new Array(N);
    fields.forEach(function (f, idx) {
      for (var k = f.o; k < f.o + f.s && k < N; k++) {
        byteField[k] = idx;
      }
    });
    var h2 = function (n, w) {
      var s = n.toString(16).toUpperCase();
      while (s.length < (w || 4)) {
        s = "0" + s;
      }
      return "0x" + s;
    };
    var num = function (n) {
      return Number(n).toLocaleString("en-US");
    };
    var prot = function (p) {
      var v = parseInt(p, 10);
      return (v & 1 ? "r" : "-") + (v & 2 ? "w" : "-") + (v & 4 ? "x" : "-");
    };

    // 每个段的 LC 位置与节头位置
    var segs = A.segs.map(function (s) {
      var lc = A.lcs.filter(function (l) {
        return l.o === s.lco;
      })[0];
      return {
        n: s.n, lco: s.lco, cs: lc ? lc.s : 72, vmaddr: s.vmaddr, vmsize: s.vmsize,
        fileoff: s.fileoff, filesize: s.filesize, prot: s.prot.split("/")[1],
        sects: s.sects.map(function (x, k) {
          return { n: x.n, size: x.size, ho: s.lco + 72 + 80 * k };
        })
      };
    });

    // 十六进制行
    var hexEl = $("#hex");
    var html = [];
    for (var r = 0; r < N; r += 16) {
      var row = '<div class="hrow"><span class="off">' + ("0000" + r.toString(16).toUpperCase()).slice(-4) + '  </span><span class="bytes">';
      var asc = "";
      for (var c = r; c < r + 16 && c < N; c++) {
        var f = fields[byteField[c]];
        var cls = "b g-" + (f ? f.g : "x") + (bytes[c] === 0 ? " z" : "") + (c % 16 === 8 ? " mid" : "");
        row += '<span class="' + cls + '" data-b="' + c + '">' + ("0" + bytes[c].toString(16).toUpperCase()).slice(-2) + "</span>";
        asc += bytes[c] >= 32 && bytes[c] < 127 ? String.fromCharCode(bytes[c]).replace("&", "&amp;").replace("<", "&lt;") : ".";
      }
      row += '</span><span class="asc">' + asc + "</span></div>";
      html.push(row);
    }
    hexEl.innerHTML = html.join("");
    // 列标题与字节列使用同样的结构，保证任何字号下都对齐
    var head = '<div class="hrow"><span class="off">OFFSET</span><span class="bytes">';
    for (var hc = 0; hc < 16; hc++) {
      head += '<span class="b hd' + (hc === 8 ? " mid" : "") + '">' + ("0" + hc.toString(16).toUpperCase()).slice(-2) + "</span>";
    }
    $("#hex-h").innerHTML = head + '</span><span class="asc">ASCII</span></div>';
    var byteEls = $$(".b", hexEl);

    // 解剖项：每项带若干字节区间
    var items = [];
    function addItem(el, ranges, info) {
      el.classList.add("ai");
      el.tabIndex = 0;
      items.push({ el: el, ranges: ranges, info: info });
      el.dataset.ai = String(items.length - 1);
    }

    // 01 文件头
    var hdrGrid = $("#hdr-grid");
    fields.forEach(function (f, idx) {
      if (f.g !== "hdr") {
        return;
      }
      var el = document.createElement("div");
      var short = f.v.replace(/ \(.*\)$/, "").replace(/^CPU_TYPE_/, "");
      el.innerHTML = "<span>" + f.n + "</span><em>" + short + "</em>";
      hdrGrid.appendChild(el);
      addItem(el, [[f.o, f.s]], { field: idx });
    });

    // 02 加载命令：同名命令合并成一个标签
    var chipBox = $("#lc-chips");
    var groups = [];
    A.lcs.forEach(function (l) {
      var g = groups.filter(function (x) {
        return x.n === l.n;
      })[0];
      if (!g) {
        g = { n: l.n, list: [] };
        groups.push(g);
      }
      g.list.push(l);
    });
    groups.forEach(function (g) {
      var el = document.createElement("span");
      el.className = "chip";
      el.innerHTML = g.n.replace(/^LC_/, "") + (g.list.length > 1 ? "<i>×" + g.list.length + "</i>" : "");
      el.title = g.n;
      chipBox.appendChild(el);
      addItem(el, g.list.map(function (l) {
        return [l.o, l.s];
      }), { lc: g });
    });

    // 03 段：按文件内大小画比例条，__PAGEZERO 仅占虚拟内存，画成窄条
    var segmap = $("#segmap");
    var legend = $("#seg-legend");
    var total = A.filesize;
    segs.forEach(function (s) {
      var w = s.filesize === 0 ? 5 : Math.max(1.2, (s.filesize / total) * 95);
      var bar = document.createElement("div");
      bar.style.width = w + "%";
      bar.style.setProperty("--k", "var(--c-seg)");
      bar.innerHTML = w > 12 ? "<span>" + s.n + "</span>" : "";
      bar.title = s.n;
      segmap.appendChild(bar);
      addItem(bar, [[s.lco, s.cs]], { seg: s });
      var lg = document.createElement("div");
      lg.style.setProperty("--k", "var(--c-seg)");
      lg.innerHTML = "<b>" + s.n.replace(/^__/, "") + "</b> " + (s.filesize ? fmtSize(s.filesize) : "VM");
      legend.appendChild(lg);
      addItem(lg, [[s.lco, s.cs]], { seg: s });
    });
    function fmtSize(n) {
      if (n >= 1048576) {
        return (n / 1048576).toFixed(2) + " MB";
      }
      if (n >= 1024) {
        return (n / 1024).toFixed(1) + " KB";
      }
      return n + " B";
    }

    // 04 __TEXT 的节：前 6 个节头完整落在展示的字节内
    var text = segs.filter(function (s) {
      return s.n === "__TEXT";
    })[0];
    var sectBox = $("#sect-list");
    var shown = text.sects.filter(function (x) {
      return x.ho + 80 <= N;
    });
    var maxSz = Math.max.apply(null, text.sects.map(function (x) {
      return x.size;
    }));
    shown.forEach(function (x) {
      var el = document.createElement("div");
      el.style.setProperty("--k", "var(--c-sect)");
      el.innerHTML = "<span>" + x.n + '</span><span class="bar"><i style="--w:' + Math.max(0.02, Math.sqrt(x.size / maxSz)).toFixed(3) + '"></i></span><span class="sz">' + fmtSize(x.size) + "</span>";
      sectBox.appendChild(el);
      addItem(el, [[x.ho, 80]], { sect: x });
    });
    var rest = text.sects.slice(shown.length);
    var more = document.createElement("div");
    more.className = "sect-more";
    sectBox.appendChild(more);
    function renderMore() {
      more.textContent = t("js.more", {
        n: rest.length,
        list: rest.slice(0, 4).map(function (x) {
          return x.n;
        }).join(", ")
      });
    }
    renderMore();
    langListeners.push(renderMore);

    // 检查器
    var ins = { off: $("#insp-off"), name: $("#insp-name"), size: $("#insp-size"), val: $("#insp-val") };
    function ctxName(f) {
      if (f.g === "hdr") {
        return "mach_header_64." + f.n;
      }
      if (f.g === "seg") {
        var s = segs.filter(function (x) {
          return f.o >= x.lco && f.o < x.lco + 72;
        })[0];
        return "segment_command_64(" + (s ? s.n : "?") + ")." + f.n;
      }
      var hit = null;
      segs.forEach(function (s) {
        s.sects.forEach(function (x) {
          if (f.o >= x.ho && f.o < x.ho + 80) {
            hit = x;
          }
        });
      });
      return "section_64(" + (hit ? hit.n : "?") + ")." + f.n;
    }
    function typeOf(s) {
      return s === 4 ? "uint32" : s === 8 ? "uint64" : s === 16 ? "char[16]" : "uint32 × 3";
    }

    var current = null;
    function describe(info) {
      if (info.field !== undefined) {
        var f = fields[info.field];
        return {
          off: h2(f.o) + " (" + f.o + ")",
          name: ctxName(f),
          size: f.s + " B · " + typeOf(f.s),
          val: f.v
        };
      }
      if (info.lc) {
        var first = info.lc.list[0];
        var sum = info.lc.list.reduce(function (a, l) {
          return a + l.s;
        }, 0);
        var out = first.o >= N;
        return {
          off: h2(first.o) + (out ? " · " + t("js.outside", { n: N }) : ""),
          name: info.lc.n,
          size: sum + " B · " + t("js.count", { n: info.lc.list.length }),
          val: info.lc.list.map(function (l) {
            return h2(l.o);
          }).slice(0, 6).join("  ") + (info.lc.list.length > 6 ? " …" : "")
        };
      }
      if (info.seg) {
        var s = info.seg;
        return {
          off: h2(s.lco) + " (LC_SEGMENT_64, " + s.cs + " B)",
          name: s.n,
          size: s.filesize ? num(s.filesize) + " B" : t("js.vmonly"),
          val: "vmaddr " + s.vmaddr + " · vmsize " + s.vmsize + " · fileoff " + num(s.fileoff) + " · " + prot(s.prot)
        };
      }
      var x = info.sect;
      return {
        off: h2(x.ho) + " (" + t("js.sect") + ", 80 B)",
        name: "__TEXT," + x.n,
        size: num(x.size) + " B",
        val: "size " + h2(x.size, 1)
      };
    }

    // 聚焦：高亮字节区间与包含起点偏移的所有解剖项
    var onBytes = [];
    var onItems = [];
    function focus(ranges, info, scroll) {
      onBytes.forEach(function (el) {
        el.classList.remove("on", "s", "e");
      });
      onItems.forEach(function (el) {
        el.classList.remove("on");
      });
      onBytes = [];
      onItems = [];
      var start = ranges[0][0];
      ranges.forEach(function (rg) {
        for (var k = rg[0]; k < rg[0] + rg[1] && k < N; k++) {
          var el = byteEls[k];
          el.classList.add("on");
          if (k === rg[0] || k % 16 === 0) {
            el.classList.add("s");
          }
          if (k === rg[0] + rg[1] - 1 || k % 16 === 15) {
            el.classList.add("e");
          }
          onBytes.push(el);
        }
      });
      items.forEach(function (it) {
        var hit = it.ranges.some(function (rg) {
          return start >= rg[0] && start < rg[0] + rg[1];
        });
        if (hit) {
          it.el.classList.add("on");
          onItems.push(it.el);
        }
      });
      current = info;
      renderInspector();
      if (scroll && start < N) {
        var rowH = byteEls[0].parentNode.parentNode.offsetHeight || 22;
        var row = Math.floor(start / 16);
        var top = row * rowH;
        var view = hexEl.scrollTop;
        if (top < view + rowH || top > view + hexEl.clientHeight - rowH * 3) {
          hexEl.scrollTo({ top: Math.max(0, top - hexEl.clientHeight / 3), behavior: reduceMotion.matches ? "auto" : "smooth" });
        }
      }
    }
    function renderInspector() {
      if (!current) {
        return;
      }
      var d = describe(current);
      ins.off.textContent = d.off;
      ins.name.textContent = d.name;
      ins.size.textContent = d.size;
      ins.val.textContent = d.val;
    }
    langListeners.push(renderInspector);

    function focusField(idx, scroll) {
      var f = fields[idx];
      focus([[f.o, f.s]], { field: idx }, scroll);
    }
    function focusItem(it) {
      focus(it.ranges, it.info, true);
    }

    // 交互：悬停字节 / 悬停解剖项
    var scanIdx = 0;
    hexEl.addEventListener("pointerover", function (e) {
      var b = e.target.closest(".b");
      if (b) {
        var idx = byteField[+b.dataset.b];
        if (idx !== undefined) {
          scanIdx = idx;
          focusField(idx, false);
        }
      }
    });
    var layersEl = $("#layers");
    function fromItemEvent(e) {
      var el = e.target.closest(".ai");
      if (el) {
        focusItem(items[+el.dataset.ai]);
      }
    }
    layersEl.addEventListener("pointerover", fromItemEvent);
    layersEl.addEventListener("focusin", fromItemEvent);
    layersEl.addEventListener("click", fromItemEvent);

    // 自动扫描：空闲时逐个字段推进；悬停、离开视口或页面隐藏时暂停
    var plate = $("#plate");
    var visible = false, hovering = false, timer = 0, resumeAt = 0;
    function tick() {
      timer = 0;
      if (!visible || hovering || document.hidden || reduceMotion.matches) {
        return;
      }
      if (Date.now() >= resumeAt) {
        scanIdx = (scanIdx + 1) % fields.length;
        focusField(scanIdx, true);
      }
      timer = setTimeout(tick, 1300);
    }
    function kick() {
      if (!timer) {
        timer = setTimeout(tick, 1300);
      }
    }
    plate.addEventListener("pointerenter", function (e) {
      if (e.pointerType === "mouse") {
        hovering = true;
      }
    });
    plate.addEventListener("pointerleave", function () {
      hovering = false;
      resumeAt = Date.now() + 2500;
      kick();
    });
    // 触屏：一次点按后暂停扫描一会儿
    plate.addEventListener("pointerdown", function () {
      resumeAt = Date.now() + 6000;
    });
    hexEl.addEventListener("scroll", function () {
      if (!hovering) {
        return;
      }
      resumeAt = Date.now() + 2500;
    }, { passive: true });
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) {
        kick();
      }
    });
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (en) {
        visible = en[0].isIntersecting;
        if (visible) {
          kick();
        }
      }, { threshold: 0.15 }).observe(plate);
    } else {
      visible = true;
      kick();
    }

    focusField(0, false);
    // 逐层展开
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        $("#anat").classList.remove("anat-pending");
      });
    });
    return true;
  })();
  if (!anatomy) {
    $("#anat").classList.remove("anat-pending");
  }

  /* ---------- 终端回放 ---------- */
  (function terminal() {
    var scenes = window.MK_CLI_SCENES;
    var body = $("#term-body");
    if (!scenes || !body) {
      return;
    }
    var tabs = $$("#term-tabs button");
    var PROMPT = '<span class="pr"><b>demo</b> %</span> ';
    var esc = function (s) {
      return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    };
    // 输出着色：✗/错误标红，✓/OK 标绿，键名弱化，JSON 字符串上色
    function paint(line) {
      var s = esc(line);
      if (/^✗|^error|FAILED/.test(line)) {
        return '<span class="bad">' + s + "</span>";
      }
      if (/^✓|^Validation: OK/.test(line)) {
        return '<span class="ok">' + s + "</span>";
      }
      if (/^\s*"/.test(line)) {
        return s.replace(/^(\s*)("[^"]+")( : )/, '$1<span class="k">$2</span>$3').replace(/(: )("[^"]*")/, '$1<span class="str">$2</span>');
      }
      if (/^-+$/.test(line)) {
        return '<span class="dim2">' + s + "</span>";
      }
      var m = /^(\s*)([A-Za-z0-9 \-]+:)(\s.*)?$/.exec(line);
      if (m) {
        return m[1] + '<span class="k">' + esc(m[2]) + "</span>" + esc(m[3] || "");
      }
      return s;
    }

    var token = 0, active = 0, visible = false, started = false;
    function sleep(ms, my) {
      return new Promise(function (res, rej) {
        setTimeout(function check() {
          if (my !== token) {
            rej("cancel");
            return;
          }
          if (!visible || document.hidden) {
            setTimeout(check, 250);
            return;
          }
          res();
        }, ms);
      });
    }
    function setTab(i, p) {
      tabs.forEach(function (b, k) {
        b.setAttribute("aria-selected", String(k === i));
        b.tabIndex = k === i ? 0 : -1;
        if (k === i) {
          b.style.setProperty("--p", p);
        }
      });
    }
    function toBottom() {
      body.scrollTop = body.scrollHeight;
    }
    function renderInstant(i) {
      var out = "";
      scenes[i].steps.forEach(function (st) {
        out += PROMPT + esc(st.c) + "\n" + st.o.split("\n").map(paint).join("\n") + "\n";
      });
      body.innerHTML = out + PROMPT + '<span class="caret"></span>';
      setTab(i, 1);
      toBottom();
    }
    async function play(i) {
      var my = ++token;
      active = i;
      setTab(i, 0);
      if (reduceMotion.matches) {
        renderInstant(i);
        return;
      }
      body.innerHTML = "";
      var steps = scenes[i].steps;
      try {
        for (var s = 0; s < steps.length; s++) {
          var st = steps[s];
          var line = document.createElement("div");
          line.innerHTML = PROMPT;
          var typed = document.createElement("span");
          var caret = document.createElement("span");
          caret.className = "caret";
          line.appendChild(typed);
          line.appendChild(caret);
          body.appendChild(line);
          toBottom();
          await sleep(500, my);
          for (var c = 0; c < st.c.length; c++) {
            typed.textContent += st.c[c];
            await sleep(18 + Math.random() * 38, my);
          }
          await sleep(320, my);
          caret.remove();
          var outLines = st.o.split("\n");
          for (var k = 0; k < outLines.length; k++) {
            var o = document.createElement("div");
            o.innerHTML = paint(outLines[k]) || " ";
            body.appendChild(o);
            if (k % 2 === 1 || outLines.length < 12) {
              toBottom();
              await sleep(outLines.length > 20 ? 14 : 34, my);
            }
          }
          toBottom();
          setTab(i, (s + 1) / steps.length);
          await sleep(700, my);
        }
        var end = document.createElement("div");
        end.innerHTML = PROMPT + '<span class="caret"></span>';
        body.appendChild(end);
        toBottom();
        await sleep(4200, my);
        play((i + 1) % scenes.length);
      } catch (e) {
        // 场景被切换或重播，丢弃当前回放
      }
    }
    tabs.forEach(function (b, k) {
      b.addEventListener("click", function () {
        started = true;
        play(k);
      });
      b.addEventListener("keydown", function (e) {
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
          var n = (k + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length;
          tabs[n].focus();
          play(n);
        }
      });
    });
    $("#term-replay").addEventListener("click", function () {
      started = true;
      play(active);
    });
    renderInstant(0);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (en) {
        visible = en[0].isIntersecting;
        if (visible && !started) {
          started = true;
          play(0);
        }
      }, { threshold: 0.3 }).observe($("#term"));
    } else {
      visible = true;
    }
  })();

  $("#year").textContent = String(new Date().getFullYear());
  applyLang(lang, false);
})();
