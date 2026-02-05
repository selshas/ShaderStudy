using System.ComponentModel.Design.Serialization;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class ChromaticAberrationRenderFeature : ScriptableRendererFeature
{
    public class RenderPass : ScriptableRenderPass
    {
        public Material Material;

        private class PassData
        {
            public Material Material;
            public TextureHandle SrcTextureHnd;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var camOpaqueTextureHnd = resourceData.cameraOpaqueTexture;

            using (var grphBuilder = renderGraph.AddRasterRenderPass<PassData>("ChromaticAberration Pass", out var passData))
            {
                passData.SrcTextureHnd = camOpaqueTextureHnd;
                passData.Material = Material;

                grphBuilder.UseTexture(passData.SrcTextureHnd);
                grphBuilder.SetRenderAttachment(resourceData.cameraColor, 0);
                grphBuilder.SetRenderFunc<PassData>((passData, context) =>
                {
                    Blitter.BlitTexture(context.cmd, passData.SrcTextureHnd, new Vector4(1, 1, 0, 0), passData.Material, 0);
                });
            }
        }
    }

    private RenderPass renderPass;

    public Material Material;

    public override void Create()
    {
        renderPass = new RenderPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing,

            Material = Material
        };
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(renderPass);
    }
}
