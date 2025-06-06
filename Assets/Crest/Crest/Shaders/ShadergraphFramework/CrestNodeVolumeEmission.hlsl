// Crest Ocean System

// Copyright 2020 Wave Harmonic Ltd

#include "OceanGraphConstants.hlsl"
#include "../OceanGlobals.hlsl"
#include "../OceanShaderHelpers.hlsl"
#include "../Helpers/WaterVolume.hlsl"

// Taken from:
// https://github.com/Unity-Technologies/Graphics/blob/f56d2b265eb9e01b0376623e909f98c88bc60662/Packages/com.unity.render-pipelines.high-definition/Runtime/Water/Shaders/WaterUtilities.hlsl#L781-L797
float EdgeBlendingFactor(float2 screenPosition, float distanceToWaterSurface)
{
    // Convert the screen position to NDC
    float2 screenPosNDC = screenPosition * 2 - 1;

    // We want the value to be 0 at the center and go to 1 at the edges
    float distanceToEdge = 1.0 - min((1.0 - abs(screenPosNDC.x)), (1.0 - abs(screenPosNDC.y)));

    // What we want here is:
    // - +inf -> 0.5 value is 0
    // - 0.5-> 0.25 value is going from  0 to 1
    // - 0.25 -> 0 value is 1
    float distAttenuation = 1.0 - saturate((distanceToWaterSurface - 0.75) / 0.25);

    // Based on if the water surface is close, we want to make the blending region even bigger
    return lerp(saturate((distanceToEdge - 0.8) / (0.2)), saturate(distanceToEdge + 0.25), distAttenuation);
}

// We take the unrefracted scene colour (i_sceneColourUnrefracted) as input because having a Scene Colour node in the graph
// appears to be necessary to ensure the scene colours are bound?
void CrestNodeSceneColour_half
(
	in const half i_refractionStrength,
	in const half3 i_scatterCol,
	in const half3 i_normalTS,
	in const float4 i_screenPos,
	in const float i_pixelZ,
	in const half3 i_sceneColourUnrefracted,
	in const float i_sceneZ,
	in const float i_deviceSceneZ,
	in const bool i_underwater,
	out half3 o_sceneColour,
	out float o_sceneDistance,
	out float3 o_scenePositionWS
)
{
#if !_SURFACE_TYPE_TRANSPARENT
	o_sceneColour = 0;
	o_sceneDistance = 1000;
	o_scenePositionWS = 0;
	return;
#endif

#ifdef SHADERGRAPH_PREVIEW
	// _CameraDepthTexture_TexelSize is not defined in shader graph. Silence error.
	float4 _CameraDepthTexture_TexelSize = (float4)0.0;
#endif

	//#if _TRANSPARENCY_ON

	// View ray intersects geometry surface either above or below ocean surface

	half2 refractOffset = i_refractionStrength * i_normalTS.xy;
	if (!i_underwater)
	{
		// We're above the water, so behind interface is depth fog
		refractOffset *= min(1.0, 0.5 * (i_sceneZ - i_pixelZ)) / i_sceneZ;
		// Blend at the edge of the screen to avoid artifacts.
		refractOffset *= 1.0 - EdgeBlendingFactor(i_screenPos.xy, i_pixelZ);
	}

	const float2 screenPosRefract = i_screenPos.xy + refractOffset;
	float sceneZRefractDevice = SHADERGRAPH_SAMPLE_SCENE_DEPTH(screenPosRefract);

	// Convert coordinates for Load.
	const float2 positionSS = i_screenPos.xy * _ScreenSize.xy;
	const float2 refractedPositionSS = screenPosRefract * _ScreenSize.xy;

#if CREST_WATER_VOLUME_HAS_BACKFACE
	bool caustics = true;
	bool backface = ApplyVolumeToOceanSurfaceRefractions(refractedPositionSS, i_deviceSceneZ, i_underwater, sceneZRefractDevice, caustics);
#endif

	const float sceneZRefract = CrestLinearEyeDepth(sceneZRefractDevice);

	// Depth fog & caustics - only if view ray starts from above water
	if (!i_underwater)
	{
		// Compute depth fog alpha based on refracted position if it landed on an underwater surface, or on unrefracted depth otherwise
		if (sceneZRefract > i_pixelZ)
		{
			float msDepth = sceneZRefractDevice;
#if CREST_WATER_VOLUME_HAS_BACKFACE
			if (!backface)
#endif
			{
#if CREST_HDRP
				// NOTE: For HDRP, refractions produce an outline which requires multisampling with a two pixel offset to
				// cover. This is without MSAA. A deeper investigation is needed.
				msDepth = CrestMultiLoadDepth
				(
					_CameraDepthTexture,
					refractedPositionSS,
					i_refractionStrength > 0 ? 2 : _CrestDepthTextureOffset,
					sceneZRefractDevice
				);
#else
				msDepth = CrestMultiSampleDepth
				(
					_CameraDepthTexture,
					sampler_CameraDepthTexture,
					_CameraDepthTexture_TexelSize.xy,
					screenPosRefract,
					i_refractionStrength > 0.0 ? 2 : _CrestDepthTextureOffset,
					sceneZRefractDevice
				);
#endif // CREST_HDRP
			}

			o_sceneDistance = CrestLinearEyeDepth(msDepth) - i_pixelZ;

			o_sceneColour = SHADERGRAPH_SAMPLE_SCENE_COLOR(screenPosRefract);

#if CREST_HDRP
			// HDRP needs a different way to unproject to world space. I tried to put this code into URP but it didnt work on 2019.3.0f1
			PositionInputs posInput = GetPositionInput(refractedPositionSS, _ScreenSize.zw, sceneZRefractDevice, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
			o_scenePositionWS = posInput.positionWS;
#if (SHADEROPTIONS_CAMERA_RELATIVE_RENDERING != 0)
			o_scenePositionWS += _WorldSpaceCameraPos;
#endif
#else
			o_scenePositionWS = ComputeWorldSpacePosition(screenPosRefract, sceneZRefractDevice, UNITY_MATRIX_I_VP);
#endif // CREST_HDRP
		}
		else
		{
			float deviceSceneZ = i_deviceSceneZ;

#if CREST_WATER_VOLUME_HAS_BACKFACE
			float backfaceZ = LOAD_DEPTH_TEXTURE_X(_CrestWaterVolumeBackFaceTexture, positionSS);
			if (backfaceZ > deviceSceneZ)
			{
				deviceSceneZ = backfaceZ;
			}
			else
#endif
			{
				deviceSceneZ = CREST_MULTILOAD_SCENE_DEPTH(positionSS, i_deviceSceneZ);
			}


			// It seems that when MSAA is enabled this can sometimes be negative
			o_sceneDistance = max(CrestLinearEyeDepth(deviceSceneZ) - i_pixelZ, 0.0);

			o_sceneColour = i_sceneColourUnrefracted;

#if CREST_HDRP
			// HDRP needs a different way to unproject to world space. I tried to put this code into URP but it didnt work on 2019.3.0f1
			PositionInputs posInput = GetPositionInput(positionSS, _ScreenSize.zw, i_deviceSceneZ, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
			o_scenePositionWS = posInput.positionWS;
#if (SHADEROPTIONS_CAMERA_RELATIVE_RENDERING != 0)
			o_scenePositionWS += _WorldSpaceCameraPos;
#endif
#else
			o_scenePositionWS = ComputeWorldSpacePosition(i_screenPos.xy, i_deviceSceneZ, UNITY_MATRIX_I_VP);
#endif // CREST_HDRP
		}

#if CREST_WATER_VOLUME_HAS_BACKFACE
		if (!caustics)
		{
			o_scenePositionWS.y = 100000;
		}
#endif
	}
	else
	{
		float2 screenPos = i_screenPos.xy;
		float deviceZ = i_deviceSceneZ;

		if (sceneZRefract > i_pixelZ)
		{
			screenPos = screenPosRefract;
			deviceZ = sceneZRefractDevice;
		}

		// Depth fog is handled by underwater shader
		o_sceneDistance = i_pixelZ;
		o_sceneColour = SHADERGRAPH_SAMPLE_SCENE_COLOR(screenPos);

#if CREST_HDRP
		// HDRP needs a different way to unproject to world space. I tried to put this code into URP but it didnt work on 2019.3.0f1
		PositionInputs posInput = GetPositionInput(screenPos * _ScreenSize.xy, _ScreenSize.zw, deviceZ, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
		o_scenePositionWS = posInput.positionWS;
#if (SHADEROPTIONS_CAMERA_RELATIVE_RENDERING != 0)
		o_scenePositionWS += _WorldSpaceCameraPos;
#endif
#else
		o_scenePositionWS = ComputeWorldSpacePosition(screenPos, deviceZ, UNITY_MATRIX_I_VP);
#endif // CREST_HDRP
	}

	//#endif // _TRANSPARENCY_ON
}
