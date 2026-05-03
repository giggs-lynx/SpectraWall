//
//  BorderTrail.metal
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/2.
//

#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position;
    float4 color;
    float  alpha;
    float  edgeDist;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float  alpha;
    float  edgeDist;
};

vertex VertexOut border_vertex(
    uint vid [[vertex_id]],
    constant Vertex* vertices [[buffer(0)]],
    constant float2& screenSize [[buffer(1)]]
) {
    Vertex in = vertices[vid];
    float2 clip = float2(
        (in.position.x / screenSize.x) * 2.0 - 1.0,
        (in.position.y / screenSize.y) * 2.0 - 1.0   // 改回這樣
    );
    VertexOut out;
    out.position = float4(clip, 0.0, 1.0);
    out.color    = in.color;
    out.alpha    = in.alpha;
    out.edgeDist = in.edgeDist;
    return out;
}

fragment float4 border_fragment(VertexOut in [[stage_in]]) {
    float d          = abs(in.edgeDist);
    float glow = exp(-d * d * 5.0);  // 2.0 → 5.0
    float core = smoothstep(0.15, 0.0, d);  // 0.4 → 0.15，core 更細
    float brightness = glow + core * 2.0;   // 0.8 → 2.0，core 更亮
    float finalAlpha = in.color.a * in.alpha * max(glow, core * 0.5);
    return float4(in.color.rgb * brightness, finalAlpha);
}
