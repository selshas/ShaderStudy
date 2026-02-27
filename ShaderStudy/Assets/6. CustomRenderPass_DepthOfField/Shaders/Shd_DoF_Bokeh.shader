Shader "Custom/6/DoF_Bokeh"
{
    HLSLINCLUDE

        #define SAMPLE_COUNT 64
        #define GOLDEN_ANGLE 2.39996322972865332 // ~137.5 degrees
        #define PI 3.14159265359
        #define MAXRADIUS 8
        
        float getCoC(float depth, float focalDistance, float focalRange)
        {
            float coc = (depth - focalDistance) / focalRange;
            return clamp(coc, -1, 1);
        }
        
        float _FocalRange;
        float _FocalDistance;
        float _BlurIntensity;
        int _EnablePostFilter;

        int _DbgDisplayMode;

    ENDHLSL

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        //Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off 
        
        // Pass 0: GrabPass
        Pass
        {
            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            #pragma vertex Vert
            #pragma fragment FragBilinear

            ENDHLSL
        }
        
        // Pass 1: FGBGSeparatedBlurPass
        Pass
        {
            Name "FGBG Separation"

            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #pragma vertex Vert
            #pragma fragment frag
            

            CBUFFER_START(UnityPerMaterial)
                SAMPLER(sampler_BlitTexture);
                float2 _DepthTexture_TexelSize;
            CBUFFER_END
            
            struct Result
            {
                float4 bg : SV_Target0;
                float4 fg : SV_Target1;
            };

            struct SeparatedSample
            {
                float4 bg_color;
                float4 fg_color;
                
                float coc;
            };

            #define GETBOKEHSAMPLE(texName_color, texName_depth, uv) GetBokehSample(texName_color, sampler##texName_color, texName_depth, sampler##texName_depth, uv)
            SeparatedSample GetBokehSample(texture2D colorTexture, SamplerState colorTexture_sampler, texture2D depthTexture, SamplerState depthTexture_sampler, float2 uv)
            {
                SeparatedSample o;

                float4 color = SAMPLE_TEXTURE2D(colorTexture, colorTexture_sampler, uv);
                float depth = LinearEyeDepth(SAMPLE_TEXTURE2D(depthTexture, depthTexture_sampler, uv).r, _ZBufferParams);
                float coc = getCoC(depth, _FocalDistance, _FocalRange);

                if (coc >= 0.0)
                {
                    float bg_coc = saturate(coc);
                    o.bg_color = color * bg_coc;
                    o.fg_color = 0.0;
                }
                else
                {
                    float fg_coc = saturate(-coc);
                    o.bg_color = 0.0;
                    o.fg_color = color * fg_coc;
                }
                o.coc = coc;

                return o;
            }

            Result frag(Varyings input)
            {
                Result r;

                float2 uv = input.texcoord;

                SeparatedSample center = GETBOKEHSAMPLE(_BlitTexture, _CameraDepthTexture, uv);
                float center_blurSize = abs(center.coc) * _BlurIntensity * MAXRADIUS;
                

                float bg_totalWeight = 1.0;
                float fg_totalWeight = 1.0;
                for (int i = 1; i < SAMPLE_COUNT; i++)
                {
                    float theta = i * GOLDEN_ANGLE;
                    float radius = sqrt(i / (float)SAMPLE_COUNT) * MAXRADIUS;
                    float2 offset = float2(cos(theta), sin(theta)) * radius * _BlitTexture_TexelSize;

                    SeparatedSample sample = GETBOKEHSAMPLE(_BlitTexture, _CameraDepthTexture, uv + offset);
                    
                    float sample_blurSize = abs(sample.coc) * _BlurIntensity * MAXRADIUS;
                    float bg_weight = saturate(((min(center_blurSize, sample_blurSize) - radius) + 2) * 0.5);
                    float fg_weight = saturate(((sample_blurSize - radius) + 2) * 0.5);

                    center.bg_color += sample.bg_color * bg_weight;
                    center.fg_color += sample.fg_color * fg_weight;

                    bg_totalWeight += bg_weight;
                    fg_totalWeight += fg_weight;
                }

                r.bg = center.bg_color * (1.0 / bg_totalWeight);
                r.fg = center.fg_color * (1.0 / fg_totalWeight);

                return r;
            }

            ENDHLSL
        }

        // Pass 2: CompositePass
        Pass
        {
            //Blend SrcAlpha OneMinusSrcAlpha
            Blend One OneMinusSrcAlpha

            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            
            #pragma vertex Vert
            #pragma fragment frag

            CBUFFER_START(UnityPerMaterial)
                TEXTURE2D(_FGTexture);
                SAMPLER(sampler_FGTexture);
                float2 _FGTexture_TexelSize;

                TEXTURE2D(_BGTexture);
                SAMPLER(sampler_BGTexture);
                float2 _BGTexture_TexelSize;
            CBUFFER_END

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                
                float4 bg_color;
                float4 fg_color;
                
                if (_EnablePostFilter)
                {
                    float4 bg_offset = float2(0.5, -0.5).xxyy * _BGTexture_TexelSize.xyxy;
                    float4 fg_offset = float2(0.5, -0.5).xxyy * _FGTexture_TexelSize.xyxy;
                    
                    bg_color = (
                          SAMPLE_TEXTURE2D(_BGTexture, sampler_BGTexture, uv + bg_offset.zw)
                        + SAMPLE_TEXTURE2D(_BGTexture, sampler_BGTexture, uv + bg_offset.xw)
                        + SAMPLE_TEXTURE2D(_BGTexture, sampler_BGTexture, uv + bg_offset.xy)
                        + SAMPLE_TEXTURE2D(_BGTexture, sampler_BGTexture, uv + bg_offset.zy)
                    ) * 0.25;
                    
                    fg_color = (
                          SAMPLE_TEXTURE2D(_FGTexture, sampler_FGTexture, uv + fg_offset.zw)
                        + SAMPLE_TEXTURE2D(_FGTexture, sampler_FGTexture, uv + fg_offset.xw)
                        + SAMPLE_TEXTURE2D(_FGTexture, sampler_FGTexture, uv + fg_offset.xy)
                        + SAMPLE_TEXTURE2D(_FGTexture, sampler_FGTexture, uv + fg_offset.zy)
                    ) * 0.25;
                }
                else
                {
                    bg_color = SAMPLE_TEXTURE2D(_BGTexture, sampler_BGTexture, uv);
                    fg_color = SAMPLE_TEXTURE2D(_FGTexture, sampler_FGTexture, uv);
                }
                
                if (_DbgDisplayMode != 0)
                {
                    if (_DbgDisplayMode == 1)
                    {
                        return (fg_color + bg_color * (1.0 - fg_color.a)).a;
                    }
                    else if (_DbgDisplayMode == 2)
                    {
                        return float4(fg_color.rgb, 1.0);
                    }
                    else if (_DbgDisplayMode == 3)
                    {
                        return float4(bg_color.rgb, 1.0);
                    }
                }

                return fg_color + bg_color * (1.0 - fg_color.a);
            }

            ENDHLSL
        }
    }
}
