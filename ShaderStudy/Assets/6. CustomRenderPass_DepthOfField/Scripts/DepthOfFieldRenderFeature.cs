using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class DepthOfFieldRenderFeature : ScriptableRendererFeature
{
    public class RenderPass : ScriptableRenderPass
    {
        private class GrabPassData
        {
            public TextureHandle SrcTextureHnd;
            public TextureHandle DstTextureHnd;
        }
        private class BlitPassData
        {
            public Material Material;
            public TextureHandle SrcTextureHnd;
            public TextureHandle SrcDepthTextureHnd;
            public TextureHandle DstTextureHnd;

            public float FocalRange;
            public float FocalDistance;
        }

        public Material Material_DOFBlit;
        public float FocalRange;
        public float FocalDistance;

        private void RecordBlurPass(RenderGraph renderGraph, TextureHandle srcTextureHnd, TextureHandle srcDepthTextureHnd, TextureHandle dstTextureHnd)
        {
            using (var grphBuilder = renderGraph.AddRasterRenderPass<BlitPassData>("DoFApplyingBlit", out var passData))
            {
                passData.Material = Material_DOFBlit;
                passData.SrcTextureHnd = srcTextureHnd;
                passData.SrcDepthTextureHnd = srcDepthTextureHnd;
                passData.DstTextureHnd = dstTextureHnd;
                passData.FocalDistance = FocalDistance;
                passData.FocalRange = FocalRange;

                grphBuilder.UseTexture(passData.SrcTextureHnd, AccessFlags.ReadWrite);
                grphBuilder.UseTexture(passData.SrcDepthTextureHnd);
                grphBuilder.SetRenderAttachment(passData.DstTextureHnd, 0);
                grphBuilder.SetRenderFunc<BlitPassData>(static (passData, context) =>
                {
                    passData.Material.SetTexture("_DepthTexture", passData.SrcDepthTextureHnd);
                    passData.Material.SetFloat("_FocalDistance", passData.FocalDistance);
                    passData.Material.SetFloat("_FocalRange", passData.FocalRange);
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.SrcTextureHnd,
                        new Vector4(1, 1, 0, 0),
                        passData.Material, 0
                    );
                });
            }
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            var cameraGrabTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(cameraData.scaledWidth, cameraData.scaledHeight), "CameraGrab",
                false,
                FilterMode.Bilinear, TextureWrapMode.Clamp
            );

            using (var grphBuilder = renderGraph.AddRasterRenderPass<GrabPassData>("DoFCameraGrab", out var passData))
            {
                passData.SrcTextureHnd = resourceData.cameraColor;
                passData.DstTextureHnd = cameraGrabTextureHnd;

                grphBuilder.UseTexture(passData.SrcTextureHnd);
                grphBuilder.SetRenderAttachment(cameraGrabTextureHnd, 0);
                grphBuilder.SetRenderFunc<GrabPassData>((passData, context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.SrcTextureHnd,
                        new Vector4(1, 1, 0, 0),
                        0, false
                    );
                });
            }

            RecordBlurPass(renderGraph, cameraGrabTextureHnd, resourceData.activeDepthTexture, resourceData.cameraColor);
            RecordBlurPass(renderGraph, resourceData.cameraColor, resourceData.activeDepthTexture, cameraGrabTextureHnd);
            RecordBlurPass(renderGraph, cameraGrabTextureHnd, resourceData.activeDepthTexture, resourceData.cameraColor);
        }
    }

    private RenderPass renderPass;

    public Material Material_DOFBlit;
    [Range(0, 10)]
    public float FocalRange = 10f;
    [Range(0, 50)]
    public float FocusDistance = 10f;

    public override void Create()
    {
        renderPass = new RenderPass() {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing,
            Material_DOFBlit = Material_DOFBlit,
            FocalDistance = FocusDistance,
            FocalRange = FocalRange,
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(renderPass);
    }
}
