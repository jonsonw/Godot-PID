class_name GPXlsxXml
extends RefCounted
# Copyright © 2026 Jonson Wang
#
# A deliberately small XML DOM for OOXML parts. It parses into plain Dictionaries so the
# xlsx layer can walk and rewrite cells without a third-party XML library, and serializes
# back with correct escaping.
# 面向 OOXML 部件的**小而够用**的 XML DOM。解析为普通 Dictionary，使 xlsx 层无需第三方
# XML 库即可读写单元格；序列化时正确转义。
#
# Node shape / 节点形状：
#   {"name": String, "attrs": {name: String}, "children": [node], "text": String}
# The document root is name "#document"; its children are the top-level elements.
# 文档根名为 "#document"，其 children 为顶层元素。
#
# WHY NOT A FULL DOM / 为何不是完整 DOM：
# XLSX parts are element/text trees with no mixed content we need to edit. Keeping text on
# the node (instead of text child nodes) makes cell edits one assignment and avoids a node
# type explosion. Comments / processing instructions / DTDs are ignored on parse — they are
# not needed to read or fill a workbook.
# XLSX 部件是我们需要编辑的元素/文本树，没有需要保留的混合内容。把文本挂在节点上（而非
# 文本子节点）使单元格编辑变成一次赋值，也避免节点类型爆炸。注释/处理指令/DTD 解析时忽略 ——
# 读写工作簿不需要它们。
#
# Coding rule: every variable declares its type explicitly; every function is static (pure).
# 编码规范：所有变量显式声明类型；函数全部静态（纯函数）。


# Build one element node. / 构造一个元素节点。
static func gpElement(gpName: String, gpAttrs: Dictionary = {},
		gpChildren: Array = [], gpText: String = "") -> Dictionary:
	return {
		"name": gpName,
		"attrs": gpAttrs.duplicate(true),
		"children": gpChildren.duplicate(),
		"text": gpText,
	}


# Parse XML text into a document node. On failure the returned node carries an "error" key
# and no children; callers must check `gpHasError()`.
# 把 XML 文本解析为文档节点。失败时节点带 "error" 且无 children；调用方必须用 gpHasError() 检查。
static func gpParse(gpText: String) -> Dictionary:
	var gpRoot: Dictionary = {"name": "#document", "attrs": {}, "children": [], "text": ""}
	var gpParser: XMLParser = XMLParser.new()
	var gpOpenErr: int = gpParser.open_buffer(gpText.to_utf8_buffer())
	if gpOpenErr != OK:
		gpRoot["error"] = "open:%d" % gpOpenErr
		return gpRoot
	var gpStack: Array = [gpRoot]
	while true:
		var gpErr: int = gpParser.read()
		if gpErr == ERR_FILE_EOF:
			break
		if gpErr != OK:
			gpRoot["error"] = "read:%d" % gpErr
			return gpRoot
		match gpParser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var gpNode: Dictionary = gpElement(gpParser.get_node_name(), _gpAttrsOf(gpParser))
				var gpParent: Dictionary = gpStack[gpStack.size() - 1] as Dictionary
				(gpParent["children"] as Array).append(gpNode)
				# A self-closing element (<Coordinate .../>) must NOT be pushed: XMLParser
				# reports it as a start event with no matching end event.
				# 自闭合元素（<Coordinate .../>）**不**入栈：XMLParser 把它报成没有匹配结束事件的
				# 开始事件。
				if not gpParser.is_empty():
					gpStack.append(gpNode)
			XMLParser.NODE_ELEMENT_END:
				if gpStack.size() > 1:
					gpStack.pop_back()
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if gpStack.size() > 1:
					var gpTop: Dictionary = gpStack[gpStack.size() - 1] as Dictionary
					gpTop["text"] = str(gpTop.get("text", "")) + gpParser.get_node_data()
			_:
				pass
	if gpStack.size() != 1:
		gpRoot["error"] = "unclosed"
	return gpRoot


# Whether a parsed node carries an error. / 解析节点是否带错误。
static func gpHasError(gpNode: Dictionary) -> bool:
	return gpNode.has("error")


# Serialize a document or element node back to XML text. / 把文档/元素节点序列化为 XML 文本。
static func gpSerialize(gpNode: Dictionary) -> String:
	var gpName: String = str(gpNode.get("name", ""))
	if gpName == "#document":
		var gpOut: String = ""
		for gpChildRaw in (gpNode.get("children", []) as Array):
			gpOut += gpSerialize(gpChildRaw as Dictionary)
		return gpOut
	if gpName == "":
		return ""
	var gpXml: String = "<" + gpName
	var gpAttrs: Dictionary = gpNode.get("attrs", {}) as Dictionary
	for gpKey in gpAttrs.keys():
		gpXml += " %s=\"%s\"" % [str(gpKey), gpEscapeAttr(str(gpAttrs[gpKey]))]
	var gpChildren: Array = gpNode.get("children", []) as Array
	var gpText: String = str(gpNode.get("text", ""))
	if gpChildren.is_empty() and gpText == "":
		return gpXml + "/>"
	gpXml += ">"
	if gpText != "":
		gpXml += gpEscapeText(gpText)
	for gpChildRaw in gpChildren:
		gpXml += gpSerialize(gpChildRaw as Dictionary)
	return gpXml + "</" + gpName + ">"


# Parse a whole part and return a document node; empty/unknown is an error node.
# 解析整个部件并返回文档节点；空/未知返回错误节点。
static func gpParsePart(gpText: String) -> Dictionary:
	if gpText.strip_edges() == "":
		var gpEmpty: Dictionary = {"name": "#document", "attrs": {}, "children": [], "text": "",
			"error": "empty"}
		return gpEmpty
	return gpParse(gpText)


# Local name without a namespace prefix ("x:row" -> "row"). / 去命名空间前缀的本地名。
static func gpLocalName(gpName: String) -> String:
	var gpPos: int = gpName.rfind(":")
	if gpPos >= 0:
		return gpName.substr(gpPos + 1)
	return gpName


# First top-level element of a document node ({} when none). / 文档节点的首个顶层元素。
static func gpRootElement(gpNode: Dictionary) -> Dictionary:
	for gpChildRaw in (gpNode.get("children", []) as Array):
		var gpChild: Dictionary = gpChildRaw as Dictionary
		if str(gpChild.get("name", "")).begins_with("#"):
			continue
		return gpChild
	return {}


# First direct child with the given local name ("" when absent). / 首个匹配本地名的直接子节点。
static func gpChild(gpNode: Dictionary, gpName: String) -> Dictionary:
	for gpChildRaw in (gpNode.get("children", []) as Array):
		var gpChild: Dictionary = gpChildRaw as Dictionary
		if gpLocalName(str(gpChild.get("name", ""))) == gpName:
			return gpChild
	return {}


# All direct children with the given local name. / 全部匹配本地名的直接子节点。
static func gpChildren(gpNode: Dictionary, gpName: String) -> Array:
	var gpOut: Array = []
	for gpChildRaw in (gpNode.get("children", []) as Array):
		var gpChild: Dictionary = gpChildRaw as Dictionary
		if gpLocalName(str(gpChild.get("name", ""))) == gpName:
			gpOut.append(gpChild)
	return gpOut


# Find the first descendant (depth-first) with the given local name. / 深度优先首个后代。
static func gpFind(gpNode: Dictionary, gpName: String) -> Dictionary:
	for gpChildRaw in (gpNode.get("children", []) as Array):
		var gpChild: Dictionary = gpChildRaw as Dictionary
		if gpLocalName(str(gpChild.get("name", ""))) == gpName:
			return gpChild
		var gpFound: Dictionary = gpFind(gpChild, gpName)
		if not gpFound.is_empty():
			return gpFound
	return {}


# Attribute value by exact name, else by local name (handles r:id). / 按全名/本地名取属性。
static func gpAttr(gpNode: Dictionary, gpKey: String, gpDefault: String = "") -> String:
	var gpAttrs: Dictionary = gpNode.get("attrs", {}) as Dictionary
	if gpAttrs.has(gpKey):
		return str(gpAttrs[gpKey])
	for gpActual in gpAttrs.keys():
		if gpLocalName(str(gpActual)) == gpLocalName(gpKey):
			return str(gpAttrs[gpActual])
	return gpDefault


# Set an attribute (keeps its existing spelling when it already exists). / 设置属性。
static func gpSetAttr(gpNode: Dictionary, gpKey: String, gpValue: String) -> void:
	var gpAttrs: Dictionary = gpNode.get("attrs", {}) as Dictionary
	if gpAttrs.has(gpKey):
		gpAttrs[gpKey] = gpValue
		return
	for gpActual in gpAttrs.keys():
		if gpLocalName(str(gpActual)) == gpLocalName(gpKey):
			gpAttrs[gpActual] = gpValue
			return
	gpAttrs[gpKey] = gpValue


# Remove a child node (by identity). / 删除一个子节点（按身份）。
static func gpRemoveChild(gpParent: Dictionary, gpChild: Dictionary) -> void:
	var gpChildren: Array = gpParent.get("children", []) as Array
	for gpI in range(gpChildren.size()):
		if gpChildren[gpI] == gpChild:
			gpChildren.remove_at(gpI)
			return


# Append a child. / 追加子节点。
static func gpAppendChild(gpParent: Dictionary, gpChild: Dictionary) -> void:
	(gpParent.get("children", []) as Array).append(gpChild)


# Text of a <t> element, preserving whitespace. / <t> 元素的文本（保留空白）。
static func gpTextOf(gpNode: Dictionary) -> String:
	return str(gpNode.get("text", ""))


# Escape text content. / 转义文本内容。
static func gpEscapeText(gpText: String) -> String:
	return gpText.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# Escape an attribute value. / 转义属性值。
static func gpEscapeAttr(gpText: String) -> String:
	return gpEscapeText(gpText).replace("\"", "&quot;").replace("'", "&apos;")


static func _gpAttrsOf(gpParser: XMLParser) -> Dictionary:
	var gpOut: Dictionary = {}
	for gpI in range(gpParser.get_attribute_count()):
		gpOut[gpParser.get_attribute_name(gpI)] = gpParser.get_attribute_value(gpI)
	return gpOut
