import Foundation

/// Lexical rules for one language family — enough for diff highlighting, not a full grammar.
struct SyntaxLanguage: Sendable {
    var keywords: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (start: String, end: String)?
    var stringDelimiters: Set<Character> = ["\"", "'"]
    /// Treat `Capitalized` identifiers as types.
    var capitalizedAreTypes = true

    static let plain = SyntaxLanguage(stringDelimiters: [], capitalizedAreTypes: false)

    /// Picks rules from the file extension / name; returns nil for unknown files.
    static func forPath(_ path: String) -> SyntaxLanguage? {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name == "dockerfile" || name == "makefile" || name.hasPrefix(".") && name.hasSuffix("rc") { return shell }
        switch (name as NSString).pathExtension {
        case "swift": return swift
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "vue", "svelte": return javascript
        case "py", "pyi": return python
        case "go": return go
        case "rs": return rust
        case "java", "kt", "kts", "scala", "groovy", "gradle", "dart", "cs": return jvm
        case "c", "h", "cc", "cpp", "hpp", "m", "mm": return cFamily
        case "rb": return ruby
        case "php": return php
        case "sh", "bash", "zsh", "fish", "env", "toml", "ini", "conf": return shell
        case "yml", "yaml": return yaml
        case "sql": return sql
        case "json", "jsonc": return json
        case "css", "scss", "less": return css
        case "html", "htm", "xml", "plist", "svg", "xib", "storyboard": return markup
        default: return nil
        }
    }

    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
    private static let cStyle: (start: String, end: String) = ("/*", "*/")

    static let swift = SyntaxLanguage(
        keywords: words("import let var func class struct enum protocol extension actor init deinit return if else guard switch case default for in while repeat break continue defer do try catch throw throws rethrows async await some any where self Self super nil true false static private fileprivate internal public open final override mutating nonisolated inout is as typealias associatedtype weak unowned lazy get set willSet didSet subscript operator"),
        lineComments: ["//"], blockComment: cStyle, stringDelimiters: ["\""])
    static let javascript = SyntaxLanguage(
        keywords: words("import export from default const let var function class extends return if else switch case for of in while do break continue try catch finally throw new delete typeof instanceof void async await yield this super null undefined true false interface type enum implements public private protected readonly static as keyof declare namespace"),
        lineComments: ["//"], blockComment: cStyle, stringDelimiters: ["\"", "'", "`"])
    static let python = SyntaxLanguage(
        keywords: words("import from as def class return if elif else for while in not and or is try except finally raise with lambda yield async await pass break continue global nonlocal None True False self del assert match case"),
        lineComments: ["#"])
    static let go = SyntaxLanguage(
        keywords: words("package import func return if else for range switch case default break continue go defer select chan map struct interface type var const nil true false fallthrough goto"),
        lineComments: ["//"], blockComment: cStyle, stringDelimiters: ["\"", "'", "`"])
    static let rust = SyntaxLanguage(
        keywords: words("use mod fn let mut const static struct enum trait impl pub crate self Self super return if else match for in while loop break continue as ref move async await dyn where type unsafe extern true false Some None Ok Err"),
        lineComments: ["//"], blockComment: cStyle, stringDelimiters: ["\""])
    static let jvm = SyntaxLanguage(
        keywords: words("package import class interface enum object record extends implements public private protected internal static final abstract override open data sealed val var fun void return if else when switch case default for while do break continue try catch finally throw throws new this super null true false is as in out suspend lateinit companion using namespace"),
        lineComments: ["//"], blockComment: cStyle)
    static let cFamily = SyntaxLanguage(
        keywords: words("include define ifdef ifndef endif pragma import int char float double long short unsigned signed void bool auto const static extern struct union enum typedef return if else switch case default for while do break continue goto sizeof class public private protected virtual template typename namespace using new delete nullptr NULL true false self nil YES NO @interface @implementation @end @property"),
        lineComments: ["//"], blockComment: cStyle)
    static let ruby = SyntaxLanguage(
        keywords: words("def end class module require include return if elsif else unless case when while until for in do begin rescue ensure raise yield self nil true false and or not then attr_accessor attr_reader"),
        lineComments: ["#"])
    static let php = SyntaxLanguage(
        keywords: words("function class public private protected static return if else elseif foreach for while switch case default break continue new use namespace echo null true false array fn match try catch throw"),
        lineComments: ["//", "#"], blockComment: cStyle)
    static let shell = SyntaxLanguage(
        keywords: words("if then else elif fi for in do done while case esac function return export local echo exit source set unset readonly FROM RUN COPY ADD CMD ENTRYPOINT ENV ARG WORKDIR EXPOSE"),
        lineComments: ["#"], capitalizedAreTypes: false)
    static let yaml = SyntaxLanguage(keywords: words("true false null yes no on off"), lineComments: ["#"], capitalizedAreTypes: false)
    static let sql = SyntaxLanguage(
        keywords: words("select from where insert into update delete set values create alter drop table index view join left right inner outer on and or not null is as group by order having limit offset distinct primary key foreign references default union all case when then else end begin commit SELECT FROM WHERE INSERT INTO UPDATE DELETE SET VALUES CREATE ALTER DROP TABLE INDEX VIEW JOIN LEFT RIGHT INNER OUTER ON AND OR NOT NULL IS AS GROUP BY ORDER HAVING LIMIT OFFSET DISTINCT PRIMARY KEY FOREIGN REFERENCES DEFAULT UNION ALL CASE WHEN THEN ELSE END"),
        lineComments: ["--"], blockComment: cStyle, capitalizedAreTypes: false)
    static let json = SyntaxLanguage(keywords: words("true false null"), stringDelimiters: ["\""], capitalizedAreTypes: false)
    static let css = SyntaxLanguage(keywords: words("important media import from to"), blockComment: cStyle, capitalizedAreTypes: false)
    static let markup = SyntaxLanguage(blockComment: ("<!--", "-->"), stringDelimiters: ["\""], capitalizedAreTypes: false)
}
