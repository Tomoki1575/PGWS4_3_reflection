Shader "Custom/Shader_16_MyShader"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" { }

        _Alpha("Alpha", Range(0, 1)) = 0.5                          // 不透明度

        _RimColor("Rim Color", Color) = (0.5, 0.9, 1, 1)            // ふちの色
        _RimPower("Rim Powor", Range(0.5, 8)) = 3                   // ふちの細さ

        _WobbleSpeed("Wobble Speed", Range(0, 5)) = 2               // 揺れの速さ
        _WobbleAmount("Wobble Amount", Range(0, 0.2)) = 0.05        // 揺れの大きさ
        _WobbleFrequency("Wobble Frequency", Range(0, 20)) = 4      // 揺れの間隔
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off

            HLSLPROGRAM
            // Blend：lerp(後ろの色, 自分の色, A) で混ぜる
            // ZWrite Off：奥行きを記録しない（後ろの半透明の物を消さないため）

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;   // 法線
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;    // 法線
                float3 positionWS : TEXCOORD2;  // ワールド座標
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half _Alpha;            // 不透明度
                half4 _RimColor;        // ふちの色
                half _RimPower;         // ふちの細さ
                half _WobbleSpeed;      // 揺れの速さ
                half _WobbleAmount;     // 揺れの大きさ
                half _WobbleFrequency;  // 揺れの間隔
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // モデル基準からワールド基準へ
                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);

                // ワールド座標で揺らす：高さ(y)によってタイミングをずらす
                float wave = _Time.y * _WobbleSpeed + positionWS.y * _WobbleFrequency;
                positionWS.x += sin(wave) * _WobbleAmount;
                positionWS.z += cos(wave) * _WobbleAmount;

                // 揺らした後のワールド座標から画面の座標へ変換
                OUT.positionHCS = TransformWorldToHClip(positionWS);
                OUT.positionWS = positionWS;

                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                // ふちの強さ : 側面ほど１に近づく
                half3 normal = normalize(IN.normalWS);
                half3 view_direction = normalize(_WorldSpaceCameraPos - IN.positionWS);
                half rim = pow(1 - saturate(dot(normal, view_direction)), _RimPower);

                // 色：本体の色からふちの色へ、rimの割合で混ぜる
                half3 color = lerp(base.rgb, _RimColor.rgb, rim);

                // 透明度：中心は本体の透明度、ふちほど不透明。最後に全体の_Alphaを掛ける
                half alpha = lerp(base.a, 1, rim) * _Alpha;

                return half4(color, alpha);
            }
            ENDHLSL
        }
    }
}
