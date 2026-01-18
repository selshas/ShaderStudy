Shader "Custom/0/StencilTest"
{
    Properties
    {
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        ColorMask 0
        ZWrite Off

        Pass
        {
            Stencil
            {
                Ref 1
                Comp Always
                Pass Replace
            }
        }
    }
}
