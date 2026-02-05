Shader "Custom/8/ChromaticAberration"
{
    Properties
    {
        _Roundness ("Roundness", Range(0, 1)) = 1
        _Hardness ("Hardness", Range(0, 1)) = 0
        _Intensity ("Intensity", Range(0, 10)) = 1
        _DepthInfluence ("DepthInfluence", Range(0, 1)) = 0
        [KeywordEnum(Radial, Rotational, X, Y)] _Direction ("Direction", int) = 0
        [Toggle] _InversedOffset ("InversedOffset", int) = 0
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
                float _DepthInfluence;
                float _Direction;
                float _InversedOffset;
            CBUFFER_END

            half4 frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.texcoord.xy;
                float2 uv_centered = (uv - 0.5) * 2.0;

                // Apply Roundness
                float mask = length(pow(abs(uv_centered), (20 - 19 * _Roundness)));
                // Apply Hardness
                mask = pow(mask, max(0.05, _Hardness) * 20);

                if (_DepthInfluence == 0)
                {
                    mask = saturate(mask);
                }
                else
                {
                    float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, IN.texcoord).r;
                    mask = saturate(mask + depth * _DepthInfluence);
                }

                //return float4(mask, mask, mask, 1);


                float2 offset = float2(0, 0);

                // Radial
                if (_Direction == 0)
                {
                    offset = normalize(uv_centered) * _BlitTexture_TexelSize * _Intensity;
                }
                // Rotational
                else if (_Direction == 1)
                {
                    float2 direction = normalize(uv_centered);
                    offset = float2(-direction.y, direction.x) * _BlitTexture_TexelSize * _Intensity;
                }
                // X
                else if (_Direction == 2)
                {
                    offset = float2(_BlitTexture_TexelSize.x, 0) * _Intensity;
                }
                // Y
                else if (_Direction == 3)
                {
                    offset = float2(0, _BlitTexture_TexelSize.y) * _Intensity;
                }

                if (_InversedOffset == 0)
                {
                    offset *= -1;    
                }
                
                float r = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord + offset * mask).r;
                float g = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord).g;
                float b = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord - offset * 1.5 * mask).b;

                return float4(r, g, b, 1.0);
            }
            ENDHLSL
        }
    }
}
