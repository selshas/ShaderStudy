Shader "Custom/6/DoF_Gaussian"
{
    Properties
    {
        _DepthTexture ("DepthTexture", 2D) = "white" {}
        _FocalRange ("Focal Range", Range(0, 100)) = 10
        _FocalDistance ("Focal Distance", Range(0, 1000)) = 10
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

            SAMPLER(sampler_BlitTexture);

            CBUFFER_START(UnityPerMaterial)
                float _FocalRange;
                float _FocalDistance;
                TEXTURE2D(_DepthTexture);
                SAMPLER(sampler_DepthTexture);
            CBUFFER_END
            
            static const float offsets[4] = {
                0, 1.41176470588, 3.29411764706, 5.17647058824
            };
            static const float weights[4] = {
                0.196482550151, 0.296906964673, 0.0944703978504, 0.0103813624011
            };
            static const float weights_sharp[4] = {
                1.0, 0.0, 0.0, 0.0
            };

            float gaussian(float sig, float x, float y)
            {
                if (sig == 0)
                    return 0;

                float sig_sqr = sig * sig;
                return exp(-(x * x + y * y) / (2.0 * sig_sqr)) / sqrt(2.0 * 3.14159265 * sig_sqr);
            }

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // Sample the center pixel
                float depth = SAMPLE_TEXTURE2D(_DepthTexture, sampler_DepthTexture, uv).r;
                depth = LinearEyeDepth(depth, _ZBufferParams);
                float distanceFromFocus = (_FocalRange == 0)
                    ? 1.0 
                    : min(abs(depth - _FocalDistance), _FocalRange) / _FocalRange;

                float4 color = float4(0,0,0,0);

                /*
                // Debug: visualize the distance from focus
                color.rgb = distanceFromFocus;
                color.a = 1.0;
                return color;
                */

                // Sample the surrounding pixels with chosen blur algorithm.
                for (int i = -3; i < 4; i++)
                {
                    for (int j = -3; j < 4; j++)
                    {
                        float weight = gaussian(distanceFromFocus, i, j);
                        color += SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv + _BlitTexture_TexelSize.xy * float2(i, j)) * weight;
                    }
                }

                color /= color.w;

                return color;
            }

            ENDHLSL
        }
    }
}
