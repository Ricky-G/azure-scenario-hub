using System;

namespace Azure.Communication.CallAutomation
{
    public static class AudioResampler
    {
        /// <summary>
        /// Resamples PCM audio from 16KHz to 24KHz using linear interpolation
        /// </summary>
        /// <param name="input16kHz">Input PCM audio data at 16KHz (16-bit samples)</param>
        /// <returns>Resampled PCM audio data at 24KHz (16-bit samples)</returns>
        public static byte[] Resample16kTo24k(byte[] input16kHz)
        {
            if (input16kHz == null || input16kHz.Length == 0)
                return input16kHz;

            // Convert byte array to 16-bit samples
            int inputSampleCount = input16kHz.Length / 2;
            short[] inputSamples = new short[inputSampleCount];
            Buffer.BlockCopy(input16kHz, 0, inputSamples, 0, input16kHz.Length);

            // Calculate output sample count (24/16 = 1.5x more samples)
            int outputSampleCount = (int)(inputSampleCount * 1.5);
            short[] outputSamples = new short[outputSampleCount];

            // Resample using linear interpolation
            double ratio = 16000.0 / 24000.0; // 0.6667

            for (int i = 0; i < outputSampleCount; i++)
            {
                double srcIndex = i * ratio;
                int srcIndexInt = (int)srcIndex;
                double fraction = srcIndex - srcIndexInt;

                if (srcIndexInt >= inputSampleCount - 1)
                {
                    outputSamples[i] = inputSamples[inputSampleCount - 1];
                }
                else
                {
                    // Linear interpolation between two samples
                    short sample1 = inputSamples[srcIndexInt];
                    short sample2 = inputSamples[srcIndexInt + 1];
                    outputSamples[i] = (short)(sample1 + (sample2 - sample1) * fraction);
                }
            }

            // Convert back to byte array
            byte[] output24kHz = new byte[outputSamples.Length * 2];
            Buffer.BlockCopy(outputSamples, 0, output24kHz, 0, output24kHz.Length);

            return output24kHz;
        }

        /// <summary>
        /// Resamples PCM audio from 24KHz to 16KHz using decimation
        /// </summary>
        /// <param name="input24kHz">Input PCM audio data at 24KHz (16-bit samples)</param>
        /// <returns>Resampled PCM audio data at 16KHz (16-bit samples)</returns>
        public static byte[] Resample24kTo16k(byte[] input24kHz)
        {
            if (input24kHz == null || input24kHz.Length == 0)
                return input24kHz;

            // Convert byte array to 16-bit samples
            int inputSampleCount = input24kHz.Length / 2;
            short[] inputSamples = new short[inputSampleCount];
            Buffer.BlockCopy(input24kHz, 0, inputSamples, 0, input24kHz.Length);

            // Calculate output sample count (16/24 = 0.6667x samples)
            int outputSampleCount = (int)(inputSampleCount * (16000.0 / 24000.0));
            short[] outputSamples = new short[outputSampleCount];

            // Resample using linear interpolation
            double ratio = 24000.0 / 16000.0; // 1.5

            for (int i = 0; i < outputSampleCount; i++)
            {
                double srcIndex = i * ratio;
                int srcIndexInt = (int)srcIndex;
                double fraction = srcIndex - srcIndexInt;

                if (srcIndexInt >= inputSampleCount - 1)
                {
                    outputSamples[i] = inputSamples[inputSampleCount - 1];
                }
                else
                {
                    // Linear interpolation between two samples
                    short sample1 = inputSamples[srcIndexInt];
                    short sample2 = inputSamples[srcIndexInt + 1];
                    outputSamples[i] = (short)(sample1 + (sample2 - sample1) * fraction);
                }
            }

            // Convert back to byte array
            byte[] output16kHz = new byte[outputSamples.Length * 2];
            Buffer.BlockCopy(outputSamples, 0, output16kHz, 0, output16kHz.Length);

            return output16kHz;
        }
    }
}