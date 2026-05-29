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
    // Sentinel: edgeDist >= 2.0 = uniform fill mode (used by border ghost's
    // filled silhouette so the whole interior renders at full colour/alpha
    // instead of fading to transparent at the strip edges like the trail.
    if (in.edgeDist >= 1.5) {
        return float4(in.color.rgb, in.color.a * in.alpha);
    }
    float d          = abs(in.edgeDist);
    float glow = exp(-d * d * 5.0);
    float core = smoothstep(0.15, 0.0, d);
    float brightness = glow + core * 2.0;
    float finalAlpha = in.color.a * in.alpha * max(glow, core * 0.5);
    return float4(in.color.rgb * brightness, finalAlpha);
}

// MARK: - Debug overlay

// Flat-colour pass for the geometry debug overlay. Primitive-agnostic (the
// renderer submits .triangle quads). No edge shaping — just the vertex colour
// so skeleton lines read crisply on top of every effect.
vertex VertexOut debug_vertex(
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

fragment float4 debug_fragment(VertexOut in [[stage_in]]) {
    return float4(in.color.rgb, in.color.a * in.alpha);
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
    return float4(in.color.rgb, in.color.a * in.alpha);
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
    // edgeDist sign encodes layer type:
    //   >= 0  →  inner solid disk  (edgeDist: 0=center, +1=edge)
    //   <  0  →  outer glow ring   (edgeDist: 0=center, -1=edge)
    float d = clamp(abs(in.edgeDist), 0.0, 1.0);
    float mask;
    if (in.edgeDist < 0.0) {
        // Outer glow: solid filled circle matching SKShapeNode, 5% antialiasing at edge
        mask = smoothstep(1.0, 0.95, d);
    } else {
        // Inner solid disk with minimal anti-aliasing
        mask = smoothstep(1.0, 0.95, d);
    }
    return float4(in.color.rgb, in.color.a * in.alpha * mask);
}
