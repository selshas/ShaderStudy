Shader "Custom/3/Vignette"
{
    Properties
    {
        [KeywordEnum(Elipse, Circle, Border)] _Type("Type", Integer) = 0
        _Roundness("Roundness", range(0.0, 1.0)) = 0.5
        _Smoothness("Smoothness", range(0.0, 1.0)) = 1.0
        _Intensity("Intensity", range(0.0, 1.0)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "PreviewType"="Plane" }

        ZWrite Off
        Cull Off
        Blend Off

        Pass
        {
            HLSLPROGRAM

            #define VignetteTypeElipse 0
            #define VignetteTypeCircle 1
            #define VignetteTypeBorder 2

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Type;
            float _Roundness;
            float _Intensity;
            float _Smoothness;

            half4 frag(Varyings IN) : SV_Target
            {
                float distance = 0.0;

                // Elipse
                if (_Type == VignetteTypeElipse)
                {
                    distance = length(IN.texcoord - float2(0.5, 0.5)) * 2 * _Intensity;
                    distance = pow(distance, (1.0 - _Intensity));
                }
                // Circle
                else if (_Type == VignetteTypeCircle)
                {
                    float2 centerSS = _ScreenParams.xy * 0.5;
                    float2 positionSS = IN.texcoord * _ScreenParams.xy;

                    distance = length(positionSS - centerSS) * 2 / _ScreenParams.y * _Intensity;
                    distance = saturate(distance);
                    distance = pow(distance, (1.0 - _Intensity));
                }
                // Border and Fallback
                else
                {
                    float2 d = saturate(abs(IN.texcoord - float2(0.5, 0.5)) * 2);
                    _Roundness = (1.0 + (1.0 - _Roundness) * 20);
                    d = pow(d, _Roundness);

                    distance = length(d) * _Intensity;
                }

                float vignette = saturate(1.0 - distance);
                vignette = pow(vignette, _Smoothness);
                vignette = pow(vignette, 2.2); // Gamma Correction
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, IN.texcoord) * vignette;
                return float4(color.rgb, 1.0);
            }

            ENDHLSL
        }
    }
}
