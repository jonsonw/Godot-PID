class_name GPPreviewTransform
extends RefCounted

## Pure coordinate mapping for a glyph preview: preview-local pixels <-> author space, plus the
## normalized (0..1) port space used by the working port list.
## 字形预览的纯坐标映射：预览本地像素 <-> 作者空间，以及工作端口表所用的归一化（0..1）端口空间。
##
## Why it exists / 为何存在：
## these six helpers used to be private methods of GPMakeSymbolDialog. They are pure math over
## (view size, glyph bbox) with no Control dependency, so they were both untestable and
## unreusable — yet the W8 symbol-library work and any future "edit symbol in place" surface
## need exactly the same mapping. Extracting them makes the round-trip assertable in headless.
## 这六个助手原是 GPMakeSymbolDialog 的私有方法。它们是仅依赖（视图尺寸、字形包围盒）的纯数学，
## 却既不可测也不可复用——而 W8 符号库工作与未来任何「就地编辑图元」界面都需要完全相同的映射。
## 抽出后即可在 headless 中断言往返一致性。
##
## Contract / 契约：
## the painter fits the glyph's bbox into the preview rect with UNIFORM scale + centering;
## this class reproduces that exact transform so clicks land where the glyph is drawn.
## 渲染器以「均匀缩放 + 居中」把字形包围盒塞入预览矩形；本类复现同一变换，使点击落点即图形绘制处。

# Inner margin (px) kept around the preview content, matching the painter's inset.
# 预览内容保留的内边距（像素），与渲染器的内缩一致。
const GP_VIEW_INSET: float = 4.0

# Canonical author-space box used when the glyph has no geometry yet, so clicks still map.
# 字形尚无几何时使用的规范作者空间框，使点击仍可映射。
const GP_UNIT_BOX: float = 100.0


# Pixel size of the preview Control (its `size`, not its rect).
# 预览 Control 的像素尺寸（其 `size`，非矩形）。
var gpViewSize: Vector2 = Vector2.ZERO

# Author-space bounding box of the glyph being previewed.
# 被预览字形的作者空间包围盒。
var gpBox: Rect2 = Rect2(Vector2.ZERO, Vector2(GP_UNIT_BOX, GP_UNIT_BOX))


# Build a transform for gpShapes inside a preview of gpViewSize pixels.
# 为 gpShapes 构造「gpViewSize 像素预览内」的变换。
static func gpForShapes(gpShapes: Array[GPShape], gpViewSize: Vector2) -> GPPreviewTransform:
	var gpT: GPPreviewTransform = GPPreviewTransform.new()
	gpT.gpViewSize = gpViewSize
	gpT.gpBox = gpBoxOf(gpShapes)
	return gpT


# Author-space bbox of gpShapes, falling back to the canonical unit box when there is no
# usable geometry (empty list, or a degenerate zero-area box).
# gpShapes 的作者空间包围盒；无可用几何（空列表或零面积退化框）时回退为规范单位框。
static func gpBoxOf(gpShapes: Array[GPShape]) -> Rect2:
	var gpSpec: Dictionary = GPShapeSpec.gpBuild(gpShapes)
	var gpArr: Array = gpSpec.get("box", [])
	if gpArr.size() >= 4 and float(gpArr[2]) > 0.0 and float(gpArr[3]) > 0.0:
		return Rect2(Vector2(float(gpArr[0]), float(gpArr[1])), Vector2(float(gpArr[2]), float(gpArr[3])))
	return Rect2(Vector2.ZERO, Vector2(GP_UNIT_BOX, GP_UNIT_BOX))


# The drawable rect inside the preview Control (inset on all sides).
# 预览 Control 内的可绘制矩形（四周内缩）。
func gpViewRect() -> Rect2:
	return Rect2(Vector2(GP_VIEW_INSET, GP_VIEW_INSET), gpViewSize - Vector2(GP_VIEW_INSET * 2.0, GP_VIEW_INSET * 2.0))


# Uniform author -> pixel scale. Guarded against a non-positive view or box (which would
# otherwise yield inf/nan and silently break every hit test).
# 作者空间 -> 像素的均匀缩放。对非正视图 / 包围盒做保护（否则会得到 inf/nan 并静默破坏全部命中测试）。
func gpScale() -> float:
	var gpView: Rect2 = gpViewRect()
	var gpK: float = minf(gpView.size.x / maxf(gpBox.size.x, 0.001), gpView.size.y / maxf(gpBox.size.y, 0.001))
	if gpK <= 0.0 or not is_finite(gpK):
		return 1.0
	return gpK


# Preview-local pixel -> author space.
# 预览本地像素 -> 作者空间。
func gpLocalToAuthor(gpLocal: Vector2) -> Vector2:
	var gpView: Rect2 = gpViewRect()
	var gpK: float = gpScale()
	var gpCtr: Vector2 = gpView.get_center()
	var gpBoxCtr: Vector2 = gpBox.get_center()
	return Vector2(gpBoxCtr.x + (gpLocal.x - gpCtr.x) / gpK, gpBoxCtr.y + (gpLocal.y - gpCtr.y) / gpK)


# Author space -> preview-local pixel.
# 作者空间 -> 预览本地像素。
func gpAuthorToLocal(gpAuthor: Vector2) -> Vector2:
	var gpView: Rect2 = gpViewRect()
	var gpK: float = gpScale()
	var gpCtr: Vector2 = gpView.get_center()
	var gpBoxCtr: Vector2 = gpBox.get_center()
	return Vector2(gpCtr.x + (gpAuthor.x - gpBoxCtr.x) * gpK, gpCtr.y + (gpAuthor.y - gpBoxCtr.y) * gpK)


# Normalized port (0..1) -> preview-local pixel. The FULL preview rect is the envelope,
# matching how GPSymbolView draws ports against the symbol's nominal envelope on the canvas.
# 归一化端口（0..1）-> 预览本地像素。整幅预览矩形即包络，与画布上 GPSymbolView
# 相对图元标称包络绘制端口的方式一致。
func gpPortLocal(gpN: Vector2) -> Vector2:
	var gpView: Rect2 = gpViewRect()
	return gpView.get_center() + (gpN - Vector2(0.5, 0.5)) * gpView.size


# Preview-local pixel -> normalized port (0..1), clamped to the envelope.
# 预览本地像素 -> 归一化端口（0..1），夹取到包络内。
func gpLocalToNorm(gpLocal: Vector2) -> Vector2:
	var gpView: Rect2 = gpViewRect()
	var gpN: Vector2 = (gpLocal - gpView.get_center()) / gpView.size + Vector2(0.5, 0.5)
	gpN.x = clampf(gpN.x, 0.0, 1.0)
	gpN.y = clampf(gpN.y, 0.0, 1.0)
	return gpN
