# 设计方案：阅读记忆（Reading Memory）

状态：待批准 · 目标版本：0.6.0 · 作者：lima

## 1. 要做什么

现在 WhyText 每次查询用完即弃：`HistoryStore` 只是 50 条的结果缓存，注释里写明它“不是用户要求保留的数据”。阅读记忆要把每次查询**沉淀**下来，并让它**反过来改善下一次结果**：

1. **记录**：每次成功的翻译/解释都写入本地日志，带上出处（App、窗口标题、文件或网址）和原句。
2. **重复提示**：同一个短词第 N 次查时，面板提示“第 N 次查”。
3. **术语表**：用户把一个词“记住”后，以后翻译到含这个词的文本时，按用户认可的译法翻。
4. **导出**：一键导出成纯 Markdown 文件夹，卸载 App 后仍然可读。

硬约束：**快捷键 → 首字出现这条主路径不能变慢**。所有记录和导出都在主路径之外完成，可以整体关闭。

## 2. 不做什么（第一版）

- **不把上下文发给服务商。** 原句只存本地、只进导出文件。是否把它拼进翻译 prompt，是一次隐私承诺的变更，单独立项（见 §10）。
- 不做间隔复习、每周回顾、Anki 导出。
- 不自动把词加入术语表。只有用户点了“记住”才算。重复次数只是提示，不会自动入表。
- 不做导出文件夹的自动同步，也不读回导出文件。导出是单向快照。
- 追问（follow-up）不进记录。
- 解释模式不注入术语表。

## 3. 方案与取舍

**选定：新增独立的 `ReadingMemoryStore`（追加写 JSONL）+ 小的 `glossary.json`。`HistoryStore` 保持缓存职责不变。**

放弃的方案：把 `HistoryStore` 扩容成无上限。理由有三：
- 它的去重键包含 template、model、maxInputCharacters 等缓存维度，同一个词换个模型就会变成另一条，不能用来数“第几次查”。
- 它每次整文件重写 JSON，数据一大就会变成主线程上的成本。
- 关闭“保存历史”会清空它，而阅读记忆需要独立的生命周期。

数据量估算：每天 20 次查询、每条约 1.5 KB，一年约 11 MB 的 JSONL。追加写是 O(1)，启动时一次性读入内存，在这个量级都没问题。

## 4. 数据模型

纯模型和纯函数放在 `WhyTextCore`，这样能被现有的 smoke tests 覆盖；需要读写文件或依赖 AppKit 的部分放在 `WhyText`。

```swift
// Sources/WhyTextCore/ReadingMemory.swift

public enum LookupInput: String, Codable { case selection, bubble, manual, screenshot }

public struct LookupSource: Codable, Equatable {
    public var appName: String?          // NSRunningApplication.localizedName
    public var bundleID: String?
    public var windowTitle: String?      // AXFocusedWindow → AXTitle
    public var documentURL: String?      // AXWebArea 的 AXURL，或窗口的 AXDocument（file://）
    public var sentence: String?         // 选中文字所在的整句，最长 400 字符
}

public struct LookupRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var action: String            // "translate" | "explain"（PanelAction.rawValue）
    public var input: LookupInput
    public var sourceText: String
    public var resultText: String
    public var targetLanguage: String?   // TranslationLanguage.rawValue；解释为 nil
    public var source: LookupSource
    /// 短词的归一化形式，用于计数和导出时分组；长段落为 nil。
    public var termKey: String?
}

public struct GlossaryEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var term: String              // 原文写法，例如 "moat"
    public var rendering: String         // 用户认可的译法，例如 "护城河"
    public var targetLanguage: String    // 这条译法对应的目标语言
    public var note: String?
    public var createdAt: Date
}

public enum TermKey {
    /// 超过 40 个字符，或多于 4 个拉丁词，就当作段落，返回 nil。
    /// 其余情况：trim → 合并空白 → lowercased → 去掉首尾标点。
    public static func make(_ text: String) -> String?
}
```

**存储位置**：与 `HistoryStore` 同一个目录。`HistoryStore.defaultFileURL()` 现在是 `private`，需要把其中拼出“Application Support/<bundle ID>”目录的逻辑提成一个 internal 静态函数，供两个 store 共用。

```
~/Library/Application Support/<bundle ID>/memory/
  lookups.jsonl     每行一个 LookupRecord（JSONEncoder，dateEncodingStrategy = .iso8601）
  glossary.json     [GlossaryEntry]，整文件原子写（条目少）
```

两个文件都用 `.completeFileProtection` 写入，与现有 history 一致。JSONL 读取时逐行解码，**跳过坏行**而不是整体失败，这样意外崩溃导致的半行只会丢掉那一条。

**`ReadingMemoryStore`**（`Sources/WhyText/Stores/ReadingMemoryStore.swift`，只在主线程使用，与 `HistoryStore` 一致）：

```swift
final class ReadingMemoryStore: ObservableObject {
    @Published private(set) var glossary: [GlossaryEntry]
    private(set) var records: [LookupRecord]          // 启动时读入
    private var termCounts: [String: Int]             // termKey → 次数

    func append(_ record: LookupRecord)               // 更新内存，写文件放到串行后台队列
    func count(for termKey: String) -> Int
    func glossaryEntry(term: String, target: String) -> GlossaryEntry?
    func upsertGlossary(_ entry: GlossaryEntry)
    func removeGlossary(id: UUID)
    func clearAll()                                    // 删除 lookups.jsonl 和 glossary.json
}
```

写文件放在 `DispatchQueue(label: "whytext.memory", qos: .utility)` 上，用 `FileHandle` 追加，主线程不做任何 IO。

## 5. 上下文怎么采集

### 5.1 出处（所有输入方式都有）

在 `SelectionReader.readSelectedText` 读取成功的同一时刻采集，因为面板弹出后前台 App 可能会变：

- `appName` / `bundleID`：`NSWorkspace.shared.frontmostApplication`。
- `windowTitle`：`AXFocusedApplication` → `AXFocusedWindow` → `kAXTitleAttribute`。
- `documentURL`：先从找到选区的元素沿 `kAXParentAttribute` 向上最多 12 层，找 role 为 `AXWebArea` 的元素读 `"AXURL"`（Safari 和 Chromium 都提供）；找不到时读焦点窗口的 `kAXDocumentAttribute`（Preview、TextEdit、Pages 等文档类 App）。只保留 `http`、`https`、`file` 三种 scheme。

气泡路径（`openPanelFromSelectionBubble`）用的是 `SelectionAutoPopupCoordinator.pendingText`，没有经过 `SelectionReader`。因此在 coordinator 记录 `pendingText` 的同一时刻，调用同一个 `captureSource()`，存成 `pendingSource`。

手动输入和截图 OCR 只记 `appName`（截图前的前台 App），其余字段为 nil。

### 5.2 原句（尽力而为）

`AccessibilitySelectionService` 的 `selectedText(for: selectedRangeValue, in:)` 这条路径同时拿得到元素的完整 `kAXValueAttribute` 字符串和 `CFRange`，这是唯一能可靠截出原句的地方。改动如下：

- `SelectedTextResult` 增加 `sentence: String?`。
- 走 range 路径时，调用新的纯函数：

```swift
// Sources/WhyTextCore/SentenceContext.swift
public enum SentenceContext {
    /// 用 NSString.enumerateSubstrings(options: .bySentences) 找出覆盖选区的句子，
    /// 跨多句时合并；结果超过 maxLength 时以选区为中心截断，两端加“…”。
    /// 选区本身已经是整句或更长时返回 nil（没有额外信息）。
    public static func extract(fullText: String, selectionUTF16: NSRange, maxLength: Int = 400) -> String?
}
```

- `kAXSelectedTextAttribute` 直接命中，以及 marker range（WebKit）这两条路径，在第一版里 `sentence` 为 nil。
- 剪贴板兜底路径也为 nil。

`SelectionReader.Result` 增加 `source: LookupSource`，并透传 `sentence`。

**最脆弱的假设：** 方案假设原生文本控件（TextEdit、Notes、Xcode、Pages、大多数 AppKit App）会走 range 路径。如果不成立，比如浏览器和 Electron 大多走 marker 或直接命中，那么从网页上查的词就**只有标题和网址、没有原句**。设计已经按这个情况变形：原句是可选字段，导出格式和计数都不依赖它。第一版会在“选区诊断”报告里加一行 `sentenceCaptured: true/false`，并在 `docs/manual-checklist.md` 里按 App 记录采集情况，作为下一版是否补 marker 路径的依据。

## 6. 术语表怎么喂给 prompt

### 6.1 入表

- 结果面板标题栏在 pin 和复制按钮旁加一个 `star` / `star.fill` 按钮。只有在 **翻译模式 + `TermKey.make(sourceText) != nil` + 结果已完成** 时才显示。
- 点击后写入 `GlossaryEntry(term: sourceText（trim 后）, rendering: resultText 的第一行（trim 后，最多 60 字符）, targetLanguage: 当前目标语言)`。再点一次就删除。
- 译法可以在设置的“阅读记忆”页里修改。第一版不在面板里提供编辑。

### 6.2 匹配

```swift
// Sources/WhyTextCore/GlossaryMatcher.swift
public enum GlossaryMatcher {
    /// 返回出现在 text 中、目标语言一致的条目，按 term 长度降序，最多 limit 条。
    /// 拉丁词：大小写不敏感 + 词边界（\b，用 NSRegularExpression.escapedPattern）。
    /// CJK 等无空格文字：大小写不敏感的子串匹配。
    /// 长词优先，避免 "machine learning" 和 "learning" 同时命中时短词抢先。
    public static func matches(in text: String, entries: [GlossaryEntry],
                               targetLanguage: String, limit: Int = 20) -> [GlossaryEntry]

    /// 空数组返回 nil；否则返回注入 prompt 的固定文案。
    public static func hint(for entries: [GlossaryEntry]) -> String?
}
```

注入文案（中文写死，与现有 `structureHint` 的风格一致）：

```
下列术语按给定译法翻译，不要改用别的说法：
- moat → 护城河
- context window → 上下文窗口
```

### 6.3 注入位置

- `UnifiedTranslationRequest` 增加 `var glossaryHint: String? = nil`。`renderedPrompt` 在 `structureHint` 之后、正文 prompt 之前拼接，格式为 `"\(structureHint)\n\n\(glossaryHint)\n\n\(prompt)"`。
- 用户的自定义模板**不需要**新占位符，现有模板照常生效。新增配置项：0 个。
- 分块翻译时，`PromptRunner.run` 按**每个 chunk** 单独匹配，再生成各自的 hint，避免把整篇的术语塞进每一块。为此 `PromptRunner.run` 改为接收 `glossary: [GlossaryEntry]`，而不是一个现成的字符串。
- 追问（`runFollowUp`）和解释模式传空数组。
- `transcriptPrompt` 也要带上整篇匹配出的 hint，这样追问时模型能看到当初的约束。

### 6.4 缓存键

`HistoryCacheKey` 必须包含术语约束，否则改了术语表以后，命中缓存会拿到旧译法：

```swift
var glossaryHint: String?   // 可选：旧的 recent-results.json 解码为 nil，不会解码失败
```

`AppModel.run` 在构造 key 之前，先对整段 `selectedText` 跑一次 `GlossaryMatcher`，把结果拼成字符串放进 key。

## 7. 重复提示

`AppModel.run` 成功（包括命中缓存）后：

1. 用 `TermKey.make(sourceText)` 算出 `termKey`，追加 `LookupRecord`。
2. 如果 `termKey != nil` 且 `count(for:) >= 2`，设置 `panelState.noticeMessage = L10n.f("第 %@ 次查这个词", n)`。复用现有的 notice 行，不新增 UI。

计数包含翻译和解释两种动作。

## 8. Markdown 导出格式

触发方式：设置的“阅读记忆”页 → “导出到文件夹…” → `NSOpenPanel` 选一个父目录。在里面创建或覆盖 `WhyText 阅读记忆/` 文件夹，导出完成后在 Finder 中显示。

```
WhyText 阅读记忆/
  .whytext-export          标记文件；只有存在它时才允许覆盖这个文件夹
  README.md                说明这是什么、导出时间、记录总数
  术语表.md
  词条/
    moat.md
    context window.md
  日志/
    2026-10.md
    2026-11.md
```

**覆盖规则：** 如果目标文件夹已存在、但没有 `.whytext-export` 标记，就放弃导出并提示用户，绝不覆盖用户自己的文件。如果有标记，就先写到同级临时目录 `.WhyText 阅读记忆.tmp`，成功后再用 `FileManager.replaceItemAt` 整体替换，保证不会导出一半。

**文件名：** 把 `/ : \ ? * " < > |` 和换行替换成空格，再合并连续空格，截断到 80 字符。如果大小写不敏感地重名，就依次追加 ` (2)`、` (3)`。

**`术语表.md`：**

```markdown
# 术语表

| 原文 | 译法 | 目标语言 | 备注 |
| --- | --- | --- | --- |
| moat | 护城河 | 简体中文 | |
```

表格单元格里的 `|` 转义成 `\|`，换行替换为空格。

**`词条/<term>.md`**：每个 `termKey` 一个文件，按最近一次的时间倒序。

```markdown
---
term: moat
count: 3
first_seen: 2026-10-02
last_seen: 2026-10-23
in_glossary: true
---

# moat

## 2026-10-23 · Safari
**来源**：Make Something Heavy — https://www.workingtheorys.com/p/make-something-heavy
> AI making things easier to create and easier to disrupt, so it largely wipes out **moats** and the middle of any given category.

护城河

## 2026-10-02 · Preview
**来源**：Zero to One.pdf
> …

护城河（竞争壁垒）
```

规则：
- 原句里第一次出现的选中文字（大小写不敏感）用 `**…**` 加粗；没有原句就省略引用行。
- “来源”行优先写 `windowTitle — documentURL`。`file://` 只写文件名。两者都没有就省略这一行。
- 结果原样写入（模型输出本来就是 Markdown）。

**`日志/YYYY-MM.md`**：按月存放所有记录，包括长段落，时间正序。

```markdown
# 2026-10

### 10-23 14:02 · 翻译 · Safari
**来源**：Make Something Heavy — https://…

> 原文（长段落完整保留，每行前加 "> "）

译文…

---
```

所有渲染都是纯函数 `MemoryMarkdownExporter.render(records:glossary:) -> [String: String]`（相对路径 → 内容），放在 `WhyTextCore`，可以被测试；`WhyText` 里只负责写盘。日期按本地时区格式化，时区作为参数传入，保证测试结果稳定。

## 9. 设置与开关

新增设置页 `.memory`（“阅读记忆”），放在 sidebar 里 `prompts` 之后：

| 控件 | 行为 |
| --- | --- |
| 记录阅读记忆（开关，默认开） | `SettingsStore.saveReadingMemory`。关闭后不再写入，已有数据保留。 |
| 术语表列表 | 每行显示 term / rendering（可编辑的 TextField）/ 删除按钮。为空时显示一行说明。 |
| 导出到文件夹… | §8 |
| 清空阅读记忆… | 二次确认后调用 `clearAll()`。 |

它和现有的“保存历史”开关互相独立：一个管缓存，一个管积累。

新增设置项：1 个（`saveReadingMemory`）。新增命令、环境变量、服务：0 个。

## 10. 第一版范围与分期

三个阶段，每个阶段都能单独合并和发布；后一个阶段不落地，前一个阶段也完整可用。

| 阶段 | 内容 | 合并后用户得到什么 |
| --- | --- | --- |
| **A. 记录 + 导出 + 重复提示** | §4 模型和存储；§5.1 出处采集；§7；§8 导出；§9 设置页（不含术语表列表）。 | 查过的东西能留下来，能导出，能看到“第 N 次”。 |
| **B. 原句采集** | §5.2；诊断报告加 `sentenceCaptured`；导出的引用行开始有内容。 | 笔记带上下文。 |
| **C. 术语表** | §6 全部；设置页加术语表列表；导出 `术语表.md` 和 `in_glossary`。 | 翻译越用越贴合自己。 |

**阶段 A 实施时与上文的差异**（已落地，后续阶段以此为准）：

- `LookupRecord` 多了 `sessionID`，每打开一次面板生成一个。“第 N 次”和导出里的 `count` 按会话去重，所以在同一个面板里切换翻译/解释、或者改目标语言，不会抬高次数。
- 导出的标签、文件夹名（`WhyText 阅读记忆`、`词条`、`日志`）跟随界面语言，不再固定用中文。
- `documentURL` 是从前台 App 当前的焦点元素向上找 `AXWebArea`，而不是从找到选区的那个元素开始。两者在实际中基本是同一个，这样改不用动选区搜索的代码。
- 设置页的说明文案、导出前的文件夹选择提示，用的都是新加的本地化文案。

**0.6.0 = A + B + C。** 下一版候选（不在本方案内）：把原句发给服务商（需要更新 README 隐私表并加开关）、补 marker 路径的原句采集、复习。

## 11. 改动的文件

超过 8 个文件，这里明确列出。没有新服务，也没有新依赖。

新增（6 个）：
- `Sources/WhyTextCore/ReadingMemory.swift`：模型、`TermKey`
- `Sources/WhyTextCore/SentenceContext.swift`
- `Sources/WhyTextCore/GlossaryMatcher.swift`
- `Sources/WhyTextCore/MemoryMarkdownExporter.swift`
- `Sources/WhyText/Stores/ReadingMemoryStore.swift`
- `Sources/WhyText/UI/MemorySettingsView.swift`

修改：
- `Services/AccessibilitySelectionService.swift`：`sentence`、`captureSource()`、诊断行
- `Services/SelectionReader.swift`：`Result.source`
- `Services/SelectionAutoPopupCoordinator.swift`：`pendingSource`
- `Services/LLMClient.swift`：`UnifiedTranslationRequest.glossaryHint`
- `Services/PromptRunner.swift`、`Services/TranslationSession.swift`：透传 glossary
- `Stores/HistoryStore.swift`：`HistoryCacheKey.glossaryHint`
- `Stores/SettingsStore.swift`：`saveReadingMemory`
- `AppModel.swift`：记录、计数提示、star 切换、导出入口
- `UI/SettingsView.swift`：新页面；`UI/FloatingPanelView.swift`：star 按钮
- `WhyTextCore/Localization/L10n+*.swift`：5 个语言的新文案
- `WhyTextCoreSmokeTests/main.swift`
- `README.md`、`README.zh-CN.md`（功能和隐私表加一行：阅读记忆存在本地 `memory/` 目录，术语会随翻译请求发给服务商）、`docs/manual-checklist.md`

## 12. 数据流

```
 hotkey / bubble / manual / OCR
          │
          ▼
 SelectionReader ──(text, source{app,title,url,sentence})──► AppModel.run
                                                              │
                     ReadingMemoryStore.glossary ──► GlossaryMatcher ──► HistoryCacheKey
                                                              │
                                                    TranslationSession → PromptRunner
                                                    (每个 chunk 一个 glossaryHint)
                                                              │
                                                     onFinished(.success)
                                                              │
                                ┌─────────────────────────────┼──────────────────┐
                                ▼                             ▼                  ▼
                       HistoryStore.record        ReadingMemoryStore.append   notice "第 N 次"
                                                              │
                                                  （设置页）MemoryMarkdownExporter → 文件夹
```

数据单向流动，没有环。术语表只在请求开始时读取一次，请求进行中改动它不影响当前这次请求。

## 13. 验证

### 自动（`WhyTextCoreSmokeTests`，CI 已在跑）

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift build --cache-path /tmp/swiftpm-cache
```

```bash
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift run WhyTextCoreSmokeTests --cache-path /tmp/swiftpm-cache
```

新增用例：
- `TermKey`：`"  Moat. "` → `"moat"`；41 个字符 → nil；5 个英文词 → nil；`"护城河"` → `"护城河"`。
- `SentenceContext`：选区位于中间句 → 返回该句；选区跨两句 → 合并；选区等于整句 → nil；超长句 → 以选区为中心截断、两端带 `…`；含 emoji 时 UTF-16 偏移仍然正确。
- `GlossaryMatcher`：`"learning"` 不命中 `"learnings"`；大小写不敏感；`"machine learning"` 排在 `"learning"` 前面；目标语言不一致时不命中；超过 limit 截断；CJK 子串命中；term 含正则特殊字符（`C++`）不崩溃。
- `renderedPrompt`：有 hint 时顺序为 structureHint → glossaryHint → prompt；hint 为 nil 时输出与现在逐字节一致（回归保护）。
- `HistoryCacheKey`：用旧格式 JSON 解码成功，`glossaryHint == nil`。
- `MemoryMarkdownExporter`：固定时区下的快照断言，包括文件名清理、重名加后缀、`|` 转义、无原句时省略引用、`file://` 只显示文件名。
- JSONL 坏行：三行里中间一行损坏 → 读出 2 条（`ReadingMemoryStore` 的解码函数放到 Core 里测试）。

### 手动（写进 `docs/manual-checklist.md`）

1. TextEdit 里选中一个词并翻译 → 导出 → `词条/<词>.md` 有原句并且加粗。
2. Safari 里选中一个词 → 导出 → 有标题和网址；记录 `sentenceCaptured` 的实际值。
3. 同一个词查第 2 次 → 面板显示“第 2 次查这个词”。
4. 点 star → 在一句包含该词的长句里翻译 → 译文使用了术语表里的译法；再点一次 star 取消 → 重新翻译不再命中缓存（缓存键变了）。
5. 在设置里修改译法 → 再翻译同一句 → 得到新译法。
6. 导出到一个已存在、但没有标记的同名文件夹 → 拒绝导出，原文件不动。
7. 关闭“记录阅读记忆” → 查询后 `lookups.jsonl` 行数不变。
8. 清空 → `memory/` 下的两个文件都被删除。
9. 主路径耗时：开启和关闭阅读记忆，各在同一个词上按 10 次快捷键，首字出现时间无可感知差异（选区读取多了一次 AX 查询，预算不超过 20 ms）。

## 14. 回滚

- 每个阶段都是独立的提交组，可以直接 revert。
- 数据只新增 `memory/` 目录，回滚后旧版本会忽略它。旧版本解码新的 `recent-results.json` 时，合成的 `Codable` 会忽略多出的 `glossaryHint` 键，不会失败。所以回滚不需要迁移任何数据。
- 不涉及任何外部账号、密钥或服务。

## 15. 关键决策汇总

1. **独立存储，追加写 JSONL**：记录和缓存的生命周期、去重语义都不同；追加写在一年 10 MB 的量级下仍是 O(1)。
2. **上下文第一版只存本地**：不改变“只发送选中文字”的隐私承诺，同时避开了要用户来裁决的问题。
3. **术语表靠用户显式“记住”入表，自动注入、零新占位符**：避免自动入表带来的污染；现有自定义模板无需改动。
4. **按 chunk 匹配术语、把术语写进缓存键**：保证长文翻译的 prompt 不膨胀，也保证改了术语后不会拿到旧结果。
5. **导出是带标记文件的单向快照**：格式比 App 活得久，又绝不覆盖用户自己的文件。

## 16. 延后事项

| 事项 | 为什么延后 | 由谁决定 |
| --- | --- | --- |
| 把原句发给服务商 | 改变隐私承诺，需要 README 和开关同步调整；先用阶段 B 的采集率数据判断值不值得。 | lima，看 0.6.0 的手动检查结果 |
| marker 路径（WebKit/Chromium）采集原句 | 需要逐个 App 实测 AX 属性，没有数据前无法设计。 | 根据阶段 B 诊断数据另行立项 |
