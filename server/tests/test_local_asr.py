import asyncio
import unittest
from unittest.mock import patch

from app.config import settings
from app.services.asr import is_asr_configured
from app.services.asr.base import ASRError
from app.services.asr.local import LocalASRProvider


class LocalSpeechTest(unittest.TestCase):
    def test_audio_validation_timing_and_missing_model(self):
        provider = LocalASRProvider()
        with self.assertRaises(ASRError): asyncio.run(provider.transcribe_chunk(b'1', 0))
        with patch.object(provider, '_transcribe', return_value='recognized speech'):
            result = asyncio.run(provider.transcribe_chunk(bytes(32000), 3))
            self.assertEqual(result.text, 'recognized speech')
            self.assertEqual((result.start_ms, result.end_ms), (12000, 13000))
        with patch('app.services.asr.local.model_path') as path:
            path.return_value.__truediv__.return_value.is_file.return_value = False
            with self.assertRaisesRegex(ASRError, 'prepare_models'):
                asyncio.run(provider.transcribe_chunk(bytes(32000), 0))
        with patch.object(settings, 'asr_provider', 'mock'):
            self.assertFalse(is_asr_configured())
