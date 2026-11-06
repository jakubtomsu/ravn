#ifndef _RAVN_HASH_INCLUDED
#define _RAVN_HASH_INCLUDED 1

// Based on original GLSL code https://www.shadertoy.com/view/4djSRW by David Hoskins, MIT license

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(float2 p) {
	float3 p3  = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash31(float3 p3) {
	p3  = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float hash41(float4 p4) {
	p4 = fract(p4  * float4(.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.x + p4.y) * (p4.z + p4.w));
}

float2 hash12(float p) {
	float3 p3 = fract(float3(p) * float3(.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

float2 hash22(float2 p) {
	float3 p3 = fract(float3(p.xyx) * float3(.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);

}

float2 hash32(float3 p3) {
	p3 = fract(p3 * float3(.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

float3 hash13(float p) {
   float3 p3 = fract(float3(p) * float3(.1031, 0.1030, 0.0973));
   p3 += dot(p3, p3.yzx+33.33);
   return fract((p3.xxy+p3.yzz)*p3.zyx);
}

float3 hash23(float2 p) {
	float3 p3 = fract(float3(p.xyx) * float3(.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz+33.33);
    return fract((p3.xxy+p3.yzz)*p3.zyx);
}

float3 hash33(float3 p3) {
	p3 = fract(p3 * float3(.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz+33.33);
    return fract((p3.xxy + p3.yxx)*p3.zyx);
}

float4 hash14(float p) {
	float4 p4 = fract(float4(p) * float4(.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}

float4 hash24(float2 p) {
	float4 p4 = fract(float4(p.xyxy) * float4(.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}

float4 hash34(float3 p) {
	float4 p4 = fract(float4(p.xyzx)  * float4(.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}

float4 hash44(float4 p4) {
	p4 = fract(p4  * float4(.1031, 0.1030, 0.0973, 0.1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}

#endif // _RAVN_HASH_INCLUDED