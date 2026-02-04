Shader "Custom/7/Shd_BokehBlur"
{
    Properties
    {
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            SAMPLER(sampler_BlitTexture);

            CBUFFER_START(UnityPerMaterial)
            CBUFFER_END

            #define SAMPLE_COUNT 32
            #define GOLDEN_ANGLE 2.39996322972865332; // ~137.5 degrees in radians

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord);

                for (int i = 0; i < SAMPLE_COUNT; i++)
                {
                    float theta = i * GOLDEN_ANGLE;
                    float radius = sqrt(i) + 0.5;
                    float2 offset = float2(cos(theta), sin(theta)) * _BlitTexture_TexelSize.xy * radius;
                    float4 colorSample = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord + offset);
                    color += colorSample;
                }

                return color / (SAMPLE_COUNT + 1);
            }
            ENDHLSL
        }
    }
}
