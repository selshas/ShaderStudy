Shader "Custom/5/Blur"
{
    Properties
    {
        [KeywordEnum(Horizontal, Vertical)] _Direction ("Direction", Integer) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "PreviewType"="Plane" }

        ZWrite Off
        Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            HLSLPROGRAM

            #define Dir_Horizontal 0
            #define Dir_Vertical 1

            #define HALFKERNELSIZE 4

            #pragma vertex Vert
            #pragma fragment frag

            #define STD_RESOLUTION_HEIGHT 1080

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"

            SAMPLER(sampler_BlitTexture);

            TEXTURE2D(_EmissionDepthTexture);
            SAMPLER(sampler_EmissionDepthTexture);
            
            CBUFFER_START(UnityPerMaterial)
                int _Direction;
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
           
            float gaussian(float sig, float x)
            {
                if (sig == 0)
                    return 0;

                float sig_sqr = sig * sig;
                return exp(-(x * x) / (2.0 * sig_sqr)) / sqrt(2.0 * 3.14159265 * sig_sqr);
            }

            float depthToBrightness(float depth)
            {
                if (unity_OrthoParams.w == 0)
                {
                    return (1.0 - Linear01Depth(depth, _ZBufferParams) - 0.75) * 4.0;
                }

                return depth;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                //depth = 1.0 - Linear01Depth(depth, _ZBufferParams);

                //return float4(depth, depth, depth, 1);
                //float sigma = 1 + (HALFKERNELSIZE * 2 - 1) * depth;

                float2 direction = ((_Direction == Dir_Horizontal) 
                    ? float2(_BlitTexture_TexelSize.x, 0) 
                    : float2(0, _BlitTexture_TexelSize.y));
                
                float4 color = float4(SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord).rgb * weights[0], weights[0]);
                float depth_o = SAMPLE_TEXTURE2D(_EmissionDepthTexture, sampler_EmissionDepthTexture, IN.texcoord).r;
                color.rgb *= depthToBrightness(depth_o);
                for (int i = 1; i < 4; i++)
                {
                    float2 offset = direction * offsets[i];
                    
                    float depth_r = SAMPLE_TEXTURE2D(_EmissionDepthTexture, sampler_EmissionDepthTexture, IN.texcoord + offset).r;
                    float depth_l = SAMPLE_TEXTURE2D(_EmissionDepthTexture, sampler_EmissionDepthTexture, IN.texcoord - offset).r;

                    float weight_r = lerp(weights_sharp[i], weights[i], depth_r);
                    float weight_l = lerp(weights_sharp[i], weights[i], depth_l);

                    color.rgb += SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, saturate(IN.texcoord + offset)).rgb * depthToBrightness(depth_r) * weight_r;
                    color.rgb += SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, saturate(IN.texcoord - offset)).rgb * depthToBrightness(depth_l) * weight_l;
                    color.w += weight_r + weight_l;
                }

                color /= color.w;
                
                return color;
            }

            ENDHLSL
        }
    }
}
