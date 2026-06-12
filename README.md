# wc2026-photobooth-worker

RunPod Serverless worker for the WC2026 photobooth: ComfyUI + FLUX.2 Klein 9B virtual try-on workflow.

## Architecture

- Docker image hosted on `ghcr.io/jetthuangai/wc2026-photobooth-worker:latest`
- Models on a RunPod Network Volume mounted at `/runpod-volume`; first cold start downloads them via `download_models.py`
- ComfyUI runs on `127.0.0.1:8188` inside the container; `handler.py` queues prompts and returns base64 PNG
- Jersey images are fetched at request time from the live frontend at `https://wc2026booth.fun/kits/{teamId}_{kit}.jpg`

## Request / response

`POST https://api.runpod.ai/v2/{endpoint_id}/run`

```json
{
  "input": {
    "photo": "data:image/jpeg;base64,...",
    "teamId": "BRA",
    "kit": "home"
  }
}
```

Worker output:

```json
{
  "imageBase64": "<base64 PNG without data URI prefix>",
  "mimeType": "image/png"
}
```

## Required env vars on the RunPod endpoint

- `HF_TOKEN` — HuggingFace token for downloading FLUX.2 models
- `KITS_BASE_URL` (optional) — defaults to `https://wc2026booth.fun/kits`

## Build

GitHub Actions builds on every push to `main` and publishes to GHCR.
