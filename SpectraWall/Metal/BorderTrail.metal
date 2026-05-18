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
    float glow = exp(-d * d * 5.0);
    float core = smoothstep(0.15, 0.0, d);
    float brightness = glow + core * 2.0;
    float finalAlpha = in.color.a * in.alpha * max(glow, core * 0.5);
    return float4(in.color.rgb * brightness, finalAlpha);
}

// MARK: - Spectrum

vertex VertexOut spectrum_vertex(
    uint vid [[vertex_id]],
    constant Vertex* vertices [[buffer(0)]],
    constant float2& screenSize [[buffer(1)]]
) {
    Vertex in = vertices[vid];
    VertexOut out;
    out.position = float4((in.position.x / screenSize.x) * 2.0 - 1.0,
                          (in.position.y / screenSize.y) * 2.0 - 1.0,
                          0.0, 1.0);
    out.color    = in.color;
    out.alpha    = in.alpha;
    out.edgeDist = in.edgeDist;
    return out;
}

fragment float4 spectrum_fragment(VertexOut in [[stage_in]]) {
    // edgeDist: -1 = bottom of bar (full opacity), 1 = top (fade out)
    float t    = (in.edgeDist + 1.0) * 0.5;          // remap -1…1 → 0…1
    float fade = 1.0 - t * t;                         // quadratic fade toward top
    float finalAlpha = in.color.a * in.alpha * fade;
    return float4(in.color.rgb, finalAlpha);
}

// MARK: - Orb

vertex VertexOut orb_vertex(
    uint vid [[vertex_id]],
    constant Vertex* vertices [[buffer(0)]],
    constant float2& screenSize [[buffer(1)]]
) {
    Vertex in = vertices[vid];
    VertexOut out;
    out.position = float4((in.position.x / screenSize.x) * 2.0 - 1.0,
                          (in.position.y / screenSize.y) * 2.0 - 1.0,
                          0.0, 1.0);
    out.color    = in.color;
    out.alpha    = in.alpha;
    out.edgeDist = in.edgeDist;
    return out;
}

fragment float4 orb_fragment(VertexOut in [[stage_in]]) {
    // edgeDist: 0 = orb center, 1 = edge
    float d    = clamp(abs(in.edgeDist), 0.0, 1.0);
    float glow = exp(-d * d * 3.0);
    float core = smoothstep(0.3, 0.0, d);
    float finalAlpha = in.color.a * in.alpha * max(glow, core * 0.5);
    return float4(in.color.rgb * (glow + core * 1.5), finalAlpha);
}
