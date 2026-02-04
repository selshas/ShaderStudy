using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class BokehBlurRenderFeature : ScriptableRendererFeature
{
    private class RenderPass : ScriptableRenderPass
    {
        public Material Material_Bokeh;

        private class CameraGrabPassData
        {
            public TextureHandle SrcTextureHnd;
        }
        private class BokehPassData
        {
            public Material Material;
            public TextureHandle SrcTextureHnd;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraColorDesc = resourceData.cameraColor.GetDescriptor(renderGraph);

            var grapTextureHnd = UniversalRenderer.CreateRenderGraphTexture(renderGraph, new RenderTextureDescriptor(cameraColorDesc.width, cameraColorDesc.height), "GrabTexture", true, FilterMode.Bilinear, TextureWrapMode.Clamp);

            using (var grphBuilder = renderGraph.AddRasterRenderPass<CameraGrabPassData>("Bokeh - CameraGrab", out var passData))
            {
                passData.SrcTextureHnd = resourceData.cameraColor;

                grphBuilder.SetRenderAttachment(grapTextureHnd, 0);
                grphBuilder.SetRenderFunc<CameraGrabPassData>(static (passData, context) => 
                {
                    Blitter.BlitTexture(context.cmd, passData.SrcTextureHnd, new Vector4(1,1,0,0), 0, true);
                });

                grphBuilder.AllowPassCulling(false);
            }
            using (var grphBuilder = renderGraph.AddRasterRenderPass<BokehPassData>("Bokeh - Apply", out var passData))
            {
                passData.Material = Material_Bokeh;
                passData.SrcTextureHnd = grapTextureHnd;

                grphBuilder.UseTexture(grapTextureHnd);
                grphBuilder.SetRenderAttachment(resourceData.cameraColor, 0);
                grphBuilder.SetRenderFunc<BokehPassData>((passData, context) => 
                {
                    Blitter.BlitTexture(context.cmd, passData.SrcTextureHnd, new Vector4(1,1,0,0), passData.Material, 0);
                });
                grphBuilder.AllowPassCulling(false);
            }
        }
    }


    private RenderPass renderPass;

    public Material Material_Bokeh;

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(renderPass);
    }

    public override void Create()
    {
        renderPass = new RenderPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing,
            Material_Bokeh = Material_Bokeh
        };
    }
}
