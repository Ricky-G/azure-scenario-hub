"""
Audio resampling utilities for converting between different sample rates.
"""
import numpy as np
from scipy import signal
import logging

logger = logging.getLogger(__name__)


class AudioResampler:
    """Audio resampling utilities for Voice Live API integration."""
    
    @staticmethod
    def resample_24k_to_16k(audio_bytes: bytes) -> bytes:
        """
        Resample audio from 24kHz to 16kHz to match ACS requirements.
        Voice Live API outputs 24kHz audio, but ACS expects 16kHz.
        
        Args:
            audio_bytes: PCM audio data at 24kHz, 16-bit, mono
            
        Returns:
            Resampled PCM audio data at 16kHz, 16-bit, mono
        """
        try:
            # Convert bytes to numpy array (16-bit PCM)
            audio_array = np.frombuffer(audio_bytes, dtype=np.int16)
            
            if len(audio_array) == 0:
                return audio_bytes
            
            # Resample from 24kHz to 16kHz
            # This is a ratio of 2:3, so we need to downsample
            num_samples_output = int(len(audio_array) * 16000 / 24000)
            
            # Use scipy.signal.resample for high-quality resampling
            resampled_array = signal.resample(audio_array, num_samples_output)
            
            # Convert back to int16 and then to bytes
            resampled_int16 = np.round(resampled_array).astype(np.int16)
            resampled_bytes = resampled_int16.tobytes()
            
            return resampled_bytes
            
        except Exception as e:
            logger.error(f"Error resampling audio: {e}")
            # Return original audio if resampling fails
            return audio_bytes
    
    @staticmethod
    def resample_16k_to_24k(audio_bytes: bytes) -> bytes:
        """
        Resample audio from 16kHz to 24kHz for Voice Live API.
        ACS outputs 16kHz audio, but Voice Live API expects 24kHz.
        
        Args:
            audio_bytes: PCM audio data at 16kHz, 16-bit, mono
            
        Returns:
            Resampled PCM audio data at 24kHz, 16-bit, mono
        """
        try:
            # Convert bytes to numpy array (16-bit PCM)
            audio_array = np.frombuffer(audio_bytes, dtype=np.int16)
            
            if len(audio_array) == 0:
                return audio_bytes
            
            # Resample from 16kHz to 24kHz
            # This is a ratio of 3:2, so we need to upsample
            num_samples_output = int(len(audio_array) * 24000 / 16000)
            
            # Use scipy.signal.resample for high-quality resampling
            resampled_array = signal.resample(audio_array, num_samples_output)
            
            # Convert back to int16 and then to bytes
            resampled_int16 = np.round(resampled_array).astype(np.int16)
            resampled_bytes = resampled_int16.tobytes()
            
            return resampled_bytes
            
        except Exception as e:
            logger.error(f"Error resampling audio 16k→24k: {e}")
            # Return original audio if resampling fails
            return audio_bytes
    
    @staticmethod
    def is_silent_audio(audio_bytes: bytes, threshold: float = 0.01) -> bool:
        """
        Check if audio data is silent (below threshold).
        
        Args:
            audio_bytes: PCM audio data
            threshold: RMS threshold for silence detection (0.0 - 1.0)
            
        Returns:
            True if audio is considered silent
        """
        try:
            if len(audio_bytes) == 0:
                return True
                
            # Convert to numpy array
            audio_array = np.frombuffer(audio_bytes, dtype=np.int16)
            
            # Calculate RMS (Root Mean Square)
            rms = np.sqrt(np.mean(audio_array.astype(np.float32) ** 2))
            
            # Normalize RMS to 0-1 range (32767 is max value for int16)
            normalized_rms = rms / 32767.0
            
            return normalized_rms < threshold
            
        except Exception as e:
            logger.error(f"Error checking audio silence: {e}")
            return False
