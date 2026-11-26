package com.androlua;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Movie;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.SurfaceTexture;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.media.MediaPlayer;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;

import com.androlua.AsyncTaskX;
import com.osfans.trime.BuildConfig;

import org.luaj.LuaValue;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Created by nirenr on 2018/09/05 0005.
 * Updated to support video playback as background.
 */

public class LuaBitmapDrawable extends Drawable implements Runnable, LuaGcable, SurfaceTexture.OnFrameAvailableListener {

    private LuaContext mLuaContext;
    private int mDuration;
    private long mMovieStart;
    private int mCurrentAnimationTime;
    private Movie mMovie;
    private LoadingDrawable mLoadingDrawable;
    private Drawable mBitmapDrawable;
    private NineBitmapDrawable mNineBitmapDrawable;
    private ColorFilter mColorFilter;
    private int mFillColor;
    private int mScaleType = FIT_XY;
    private GifDecoder mGifDecoder;
    private GifDecoder mGifDecoder2;
    private Handler mHandler = new Handler(Looper.getMainLooper());
    private GifDecoder.GifFrame mGifFrame;
    private int mDelay;
    private boolean mGc;
    private int mAlpha = 255;
    private Paint mPaint = new Paint();

    // ====== 视频背景相关属性 ======
    private MediaPlayer mMediaPlayer;
    private SurfaceTexture mSurfaceTexture;
    private Surface mSurface;
    private boolean mIsVideo = false;
    private int mVideoWidth = 0;
    private int mVideoHeight = 0;
    private boolean mIsVideoReady = false;

    public static void setCacheTime(long time) {
        mCacheTime = time;
    }

    public static long getCacheTime() {
        return mCacheTime;
    }

    private static long mCacheTime = 7 * 24 * 60 * 60 * 1000;

    public LuaBitmapDrawable(LuaContext context, String path, Drawable def) {
        this(context, path);
        mBitmapDrawable = def;
    }

    public LuaBitmapDrawable(LuaContext context, String path) {
        mLuaContext = context;
        mLoadingDrawable = new LoadingDrawable(context.getContext());
        if (path.toLowerCase().startsWith("http://") || path.toLowerCase().startsWith("https://")) {
            initHttp(context, path);
        } else {
            if (!path.startsWith("/")) {
                path = context.getLuaPath(path);
            }
            init(path);
        }
    }

    public LuaBitmapDrawable(Context context, String path) {
        mLoadingDrawable = new LoadingDrawable(context);
        init(path);
    }

    public LuaBitmapDrawable(String path) {
        mLoadingDrawable = new LoadingDrawable();
        init(path);
    }

    private void initHttp(final LuaContext context, final String path) {
        if (LuaBitmap.checkCache(context, path))
            init(LuaBitmap.getCachePath(context, path));
        new AsyncTaskX<String, String, String>() {
            @Override
            protected String doInBackground(String... strings) {
                try {
                    return getHttpBitmap(context, path);
                } catch (Exception e) {
                    if (BuildConfig.DEBUG)
                        e.printStackTrace();
                }
                return "";
            }

            @Override
            protected void onPostExecute(String s) {
                init(s);
            }
        }.execute();
    }

    private void init(final String path) {
        // 判断是否为常见的视频后缀
        if (isVideoFile(path)) {
            initVideo(path);
            return;
        }

        try {
            if (mLuaContext != null)
                mBitmapDrawable = new BitmapDrawable(LuaBitmap.getLocalBitmap(mLuaContext, path));
        } catch (Exception e) {
            e.printStackTrace();
        }
        try {
            mGifDecoder = new GifDecoder(new FileInputStream(path), new GifDecoder.GifAction() {
                @Override
                public void parseOk(boolean parseStatus, int frameIndex) {
                    if (!parseStatus && frameIndex < 0) {
                        init2(path);
                    } else if (parseStatus && mGifDecoder2 == null && mGifDecoder.getFrameCount() > 1) {
                        mGifDecoder2 = mGifDecoder;
                        invalidateSelf();
                    }
                }
            });
            mGifDecoder.start();
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                e.printStackTrace();
            init2(path);
        }
    }

    /**
     * 判断路径是否为视频格式
     */
    private boolean isVideoFile(String path) {
        if (path == null) return false;
        String lower = path.toLowerCase();
        return lower.endsWith(".mp4") || lower.endsWith(".mkv") ||
               lower.endsWith(".webm") || lower.endsWith(".3gp") || lower.endsWith(".avi");
    }

    /**
     * 初始化视频播放器
     */
    private void initVideo(final String path) {
        mIsVideo = true;
        try {
            mMediaPlayer = new MediaPlayer();
            mMediaPlayer.setDataSource(path);
            mMediaPlayer.setLooping(true); // 视频背景默认循环播放
            mMediaPlayer.setVolume(0, 0);  // 背景视频默认静音

            // 创建离屏渲染纹理
            mSurfaceTexture = new SurfaceTexture(10);
            mSurfaceTexture.setOnFrameAvailableListener(this);
            mSurface = new Surface(mSurfaceTexture);
            mMediaPlayer.setSurface(mSurface);

            mMediaPlayer.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
                @Override
                public void onPrepared(MediaPlayer mp) {
                    mVideoWidth = mp.getVideoWidth();
                    mVideoHeight = mp.getVideoHeight();
                    mIsVideoReady = true;
                    mp.start();
                    invalidateSelf();
                }
            });

            mMediaPlayer.setOnErrorListener(new MediaPlayer.OnErrorListener() {
                @Override
                public boolean onError(MediaPlayer mp, int what, int extra) {
                    mIsVideo = false;
                    init2(path); // 视频解码失败后降级处理
                    return true;
                }
            });

            mMediaPlayer.prepareAsync();
        } catch (Exception e) {
            if (BuildConfig.DEBUG) e.printStackTrace();
            mIsVideo = false;
            init2(path);
        }
    }

    @Override
    public void onFrameAvailable(SurfaceTexture surfaceTexture) {
        // 当视频有新一帧准备好时，通知重绘 Canvas
        mHandler.post(this);
    }

    private void init2(String path) {
        if (path.isEmpty()) {
            mHandler.postDelayed(new Runnable() {
                @Override
                public void run() {
                    mLoadingDrawable.setState(-1);
                }
            }, 1000);
            invalidateSelf();
            return;
        }

        if (mMovie != null) {
            mDuration = mMovie.duration();
            if (mDuration == 0)
                mDuration = 1000;
        } else {
            try {
                mNineBitmapDrawable = new NineBitmapDrawable(path);
            } catch (Exception e) {
                try {
                    if (mLuaContext != null)
                        mBitmapDrawable = new BitmapDrawable(LuaBitmap.getLocalBitmap(mLuaContext, path));
                    else
                        mBitmapDrawable = new BitmapDrawable(LuaBitmap.getLocalBitmap(path));
                } catch (Exception e1) {
                    if (BuildConfig.DEBUG)
                        e1.printStackTrace();
                }
            }
        }
        if (mMovie == null && mBitmapDrawable == null && mNineBitmapDrawable == null && !mIsVideo) {
            mHandler.postDelayed(new Runnable() {
                @Override
                public void run() {
                    mLoadingDrawable.setState(-1);
                }
            }, 1000);
        }
        invalidateSelf();
    }

    public int getWidth() {
        if (mIsVideo) {
            return mVideoWidth;
        } else if (mMovie != null) {
            return mMovie.width();
        } else if (mGifDecoder2 != null) {
            if (mGifFrame == null)
                mGifFrame = mGifDecoder2.next();
            if (mGifFrame != null)
                return mGifFrame.image.getWidth();
            return mGifDecoder2.width;
        } else if (mBitmapDrawable != null) {
            return mBitmapDrawable.getIntrinsicWidth();
        } else if (mNineBitmapDrawable != null) {
            return mNineBitmapDrawable.getIntrinsicWidth();
        }
        return super.getIntrinsicWidth();
    }

    public int getHeight() {
        if (mIsVideo) {
            return mVideoHeight;
        } else if (mMovie != null) {
            return mMovie.height();
        } else if (mGifDecoder2 != null) {
            if (mGifFrame == null)
                mGifFrame = mGifDecoder2.next();
            if (mGifFrame != null)
                return mGifFrame.image.getHeight();
            return mGifDecoder2.height;
        } else if (mBitmapDrawable != null) {
            return mBitmapDrawable.getIntrinsicHeight();
        } else if (mNineBitmapDrawable != null) {
            return mNineBitmapDrawable.getIntrinsicHeight();
        }
        return super.getIntrinsicHeight();
    }

    @Override
    public void draw(Canvas canvas) {
        canvas.drawColor(mFillColor);
        if (mColorFilter != null)
            setColorFilter(mColorFilter);

        // ====== 绘制视频背景 ======
        if (mIsVideo) {
            if (mIsVideoReady && mSurfaceTexture != null) {
                synchronized (this) {
                    try {
                        mSurfaceTexture.updateTexImage(); // 更新最新的视频帧纹理
                    } catch (Exception e) {
                        // 防止在快速切换或释放时抛出异常
                    }
                }
                // 触发下一帧更新
                invalidateSelf();
            }
            return;
        }

        // ====== 原有 GIF / Movie / Bitmap 逻辑 ======
        if (mGifDecoder2 != null) {
            long now = System.currentTimeMillis();
            if (mMovieStart == 0 || mGifFrame == null) {
                mGifFrame = mGifDecoder2.next();
                mDelay = mGifFrame.delay;
                mMovieStart = now;
            } else {
                while (now - mMovieStart > mDelay) {
                    mGifFrame = mGifDecoder2.next();
                    mDelay = mGifFrame.delay;
                    mMovieStart += mDelay;
                }
            }
            if (mGifFrame != null) {
                Rect bound = getBounds();
                BitmapDrawable bitmapDrawable = new BitmapDrawable(mGifFrame.image);
                bitmapDrawable.setColorFilter(mColorFilter);
                int width = bitmapDrawable.getIntrinsicWidth();
                int height = bitmapDrawable.getIntrinsicHeight();
                float mScale = 1;
                if (mScaleType == FIT_XY) {
                    float mScaleX = (float) (bound.right - bound.left) / (float) width;
                    float mScaleY = (float) (bound.bottom - bound.top) / (float) height;
                    width = (int) (width * mScaleX);
                    height = (int) (height * mScaleY);
                } else if (mScaleType != MATRIX) {
                    mScale = Math.min((float) (bound.bottom - bound.top) / (float) height, (float) (bound.right - bound.left) / (float) width);
                    width = (int) (width * mScale);
                    height = (int) (height * mScale);
                }
                int left = bound.left;
                int top = bound.top;
                switch (mScaleType) {
                    case FIT_CENTER:
                        left = (int) (((bound.right - bound.left) - width) / 2);
                        top = (int) (((bound.bottom - bound.top) - height) / 2);
                        break;
                    case FIT_END:
                        top = (int) ((bound.bottom - bound.top) - height);
                        break;
                }
                bitmapDrawable.setBounds(new Rect(left, top, left + width, top + height));
                bitmapDrawable.draw(canvas);
            }
            invalidateSelf();
        } else if (mMovie != null) {
            long now = System.currentTimeMillis();
            if (mMovieStart == 0)
                mMovieStart = now;
            mCurrentAnimationTime = (int) ((now - mMovieStart) % mDuration);
            mMovie.setTime(mCurrentAnimationTime);
            Rect bound = getBounds();
            canvas.save();
            int width = mMovie.width();
            int height = mMovie.height();
            float mScale = 1;
            if (mScaleType == FIT_XY) {
                float mScaleX = (float) (bound.right - bound.left) / (float) width;
                float mScaleY = (float) (bound.bottom - bound.top) / (float) height;
                canvas.scale(mScaleX, mScaleY);
                width = (int) (width * mScaleX);
                height = (int) (height * mScaleY);
            } else if (mScaleType != MATRIX) {
                mScale = Math.min((float) (bound.bottom - bound.top) / (float) height, (float) (bound.right - bound.left) / (float) width);
                canvas.scale(mScale, mScale);
                width = (int) (width * mScale);
                height = (int) (height * mScale);
            }
            int left = bound.left;
            int top = bound.top;
            switch (mScaleType) {
                case FIT_CENTER:
                    left = (int) (((bound.right - bound.left) - width) / mScale / 2);
                    top = (int) (((bound.bottom - bound.top) - height) / mScale / 2);
                    break;
                case FIT_END:
                    top = (int) (((bound.bottom - bound.top)) - height / mScale);
                    break;
            }
            mMovie.draw(canvas, left, top, mPaint);
            canvas.restore();
            invalidateSelf();

        } else if (mBitmapDrawable != null) {
            Rect bound = getBounds();
            int width = mBitmapDrawable.getIntrinsicWidth();
            int height = mBitmapDrawable.getIntrinsicHeight();
            float mScale = 1;
            if (mScaleType == FIT_XY) {
                float mScaleX = (float) (bound.right - bound.left) / (float) width;
                float mScaleY = (float) (bound.bottom - bound.top) / (float) height;
                width = (int) (width * mScaleX);
                height = (int) (height * mScaleY);
            } else if (mScaleType != MATRIX) {
                mScale = Math.min((float) (bound.bottom - bound.top) / (float) height, (float) (bound.right - bound.left) / (float) width);
                width = (int) (width * mScale);
                height = (int) (height * mScale);
            }
            int left = bound.left;
            int top = bound.top;
            switch (mScaleType) {
                case FIT_CENTER:
                    left = (int) (((bound.right - bound.left) - width) / 2);
                    top = (int) (((bound.bottom - bound.top) - height) / 2);
                    break;
                case FIT_END:
                    top = (int) ((bound.bottom - bound.top) - height);
                    break;
            }
            mBitmapDrawable.setBounds(new Rect(left, top, left + width, top + height));
            mBitmapDrawable.draw(canvas);
        } else if (mNineBitmapDrawable != null) {
            mNineBitmapDrawable.setBounds(getBounds());
            mNineBitmapDrawable.draw(canvas);
        } else if (mLoadingDrawable != null) {
            mLoadingDrawable.setBounds(getBounds());
            mLoadingDrawable.draw(canvas);
            invalidateSelf();
        }
    }

    @Override
    protected void finalize() throws Throwable {
        super.finalize();
        releaseVideo();
        if (mGifDecoder2 != null)
            mGifDecoder2.free();
    }

    /**
     * 释放视频播放相关资源
     */
    private void releaseVideo() {
        if (mMediaPlayer != null) {
            try {
                if (mMediaPlayer.isPlaying()) {
                    mMediaPlayer.stop();
                }
                mMediaPlayer.release();
            } catch (Exception e) {
                e.printStackTrace();
            }
            mMediaPlayer = null;
        }
        if (mSurface != null) {
            mSurface.release();
            mSurface = null;
        }
        if (mSurfaceTexture != null) {
            mSurfaceTexture.release();
            mSurfaceTexture = null;
        }
        mIsVideoReady = false;
    }

    public void setScaleType(int scaleType) {
        if (mScaleType != scaleType) {
            mScaleType = scaleType;
            invalidateSelf();
        }
    }

    public void setFillColor(int fillColor) {
        if (fillColor == mFillColor) {
            return;
        }
        mFillColor = fillColor;
    }

    @Override
    public void setAlpha(int alpha) {
        mAlpha = alpha;
        if (mPaint != null)
            mPaint.setAlpha(alpha);
        if (mBitmapDrawable != null)
            mBitmapDrawable.setAlpha(alpha);
        if (mNineBitmapDrawable != null)
            mNineBitmapDrawable.setAlpha(alpha);
        if (mLoadingDrawable != null)
            mLoadingDrawable.setAlpha(alpha);
    }

    @Override
    public void setColorFilter(ColorFilter colorFilter) {
        mColorFilter = colorFilter;
        if (mPaint != null)
            mPaint.setColorFilter(colorFilter);
        if (mBitmapDrawable != null)
            mBitmapDrawable.setColorFilter(colorFilter);
        if (mNineBitmapDrawable != null)
            mNineBitmapDrawable.setColorFilter(colorFilter);
        if (mLoadingDrawable != null)
            mLoadingDrawable.setColorFilter(colorFilter);
    }

    @Override
    public int getOpacity() {
        return PixelFormat.UNKNOWN;
    }

    public static String getHttpBitmap(LuaContext context, String url) throws IOException {
        String path = context.getLuaExtDir("cache") + "/" + url.hashCode();
        File f = new File(path);
        if (f.exists() && System.currentTimeMillis() - f.lastModified() < mCacheTime) {
            return path;
        }
        new File(path).delete();
        URL myFileUrl = new URL(url);
        HttpURLConnection conn = (HttpURLConnection) myFileUrl.openConnection();
        conn.setConnectTimeout(120000);
        conn.setDoInput(true);
        conn.connect();
        InputStream is = conn.getInputStream();
        FileOutputStream out = new FileOutputStream(path);
        if (!LuaUtil.copyFile(is, out)) {
            out.close();
            is.close();
            new File(path).delete();
            throw new RuntimeException("LoadHttpBitmap Error.");
        }
        out.close();
        is.close();
        return path;
    }

    public static final int MATRIX = (0);
    public static final int FIT_XY = (1);
    public static final int FIT_START = (2);
    public static final int FIT_CENTER = (3);
    public static final int FIT_END = (4);
    public static final int CENTER = (5);
    public static final int CENTER_CROP = (6);
    public static final int CENTER_INSIDE = (7);

    @Override
    public void run() {
        invalidateSelf();
    }

    @Override
    public void gc() {
        releaseVideo();
        if (mGifDecoder2 != null)
            mGifDecoder2.free();
        if (mBitmapDrawable != null && mBitmapDrawable instanceof BitmapDrawable)
            ((BitmapDrawable) mBitmapDrawable).getBitmap().recycle();
        if (mNineBitmapDrawable != null)
            mNineBitmapDrawable.gc();
        mGifDecoder2 = null;
        mBitmapDrawable = null;
        mNineBitmapDrawable = null;
        mLoadingDrawable.setState(-1);
        mGc = true;
    }

    @Override
    public boolean isGc() {
        return mGc;
    }
}