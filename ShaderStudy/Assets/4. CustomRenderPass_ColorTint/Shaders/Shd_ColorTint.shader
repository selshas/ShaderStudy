Shader "Custom/4/ColorTint"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
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

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            float4 _Color;
            SAMPLER(sampler_BlitTexture);

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, IN.texcoord) * _Color;
                return float4(color.rgb, 1.0);
            }

            ENDHLSL
        }
    }
}
