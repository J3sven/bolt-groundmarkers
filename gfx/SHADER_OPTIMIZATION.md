# Shader-Based Rendering Optimization

## Overview

The ground markers plugin now uses custom GLSL shaders to render tile outlines efficiently. This replaces the previous approach of making multiple `surface:drawtoscreen()` calls per line segment.

## Problem

Previously, the plugin rendered each tile edge by calling `draw.drawLine()`, which internally made multiple `drawtoscreen()` calls in a loop to draw a thick line. When many tiles came into render distance, this resulted in:
- Hundreds or thousands of GPU calls per frame
- Significant frame drops
- Poor rendering performance

## Solution

The shader-based approach:
1. **Batches all lines** of the same color into a single array
2. **Generates quad geometry** for each line (2 triangles per line to handle thickness)
3. **Makes a single shader draw call** per color group
4. **Uses GPU-based rendering** with custom vertex and fragment shaders

## Technical Details

### Shader Pipeline

1. **Vertex Shader** ([gfx/shaders.lua:18-28](gfx/shaders.lua#L18-L28))
   - Takes position (vec2) and color (vec4) as inputs
   - Passes color through to fragment shader
   - Outputs transformed position

2. **Fragment Shader** ([gfx/shaders.lua:30-38](gfx/shaders.lua#L30-L38))
   - Receives interpolated color from vertex shader
   - Outputs final pixel color

### Line to Quad Conversion

Each line is converted to a quad (rectangle) to achieve thickness:

```
Line: (x1, y1) -------- (x2, y2)
                ↓
Quad:  (x1_top, y1_top) -------- (x2_top, y2_top)
              |                          |
       (x1_bot, y1_bot) -------- (x2_bot, y2_bot)
```

The perpendicular offset is calculated as:
```lua
px = (-dy / len) * (thickness / 2.0)
py = (dx / len) * (thickness / 2.0)
```

### Coordinate Transformation

Screen coordinates → Normalized Device Coordinates (NDC):
```lua
ndcX = (x / screenWidth) * 2.0 - 1.0
ndcY = 1.0 - (y / screenHeight) * 2.0  -- Y-axis flipped
```

NDC range: `[-1, 1]` for both x and y

### Memory Layout

Each vertex in the shader buffer:
```
Offset | Size | Type  | Attribute
-------|------|-------|----------
0      | 8    | vec2  | Position (x, y)
8      | 16   | vec4  | Color (r, g, b, a)
Total: 24 bytes per vertex
```

Each line requires 6 vertices (2 triangles):
- Triangle 1: top-left, bottom-left, top-right
- Triangle 2: bottom-left, bottom-right, top-right

## Integration Points

### render.lua

Modified sections:
- [Line 4](gfx/render.lua#L4): Added shader module import
- [Line 189](gfx/render.lua#L189): Initialize shaders
- [Line 212](gfx/render.lua#L212): Update screen dimensions
- [Lines 355-438](gfx/render.lua#L355-L438): Batch lines and call shader renderer

### Backward Compatibility

The shader implementation:
- ✅ Respects user's color palette
- ✅ Honors line thickness settings
- ✅ Works with all tile types (persistent, instance, layout)
- ✅ Maintains proper alpha blending
- ✅ Preserves existing culling and viewport checks

## Performance Impact

**Before:**
- N tiles × 4 edges × subdivisions × thickness steps = ~thousands of draw calls
- Example: 100 tiles = ~1600+ `drawtoscreen()` calls per frame

**After:**
- 1 shader call per unique color in view
- Typical: 1-8 shader calls per frame (depending on palette usage)

**Expected improvement:** 100x-1000x reduction in GPU calls

## Future Optimizations

Potential improvements:
- Reuse shader buffers across frames (currently recreated each frame)
- Implement geometry instancing for repeated line patterns
- Use geometry shaders to generate quads from line endpoints
- Add anti-aliasing with multisampling

## Testing

To verify the optimization works:
1. Load a layout with many tiles (100+)
2. Quickly move through the world to bring tiles into view
3. Check for frame rate stability (should no longer drop significantly)
4. Verify colors, thickness, and positioning are correct
