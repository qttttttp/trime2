package com.osfans.trime.util;

import android.Manifest;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.util.Log;

import androidx.core.app.ActivityCompat;

import com.androlua.LuaApplication;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public class AudioRecorderHelper {

    private static final String TAG = "AudioRecorderHelper";

    private AudioRecord audioRecord;
    private boolean isRecording;

    private final int sampleRate = 16000;
    private final int channelConfig = AudioFormat.CHANNEL_IN_MONO;
    private final int audioFormat = AudioFormat.ENCODING_PCM_16BIT;

    private int bufferSize;
    private ByteArrayOutputStream outputStream;
    private Thread recordThread;

    public AudioRecorderHelper() {
        // 获取最小缓冲区大小
        int minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat);
        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            minBufferSize = sampleRate * 2; // 兜底大小
        }
        // 放大缓冲区（通常建议 2~4 倍以防爆音）
        bufferSize = minBufferSize * 2;

        if (ActivityCompat.checkSelfPermission(LuaApplication.getInstance(), Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "缺少 RECORD_AUDIO 权限");
            return;
        }

        // 推荐使用 VOICE_RECOGNITION 兼容性更好、杂音更少
        audioRecord = new AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize);

        if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord 初始化失败！");
        }
    }

    /**
     * 开始录音
     */
    public void startRecord() {
        if (isRecording || audioRecord == null) {
            return;
        }

        if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord 未初始化，无法开始录音");
            return;
        }

        outputStream = new ByteArrayOutputStream();

        try {
            audioRecord.startRecording();
            isRecording = true;
        } catch (Exception e) {
            e.printStackTrace();
            isRecording = false;
            return;
        }

        recordThread = new Thread(() -> {
            // 使用 short 数组读取 16bit 音频，避免字节对齐问题引起的爆音
            short[] shortBuffer = new short[bufferSize / 2];

            while (isRecording) {
                int readSize = audioRecord.read(shortBuffer, 0, shortBuffer.length);
                if (readSize > 0) {
                    // 将 short 转换为 byte 写入（小端序）
                    byte[] bData = shortsToBytes(shortBuffer, readSize);
                    try {
                        outputStream.write(bData, 0, bData.length);
                    } catch (Exception e) {
                        e.printStackTrace();
                    }
                }
            }
        });

        recordThread.start();
    }

    /**
     * 停止录音
     * @return WAV格式音频数据
     */
    public byte[] stopRecord() {
        if (!isRecording) {
            return new byte[0];
        }

        isRecording = false;

        try {
            if (recordThread != null) {
                recordThread.join();
            }
        } catch (InterruptedException e) {
            e.printStackTrace();
        }

        try {
            if (audioRecord != null && audioRecord.getState() == AudioRecord.STATE_INITIALIZED) {
                audioRecord.stop();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        byte[] audioData = outputStream.toByteArray();

        try {
            outputStream.close();
        } catch (Exception e) {
            e.printStackTrace();
        }

        return pcmToWav(audioData, sampleRate, channelConfig == AudioFormat.CHANNEL_IN_MONO ? 1 : 2, 16);
    }

    /**
     * 释放资源
     */
    public void release() {
        isRecording = false;
        if (audioRecord != null) {
            try {
                audioRecord.release();
            } catch (Exception e) {
                e.printStackTrace();
            }
            audioRecord = null;
        }
    }

    private byte[] shortsToBytes(short[] shorts, int length) {
        byte[] bytes = new byte[length * 2];
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().put(shorts, 0, length);
        return bytes;
    }

    public static byte[] pcmToWav(byte[] pcmData, int sampleRate, int channels, int bitsPerSample) {
        int dataSize = pcmData.length;
        int totalSize = dataSize + 36;
        ByteArrayOutputStream out = new ByteArrayOutputStream();

        try {
            out.write("RIFF".getBytes());
            writeInt(out, totalSize);
            out.write("WAVE".getBytes());
            out.write("fmt ".getBytes());
            writeInt(out, 16);
            writeShort(out, (short) 1);
            writeShort(out, (short) channels);
            writeInt(out, sampleRate);

            int byteRate = sampleRate * channels * bitsPerSample / 8;
            writeInt(out, byteRate);

            short blockAlign = (short) (channels * bitsPerSample / 8);
            writeShort(out, blockAlign);
            writeShort(out, (short) bitsPerSample);

            out.write("data".getBytes());
            writeInt(out, dataSize);
            out.write(pcmData);

            return out.toByteArray();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    private static void writeInt(ByteArrayOutputStream out, int value) throws IOException {
        out.write(value & 0xff);
        out.write((value >> 8) & 0xff);
        out.write((value >> 16) & 0xff);
        out.write((value >> 24) & 0xff);
    }

    private static void writeShort(ByteArrayOutputStream out, short value) throws IOException {
        out.write(value & 0xff);
        out.write((value >> 8) & 0xff);
    }
}
