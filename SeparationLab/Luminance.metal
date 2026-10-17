#include <metal_stdlib>
using namespace metal;
kernel void luminance(texture2d<float, access::read> input [[texture(0)]],
                      texture2d<float, access::write> output [[texture(1)]],
                      uint2 p [[thread_position_in_grid]]) {
    if (p.x >= input.get_width() || p.y >= input.get_height()) return;
    float3 c = input.read(p).rgb;
    float y = dot(c, float3(0.2126, 0.7152, 0.0722));
    output.write(float4(y, y, y, 1), p);
}
