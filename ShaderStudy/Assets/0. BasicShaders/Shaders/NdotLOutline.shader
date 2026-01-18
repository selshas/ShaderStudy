Shader "Custom/0/NdotLOutline"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        _Outline_width_min("Outline Width Min", Range(0, 1)) = 0.0
        _Outline_width_max("Outline Width Max", Range(0, 1)) = 5.0
    }
    
    HLSLINCLUDE

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

    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"}
        
        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

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
                float3 lightDir = normalize(_MainLightPosition.xyz);
                float3 normal = normalize(IN.normal);

                half3 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).xyz;
                float alpha = 1.0;
                
                float NDotL = dot(normal, lightDir);
                // NDotL = (NDotL + 1.0) * 0.5; // Half-Lambertian

                return float4(color * saturate(NDotL), alpha);
            }
            ENDHLSL
        }

        Pass
        {
            Tags { "LightMode" = "Outline" }

            Cull Front
            Blend One OneMinusSrcAlpha

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float _Outline_width_max;
                float _Outline_width_min;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                
                float3 l = _MainLightPosition.xyz;
                float3 n = mul(transpose(unity_WorldToObject), float4(IN.normal, 0)).xyz;
                float NDotL = saturate(dot(n, l));

                if (_Outline_width_min > _Outline_width_max)
                {
                    float tmp = _Outline_width_min;
                    _Outline_width_min = _Outline_width_max;
                    _Outline_width_max = tmp;
                }

                float3 positionOS = IN.positionOS.xyz;

                float width_delta = (_Outline_width_max - _Outline_width_min);
                if (width_delta > 0.0)
                {
                    float extrusion = (width_delta * (1.0 - NDotL)) + _Outline_width_min;
                    positionOS += IN.normal * extrusion;
                }

                OUT.positionHCS = TransformObjectToHClip(positionOS);
                OUT.positionWS = mul(unity_ObjectToWorld, IN.positionOS).xyz;
                OUT.normal = n;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 lightDir = normalize(_MainLightPosition.xyz);
                float3 n = normalize(IN.normal);

                float NDotL = dot(n, lightDir);
                
                half3 color_surface = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).xyz * saturate(NDotL);
                half3 color_outline = float3(0.0, 0.0, 0.0);
                float blend = 0.1;
                float alpha = 1.0;

                return float4(lerp(color_outline, color_surface, blend), alpha);
            }
            ENDHLSL
        }
    }
}
