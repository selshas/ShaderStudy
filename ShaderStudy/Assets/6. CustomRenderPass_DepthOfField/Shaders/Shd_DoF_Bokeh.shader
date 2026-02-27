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
        
        // Pass 1: BlurPass
        Pass
        {
            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment frag
            
            SAMPLER(sampler_BlitTexture);

            float2 _DepthTexture_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                TEXTURE2D(_DepthTexture);
                SAMPLER(sampler_DepthTexture);
            CBUFFER_END

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // Sample the center pixel
                float4 center_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);
                float center_depth = LinearEyeDepth(SAMPLE_TEXTURE2D(_DepthTexture, sampler_DepthTexture, uv).r, _ZBufferParams);
                float center_coc = getCoC(center_depth, _FocalDistance, _FocalRange);
                float center_blurSize = center_coc * _BlurIntensity * MAXRADIUS;
                float center_weight = abs(center_coc);

                float4 bg_color = 0;
                float bg_totalWeight = 0;
                
                float4 fg_color = 0;
                float fg_totalWeight = 0;
                
                float radius = 0.5;
                for (int i = 0; i < SAMPLE_COUNT; i++)
                {
                    float kernel_radius = sqrt(i/(float)SAMPLE_COUNT);
                    radius = kernel_radius * MAXRADIUS;
                
                    float theta = (i * GOLDEN_ANGLE);
                    float2 offset = float2(cos(theta), sin(theta)) * radius * _BlitTexture_TexelSize;

                    float4 sample_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv + offset);
                    float sample_depth = LinearEyeDepth(SAMPLE_TEXTURE2D(_DepthTexture, sampler_DepthTexture, uv + offset).r, _ZBufferParams);
                    float sample_coc = getCoC(sample_depth, _FocalDistance, _FocalRange);
                    float sample_blurSize = sample_coc * _BlurIntensity * MAXRADIUS;

                    float sample_bg_weight = saturate((max(0, min(center_blurSize, sample_blurSize)) - radius + 2) * 0.5);
                    float sample_fg_weight = saturate((-sample_blurSize - radius + 2) * 0.5);

                    //sample_fg_weight *= step(_DepthTexture_TexelSize.y * 2, sample_blurSize);

                    bg_color += sample_color * sample_bg_weight;
                    bg_totalWeight += sample_bg_weight;

                    fg_color += sample_color * sample_fg_weight;
                    fg_totalWeight += sample_fg_weight;
				}
                
                bg_color = max(0, bg_color * (1 / bg_totalWeight + (bg_totalWeight == 0.0)));
                fg_color = max(0, fg_color * (1 / fg_totalWeight + (fg_totalWeight == 0.0)));
                
                if (_DbgDisplayMode != 0)
                {
                    if (_DbgDisplayMode == 2)
                    {
                        return fg_color;
                    }
                    else if (_DbgDisplayMode == 3)
                    {
                        return bg_color;
                    }
                }

                float blend = min(1, fg_totalWeight * PI / SAMPLE_COUNT);
                float4 output_color = lerp(bg_color, fg_color, blend);

                return float4(output_color.rgb, blend);
            }

            ENDHLSL
        }

        // Pass 2: CompositePass
        Pass
        {
            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            #pragma vertex Vert
            #pragma fragment frag
            
            SAMPLER(sampler_BlitTexture);
            float2 _BlurredTexture_TexelSize;
            
            CBUFFER_START(UnityPerMaterial)
                TEXTURE2D(_BlurredTexture);
                SAMPLER(sampler_BlurredTexture);
                int _EnablePostFilter;
            CBUFFER_END

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float depth = LinearEyeDepth(SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_LinearClamp, uv).r, _ZBufferParams);
                float coc = getCoC(depth, _FocalDistance, _FocalRange);
                if (_DbgDisplayMode != 0)
                {
                    if (_DbgDisplayMode == 1)
                    {
                        coc = abs(coc);
                        return float4(coc, coc, coc, 1.0);
                    }
                    else
                    {
                        return SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, uv);
                    }
                }
                
                float4 color_sharp = SAMPLE_TEXTURE2D(_BlitTexture, sampler_BlitTexture, uv);
                float4 color_blur;

                if (_EnablePostFilter)
                {
                    float4 offset = float2(0.5, -0.5).xxyy * _BlurredTexture_TexelSize.xyxy;
                    
                    color_blur = (
                          SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, uv + offset.zw)
                        + SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, uv + offset.xw)
                        + SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, uv + offset.xy)
                        + SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, uv + offset.zy)
                    ) * 0.25;
                }
                else
                {
                    color_blur = SAMPLE_TEXTURE2D(_BlurredTexture, sampler_BlurredTexture, uv);
                }

                float d = abs(coc);
                float blend = d + color_blur.a - d * color_blur.a;

                float3 color = lerp(color_sharp.rgb, color_blur.rgb, blend);
                return float4(color.rgb, color_sharp.a);
            }

            ENDHLSL
        }

        // Pass 3: FGBGSeparationPass
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
                    float bg_coc = saturate(-coc);
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

        // Pass 4: CompositePass 2
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

                TEXTURE2D(_BGTexture);
                SAMPLER(sampler_BGTexture);
            CBUFFER_END

            float4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                
                float4 bg_color = SAMPLE_TEXTURE2D(_BGTexture, sampler_BGTexture, uv);
                float4 fg_color = SAMPLE_TEXTURE2D(_FGTexture, sampler_FGTexture, uv);
                
                if (_DbgDisplayMode != 0)
                {
                    if (_DbgDisplayMode == 2)
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
