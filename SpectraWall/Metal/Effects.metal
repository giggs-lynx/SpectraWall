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
    // Border capsule-SDF data (zero/unused for other effects). Layout must mirror
    // Swift's EffectVertex exactly.
    float2 segA;
    float2 segB;
    float  radius;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float  alpha;
    float  edgeDist;
    float2 worldPos;   // this fragment's scene-space position (for the SDF)
    float2 segA;
    float2 segB;
    float  radius;
};

// Unsigned distance from p to segment [a, b]. Degenerate (a == b) → distance to
// the point, which gives the trail's round head/tail cap for free.
static float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float denom = dot(ba, ba);
    if (denom < 1e-6) { return length(pa); }
    float h = clamp(dot(pa, ba) / denom, 0.0, 1.0);
    return length(pa - ba * h);
}

vertex VertexOut border_vertex(
    uint vid [[vertex_id]],
    constant Vertex* vertices [[buffer(0)]],
    constant float2& screenSize [[buffer(1)]]
) {
    Vertex in = vertices[vid];
    float2 clip = float2(
        (in.position.x / screenSize.x) * 2.0 - 1.0,
        (in.position.y / screenSize.y) * 2.0 - 1.0
    );
    VertexOut out;
    out.position = float4(clip, 0.0, 1.0);
    out.color    = in.color;
    out.alpha    = in.alpha;
    out.edgeDist = in.edgeDist;
    out.worldPos = in.position;   // scene-space; interpolates across the quad
    out.segA     = in.segA;
    out.segB     = in.segB;
    out.radius   = in.radius;
    return out;
}

fragment float4 border_fragment(VertexOut in [[stage_in]]) {
    // Each quad carries one centerline segment [segA, segB]; shade by the true
    // 2D distance from this pixel to that capsule. Distance is well-defined
    // everywhere, so corners round off instead of folding into a spike.
    float dist = sdSegment(in.worldPos, in.segA, in.segB);
    float R = max(in.radius, 1e-3);

    // Sentinel: edgeDist >= 1.5 = uniform fill (border ghost's solid silhouette).
    if (in.edgeDist >= 1.5) {
        float aa = smoothstep(0.5, -0.5, dist - R);   // 1 inside capsule, ~1px AA edge
        float a  = in.color.a * in.alpha * aa;
        return float4(in.color.rgb * a, a * a);
    }

    // Glow: same falloff as the old swept-strip shader, but driven by dist/R
    // (along the normal dist/R == the old |edgeDist|, on straights AND corners,
    // so the profile is unchanged).
    float dn         = dist / R;
    float glow       = exp(-dn * dn * 5.0);
    float core       = smoothstep(0.15, 0.0, dn);
    float brightness = glow + core * 2.0;
    float finalAlpha = in.color.a * in.alpha * max(glow, core * 0.5);
    // rgb premultiplied once so `.lighten` (max) composites overlapping capsules
    // as one continuous glow. Framebuffer alpha is α² — matching what the old
    // additive pipeline (srcAlpha·srcAlpha) wrote — so the desktop behind the
    // halo shows through at the same strength; writing plain α occludes the
    // wallpaper noticeably more and reads as a dimmer glow.
    return float4(in.color.rgb * brightness * finalAlpha, finalAlpha * finalAlpha);
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

// MARK: - Ambient Glow

// Reuses spectrum_vertex. edgeDist carries the fade coordinate: 0 at the
// inner (transparent) edge, 1 at the screen edge. Smoothstep instead of the
// vertex-interpolated linear ramp so large fills don't band.
fragment float4 glow_fragment(VertexOut in [[stage_in]]) {
    float t = smoothstep(0.0, 1.0, clamp(in.edgeDist, 0.0, 1.0));
    return float4(in.color.rgb, in.color.a * in.alpha * t);
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
