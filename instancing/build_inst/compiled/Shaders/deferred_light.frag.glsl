#version 450

#include "compiled.inc"
#include "std/gbuffer.glsl"
#include "std/light.glsl"
#ifdef _Clusters
#include "std/clusters.glsl"
#endif
#ifdef _Irr
#include "std/shirr.glsl"
#endif
#ifdef _VoxelGI
#include "std/conetrace.glsl"
#endif
#ifdef _VoxelAOvar
#include "std/conetrace.glsl"
#endif
#ifdef _SSS
#include "std/sss.glsl"
#endif
#ifdef _SSRS
#include "std/ssrs.glsl"
#endif
#ifdef _LightIES
#include "std/ies.glsl"
#endif
#ifdef _LTC
#include "std/ltc.glsl"
#endif

uniform sampler2D gbufferD;
uniform sampler2D gbuffer0;
uniform sampler2D gbuffer1;

#ifdef _VoxelGI
uniform sampler3D voxels;
#endif
#ifdef _VoxelAOvar
uniform sampler3D voxels;
#endif
#ifdef _VoxelGITemporal
uniform sampler3D voxelsLast;
uniform float voxelBlend;
#endif
#ifdef _VoxelGICam
uniform vec3 eyeSnap;
#endif

uniform float envmapStrength;
#ifdef _Irr
//!uniform vec4 shirr[7];
#endif
#ifdef _Brdf
uniform sampler2D senvmapBrdf;
#endif
#ifdef _Rad
uniform sampler2D senvmapRadiance;
uniform int envmapNumMipmaps;
#endif
#ifdef _EnvCol
uniform vec3 backgroundCol;
#endif

#ifdef _SSAO
uniform sampler2D ssaotex;
#endif

#ifdef _SSS
uniform vec2 lightPlane;
#endif

#ifdef _SSRS
//!uniform mat4 VP;
uniform mat4 invVP;
#endif

#ifdef _LightIES
//!uniform sampler2D texIES;
#endif

#ifdef _SMSizeUniform
//!uniform vec2 smSizeUniform;
#endif

#ifdef _LTC
uniform vec3 lightArea0;
uniform vec3 lightArea1;
uniform vec3 lightArea2;
uniform vec3 lightArea3;
uniform sampler2D sltcMat;
uniform sampler2D sltcMag;
#endif

uniform vec2 cameraProj;
uniform vec3 eye;
uniform vec3 eyeLook;

#ifdef _Clusters
uniform vec4 lightsArray[maxLights * 2];
	#ifdef _Spot
	uniform vec4 lightsArraySpot[maxLights];
	#endif
uniform sampler2D clustersData;
uniform vec2 cameraPlane;
#endif

#ifdef _ShadowMap
#ifdef _SinglePoint
	#ifdef _Spot
	//!uniform sampler2DShadow shadowMapSpot[1];
	//!uniform mat4 LWVPSpot0;
	#else
	//!uniform samplerCubeShadow shadowMapPoint[1];
	//!uniform vec2 lightProj;
	#endif
#endif
#ifdef _Clusters
	//!uniform samplerCubeShadow shadowMapPoint[4];
	//!uniform vec2 lightProj;
	#ifdef _Spot
	//!uniform sampler2DShadow shadowMapSpot[4];
	//!uniform mat4 LWVPSpot0;
	//!uniform mat4 LWVPSpot1;
	//!uniform mat4 LWVPSpot2;
	//!uniform mat4 LWVPSpot3;
	#endif
#endif
#endif

#ifdef _Sun
uniform vec3 sunDir;
uniform vec3 sunCol;
	#ifdef _ShadowMap
	uniform sampler2DShadow shadowMap;
	uniform float shadowsBias;
	#ifdef _CSM
	//!uniform vec4 casData[shadowmapCascades * 4 + 4];
	#else
	uniform mat4 LWVP;
	#endif
	// #ifdef _SoftShadows
	// uniform sampler2D svisibility;
	// #else
	#endif // _ShadowMap
#endif

#ifdef _SinglePoint // Fast path for single light
uniform vec3 pointPos;
uniform vec3 pointCol;
uniform float pointBias;
	#ifdef _Spot
	uniform vec3 spotDir;
	uniform vec2 spotData;
	#endif
#endif

#ifdef _LightClouds
uniform sampler2D texClouds;
uniform float time;
#endif

in vec2 texCoord;
in vec3 viewRay;
out vec4 fragColor;

void main() {
	vec4 g0 = textureLod(gbuffer0, texCoord, 0.0); // Normal.xy, metallic/roughness, depth
	
	vec3 n;
	n.z = 1.0 - abs(g0.x) - abs(g0.y);
	n.xy = n.z >= 0.0 ? g0.xy : octahedronWrap(g0.xy);
	n = normalize(n);

	vec2 metrough = unpackFloat(g0.b);
	vec4 g1 = textureLod(gbuffer1, texCoord, 0.0); // Basecolor.rgb, spec/occ
	vec2 occspec = unpackFloat2(g1.a);
	vec3 albedo = surfaceAlbedo(g1.rgb, metrough.x); // g1.rgb - basecolor
	vec3 f0 = surfaceF0(g1.rgb, metrough.x);

	float depth = textureLod(gbufferD, texCoord, 0.0).r * 2.0 - 1.0;
	vec3 p = getPos(eye, eyeLook, normalize(viewRay), depth, cameraProj);
	vec3 v = normalize(eye - p);
	float dotNV = max(dot(n, v), 0.0);

#ifdef _Brdf
	vec2 envBRDF = textureLod(senvmapBrdf, vec2(metrough.y, 1.0 - dotNV), 0.0).xy;
#endif

#ifdef _VoxelGI
	#ifdef _VoxelGICam
	vec3 voxpos = (p - eyeSnap) / voxelgiHalfExtents;
	#else
	vec3 voxpos = p / voxelgiHalfExtents;
	#endif

	#ifdef _VoxelGITemporal
	vec4 indirectDiffuse = traceDiffuse(voxpos, n, voxels) * voxelBlend + traceDiffuse(voxpos, n, voxelsLast) * (1.0 - voxelBlend);
	#else
	vec4 indirectDiffuse = traceDiffuse(voxpos, n, voxels);
	#endif

	fragColor.rgb = indirectDiffuse.rgb * voxelgiDiff * g1.rgb;

	if (occspec.y > 0.0) {
		vec3 indirectSpecular = traceSpecular(voxels, voxpos, n, v, metrough.y);
		indirectSpecular *= f0 * envBRDF.x + envBRDF.y;
		fragColor.rgb += indirectSpecular * voxelgiSpec * occspec.y;
	}

	// if (!isInsideCube(voxpos)) fragColor = vec4(1.0); // Show bounds
#endif

	// Envmap
#ifdef _Irr
	vec3 envl = shIrradiance(n);
	#ifdef _EnvTex
	envl /= PI;
	#endif
#else
	vec3 envl = vec3(1.0);
#endif

#ifdef _Rad
	vec3 reflectionWorld = reflect(-v, n);
	float lod = getMipFromRoughness(metrough.y, envmapNumMipmaps);
	vec3 prefilteredColor = textureLod(senvmapRadiance, envMapEquirect(reflectionWorld), lod).rgb;
#endif

#ifdef _EnvLDR
	envl.rgb = pow(envl.rgb, vec3(2.2));
	#ifdef _Rad
		prefilteredColor = pow(prefilteredColor, vec3(2.2));
	#endif
#endif

	envl.rgb *= albedo;
	
#ifdef _Rad // Indirect specular
	envl.rgb += prefilteredColor * (f0 * envBRDF.x + envBRDF.y) * 1.5 * occspec.y;
#else
	#ifdef _EnvCol
	envl.rgb += backgroundCol * surfaceF0(g1.rgb, metrough.x); // f0
	#endif
#endif

	envl.rgb *= envmapStrength * occspec.x;

#ifdef _VoxelAOvar

	#ifdef _VoxelGICam
	vec3 voxpos = (p - eyeSnap) / voxelgiHalfExtents;
	#else
	vec3 voxpos = p / voxelgiHalfExtents;
	#endif
	
	#ifdef _VoxelGITemporal
	envl.rgb *= 1.0 - (traceAO(voxpos, n, voxels) * voxelBlend +
					   traceAO(voxpos, n, voxelsLast) * (1.0 - voxelBlend));
	#else
	envl.rgb *= 1.0 - traceAO(voxpos, n, voxels);
	#endif
	
#endif

#ifdef _VoxelGI
	fragColor.rgb += envl * voxelgiEnv;
#else
	fragColor.rgb = envl;
#endif

#ifdef _SSAO
	// #ifdef _RTGI
	// fragColor.rgb *= textureLod(ssaotex, texCoord, 0.0).rgb;
	// #else
	fragColor.rgb *= textureLod(ssaotex, texCoord, 0.0).r;
	// #endif
#endif

	// Show voxels
	// vec3 origin = vec3(texCoord * 2.0 - 1.0, 0.99);
	// vec3 direction = vec3(0.0, 0.0, -1.0);
	// vec4 color = vec4(0.0f);
	// for(uint step = 0; step < 400 && color.a < 0.99f; ++step) {
	// 	vec3 point = origin + 0.005 * step * direction;
	// 	color += (1.0f - color.a) * textureLod(voxels, point * 0.5 + 0.5, 0);
	// } 
	// fragColor.rgb += color.rgb;

	// Show SSAO
	// fragColor.rgb = texture(ssaotex, texCoord).rrr;

#ifdef _Sun
	vec3 sh = normalize(v + sunDir);
	float sdotNH = dot(n, sh);
	float sdotVH = dot(v, sh);
	float sdotNL = dot(n, sunDir);
	float svisibility = 1.0;
	vec3 sdirect = lambertDiffuseBRDF(albedo, sdotNL) +
				   specularBRDF(f0, metrough.y, sdotNL, sdotNH, dotNV, sdotVH) * occspec.y;

	// #ifdef _SoftShadows
	// svisibility = textureLod(svisibility, texCoord, 0.0).r;
	// #endif

	#ifdef _ShadowMap
	// if (lightShadow == 1) {
		#ifdef _CSM
		svisibility = shadowTestCascade(shadowMap, eye, p + n * shadowsBias * 10, shadowsBias);
		#else
		vec4 lPos = LWVP * vec4(p + n * shadowsBias * 100, 1.0);
		if (lPos.w > 0.0) svisibility = shadowTest(shadowMap, lPos.xyz / lPos.w, shadowsBias);
		#endif
	// }
	#endif

	#ifdef _VoxelGIShadow // #else
		#ifdef _VoxelGICam
		vec3 voxpos = (p - eyeSnap) / voxelgiHalfExtents;
		#else
		vec3 voxpos = p / voxelgiHalfExtents;
		#endif
		if (dotNL > 0.0) svisibility = max(0, 1.0 - traceShadow(voxels, voxpos, l, 0.1, 10.0, n));
	#endif

	#ifdef _SSRS
	float tvis = traceShadowSS(-sunDir, p, gbufferD, invVP, eye);
	// vec2 coords = getProjectedCoord(hitCoord);
	// vec2 deltaCoords = abs(vec2(0.5, 0.5) - coords.xy);
	// float screenEdgeFactor = clamp(1.0 - (deltaCoords.x + deltaCoords.y), 0.0, 1.0);
	// tvis *= screenEdgeFactor;
	svisibility *= tvis;
	#endif

	fragColor.rgb += sdirect * svisibility * sunCol;
#endif

// #ifdef _Hair // Aniso
// 	if (textureLod(gbuffer2, texCoord, 0.0).a == 2) {
// 		const float shinyParallel = metrough.y;
// 		const float shinyPerpendicular = 0.1;
// 		const vec3 v = vec3(0.99146, 0.11664, 0.05832);
// 		vec3 T = abs(dot(n, v)) > 0.99999 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, v);
// 		fragColor.rgb = orenNayarDiffuseBRDF(albedo, metrough.y, dotNV, dotNL, dotVH) + wardSpecular(n, h, dotNL, dotNV, dotNH, T, shinyParallel, shinyPerpendicular) * spec;
// 	}
// 	else fragColor.rgb = lambertDiffuseBRDF(albedo, dotNL) + specularBRDF(f0, metrough.y, dotNL, dotNH, dotNV, dotVH) * spec;
// #endif

#ifdef _LightClouds
	visibility *= textureLod(texClouds, vec2(p.xy / 100.0 + time / 80.0), 0.0).r * dot(n, vec3(0,0,1));
#endif

#ifdef _SSS
	if (textureLod(gbuffer2, texCoord, 0.0).a == 2) {
		#ifdef _CSM
		int casi, casindex;
		mat4 LWVP = getCascadeMat(distance(eye, p), casi, casindex);
		#endif
		fragColor.rgb += fragColor.rgb * SSSSTransmittance(LWVP, p, n, l, lightPlane.y, shadowMap);
	}
#endif

#ifdef _SinglePoint
	fragColor.rgb += sampleLight(
		p, n, v, dotNV, pointPos, pointCol, albedo, metrough.y, occspec.y, f0
		#ifdef _ShadowMap
			, 0, pointBias
		#endif
		#ifdef _Spot
		, true, spotData.x, spotData.y, spotDir
		#endif
	);
#endif

#ifdef _Clusters
	float viewz = linearize(depth * 0.5 + 0.5, cameraProj);
	int clusterI = getClusterI(texCoord, viewz, cameraPlane);
	int numLights = int(texelFetch(clustersData, ivec2(clusterI, 0), 0).r * 255);

	#ifdef HLSL
	viewz += textureLod(clustersData, vec2(0.0), 0.0).r * 1e-9; // TODO: krafix bug, needs to generate sampler
	#endif

	#ifdef _Spot
	int numSpots = int(texelFetch(clustersData, ivec2(clusterI, 1 + maxLightsCluster), 0).r * 255);
	int numPoints = numLights - numSpots;
	#endif

	for (int i = 0; i < min(numLights, maxLightsCluster); i++) {
		int li = int(texelFetch(clustersData, ivec2(clusterI, i + 1), 0).r * 255);
		fragColor.rgb += sampleLight(
			p,
			n,
			v,
			dotNV,
			lightsArray[li * 2].xyz, // lp
			lightsArray[li * 2 + 1].xyz, // lightCol
			albedo,
			metrough.y,
			occspec.y,
			f0
			#ifdef _ShadowMap
				, li, lightsArray[li * 2].w // bias
			#endif
			#ifdef _Spot
			, li > numPoints - 1
			, lightsArray[li * 2 + 1].w // cutoff
			, lightsArraySpot[li].w // cutoff - exponent
			, lightsArraySpot[li].xyz // spotDir
			#endif
		);
	}
#endif // _Clusters
}
