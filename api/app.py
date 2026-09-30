"""Retired standalone analyzer: never return unevaluated recitation scores.

Use the authenticated recitation API's upload and polling endpoints. This
legacy endpoint did not perform inference and cannot safely analyze audio.
"""

from fastapi import FastAPI, HTTPException

app = FastAPI()

@app.post("/analyze")
async def analyze():
    raise HTTPException(
        status_code=503,
        detail={
            "code": "analysis_unavailable",
            "message": (
                "Standalone recitation analysis is unavailable. "
                "Use the authenticated /v1/recitations/upload endpoint."
            ),
        },
    )
