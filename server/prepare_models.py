"""Download once; normal inference does not contact model repositories."""
from faster_whisper.utils import download_model
from app.services.asr.local import model_path
from app.config import settings

if __name__ == "__main__":
    download_model(settings.asr_local_model, output_dir=str(model_path()))
    print("Local speech model ready:", model_path())
