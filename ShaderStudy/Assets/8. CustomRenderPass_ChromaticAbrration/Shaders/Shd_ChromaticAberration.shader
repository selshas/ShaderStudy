Shader "Custom/8/ChromaticAberration"
{
    Properties
    {
        _Roundness ("Roundness", Range(0, 1)) = 1
        _Hardness ("Hardness", Range(0, 1)) = 0
        _Intensity ("Intensity", Range(0, 1)) = 1
        [Toggle] _IncludeDepth ("_IncludeDepth", int) = 0
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"


            SAMPLER(sampler_BlitTexture);

            CBUFFER_START(UnityPerMaterial)
                float _Roundness;
                float _Hardness;
                float _Intensity;
                bool _IncludeDepth;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord.xy;
                float2 uv_centered = (uv - 0.5) * 2.0;
                float mask = length(
                    pow(
                        abs(uv_centered), 
                        (20 - 19 * _Roundness)
                    )
                );
                mask = pow(mask, max(0.05, _Hardness) * 20);
                if (_IncludeDepth)
                {
                    float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, IN.texcoord).r;
                    mask = saturate(mask * _Intensity + depth);
                }
                else
                {
                    mask = saturate(mask * _Intensity);
                }

                //return float4(mask, mask, mask, 1);

                float2 xOffset = float2(_BlitTexture_TexelSize.x, 0) * 6;
                float2 yOffset = float2(0, _BlitTexture_TexelSize.y) * 6;

                float r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord + xOffset * mask).r;
                float g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord - xOffset * mask).g;
                float b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord).b;

                return float4(r, g, b, 1.0);
            }
            ENDHLSL
        }
    }
}
