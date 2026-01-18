Shader "Custom/1/Fire"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)

        [MainTexture] _BaseTexture("Base Texture", 2D) = "white"
        _SubTexture("Sub Texture", 2D) = "white"
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            //"Queue"="Geometry" 
            "Queue"="Transparent" 
            "RenderPipeline" = "UniversalPipeline" 
            "PreviewType"="Plane"
        }

        Pass
        {
            ZWrite Off
            //Blend One One
            Blend SrcAlpha OneMinusSrcAlpha
            CULL Off

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv0 : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
            };

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture);

            TEXTURE2D(_SubTexture);
            SAMPLER(sampler_SubTexture);


            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseTexture_ST;
                float4 _SubTexture_ST;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv0 = TRANSFORM_TEX(IN.uv, _BaseTexture);
                OUT.uv1 = TRANSFORM_TEX(IN.uv, _SubTexture);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 main = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, IN.uv0) * _BaseColor;
                
                float2 uv1 = IN.uv1;
                uv1.y -= _Time * 16;
                half4 sub = SAMPLE_TEXTURE2D(_SubTexture, sampler_SubTexture, uv1) * _BaseColor;

                float4 color = main + sub;
                color.a = min(main.a, sub.a);
                return color;
            }
            ENDHLSL
        }
    }
}
