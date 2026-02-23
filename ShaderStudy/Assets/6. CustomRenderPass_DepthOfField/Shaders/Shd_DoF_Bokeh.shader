Shader "Custom/6/DoF_Bokeh"
{
    Properties
    {
        _DepthTexture ("Depth Texture", 2D) = "white" {}
        _BlurIntensity ("Blur Intensity", Range(0, 1)) = 0.1
        _FocalRange ("Focal Range", Range(0, 100)) = 10
        _FocalDistance ("Focal Distance", Range(0, 1000)) = 10
        _BlurredTexture ("Blurred Texture", 2D) = "white" {}
        [Toggle] _EnablePostFilter ("Enable PostFilter", int) = 0
        [KeywordEnum(Blended, COC, Foreground, Background)] _DbgDisplayMode ("Debug - Display Mode", int) = 0
    }

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

            int _DbgDisplayMode;

            float2 _DepthTexture_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                float _BlurIntensity;
                float _FocalRange;
                float _FocalDistance;
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
                float _FocalDistance;
                float _FocalRange;
                int _EnablePostFilter;
                int _DbgDisplayMode;
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
    }
}
