Shader "Custom/0/BasicNdotL"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal: NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normal : TEXCOORD2;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = mul(unity_ObjectToWorld, IN.positionOS).xyz;
                OUT.normal = mul(transpose(unity_WorldToObject), float4(IN.normal, 0)).xyz;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 lightDir = _MainLightPosition.xyz;
                float3 n = normalize(IN.normal);
                half3 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).xyz;
                float alpha = 1.0;
                
                float NDotL = dot(n, lightDir);
                // NDotL = (NDotL + 1.0) * 0.5; // Half-Lambertian

                return float4(color * saturate(NDotL), alpha);
            }
            ENDHLSL
        }
    }
}
