import os
import json
import subprocess
from fastapi import FastAPI, UploadFile, File, Form

app = FastAPI()

@app.post("/analyze")
async def analyze(audio_file: UploadFile = File(...), surah_id: int = Form(...), ayah_number: int = Form(...)):
    tmp_path = f"/tmp/test_audio_{audio_file.filename}"
    with open(tmp_path, "wb") as buffer:
        buffer.write(await audio_file.read())
    result = subprocess.run(
        ["/home/ubuntu/qari-env/bin/python", "/tmp/deploy_vps/adapter_infer_sub.py", tmp_path, str(surah_id), str(ayah_number)],
        capture_output=True, text=True
    )
    os.remove(tmp_path)
    try:
        for line in reversed(result.stdout.strip().split('\n')):
            if line.strip().startswith('{') and line.strip().endswith('}'):
                return json.loads(line)
        return {"error": "Parse failed", "stdout": result.stdout[-500:], "stderr": result.stderr[-500:]}
    except Exception as e:
        return {"error": str(e)}
