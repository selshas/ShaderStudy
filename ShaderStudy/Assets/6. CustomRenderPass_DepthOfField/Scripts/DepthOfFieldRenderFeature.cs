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
            public Material Material;
            public TextureHandle SrcTextureHnd;
            public TextureHandle DstTextureHnd;
        }
        private class SeparatedBlurPassData
        {
            public Material Material;

            public TextureHandle CamColorTextureHnd;
            public TextureHandle CamDepthTextureHnd;
            public TextureHandle DstBGTextureHnd;
            public TextureHandle DstFGTextureHnd;

            public float BlurIntensity;
            public float FocalRange;
            public float FocalDistance;
        }
        private class CompositePassData
        {
            public Material Material;
            public TextureHandle FGTextureHnd;
            public TextureHandle BGTextureHnd;
            
            public bool EnablePostFilter;

            public DOFDisplayMode DisplayMode;
        }


        public Material Material_DOFBlit;
        public float BlurIntensity;
        public float FocalRange;
        public float FocalDistance;
        public DOFDisplayMode DisplayMode;
        public bool EnablePostFilter;

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            var camColorDesc = resourceData.cameraColor.GetDescriptor(renderGraph);

            var cameraGrabTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(camColorDesc.width, camColorDesc.height, RenderTextureFormat.ARGBHalf), "CameraGrab",
                false,
                FilterMode.Bilinear, TextureWrapMode.Clamp
            );

            var blurredTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(camColorDesc.width / 2, camColorDesc.height / 2, RenderTextureFormat.ARGBHalf), "Result",
                false,
                FilterMode.Bilinear, TextureWrapMode.Clamp
            );

            using (var grphBuilder = renderGraph.AddRasterRenderPass<GrabPassData>("DoF - CameraGrab", out var passData))
            {
                passData.SrcTextureHnd = resourceData.cameraColor;
                passData.DstTextureHnd = cameraGrabTextureHnd;
                passData.Material = Material_DOFBlit;

                grphBuilder.UseTexture(passData.SrcTextureHnd);
                grphBuilder.SetRenderAttachment(cameraGrabTextureHnd, 0);
                grphBuilder.SetRenderFunc<GrabPassData>((passData, context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        passData.SrcTextureHnd,
                        new Vector4(1, 1, 0, 0),
                        passData.Material, 0
                    );
                });
            }


            var bgTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(camColorDesc.width / 2, camColorDesc.height / 2, RenderTextureFormat.DefaultHDR), "Background",
                false,
                FilterMode.Bilinear, TextureWrapMode.Clamp
            );
            var fgTextureHnd = UniversalRenderer.CreateRenderGraphTexture(
                renderGraph,
                new RenderTextureDescriptor(camColorDesc.width / 2, camColorDesc.height / 2, RenderTextureFormat.DefaultHDR), "Foreground",
                false,
                FilterMode.Bilinear, TextureWrapMode.Clamp
            );

            using (var grphBuilder = renderGraph.AddRasterRenderPass<SeparatedBlurPassData>("DoF - SeparatedBlur", out var passData))
            {
                passData.Material = Material_DOFBlit;

                passData.CamColorTextureHnd = resourceData.cameraColor;
                passData.CamDepthTextureHnd = resourceData.cameraDepth;
                passData.FocalDistance = FocalDistance;
                passData.FocalRange = FocalRange;
                passData.BlurIntensity = BlurIntensity;

                grphBuilder.UseTexture(passData.CamColorTextureHnd);
                grphBuilder.UseTexture(passData.CamDepthTextureHnd);
                grphBuilder.SetRenderAttachment(bgTextureHnd, 0);
                grphBuilder.SetRenderAttachment(fgTextureHnd, 1);
                grphBuilder.SetRenderFunc<SeparatedBlurPassData>((passData, context) =>
                {
                    passData.Material.SetFloat("_FocalDistance", passData.FocalDistance);
                    passData.Material.SetFloat("_FocalRange", passData.FocalRange);
                    passData.Material.SetFloat("_BlurIntensity", passData.BlurIntensity);

                    Blitter.BlitTexture(
                        context.cmd,
                        passData.CamColorTextureHnd,
                        new Vector4(1, 1, 0, 0),
                        passData.Material, 1
                    );
                });

                grphBuilder.AllowPassCulling(false);
            }

            using (var grphBuilder = renderGraph.AddRasterRenderPass<CompositePassData>("DoF - Composition", out var passData))
            {
                passData.FGTextureHnd = fgTextureHnd;
                passData.BGTextureHnd = bgTextureHnd;
                passData.DisplayMode = DisplayMode;
                passData.EnablePostFilter = EnablePostFilter;

                passData.Material = Material_DOFBlit;

                grphBuilder.UseTexture(passData.FGTextureHnd);
                grphBuilder.UseTexture(passData.BGTextureHnd);
                grphBuilder.SetRenderAttachment(resourceData.cameraColor, 0);
                grphBuilder.SetRenderFunc<CompositePassData>((passData, context) =>
                {
                    passData.Material.SetTexture("_FGTexture", passData.FGTextureHnd);
                    passData.Material.SetTexture("_BGTexture", passData.BGTextureHnd);
                    passData.Material.SetInt("_DbgDisplayMode", (int)passData.DisplayMode);
                    passData.Material.SetInt("_EnablePostFilter", passData.EnablePostFilter ? 1 : 0);

                    Blitter.BlitTexture(
                        context.cmd,
                        new Vector4(1, 1, 0, 0),
                        passData.Material, 2
                    );
                });
            }
        }
    }

    public enum DOFDisplayMode
    { 
        Blended = 0,
        COCVisualization = 1,
        Foreground = 2,
        Background = 3
    }

    private RenderPass renderPass;

    public Material Material_DOFBlit;
    [Range(0, 1)]
    public float BlurIntensity = 0.1f;
    [Range(0, 100)]
    public float FocalRange = 10f;
    [Range(0, 100)]
    public float FocusDistance = 10f;
    public DOFDisplayMode DisplayMode = DOFDisplayMode.Blended;
    public bool EnablePostFilter = true;

    public override void Create()
    {
        renderPass = new RenderPass() {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing,
            Material_DOFBlit = Material_DOFBlit,
            BlurIntensity = BlurIntensity,
            FocalDistance = FocusDistance,
            FocalRange = FocalRange,
            DisplayMode = DisplayMode,
            EnablePostFilter = EnablePostFilter,
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(renderPass);
    }
}
