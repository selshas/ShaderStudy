Shader "Custom/6/DoF_Bokeh"
{
    Properties
    {
        _DepthTexture ("DepthTexture", 2D) = "white" {}
        _BlurIntensity ("Blur Intensity", Range(0, 1)) = 0.1
        _FocalRange ("Focal Range", Range(0, 100)) = 10
        _FocalDistance ("Focal Distance", Range(0, 1000)) = 10
        [Toggle] _DbgCOC ("Debug - Display COC", int) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        ZWrite Off 

        Pass
        {
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #define SAMPLE_COUNT 64
            #define GOLDEN_ANGLE 2.39996322972865332 // ~137.5 degrees
            #define MAXRADIUS 8

            SAMPLER(sampler_BlitTexture);

            int _DbgCOC;

            CBUFFER_START(UnityPerMaterial)
                float _BlurIntensity;
                float _FocalRange;
                float _FocalDistance;
                TEXTURE2D(_DepthTexture);
                SAMPLER(sampler_DepthTexture);
            CBUFFER_END

            float getCoC(float depth)
            {
                return saturate(abs((depth - _FocalDistance) / _FocalRange));
            }

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // Sample the center pixel
                float4 center_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);
                float center_depth = LinearEyeDepth(SAMPLE_TEXTURE2D(_DepthTexture, sampler_DepthTexture, uv).r, _ZBufferParams);
                float center_coc = getCoC(center_depth);
                float center_blurSize = center_coc * _BlurIntensity * MAXRADIUS;
                float center_weight = 1.0;

                if (_DbgCOC == 1)
                {
                    float4 color = float4(0,0,0,1.0);
                    color.rgb = center_coc * _BlurIntensity;

                    return color;
                }

                if (center_blurSize == 0)
                {
                    //return float4(1,0,0,1);
                    return center_color;
                }

                float4 output_color = center_color;
                float totalWeight = center_weight;

                float radius = 0.5;
                for (int i = 0; radius < MAXRADIUS; i++)
                {
                    float theta = i * GOLDEN_ANGLE;
                    float2 offset = float2(cos(theta), sin(theta)) * _BlitTexture_TexelSize * radius;

                    float4 sample_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv + offset);
                    float sample_depth = LinearEyeDepth(SAMPLE_TEXTURE2D(_DepthTexture, sampler_DepthTexture, uv + offset).r, _ZBufferParams);
                    float sample_coc = getCoC(sample_depth);
                    //float sample_blurSize = sample_coc * _BlurIntensity * MAXRADIUS;
                    float sample_weight = (center_blurSize / radius) * ((sample_depth < center_depth) ? sample_coc : center_coc);

                    output_color += (sample_color * sample_weight);
                    totalWeight += sample_weight;
                    
                    radius = radius + (0.5 / radius);
                }
                    
                return float4(output_color.rgb / totalWeight, 1.0);
            }

            ENDHLSL
        }
    }
}
